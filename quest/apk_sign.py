"""Minimal APK Signature Scheme v2 signer (RSA-2048, PKCS#1 v1.5 SHA-256).

The APK must already be zip-aligned; the signing block is inserted before the
central directory, as apksigner does.
"""
import datetime, hashlib, os, struct
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.x509.oid import NameOID

V2_ID = 0x7109871A
ALG = 0x0103  # RSASSA-PKCS1-v1_5 with SHA2-256
MAGIC = b"APK Sig Block 42"


def load_or_make_key(path):
    if os.path.exists(path):
        data = open(path, "rb").read()
        key = serialization.load_pem_private_key(data.split(b"-----BEGIN CERTIFICATE-----")[0], None)
        cert = x509.load_pem_x509_certificate(b"-----BEGIN CERTIFICATE-----" + data.split(b"-----BEGIN CERTIFICATE-----")[1])
        return key, cert
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "VHR Quest local build")])
    now = datetime.datetime(2026, 1, 1)
    cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key())
            .serial_number(x509.random_serial_number()).not_valid_before(now)
            .not_valid_after(now + datetime.timedelta(days=365 * 30)).sign(key, hashes.SHA256()))
    with open(path, "wb") as f:
        f.write(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        f.write(cert.public_bytes(serialization.Encoding.PEM))
    return key, cert


def lp(b):
    return struct.pack("<I", len(b)) + b


def find_eocd(data):
    i = data.rfind(b"PK\x05\x06", max(0, len(data) - 65557))
    if i < 0:
        raise ValueError("no EOCD")
    cd_size, cd_off = struct.unpack("<II", data[i + 12:i + 20])
    return i, cd_off, cd_size


def chunked_digest(sections):
    digests = []
    for sec in sections:
        for o in range(0, len(sec), 1 << 20):
            c = sec[o:o + (1 << 20)]
            digests.append(hashlib.sha256(b"\xa5" + struct.pack("<I", len(c)) + c).digest())
    return hashlib.sha256(b"\x5a" + struct.pack("<I", len(digests)) + b"".join(digests)).digest()


def sign(apk_in, apk_out, keyfile):
    key, cert = load_or_make_key(keyfile)
    data = open(apk_in, "rb").read()
    eocd, cd_off, cd_size = find_eocd(data)
    if data[cd_off - 16:cd_off] == MAGIC:
        raise ValueError("already signed with v2+; strip first")
    entries, cd, eocd_b = data[:cd_off], data[cd_off:eocd], bytearray(data[eocd:])
    digest = chunked_digest([entries, cd, bytes(eocd_b)])
    cert_der = cert.public_bytes(serialization.Encoding.DER)
    signed = lp(lp(struct.pack("<I", ALG) + lp(digest))) + lp(lp(cert_der)) + lp(b"")
    sig = key.sign(signed, padding.PKCS1v15(), hashes.SHA256())
    pub = key.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    signer = lp(signed) + lp(lp(struct.pack("<I", ALG) + lp(sig))) + lp(pub)
    value = lp(lp(signer))
    pair = struct.pack("<Q", 4 + len(value)) + struct.pack("<I", V2_ID) + value
    size = len(pair) + 8 + 16
    block = struct.pack("<Q", size) + pair + struct.pack("<Q", size) + MAGIC
    # The digest covers the EOCD with the CD offset pointing at the signing block's start.
    # Recompute: digest input EOCD must hold the ORIGINAL cd offset (= block start). It does.
    new_eocd = bytearray(eocd_b)
    struct.pack_into("<I", new_eocd, 16, cd_off + len(block))
    with open(apk_out, "wb") as f:
        f.write(entries + block + cd + bytes(new_eocd))
