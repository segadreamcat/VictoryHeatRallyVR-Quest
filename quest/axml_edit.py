"""Minimal binary AndroidManifest.xml editor.

Keeps every existing chunk byte-for-byte (so attribute types stay exactly as aapt wrote
them) and only appends strings and inserts new elements. Enough for the Quest tweaks.
"""
import struct

ANDROID_NS = "http://schemas.android.com/apk/res/android"
RES_ID = {"name": 0x01010003, "value": 0x01010024, "authorities": 0x01010018, "required": 0x0101028E}
T_STRING, T_INT_BOOLEAN = 0x03, 0x12


class Manifest:
    def __init__(self, raw):
        assert struct.unpack_from("<HHI", raw, 0)[0] == 0x0003
        pos = 8
        self.chunks = []
        while pos < len(raw):
            t, hs, sz = struct.unpack_from("<HHI", raw, pos)
            self.chunks.append([t, raw[pos:pos + sz]])
            pos += sz
        pool = self.chunks[0][1]
        assert self.chunks[0][0] == 0x0001
        _, hs, sz, n, nstyles, flags, sstart, ystart = struct.unpack_from("<HHIIIIII", pool, 0)
        assert nstyles == 0, "styled strings not supported"
        self.utf8 = bool(flags & 0x100)
        offs = struct.unpack_from("<%dI" % n, pool, hs)
        self.strings = [self._read(pool, sstart + o) for o in offs]
        self.flags = flags

    def _read(self, b, p):
        if self.utf8:
            n = b[p]; p += 2 if n & 0x80 else 1
            n8 = b[p]
            if n8 & 0x80:
                n8 = ((n8 & 0x7F) << 8) | b[p + 1]; p += 2
            else:
                p += 1
            return b[p:p + n8].decode("utf-8")
        n = struct.unpack_from("<H", b, p)[0]; p += 2
        if n & 0x8000:
            n = ((n & 0x7FFF) << 16) | struct.unpack_from("<H", b, p)[0]; p += 2
        return b[p:p + 2 * n].decode("utf-16-le")

    def check_attr_names(self):
        rmap = next((b for t, b in self.chunks if t == 0x0180), b"")
        n = (len(rmap) - 8) // 4
        for k, rid in RES_ID.items():
            if k in self.strings:
                i = self.strings.index(k)
                assert i < n and struct.unpack_from("<I", rmap, 8 + 4 * i)[0] == rid, "attribute %s not resource-mapped" % k

    def sid(self, s):
        # Attribute-name strings must keep their resource-map slots, so reuse existing entries.
        if s in self.strings:
            return self.strings.index(s)
        self.strings.append(s)
        return len(self.strings) - 1

    def _pool(self):
        data, offs = bytearray(), []
        for s in self.strings:
            offs.append(len(data))
            if self.utf8:
                e = s.encode("utf-8")
                for ln in (len(s), len(e)):
                    data += bytes([ln]) if ln < 0x80 else bytes([0x80 | (ln >> 8), ln & 0xFF])
                data += e + b"\0"
            else:
                e = s.encode("utf-16-le")
                data += struct.pack("<H", len(s)) + e + b"\0\0"
        while len(data) % 4:
            data += b"\0"
        hs = 28
        sstart = hs + 4 * len(self.strings)
        body = struct.pack("<%dI" % len(offs), *offs) + bytes(data)
        return struct.pack("<HHIIIIII", 1, hs, hs + len(body), len(self.strings), 0, self.flags, sstart, 0) + body

    # -- element helpers -------------------------------------------------------------------
    def _ns(self):
        return self.sid(ANDROID_NS)

    def start(self, tag, attrs):
        ns = self._ns()
        items = []
        for k, v in attrs:
            name = self.sid(k)
            if isinstance(v, bool):
                items.append((RES_ID[k], struct.pack("<IIIHBBI", ns, name, 0xFFFFFFFF, 8, 0, T_INT_BOOLEAN, 0xFFFFFFFF if v else 0)))
            else:
                s = self.sid(v)
                items.append((RES_ID[k], struct.pack("<IIIHBBI", ns, name, s, 8, 0, T_STRING, s)))
        items.sort(key=lambda x: x[0])
        body = struct.pack("<IIIIHHHHHH", 1, 0xFFFFFFFF, 0xFFFFFFFF, self.sid(tag), 20, 20, len(items), 0, 0, 0)
        body += b"".join(a for _, a in items)
        return [0x0102, struct.pack("<HHI", 0x0102, 16, 8 + len(body)) + body]

    def end(self, tag):
        body = struct.pack("<IIII", 1, 0xFFFFFFFF, 0xFFFFFFFF, self.sid(tag))
        return [0x0103, struct.pack("<HHI", 0x0103, 16, 8 + len(body)) + body]

    def elements(self):
        """Yield (index, kind, tagname, attrs dict name->(rawstring or data))."""
        for i, (t, b) in enumerate(self.chunks):
            if t == 0x0102:
                name = self.strings[struct.unpack_from("<I", b, 20)[0]]
                n = struct.unpack_from("<H", b, 28)[0]
                at = {}
                for k in range(n):
                    ans, an, raw, _, _, typ, data = struct.unpack_from("<IIIHBBI", b, 36 + 20 * k)
                    at[self.strings[an]] = (self.strings[raw] if raw != 0xFFFFFFFF else None, typ, data, 36 + 20 * k)
                yield i, "start", name, at
            elif t == 0x0103:
                yield i, "end", self.strings[struct.unpack_from("<I", b, 20)[0]], {}

    def set_string_attr(self, i, attr, value):
        b = bytearray(self.chunks[i][1])
        n = struct.unpack_from("<H", b, 28)[0]
        for k in range(n):
            off = 36 + 20 * k
            an = struct.unpack_from("<I", b, off + 4)[0]
            if self.strings[an] == attr:
                s = self.sid(value)
                struct.pack_into("<IHBBI", b, off + 8, s, 8, 0, T_STRING, s)
        self.chunks[i][1] = bytes(b)

    def set_int_attr(self, i, attr, value):
        b = bytearray(self.chunks[i][1])
        n = struct.unpack_from("<H", b, 28)[0]
        for k in range(n):
            off = 36 + 20 * k
            if self.strings[struct.unpack_from("<I", b, off + 4)[0]] == attr:
                struct.pack_into("<IHBBI", b, off + 8, 0xFFFFFFFF, 8, 0, 0x10, value)
        self.chunks[i][1] = bytes(b)

    def pack(self):
        pool = self._pool()
        rest = b"".join(b for _, b in self.chunks[1:])
        total = 8 + len(pool) + len(rest)
        return struct.pack("<HHI", 3, 8, total) + pool + rest


