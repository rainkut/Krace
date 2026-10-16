class_name Data
extends RefCounted
## Static game content: bikes, upgrades, weapons, difficulty, races.

const BIKES := [
	{"id": "dustrunner", "name": "Dustrunner", "price": 0, "color": Color(0.92, 0.45, 0.12), "body": 0,
		"desc": "Honest all-rounder. Starts every career.",
		"speed": 0.50, "accel": 0.55, "handling": 0.55, "armor": 0.45, "nitro": 0.50, "weight": 0.50},
	{"id": "hornet", "name": "Hornet S", "price": 1800, "color": Color(0.95, 0.80, 0.10), "body": 1,
		"desc": "Light and twitchy. Great in the curves.",
		"speed": 0.55, "accel": 0.70, "handling": 0.80, "armor": 0.30, "nitro": 0.55, "weight": 0.30},
	{"id": "viper", "name": "Viper RX", "price": 3200, "color": Color(0.80, 0.10, 0.18), "body": 2,
		"desc": "Top-speed monster. Fragile if you crash.",
		"speed": 0.85, "accel": 0.65, "handling": 0.55, "armor": 0.30, "nitro": 0.70, "weight": 0.40},
	{"id": "boulder", "name": "Boulder 900", "price": 4200, "color": Color(0.25, 0.45, 0.75), "body": 3,
		"desc": "Heavy tourer. Shrugs off hits, shoves rivals aside.",
		"speed": 0.55, "accel": 0.40, "handling": 0.40, "armor": 0.85, "nitro": 0.45, "weight": 0.90},
	{"id": "ironclad", "name": "Ironclad", "price": 6500, "color": Color(0.30, 0.70, 0.38), "body": 4,
		"desc": "Armoured chopper with a big nitro tank.",
		"speed": 0.70, "accel": 0.55, "handling": 0.50, "armor": 0.75, "nitro": 0.90, "weight": 0.75},
]

const UPGRADES := [
	{"id": "engine", "name": "Engine", "desc": "Top speed and acceleration"},
	{"id": "brakes", "name": "Brakes", "desc": "Stopping power"},
	{"id": "tires", "name": "Tires", "desc": "Grip in curves and on dirt"},
	{"id": "armor", "name": "Armor", "desc": "Less damage taken"},
	{"id": "nitro", "name": "Nitro", "desc": "Bigger tank, faster refill"},
	{"id": "handling", "name": "Handling", "desc": "Sharper steering"},
]
const MAX_UPGRADE := 5

# reach = lateral reach in metres, cd = cooldown s, dmg = health damage, knock = lateral impulse, slow = speed loss factor
const WEAPONS := {
	"punch": {"name": "Punch", "reach": 2.5, "cd": 0.55, "dmg": 9.0, "knock": 7.0, "slow": 0.04, "dur": 0},
	"kick": {"name": "Kick", "reach": 2.7, "cd": 0.85, "dmg": 12.0, "knock": 12.0, "slow": 0.06, "dur": 0},
	"bat": {"name": "Bat", "reach": 3.0, "cd": 0.70, "dmg": 18.0, "knock": 11.0, "slow": 0.08, "dur": 8},
	"chain": {"name": "Chain", "reach": 3.6, "cd": 0.80, "dmg": 16.0, "knock": 9.0, "slow": 0.10, "dur": 8},
	"pipe": {"name": "Pipe", "reach": 2.9, "cd": 0.95, "dmg": 26.0, "knock": 15.0, "slow": 0.14, "dur": 6},
}

const DIFFICULTY := [
	{"name": "Easy", "ai_speed": 0.92, "aggr": 0.6, "mistake": 1.6, "dmg_taken": 0.7, "rubber": 0.03},
	{"name": "Normal", "ai_speed": 0.98, "aggr": 1.0, "mistake": 1.0, "dmg_taken": 1.0, "rubber": 0.05},
	{"name": "Hard", "ai_speed": 1.04, "aggr": 1.4, "mistake": 0.5, "dmg_taken": 1.12, "rubber": 0.06},
]

# per archetype multipliers: top speed, accel, health, damage dealt, aggression 0..1, mass
const ARCH := {
	"balanced": {"label": "Balanced", "spd": 1.00, "acc": 1.00, "hp": 100.0, "dmg": 1.0, "aggr": 0.35, "mass": 1.0, "color": Color(0.30, 0.55, 0.85)},
	"speed": {"label": "Speed", "spd": 1.07, "acc": 1.05, "hp": 75.0, "dmg": 0.8, "aggr": 0.12, "mass": 0.8, "color": Color(0.95, 0.85, 0.2)},
	"heavy": {"label": "Heavy", "spd": 0.93, "acc": 0.85, "hp": 150.0, "dmg": 1.4, "aggr": 0.5, "mass": 1.5, "color": Color(0.45, 0.35, 0.25)},
	"aggressive": {"label": "Aggressive", "spd": 1.00, "acc": 1.05, "hp": 95.0, "dmg": 1.25, "aggr": 0.95, "mass": 1.1, "color": Color(0.85, 0.15, 0.15)},
	"defensive": {"label": "Defensive", "spd": 0.99, "acc": 0.95, "hp": 120.0, "dmg": 1.0, "aggr": 0.3, "mass": 1.2, "color": Color(0.35, 0.7, 0.4)},
}

const RIVAL_NAMES := ["Rex Hollow", "Juno Vale", "Boulder Bram", "Mara Slate", "Dutch Karrow", "Skye Ember", "Tank Orlo", "Vega Lund", "Nico Brask", "Ash Calder"]

