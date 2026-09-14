"""Static ARM64 ADRP/add references; reads installed binary without executing it."""
import struct
from pathlib import Path
b=Path('/Applications/EmotivApps/EMOTIV Launcher.app/Contents/MacOS/CortexService').read_bytes()
n=struct.unpack_from('>I',b,4)[0]
for i in range(n):
 cpu,sub,off,size,align=struct.unpack_from('>IIIII',b,8+20*i)
 if cpu==0x100000c: break
m=b[off:off+size];p=32
for _ in range(struct.unpack_from('<I',m,16)[0]):
 cmd,sz=struct.unpack_from('<II',m,p)
 if cmd==0x19:
  for j in range(struct.unpack_from('<I',m,p+64)[0]):
   s=p+72+j*80
   if m[s:s+16].rstrip(b'\0')==b'__text':
    addr,length,fo=struct.unpack_from('<QQI',m,s+32)
 p+=sz
for k in range(0,length-20,4):
 w=struct.unpack_from('<I',m,fo+k)[0]
 if w&0x9f000000!=0x90000000:continue
 imm=((w>>5)&0x7ffff)*4+((w>>29)&3)
 if imm&(1<<20):imm-=1<<21
 page=((addr+k)&~4095)+(imm<<12)
 if page!=0x1033e5000:continue
 for d in range(4,20,4):
  v=struct.unpack_from('<I',m,fo+k+d)[0]
  if v&0xffc00000==0x91000000 and (v>>5)&31==w&31 and (v>>10)&4095==0xf10:
   print(hex(addr+k),hex(addr+k+d))
