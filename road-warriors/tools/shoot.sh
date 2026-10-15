#!/bin/bash
# usage (on contabo, in /root/rw): shoot.sh '<user args for main>' <frame:png|frame@method> ...
args=$1; shift
cd /root/rw && nice xvfb-run -a -s "-screen 0 1280x720x24" /root/godot/Godot_v4.7.2-stable_linux.x86_64 --audio-driver Dummy --rendering-driver opengl3 --rendering-method gl_compatibility --resolution 1280x720 -s tools/shot.gd -- "$@" $args 2>&1 | grep -E "shot|ERROR|SCRIPT" | head -20
