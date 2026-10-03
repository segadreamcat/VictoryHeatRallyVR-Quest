#!/usr/bin/env python3
"""Prebakes the driver art for the Quest build, so the headset does no per-pixel work at race start.

  gen_driver_art.py --art VHR-driver.png --out build/vhrpaint

Writes vhr-driver-clean.png (grey background removed) and one recoloured copy per car body sprite
(gloves and racing sleeves in that car's paint, see quest/tools/paint-table.json), exactly as the
in-game fallback code would. Needs Pillow (pip install pillow).
"""
import argparse, colorsys, json, math, os
from PIL import Image
def hue255(r,g,b): return colorsys.rgb_to_hsv(r/255,g/255,b/255)[0]*255
def mk(c): return (int(c[0]),int(c[1]),int(c[2]))
def merge(a,b,t): return tuple(int(a[i]+(b[i]-a[i])*t) for i in range(3))
def design(m):
    r,g,b=m;mx=max(m);mn=min(m);sat=0 if mx==0 else (mx-mn)/mx*255
    if sat<38: return 1
    h=hue255(r,g,b)
    if h<24 or h>=240: return 0
    if h<50: return 1
    if h<110: return 2
    if h<180: return 3
    return 4
INK=(20,20,30);WHITE=(245,245,245)
def scol(d,a,u,m,s):
    if a<7: return s if a>=2 else INK
    if d==0:
        fh=95+38*math.sin(u*7.3+1)+22*math.sin(u*17.1)+12*math.sin(u*31.7);dd=233-a
        if dd<fh:
            t=dd/max(1,fh)
            if t<0.55:
                k=0.55*(1-min(1,t*1.6));return (s[0]+(255-s[0])*k,s[1]+(240-s[1])*k,s[2]+(120-s[2])*k)
            return s
        return m
    if d==1:
        if 60<a<108:
            if a<64 or a>104: return s
            return INK if (math.floor((a-64)/11)+math.floor((u+1)*6.5))%2 else WHITE
        return m
    if d==2:
        z=(a/38)%2;c=((z if z<1 else 2-z)*2-1)*0.45;du=abs(u-c)
        if du<0.11: return s
        if du<0.16: return INK
        return m
    if d==3:
        au=abs(u)
        if 0.14<au<0.32: return s
        if 0.34<au<0.39: return WHITE
        return m
    if d==4:
        if a>20 and math.floor((a-abs(u)*55)/26)%2==0: return s
        return m
    return m
def shade(c,f):
    up=max(0,f-1);c=[min(255,v*f) for v in c];return tuple(int(v+(255-v)*up) for v in c)
def driver(m,s):
    o=base.copy();p=o.load();src=base.load()
    for (x0,y0,x1,y1) in [(255,55,445,285),(575,55,765,285)]:
        for y in range(y0,y1):
            for x in range(x0,x1):
                r,g,b,a=src[x,y]
                if a<16: continue
                mx,mn=max(r,g,b),min(r,g,b)
                if mx<31 or mx-mn<mx*0.3: continue
                hh=hue255(r,g,b)
                if 200<=hh<=250: t,ref=m,0.71
                elif 95<=hh<=150: t,ref=s,0.4
                else: continue
                p[x,y]=shade(t,(mx/255)/ref)+(a,)
    d=design(m)
    for y in range(340,H):
        for xm in range(0,361):
            along=-0.53*xm+0.848*y
            if along<228: continue
            for side in (0,1):
                x=W-1-xm if side else xm
                r,g,b,a=src[x,y]
                if a<16: continue
                mx,mn=max(r,g,b),min(r,g,b)
                if mx<70:
                    edge=False
                    for k in (1,2):
                        for dx,dy in ((-k,0),(k,0),(0,-k),(0,k)):
                            xx,yy=x+dx,y+dy
                            if not(0<=xx<W and 0<=yy<H) or src[xx,yy][3]<16: edge=True
                    if edge: continue
                c=scol(d,along-228,((0.848*xm+0.53*y)-396)/72,m,s)
                pink=mx-mn>mx*0.3 and hue255(r,g,b)>=200
                f=(mx/255)/(0.85 if pink else 0.94) if mx>=70 else 0.8
                f=max(0.55,min(1.12,f))
                p[x,y]=shade(c,f)+(a,)
    return o

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--art",required=True,help="driver artwork, 1024x559 PNG (same file the PC mod uses)")
    p.add_argument("--table",default=os.path.join(os.path.dirname(os.path.abspath(__file__)),"paint-table.json"))
    p.add_argument("--out",required=True)
    a=p.parse_args()
    global base,W,H
    base=Image.open(a.art).convert("RGBA");W,H=base.size
    if (W,H)!=(1024,559): raise SystemExit("Driver artwork must be 1024 x 559 pixels.")
    bp=base.load()
    for y in range(H):
        for x in range(W):
            r,g,b,al=bp[x,y]
            if abs(r-114)<=24 and abs(g-130)<=24 and abs(b-143)<=24: bp[x,y]=(r,g,b,0)
    os.makedirs(a.out,exist_ok=True)
    base.save(os.path.join(a.out,"vhr-driver-clean.png"),optimize=True)
    table=json.load(open(a.table))
    for i,(name,(m,s)) in enumerate(table.items()):
        driver(tuple(m),tuple(s)).save(os.path.join(a.out,name.lower()+".png"),optimize=True)
        print("  [%d/%d] %s" % (i+1,len(table),name),flush=True)
if __name__=="__main__":
    main()
