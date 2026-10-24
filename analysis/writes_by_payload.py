import csv, sys, collections
rows=[l.rstrip('\n').split('\t') for l in open('analysis/gatt.tsv')]
w=[r for r in rows if r[3]=='0x12' and r[4]=='0xb003' and len(r)>5]
by=collections.OrderedDict()
for r in w: by.setdefault(r[5],[]).append(r[1][:8])
print(len(w),'writes,',len(by),'distinct payloads')
for p,ts in by.items():
    print(f'{p}\n   x{len(ts)}: '+' '.join(ts[:12])+(' ...' if len(ts)>12 else ''))
