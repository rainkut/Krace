#!/bin/bash
# Runs on the VM in /root/lrw: bash tools/lap_vm.sh <race_id> <noise|throttle_only> [seconds]
cd /root/lrw
nice timeout 900 /root/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . -s tools/lap_test.gd -- "$@" 2>&1 | grep -E "LAPTEST|SCRIPT ERROR|Parse Error|ERROR"