def quest_manifest(raw, extension_class):
    m = Manifest(raw)
    for k in RES_ID:
        if k not in m.strings:
            raise SystemExit("manifest has no %s attribute to reuse" % k)
    m.check_attr_names()
    els = list(m.elements())
    # 1. launcher intent-filter: add the Quest VR category
    for i, kind, name, at in els:
        if kind == "start" and name == "category" and at.get("name", (None,))[0] == "android.intent.category.LAUNCHER":
            vr = [m.start("category", [("name", "com.oculus.intent.category.VR")]), m.end("category")]
            m.chunks[i + 2:i + 2] = vr  # after LAUNCHER's end tag
            break
    else:
        raise SystemExit("launcher category not found")
    els = list(m.elements())
    # 2. extension class meta-data (GameMaker reads these at startup)
    for i, kind, name, at in els:
        if kind == "start" and name == "meta-data" and at.get("name", (None,))[0] == "YYNumExtensionClasses":
            m.set_int_attr(i, "value", 1)  # GameMaker reads it with Bundle.getInt
            add = [m.start("meta-data", [("name", "YYExtensionClass0"), ("value", extension_class)]), m.end("meta-data"),
                   m.start("meta-data", [("name", "com.oculus.supportedDevices"), ("value", "quest2|questpro|quest3|quest3s")]), m.end("meta-data")]
            m.chunks[i + 2:i + 2] = add
            break
    else:
        raise SystemExit("YYNumExtensionClasses meta-data not found")
    els = list(m.elements())
    # 3. manifest-level: VR feature, OpenXR permissions, runtime broker visibility (before <application>)
    app = next(i for i, kind, name, _ in els if kind == "start" and name == "application")
    add = [m.start("uses-feature", [("name", "android.hardware.vr.headtracking"), ("required", True)]), m.end("uses-feature")]
    for p in ("org.khronos.openxr.permission.OPENXR", "org.khronos.openxr.permission.OPENXR_SYSTEM"):
        add += [m.start("uses-permission", [("name", p)]), m.end("uses-permission")]
    add += [m.start("queries", []),
            m.start("provider", [("authorities", "org.khronos.openxr.runtime_broker;org.khronos.openxr.system_runtime_broker")]), m.end("provider"),
            m.start("intent", []), m.start("action", [("name", "org.khronos.openxr.OpenXRRuntimeService")]), m.end("action"), m.end("intent"),
            m.end("queries")]
    m.chunks[app:app] = add
    return m.pack()


def dump(raw):
    m = Manifest(raw)
    depth, out = 0, []
    for _, kind, name, at in m.elements():
        if kind == "start":
            out.append("  " * depth + "<%s %s>" % (name, " ".join("%s=%r/t%d" % (k, v[0] if v[0] is not None else v[2], v[1]) for k, v in at.items())))
            depth += 1
        else:
            depth -= 1
    return "\n".join(out)
