// Victory Heat Rally VR, Quest standalone: APK builder (UndertaleModTool CLI script, no Python needed).
// Repacks runner/gamemaker-runner-2024.8.apk (a blank GameMaker Android export) around YOUR patched game data
// and game files, adds the OpenXR bridge, loader and driver art, then zip-aligns and signs (APK Signature Scheme v2).
// Inputs come from environment variables set by Install-Quest.ps1:
//   VHRVR_PACKAGE (this package), VHRQ_DATA (patched game.droid), VHRQ_GAME (game folder),
//   VHRQ_LOADER (openxr_loader_for_android .aar), VHRQ_OUT (apk path), VHRQ_KEY (signing key PEM).
// Personal use: the output contains your copy of the game. Do not distribute it.
using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

string Env(string k){var v=Environment.GetEnvironmentVariable(k);if(string.IsNullOrEmpty(v)) throw new Exception("Missing "+k);return v;}
string pkg=Env("VHRVR_PACKAGE"), dataPath=Env("VHRQ_DATA"), game=Env("VHRQ_GAME"), loader=Env("VHRQ_LOADER"), outPath=Env("VHRQ_OUT"), keyPath=Env("VHRQ_KEY");
string quest=Path.Combine(pkg,"quest");

// ------------------------------------------------------------------ collect entries: (name, source, compress)
var entries=new List<(string name, Func<byte[]> data, bool compress)>();
var have=new HashSet<string>();
void Add(string n, Func<byte[]> d, bool c){ if(!have.Add(n)) throw new Exception("duplicate entry "+n); entries.Add((n,d,c)); }
byte[] ReadEntry(ZipArchiveEntry e){using var s=e.Open();using var m=new MemoryStream();s.CopyTo(m);return m.ToArray();}

var runner=new ZipArchive(File.OpenRead(Path.Combine(pkg,"runner","gamemaker-runner-2024.8.apk")),ZipArchiveMode.Read);
if(!runner.Entries.Any(e=>e.FullName.EndsWith("libyoyo.so"))) throw new Exception("Runner APK has no libyoyo.so");
int dexCount=0;
foreach(var e in runner.Entries){
    string n=e.FullName;
    if(n.EndsWith("/")) continue;
    if(n=="assets/game.droid") continue;
    if(n.StartsWith("META-INF/") && (n.EndsWith(".SF")||n.EndsWith(".RSA")||n.EndsWith(".DSA")||n.EndsWith(".EC")||n=="META-INF/MANIFEST.MF")) continue;
    if(n.StartsWith("lib/") && !n.StartsWith("lib/arm64-v8a/")) continue; // Quest is arm64 only
    if(n.StartsWith("classes") && n.EndsWith(".dex")) dexCount++;
    bool comp=e.CompressedLength!=e.Length && !n.EndsWith(".so") && n!="resources.arsc";
    var entry=e;
    Func<byte[]> src=()=>ReadEntry(entry);
    if(n=="AndroidManifest.xml") src=()=>File.ReadAllBytes(Path.Combine(quest,"AndroidManifest-quest.bin")); // Quest VR manifest
    if(n=="assets/options.ini") src=()=>{
        string t=Encoding.UTF8.GetString(ReadEntry(entry));
        if(!t.Contains("YYNumExtensionClasses")){
            string nl=t.Contains("[Android]\r\n")?"\r\n":"\n";
            int i=t.IndexOf("[Android]"+nl);
            if(i<0) throw new Exception("options.ini has no [Android] section");
            t=t.Insert(i+9+nl.Length,"YYNumExtensionClasses=1"+nl+"YYExtensionClass0=VHRQuest"+nl);
        }
        return Encoding.UTF8.GetBytes(t);
    };
    Add(n,src,comp);
}
Add("assets/game.droid",()=>File.ReadAllBytes(dataPath),true);

// The game's own files: data/ and loose root data files (not mod logs, backups, screenshots, Windows binaries).
var skip=new HashSet<string>{"data.win","victory heat rally.exe","steam_api64.dll","steamworks_x64.dll","imguigml_x64.dll",
    "openvr_api.dll","vhrvr.dll","options.ini","vhrvr-runtime.log","vhrvr-wheel.log","sdl2.txt"};
string[] rootExt={".dat",".csv",".ttf",".mp4",".json",".evnt"};
int gameFiles=0;
foreach(var full in Directory.EnumerateFiles(game,"*",SearchOption.AllDirectories).OrderBy(x=>x,StringComparer.Ordinal)){
    string rel=Path.GetRelativePath(game,full).Replace('\\','/');
    string f=Path.GetFileName(full).ToLowerInvariant();
    if(rel.StartsWith(".") || skip.Contains(f) || rel.StartsWith("lib/")) continue;
    if(rel.Contains("/")){ if(!rel.ToLowerInvariant().StartsWith("data/")) continue; }
    else if(!rootExt.Any(x=>f.EndsWith(x))) continue;
    // GameMaker's Android runner looks bundle files up lowercased with spaces as underscores.
    string name="assets/"+rel.ToLowerInvariant().Replace(" ","_");
    if(have.Contains(name)) continue;
    string p=full;
    Add(name,()=>File.ReadAllBytes(p),!(f.EndsWith(".ogg")||f.EndsWith(".mp4")||f.EndsWith(".png")));
    gameFiles++;
}
if(gameFiles<10) throw new Exception("Too few game files found in "+game);

