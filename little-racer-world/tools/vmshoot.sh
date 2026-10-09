#!/bin/bash
# usage: vmshoot.sh <scene> '<launch json>' <WxH> <frame:/tmp/x.png>...  -> runs on VM, copies pngs to /tmp/lrw_shots/
mkdir -p /tmp/lrw_shots
ssh contabo-vm "bash /root/lrw/tools/shoot.sh '$1' '$2' $3 ${*:4}" 2>&1 | grep -v -E "leaked|^   at:|still in use" | tail -30
for a in "${@:4}"; do f=${a#*:}; [[ $f == *.png ]] && scp -q contabo-vm:$f /tmp/lrw_shots/ ; done
