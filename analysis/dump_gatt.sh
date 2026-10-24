#!/bin/bash
# usage (in container): dump_gatt.sh <btsnoop> <out.tsv>
# columns: frame, time(phone-local as stored), direction, opcode, handle, value
tshark -r "$1" -Y "btatt.opcode==0x12 || btatt.opcode==0x52 || btatt.opcode==0x1b || btatt.opcode==0x1d || btatt.opcode==0x0b || btatt.opcode==0x0a" \
  -T fields -e frame.number -e frame.time_epoch -e hci_h4.direction -e btatt.opcode -e btatt.handle -e btatt.value 2>/dev/null \
 | awk -F'\t' '{printf "%s\t%s\t%s\t%s\t%s\t%s\n",$1,strftime("%H:%M:%S",$2,1)substr($2,index($2,"."),4),$3,$4,$5,$6}' > "$2"