// Driver art (hands on the wheel, gloves and sleeves for every car), prebaked so the headset does no per-pixel work.
int art=0;
foreach(var p in Directory.GetFiles(Path.Combine(quest,"art"),"*.png").OrderBy(x=>x,StringComparer.Ordinal)){
    string q=p; Add("assets/vhrpaint_"+Path.GetFileName(p).ToLowerInvariant(),()=>File.ReadAllBytes(q),false); art++;
}
if(art<65) throw new Exception("Driver art missing: expected 65 PNGs in quest\\art, found "+art);
Add("lib/arm64-v8a/libvhrvr.so",()=>File.ReadAllBytes(Path.Combine(pkg,"bin","libvhrvr.so")),false);
Add("classes"+(dexCount+1)+".dex",()=>File.ReadAllBytes(Path.Combine(pkg,"bin","VHRQuest.dex")),true);
var aar=new ZipArchive(File.OpenRead(loader),ZipArchiveMode.Read);
var le=aar.GetEntry("jni/arm64-v8a/libopenxr_loader.so") ?? throw new Exception("OpenXR loader .aar has no arm64 lib");
Add("lib/arm64-v8a/libopenxr_loader.so",()=>ReadEntry(le),false);

// ------------------------------------------------------------------ write the aligned zip
uint[] crcT=new uint[256];
for(uint i=0;i<256;i++){uint c=i;for(int k=0;k<8;k++) c=(c&1)!=0?0xEDB88320u^(c>>1):c>>1;crcT[i]=c;}
uint Crc(byte[] b){uint c=0xFFFFFFFFu;foreach(byte x in b) c=crcT[(c^x)&0xFF]^(c>>8);return c^0xFFFFFFFFu;}
const ushort DosTime=0, DosDate=(ushort)(((2026-1980)<<9)|(1<<5)|1);
string tmp=outPath+".unsigned";
var cdir=new MemoryStream(); var cw=new BinaryWriter(cdir);
using(var fs=new FileStream(tmp,FileMode.Create,FileAccess.Write)){
    var w=new BinaryWriter(fs);
    foreach(var (name,getData,compress) in entries){
        byte[] raw=getData(); uint crc=Crc(raw); byte[] body=raw;
        if(compress){using var m=new MemoryStream();using(var d=new DeflateStream(m,CompressionLevel.Optimal,true)) d.Write(raw,0,raw.Length);body=m.ToArray();}
        byte[] nb=Encoding.UTF8.GetBytes(name);
        byte[] extra=Array.Empty<byte>();
        if(!compress){ // stored: 4-byte alignment, native libs on 16 KiB pages (zipalign-style 0xD935 field)
            long align=name.EndsWith(".so")?16384:4;
            long hdrEnd=fs.Position+30+nb.Length;
            long pad=(align-hdrEnd%align)%align;
            if(pad>0 && pad<4) pad+=align;
            if(pad>0){extra=new byte[pad];BitConverter.GetBytes((ushort)0xD935).CopyTo(extra,0);BitConverter.GetBytes((ushort)(pad-4)).CopyTo(extra,2);}
        }
        uint off=(uint)fs.Position; ushort method=(ushort)(compress?8:0);
        w.Write(0x04034b50u);w.Write((ushort)20);w.Write((ushort)0);w.Write(method);w.Write(DosTime);w.Write(DosDate);
        w.Write(crc);w.Write((uint)body.Length);w.Write((uint)raw.Length);w.Write((ushort)nb.Length);w.Write((ushort)extra.Length);
        w.Write(nb);w.Write(extra);w.Write(body);
        cw.Write(0x02014b50u);cw.Write((ushort)0x0314);cw.Write((ushort)20);cw.Write((ushort)0);cw.Write(method);cw.Write(DosTime);cw.Write(DosDate);
        cw.Write(crc);cw.Write((uint)body.Length);cw.Write((uint)raw.Length);cw.Write((ushort)nb.Length);cw.Write((ushort)0);cw.Write((ushort)0);
        cw.Write((ushort)0);cw.Write((ushort)0);cw.Write(0x81A40000u);cw.Write(off);cw.Write(nb);
    }
    w.Flush();
}
long cdOff=new FileInfo(tmp).Length;
byte[] cd=cdir.ToArray();
byte[] eocd=new byte[22];
BitConverter.GetBytes(0x06054b50u).CopyTo(eocd,0);
BitConverter.GetBytes((ushort)entries.Count).CopyTo(eocd,8);BitConverter.GetBytes((ushort)entries.Count).CopyTo(eocd,10);
BitConverter.GetBytes((uint)cd.Length).CopyTo(eocd,12);BitConverter.GetBytes((uint)cdOff).CopyTo(eocd,16);

