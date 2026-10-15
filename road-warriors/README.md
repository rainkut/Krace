# Road Warriors
Original motorcycle combat racer (Godot 4.7, GDScript, Android landscape). Inspired by the genre; no third-party IP.

- 5 bikes, 6 upgrades, 7 races/modes (race, knockout, time trial, rival, survival, highway, revenge), 3 difficulties.
- Road-relative arcade model shared by player, AI and traffic. Track = sampled centreline built from segments.
- Debug: Settings > Debug tools; F1 overlay, F2 god, F3 near finish, F4 crash, F5 nitro, F6 score.
- Headless sim: `godot --headless --fixed-fps 60 -- --sim=r1 --fresh [--diff=0..2]` (autopilot player, prints result).
- Screenshots: `tools/shoot.sh '--race=r1 --auto --fresh' 600:out.png` (xvfb, on contabo).
- Build only on contabo-vm (`--import`, then `--export-debug Android build/RoadWarriors-debug.apk`).
