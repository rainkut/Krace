#!/bin/bash
# usage: tools/audit_vm.sh <race_id> [verbose]   -> runs collision_audit on the VM (xvfb + GL compat so meshes exist)
cd /root/lrw && nice timeout 600 xvfb-run -a -s "-screen 0 800x600x24" /root/godot/Godot_v4.7.2-stable_linux.x86_64 --audio-driver Dummy --rendering-driver opengl3 --rendering-method gl_compatibility -s tools/collision_audit.gd -- "$@" 2>&1 | grep -E "AUDIT|SCRIPT ERROR|Parse Error"