// ------------------------------------------------------------------ APK Signature Scheme v2 (RSA-2048, PKCS#1 v1.5 SHA-256)
RSA rsa=RSA.Create(); byte[] certDer;
if(File.Exists(keyPath)){
    string pem=File.ReadAllText(keyPath);
    int ci=pem.IndexOf("-----BEGIN CERTIFICATE-----");
    if(ci<0) throw new Exception("Signing key file has no certificate: "+keyPath);
    rsa.ImportFromPem(pem.Substring(0,ci));
    string body=pem.Substring(ci).Replace("-----BEGIN CERTIFICATE-----","");
    body=body.Substring(0,body.IndexOf("-----END CERTIFICATE-----"));
    certDer=Convert.FromBase64String(string.Concat(body.Where(ch=>!char.IsWhiteSpace(ch))));
}else{
    rsa=RSA.Create(2048);
    var req=new CertificateRequest(new X500DistinguishedName("CN=VHR Quest local build"),rsa,HashAlgorithmName.SHA256,RSASignaturePadding.Pkcs1);
    var start=new DateTimeOffset(2026,1,1,0,0,0,TimeSpan.Zero);
    using var cert=req.CreateSelfSigned(start,start.AddYears(30));
    certDer=cert.RawData;
    File.WriteAllText(keyPath,rsa.ExportPkcs8PrivateKeyPem()+"\n"+cert.ExportCertificatePem()+"\n");
    ScriptMessage("Created your signing key: "+keyPath+" (keep it: updates must be signed with the same key)");
}
byte[] LP(params byte[][] parts){var m=new MemoryStream();int len=parts.Sum(p=>p.Length);m.Write(BitConverter.GetBytes(len));foreach(var p in parts) m.Write(p);return m.ToArray();}
byte[] U32(uint v)=>BitConverter.GetBytes(v);
byte[] Cat(params byte[][] parts)=>parts.SelectMany(p=>p).ToArray();
var digests=new List<byte[]>();
void DigestSection(Stream s,long len){
    var buf=new byte[1<<20];
    while(len>0){
        int n=(int)Math.Min(buf.Length,len); int got=0;
        while(got<n){int r=s.Read(buf,got,n-got);if(r<=0) throw new Exception("short read");got+=r;}
        var pre=new byte[5];pre[0]=0xa5;BitConverter.GetBytes((uint)n).CopyTo(pre,1);
        using var h=IncrementalHash.CreateHash(HashAlgorithmName.SHA256);h.AppendData(pre);h.AppendData(buf,0,n);digests.Add(h.GetHashAndReset());
        len-=n;
    }
}
using(var rs=new FileStream(tmp,FileMode.Open,FileAccess.Read)) DigestSection(rs,cdOff);
DigestSection(new MemoryStream(cd),cd.Length);
DigestSection(new MemoryStream(eocd),eocd.Length);
byte[] top;
using(var h=IncrementalHash.CreateHash(HashAlgorithmName.SHA256)){
    var pre=new byte[5];pre[0]=0x5a;BitConverter.GetBytes((uint)digests.Count).CopyTo(pre,1);h.AppendData(pre);foreach(var d in digests) h.AppendData(d);top=h.GetHashAndReset();
}
const uint ALG=0x0103;
byte[] signedData=Cat(LP(LP(U32(ALG),LP(top))),LP(LP(certDer)),LP());
byte[] sig=rsa.SignData(signedData,HashAlgorithmName.SHA256,RSASignaturePadding.Pkcs1);
byte[] pub=rsa.ExportSubjectPublicKeyInfo();
byte[] signer=Cat(LP(signedData),LP(LP(U32(ALG),LP(sig))),LP(pub));
byte[] value=LP(LP(signer));
var pair=new MemoryStream();pair.Write(BitConverter.GetBytes((ulong)(4+value.Length)));pair.Write(U32(0x7109871A));pair.Write(value);
ulong size=(ulong)(pair.Length+8+16);
var block=new MemoryStream();block.Write(BitConverter.GetBytes(size));block.Write(pair.ToArray());block.Write(BitConverter.GetBytes(size));block.Write(Encoding.ASCII.GetBytes("APK Sig Block 42"));
byte[] blk=block.ToArray();
BitConverter.GetBytes((uint)(cdOff+blk.Length)).CopyTo(eocd,16);
using(var o=new FileStream(outPath,FileMode.Create,FileAccess.Write)){
    using(var rs=new FileStream(tmp,FileMode.Open,FileAccess.Read)) rs.CopyTo(o);
    o.Write(blk);o.Write(cd);o.Write(eocd);
}
File.Delete(tmp);
ScriptMessage("Built "+outPath+" ("+entries.Count+" files: "+gameFiles+" game files, "+art+" driver art images)");
