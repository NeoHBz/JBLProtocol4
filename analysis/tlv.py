import struct
def frames():
    for l in open('analysis/gatt.tsv'):
        r=l.rstrip('\n').split('\t')
        if len(r)>5 and r[4] in ('0xb003','0xb005'): yield r[1], ('APP' if r[2]=='0x00' else 'DEV'), bytes.fromhex(r[5])
def parse(b):
    # [magic u16 00dd? first byte may be 00/01][dd][type u16][seq u16][len u16][payload]
    if len(b)<8 or b[1]!=0xdd: return None
    typ,seq,ln=struct.unpack('<HHH',b[2:8]); return b[0],typ,seq,ln,b[8:8+ln]
def tlvs(p):
    i=0;out=[]
    while i+4<=len(p):
        t,l=struct.unpack('<HH',p[i:i+4]); out.append((t,p[i+4:i+4+l])); i+=4+l
    return out
if __name__=='__main__':
    import sys
    tag=int(sys.argv[1],16)
    for ts,d,b in frames():
        f=parse(b)
        if d=='DEV' and f and f[1] in (1,3) and len(f[4])>=2:
            for t,v in tlvs(f[4][2:]):
                if t==tag: print(ts[:8],f'type={f[1]}',v.hex())
