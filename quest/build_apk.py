#!/usr/bin/env python3
"""Turn a blank GameMaker 2024.8 Android export into the Quest build of Victory Heat Rally VR.

  build_apk.py --runner blank.apk --data game.droid --game "<Victory Heat Rally folder>"
               --lib libvhrvr.so --loader openxr_loader_for_android.aar --out VHRQuest.apk

Keeps GameMaker's runner (libyoyo.so + Java), swaps in the patched game data and the
game's loose files, adds the OpenXR bridge and loader, makes the manifest a Quest VR
app, then aligns and signs (APK Signature Scheme v2). Personal use: the output contains
your copy of the game. Do not distribute it.
"""
import argparse, io, os, struct, sys, zipfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import apk_sign

ANDROID = "http://schemas.android.com/apk/res/android"
A = "{%s}" % ANDROID
# Loose game files the runner opens by relative path (Windows-only files left out).
SKIP = {"data.win", "victory heat rally.exe", "steam_api64.dll", "steamworks_x64.dll", "imguigml_x64.dll",
        "openvr_api.dll", "vhrvr.dll", "options.ini", "vhrvr-runtime.log", "vhrvr-wheel.log", "sdl2.txt"}


def edit_manifest(raw):
    import axml_edit
    out = axml_edit.quest_manifest(raw, "VHRQuest")
    return out, axml_edit.dump(out)


def build(a):
    src = zipfile.ZipFile(a.runner)
    names = src.namelist()
    if not any(n.endswith("libyoyo.so") for n in names):
        raise SystemExit("That APK has no GameMaker runner (libyoyo.so).")
    abis = sorted({n.split("/")[1] for n in names if n.startswith("lib/") and n.endswith(".so")})
    if "arm64-v8a" not in abis:
        raise SystemExit("Export the GameMaker project with the arm64-v8a architecture enabled.")
    files = []  # (name, bytes, compress)
    for info in src.infolist():
        n = info.filename
        if n == "assets/game.droid" or (n.startswith("META-INF/") and (n.endswith((".SF", ".RSA", ".DSA", ".EC")) or n == "META-INF/MANIFEST.MF")):
            continue
        if n.startswith("lib/") and not n.startswith("lib/arm64-v8a/"):
            continue  # Quest is arm64 only
        data = src.read(n)
        if n == "assets/options.ini":
            text = data.decode("utf-8", "replace")
            if "YYNumExtensionClasses" not in text:
                text = text.replace("[Android]\r\n", "[Android]\r\nYYNumExtensionClasses=1\r\nYYExtensionClass0=VHRQuest\r\n", 1) if "[Android]\r\n" in text else \
                       text.replace("[Android]\n", "[Android]\nYYNumExtensionClasses=1\nYYExtensionClass0=VHRQuest\n", 1)
                if "YYNumExtensionClasses" not in text:
                    raise SystemExit("options.ini has no [Android] section")
            data = text.encode("utf-8")
        if n == "AndroidManifest.xml":
            data, text = edit_manifest(data)
            if not a.template:
                open(a.out + ".manifest.xml", "w").write(text)
        files.append((n, data, info.compress_type != zipfile.ZIP_STORED and not n.endswith(".so") and n != "resources.arsc"))
    have = {f[0] for f in files}
    seen = set()
    if a.data:
        files.append(("assets/game.droid", open(a.data, "rb").read(), True))
    for base, _, fs in (os.walk(a.game) if a.game else []):
        for f in fs:
            full = os.path.join(base, f)
            rel = os.path.relpath(full, a.game).replace(os.sep, "/")
            if rel.startswith(".") or f.lower() in SKIP or rel.startswith("lib/"):
                continue
            # Only the game's own data: the data/ folder and its loose root files (not mod logs, backups,
            # screenshots or anything else that may sit in the game folder).
            if "/" in rel:
                if not rel.lower().startswith("data/"):
                    continue
            elif not f.lower().endswith((".dat", ".csv", ".ttf", ".mp4", ".json", ".evnt")):
                continue
            # GameMaker's Android runner looks bundle files up lowercased with spaces as underscores
            # (LoadSave::_GetBundleFileName), so store them that way.
            name = "assets/" + rel.lower().replace(" ", "_")
            if name in seen:
                raise SystemExit("asset name clash: %s" % name)
            seen.add(name)
            if name not in have:
                files.append((name, open(full, "rb").read(), not f.lower().endswith((".ogg", ".mp4", ".png"))))
    if a.extra:
        # Prebaked art (vhrpaint/): cockpit-paint driver sprites, so the headset does no per-pixel work.
        for base, _, fs in os.walk(a.extra):
            for f in fs:
                rel = os.path.relpath(os.path.join(base, f), a.extra).replace(os.sep, "/").lower()
                files.append(("assets/vhrpaint_" + rel.replace("/", "_"), open(os.path.join(base, f), "rb").read(), False))
    files.append(("lib/arm64-v8a/libvhrvr.so", open(a.lib, "rb").read(), False))
    dexes = sorted(f for f in have if f.startswith("classes") and f.endswith(".dex"))
    files.append(("classes%d.dex" % (len(dexes) + 1), open(a.dex, "rb").read(), True))
    if a.loader:
        with zipfile.ZipFile(a.loader) as aar:
            files.append(("lib/arm64-v8a/libopenxr_loader.so", aar.read("jni/arm64-v8a/libopenxr_loader.so"), False))

    # Align: stored entries to 4 bytes, native libs to 16 KiB pages (extractNativeLibs=false safe).
    unsigned = a.out + ".unsigned"
    with open(unsigned, "wb") as fh:
        z = zipfile.ZipFile(fh, "w")
        for name, data, compress in files:
            zi = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            zi.compress_type = zipfile.ZIP_DEFLATED if compress else zipfile.ZIP_STORED
            zi.external_attr = 0o644 << 16
            if not compress:
                align = 16384 if name.endswith(".so") else 4
                header_end = fh.tell() + 30 + len(name.encode())
                pad = (-header_end) % align
                if pad:
                    if pad < 4:  # an extra field needs its 4-byte header; go to the next boundary
                        pad += align
                    # zipalign-style padding field (id 0xD935)
                    zi.extra = struct.pack("<HH", 0xD935, pad - 4) + b"\x00" * (pad - 4)
            z.writestr(zi, data)
        z.close()
    if a.template:
        # Template for the Python-free installer (quest/Build-Apk.csx adds the game and signs).
        os.replace(unsigned, a.out)
    else:
        apk_sign.sign(unsigned, a.out, a.key)
        os.remove(unsigned)
    print("Wrote", a.out, "(%d files, runner ABIs kept: arm64-v8a)" % len(files))


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--runner", required=True)
    p.add_argument("--data")
    p.add_argument("--game")
    p.add_argument("--template", action="store_true", help="no game files, unsigned: makes runner/vhrquest-template.apk")
    p.add_argument("--lib", required=True)
    p.add_argument("--dex", required=True, help="VHRQuest Java extension class (classes.dex from d8)")
    p.add_argument("--loader")
    p.add_argument("--extra", help="folder of prebaked art to ship as assets/vhrpaint_*")
    p.add_argument("--key", default=os.path.expanduser("~/.vhrquest-key.pem"))
    p.add_argument("--out", default="VHRQuest.apk")
    build(p.parse_args())
