import struct,sys,os
import numpy as np
from PIL import Image
src,dst,k=sys.argv[1],sys.argv[2],float(sys.argv[3]); dirs=sys.argv[4:]
n=0
for dname in dirs:
    base=os.path.join(src,dname)
    for r,_,fs in os.walk(base):
        if os.path.basename(r).lower()=='orig': continue
        for f in fs:
            if not f.lower().endswith('.tga'): continue
            p=os.path.join(r,f); d=open(p,'rb').read(); idl=d[0]; ct,it=d[1],d[2]; w,h=struct.unpack('<HH',d[12:16]); bpp=d[16]
            if it!=2 or ct!=0 or bpp not in (16,32): print('skip',p,it,bpp); continue
            off=18+idl; hdr=bytearray(d[:off])
            if bpp==16:
                a=np.frombuffer(d[off:off+w*h*2],'<u2').reshape(h,w)
                rgba=np.stack([((a>>10)&31)*255//31,((a>>5)&31)*255//31,(a&31)*255//31,(a>>15)*255],-1).astype(np.uint8)
            else:
                b=np.frombuffer(d[off:off+w*h*4],np.uint8).reshape(h,w,4); rgba=b[...,[2,1,0,3]]
            W,H=round(w*k),round(h*k)
            if bpp==16:
                c=np.asarray(Image.fromarray(rgba[...,:3],'RGB').resize((W,H),Image.LANCZOS)).astype(np.int32)
                al=np.asarray(Image.fromarray(rgba[...,3],'L').resize((W,H),Image.LANCZOS)).astype(np.int32)
                im=np.dstack([c,al])
            else:
                im=np.asarray(Image.fromarray(rgba,'RGBA').resize((W,H),Image.LANCZOS)).astype(np.int32)
            hdr[12:16]=struct.pack('<HH',W,H)
            if bpp==16:
                o=(((im[...,0]*31+127)//255)<<10)|(((im[...,1]*31+127)//255)<<5)|((im[...,2]*31+127)//255)|((im[...,3]>=128).astype(np.int32)<<15)
                data=o.astype('<u2').tobytes()
            else:
                data=im[...,[2,1,0,3]].astype(np.uint8).tobytes()
            q=os.path.join(dst,os.path.relpath(p,src)); os.makedirs(os.path.dirname(q),exist_ok=True)
            open(q,'wb').write(bytes(hdr)+data); n+=1
print('scaled',n)
