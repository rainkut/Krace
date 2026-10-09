#!/bin/bash
# LRW_DRIVER_ARGS="--rendering-driver vulkan --rendering-method mobile" LRW_QUALITY=high  -> Mobile/High via lavapipe
# usage: shoot.sh <scene> '<launch json>' <res WxH> <frame:png> ...   (runs on contabo-vm in /root/lrw)
scene=$1; launch=$2; res=$3; shift 3
cd /root/lrw && nice xvfb-run -a -s "-screen 0 ${res}x24" /root/godot/Godot_v4.7.2-stable_linux.x86_64 --audio-driver Dummy ${LRW_DRIVER_ARGS:---rendering-driver opengl3 --rendering-method gl_compatibility} --resolution $res -s tools/shot.gd -- "$scene" "$launch" "$@" 2>&1 | grep -v -E "^$|Godot Engine|OpenGL API|GODOT_SILENCE|as .root|WARNING: Started|V-Sync|set_use_vsync|setup2"