const MODES := {
	"race": "Race - finish on the podium",
	"knockout": "Knockout - last rider is out every 25 s",
	"time": "Time Trial - beat the clock",
	"rival": "Rival Battle - beat one tougher rider",
	"survival": "Survival - outlast the pack",
	"highway": "Highway Run - score near misses",
	"revenge": "Revenge - take down the rider who wrecked you",
}

# seg: [length, curve(rad/m, + = left), slope amp, feature, env]; generator fills in when "segs" is absent.
const RACES := [
	{"id": "r1", "name": "Dustline Opener", "mode": "race", "len": 10000, "theme": 0, "seed": 11, "req": 0,
		"rivals": ["balanced", "speed", "heavy", "aggressive", "defensive"], "traffic": 0.55, "reward": 700, "rep": 25,
		"blurb": "Ten kilometres of open highway. Traffic, a dirt shortcut, and five riders who all want your spot.", "shortcut": true, "need_place": 3},
	{"id": "r2", "name": "Neon Overpass", "mode": "knockout", "len": 8000, "theme": 1, "seed": 23, "req": 25,
		"rivals": ["aggressive", "balanced", "speed", "heavy", "defensive"], "traffic": 0.7, "reward": 900, "rep": 35,
		"blurb": "City lights, tight traffic. Every 25 seconds the last rider is out.", "shortcut": true, "need_place": 0},
	{"id": "r3", "name": "Clockwork Canyon", "mode": "time", "len": 7500, "theme": 2, "seed": 37, "req": 60, "target": 150,
		"rivals": [], "traffic": 0.4, "reward": 1000, "rep": 30,
		"blurb": "Just you and the clock. Checkpoints add time.", "shortcut": true, "need_place": 0},
	{"id": "r4", "name": "Rival: Mara Slate", "mode": "rival", "len": 8000, "theme": 0, "seed": 41, "req": 95,
		"rivals": ["speed"], "traffic": 0.5, "reward": 1400, "rep": 45, "rival_boost": 1.04,
		"blurb": "One rider, tuned harder than anyone you've met. Win and take her respect.", "shortcut": true, "need_place": 1},
	{"id": "r5", "name": "Pileup Alley", "mode": "survival", "len": 9000, "theme": 1, "seed": 53, "req": 140, "survive": 120,
		"rivals": ["aggressive", "aggressive", "heavy", "aggressive"], "traffic": 0.8, "reward": 1600, "rep": 50,
		"blurb": "Stay alive for two minutes while the pack hunts you.", "shortcut": false, "need_place": 0},
	{"id": "r6", "name": "Interstate Rush", "mode": "highway", "len": 9000, "theme": 2, "seed": 67, "req": 190, "score_goal": 4000, "limit": 170,
		"rivals": [], "traffic": 1.1, "reward": 1800, "rep": 50,
		"blurb": "Dense traffic, no rivals. Thread the needle: 4000 points before time runs out.", "shortcut": false, "need_place": 0},
	{"id": "r7", "name": "Revenge: Tank Orlo", "mode": "revenge", "len": 9000, "theme": 0, "seed": 79, "req": 240,
		"rivals": ["heavy", "balanced", "defensive"], "traffic": 0.6, "reward": 2600, "rep": 80, "target_rival": 0,
		"blurb": "Tank Orlo forced you off the road last season. Knock him out before the line.", "shortcut": true, "need_place": 0},
	{"id": "r8", "name": "Marine Drive to Worli", "mode": "race", "len": 12000, "theme": 1, "seed": 91, "req": 280, "route": "mumbai",
		"rivals": ["speed", "aggressive", "balanced", "heavy", "defensive"], "traffic": 0.9, "reward": 3200, "rep": 90,
		"blurb": "A real route: Marine Drive, Haji Ali, the Bandra-Worli Sea Link. Mapped from OpenStreetMap.", "shortcut": false, "need_place": 2},
]

static func bike(id: String) -> Dictionary:
	for b in BIKES:
		if b["id"] == id:
			return b
	return BIKES[0]

static func upgrade_cost(level: int) -> int:
	return int(220.0 * pow(1.55, level))

## Resolve real-unit stats for a bike with upgrade levels {engine:n,...}.
static func stats(bike_id: String, upg: Dictionary) -> Dictionary:
	var b := bike(bike_id)
	var lv := func(k: String) -> float: return float(upg.get(k, 0)) / float(MAX_UPGRADE)
	var spd: float = clampf(b["speed"] + 0.30 * lv.call("engine"), 0.0, 1.3)
	var acc: float = clampf(b["accel"] + 0.30 * lv.call("engine"), 0.0, 1.3)
	var hnd: float = clampf(b["handling"] + 0.30 * lv.call("handling") + 0.10 * lv.call("tires"), 0.0, 1.3)
	var arm: float = clampf(b["armor"] + 0.30 * lv.call("armor"), 0.0, 1.2)
	var nit: float = clampf(b["nitro"] + 0.35 * lv.call("nitro"), 0.0, 1.3)
	return {
		"vmax": 44.0 + 22.0 * spd, "acc": 9.0 + 9.0 * acc, "brake": 30.0 + 10.0 * (0.4 + lv.call("brakes") * 1.5),
		"grip": 26.0 + 20.0 * hnd, "dirt": 0.55 + 0.35 * lv.call("tires") + 0.2 * hnd,
		"dmg_mult": 1.35 - 0.6 * arm, "health": 90.0 + 40.0 * arm, "mass": 0.7 + 0.8 * b["weight"],
		"nitro_cap": 70.0 + 50.0 * nit, "nitro_regen": 1.0 + 2.5 * nit,
		"bars": {"Speed": spd, "Accel": acc, "Handling": hnd, "Armor": arm, "Nitro": nit, "Weight": b["weight"]},
	}
