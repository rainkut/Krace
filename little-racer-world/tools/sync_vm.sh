#!/bin/bash
# Sync project to the VM and refresh the Godot import cache.
rsync -a --delete --exclude .godot --exclude build ~/Krace/little-racer-world/ contabo-vm:/root/lrw/ && \
ssh contabo-vm 'cd /root/lrw && nice /root/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --import >/dev/null 2>&1; echo imported'
