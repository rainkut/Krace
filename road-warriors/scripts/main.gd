extends Node
## Game flow + all menus (built in code). States: MAIN_MENU, GARAGE, RACE_SELECT, SETTINGS, COUNTDOWN,
## RACING, PAUSED, FINISHED, GAME_OVER.

const ACC := Color(1.0, 0.55, 0.12)
const TEXT := Color(0.95, 0.95, 0.93)
const DIM := Color(0.66, 0.68, 0.74)
const PANEL := Color(0.08, 0.09, 0.13, 0.94)
const GOOD := Color(0.4, 0.9, 0.5)
const BAD := Color(1.0, 0.4, 0.35)

var gstate := "MAIN_MENU"
var ui: Control
var bg: ColorRect
var hud_layer: CanvasLayer
var menu_layer: CanvasLayer
var race: Race
var hud: HUD
var touch: TouchControls
var cur_def: Dictionary = {}
var sel_race := 0
var garage_idx := 0
var rebind_action := ""
var rebind_btn: Button
var settings_back := Callable()
var confirm_reset := false
var prev_holder: Node3D
var prev_bike: Racer
var prev_vp: SubViewport
var prev_angle := 0.6
var sim_id := ""
var want_auto := false
var kicktest := false
var sim_log_t := 0.0
var theme_res: Theme

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	apply_fps()
	theme_res = _make_theme()
	bg = ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bgl := CanvasLayer.new()
	bgl.layer = -5
	add_child(bgl)
	bgl.add_child(bg)
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	menu_layer = CanvasLayer.new()
	menu_layer.layer = 10
	add_child(menu_layer)
	ui = Control.new()
	ui.theme = theme_res
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(ui)
	var arg_race := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sim="):
			sim_id = a.substr(6)
		elif a.begins_with("--race="):
			arg_race = a.substr(7)
		elif a.begins_with("--diff="):
			Save.d["set"]["diff"] = int(a.substr(7))
		elif a == "--kicktest":
			kicktest = true
		elif a == "--auto":
			want_auto = true
		elif a == "--fresh":
			Save.d = Save.defaults()
		elif a.begins_with("--rep="):
			Save.d["rep"] = int(a.substr(6))
	if sim_id != "" or arg_race != "":
		var rid := sim_id if sim_id != "" else arg_race
		if rid == "daily":
			start_race(Data.daily_def(), sim_id != "" or want_auto)
			return
		for rd in Data.RACES:
			if rd["id"] == rid:
				start_race(rd, sim_id != "" or want_auto)
				return
	show_menu()

# ---------------------------------------------------------------- theme + helpers
func _sb(col: Color, border := Color(0, 0, 0, 0), bw := 0, rad := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(rad)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 22
	t.set_stylebox("normal", "Button", _sb(Color(0.15, 0.16, 0.22), Color(0.3, 0.32, 0.4), 2))
	t.set_stylebox("hover", "Button", _sb(Color(0.22, 0.24, 0.33), ACC, 2))
	t.set_stylebox("pressed", "Button", _sb(ACC, ACC, 2))
	t.set_stylebox("disabled", "Button", _sb(Color(0.1, 0.1, 0.13), Color(0.18, 0.18, 0.22), 2))
	t.set_stylebox("focus", "Button", _sb(Color(0, 0, 0, 0), ACC, 3))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color(0.1, 0.05, 0.0))
	t.set_color("font_disabled_color", "Button", Color(0.4, 0.4, 0.45))
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", _sb(PANEL, Color(0.3, 0.32, 0.4), 2, 12))
	return t

func _lbl(txt: String, size := 22, col := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l

func _btn(txt: String, cb: Callable, min_w := 0, size := 24) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(min_w, 52)
	b.pressed.connect(func() -> void:
		Sfx.play("click", 0.7)
		cb.call())
	return b

func _clear() -> void:
	for c in ui.get_children():
		c.queue_free()
	prev_holder = null
	prev_bike = null

func _full(parent: Node) -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 40)
	m.add_theme_constant_override("margin_right", 40)
	m.add_theme_constant_override("margin_top", 28)
	m.add_theme_constant_override("margin_bottom", 28)
	parent.add_child(m)
	return m

func _bar_row(name: String, v: float, col := ACC) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var l := _lbl(name, 20, DIM)
	l.custom_minimum_size = Vector2(110, 0)
	h.add_child(l)
	var pb := ProgressBar.new()
	pb.custom_minimum_size = Vector2(190, 18)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.show_percentage = false
	pb.min_value = 0.0
	pb.max_value = 1.3
	pb.value = v
	pb.add_theme_stylebox_override("fill", _sb(col, Color(0, 0, 0, 0), 0, 4))
	pb.add_theme_stylebox_override("background", _sb(Color(0.15, 0.16, 0.2), Color(0, 0, 0, 0), 0, 4))
	h.add_child(pb)
	return h

func _money_bar() -> Label:
	return _lbl("$%d     REP %d" % [Save.d["money"], Save.d["rep"]], 24, ACC)

func _make_preview(sz: Vector2) -> SubViewportContainer:
	var c := SubViewportContainer.new()
	c.stretch = true
	c.custom_minimum_size = sz
	prev_vp = SubViewport.new()
	prev_vp.own_world_3d = true
	prev_vp.transparent_bg = true
	prev_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	c.add_child(prev_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.8)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	prev_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	prev_vp.add_child(sun)
	var cam := Camera3D.new()
	prev_vp.add_child(cam)
	cam.look_at_from_position(Vector3(2.4, 1.5, 3.0), Vector3(0, 0.75, 0))
	prev_holder = Node3D.new()
	prev_vp.add_child(prev_holder)
	return c

func _set_preview(bike_id: String) -> void:
	if prev_holder == null:
		return
	if prev_bike != null:
		prev_bike.queue_free()
	var b := Data.bike(bike_id)
	prev_bike = Racer.new()
	prev_bike.setup({"name": "", "player": true, "color": b["color"], "body": b["body"], "stats": Data.stats(bike_id, Save.bike_upg(bike_id))})
	prev_holder.add_child(prev_bike)
	var cu: Dictionary = Save.d["custom"].get(bike_id, {})
	if not cu.is_empty():
		var pi := int(cu.get("paint", -1))
		prev_bike.apply_paint(Data.PAINTS[pi] if pi >= 0 and pi < Data.PAINTS.size() else Color(0, 0, 0, 0), Data.DECALS[clampi(int(cu.get("decal", 0)), 0, Data.DECALS.size() - 1)])
	for a in [prev_bike.arm_l, prev_bike.arm_r]:
		a.rotation = Vector3(-1.15, 0, 0)
	for l in [prev_bike.leg_l, prev_bike.leg_r]:
		l.rotation = Vector3(-0.55, 0, 0)

func _process(dt: float) -> void:
	if prev_holder != null and is_instance_valid(prev_holder):
		prev_angle += dt * 0.6
		prev_holder.rotation.y = prev_angle * 0.5
		if prev_bike != null and is_instance_valid(prev_bike) and prev_bike.wheel_f != null:
			prev_bike.wheel_f.rotation.x -= dt * 3.0
			prev_bike.wheel_r.rotation.x -= dt * 3.0
	if race != null and gstate in ["COUNTDOWN", "RACING"]:
		gstate = "COUNTDOWN" if race.state == Race.RState.COUNTDOWN else "RACING"
		if sim_id != "":
			sim_log_t += dt
			if sim_log_t > 15.0:
				sim_log_t = 0.0
				print("[sim] t=%.0f s=%.0f v=%.0f place=%d hp=%.0f traffic=%d" % [race.time, race.player.s, race.player.v, race.player.place, race.player.health, race.traffic.size()])
			if race.time > 900.0:
				print("[sim] TIMEOUT")
				get_tree().quit(2)

# ---------------------------------------------------------------- screens
func _show_bg(on: bool) -> void:
	bg.visible = on

func show_menu() -> void:
	gstate = "MAIN_MENU"
	_free_race()
	_show_bg(true)
	_clear()
	Sfx.music(true)
	var m := _full(ui)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 40)
	m.add_child(h)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.custom_minimum_size = Vector2(520, 0)
	h.add_child(v)
	v.add_theme_constant_override("separation", 10)
	v.add_child(_lbl("ROAD", 84, ACC))
	v.add_child(_lbl("WARRIORS", 84, TEXT))
	v.add_child(_lbl("Outrun. Outfight. Outlast.", 26, DIM))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 4)
	v.add_child(sp)
	var dd: Dictionary = Save.d["daily"]
	var dkey := Data.daily_key()
	var dtag := "  [DONE]" if int(dd.get("claimed", 0)) == dkey else "  [NEW]"
	v.add_child(_btn("DAILY CHALLENGE" + dtag, show_daily, 340, 26))
	v.add_child(_btn("CAREER", show_race_select, 340, 30))
	v.add_child(_btn("GARAGE", show_garage, 340, 30))
	v.add_child(_btn("SETTINGS", func() -> void: show_settings(show_menu), 340, 30))
	v.add_child(_btn("CREDITS", show_credits, 340, 30))
	if OS.get_name() != "Android" and OS.get_name() != "iOS" and OS.get_name() != "Web":
		v.add_child(_btn("QUIT", func() -> void: get_tree().quit(), 340, 30))
	var sp2 := Control.new()
	sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp2)
	v.add_child(_money_bar())
	var pv := _make_preview(Vector2(640, 560))
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(pv)
	_set_preview(Save.d["bike"])

func show_daily() -> void:
	gstate = "DAILY"
	_free_race()
	_show_bg(true)
	_clear()
	var dr := Data.daily_def()
	var dd: Dictionary = Save.d["daily"]
	var key := int(dr["date"])
	var m := _full(ui)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_child(c)
	var pc := PanelContainer.new()
	c.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(620, 0)
	pc.add_child(v)
	v.add_child(_lbl("DAILY CHALLENGE", 44, ACC, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_lbl("%d-%02d-%02d" % [key / 10000, (key / 100) % 100, key % 100], 22, DIM, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_lbl(Data.MODES[dr["mode"]], 26, TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var theme_names := ["Countryside", "City", "Desert", "Graveyard"]
	v.add_child(_lbl("%.1f km   %s   %s, %s   Rivals %d" % [float(dr["len"]) / 1000.0, theme_names[int(dr["theme"])], String(dr["tod"]).capitalize(), String(dr["weather"]).capitalize(), dr["rivals"].size()], 20, TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var claimed := int(dd.get("claimed", 0)) == key
	v.add_child(_lbl("Reward  $%d   (once a day)" % int(dr["reward"]) if not claimed else "Today's reward claimed - come back tomorrow", 24, GOOD if not claimed else DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var best: Dictionary = dd.get("best", {})
	if int(best.get("date", 0)) == key:
		v.add_child(_lbl("Today's best   %s   score %d" % [_fmt_time(float(best.get("time", 0))), int(best.get("score", 0))], 22, TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_lbl("Streak  %d day(s)" % int(dd.get("streak", 0)), 20, DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	v.add_child(hb)
	hb.add_child(_btn("START", func() -> void: start_race(dr, false), 260, 28))
	hb.add_child(_btn("BACK", show_menu, 160, 24))

func show_race_select() -> void:
	gstate = "RACE_SELECT"
	_free_race()
	_show_bg(true)
	_clear()
	var m := _full(ui)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	m.add_child(root)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	root.add_child(top)
	top.add_child(_lbl("CAREER", 44, ACC))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var diff_i := int(Save.setting("diff"))
	for i in 3:
		var b := _btn(Data.DIFFICULTY[i]["name"], func() -> void:
			Save.set_setting("diff", i)
			show_race_select(), 120, 20)
		b.disabled = i == diff_i
		top.add_child(b)
	top.add_child(_money_bar())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	root.add_child(body)
	var sc := SmoothScroll.new()
	sc.custom_minimum_size = Vector2(560, 0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(lv)
	for i in Data.RACES.size():
		var rd: Dictionary = Data.RACES[i]
		var locked := false
		var done: Dictionary = Save.d["done"].get(rd["id"], {})
		var tag := "LOCKED  rep %d" % rd["req"] if locked else ("CLEARED" if done.get("win", false) else "NEW")
		var b2 := _btn("%s   [%s]   %s" % [rd["name"], String(rd["mode"]).to_upper(), tag], func() -> void:
			sel_race = i
			show_race_select(), 540, 20)
		b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b2.disabled = i == sel_race
		lv.add_child(b2)
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(pc)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 10)
	pc.add_child(dv)
	var rd2: Dictionary = Data.RACES[sel_race]
	var locked2 := false
	dv.add_child(_lbl(rd2["name"], 36, ACC))
	dv.add_child(_lbl(Data.MODES[rd2["mode"]], 22, TEXT))
	var blurb := _lbl(rd2["blurb"], 20, DIM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(500, 0)
	dv.add_child(blurb)
	var theme_names := ["Countryside", "City", "Desert", "Graveyard"]
	var wx: String = String(Race.WEATHER.get(rd2["id"], "clear")).capitalize()
	var tdn: String = String(Race.TOD.get(rd2["id"], "day")).capitalize()
	dv.add_child(_lbl("Distance   %.1f km      Setting   %s      %s, %s" % [float(rd2["len"]) / 1000.0, theme_names[int(rd2["theme"])], tdn, wx], 20))
	dv.add_child(_lbl("Rivals   %d      Traffic   %s      Shortcut   %s" % [rd2["rivals"].size(), ["light", "medium", "heavy", "heavy"][clampi(int(float(rd2["traffic"]) * 2.5), 0, 3)], "yes" if rd2["shortcut"] else "no"], 20))
	dv.add_child(_lbl("Reward   $%d   +%d rep" % [rd2["reward"], rd2["rep"]], 22, GOOD))
	var dn: Dictionary = Save.d["done"].get(rd2["id"], {})
	if dn.has("place"):
		dv.add_child(_lbl("Best   P%d   %s" % [dn["place"], _fmt_time(float(dn.get("time", 0)))], 20, DIM))
	var spx := Control.new()
	spx.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dv.add_child(spx)
	var go := _btn("START RACE" if not locked2 else "LOCKED - need %d rep" % rd2["req"], func() -> void: start_race(rd2, false), 340, 30)
	go.disabled = locked2
	dv.add_child(go)
	root.add_child(_btn("BACK", show_menu, 160))

func _fmt_time(t: float) -> String:
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]

func show_garage() -> void:
	gstate = "GARAGE"
	_free_race()
	_show_bg(true)
	_clear()
	garage_idx = clampi(garage_idx, 0, Data.BIKES.size() - 1)
	var b: Dictionary = Data.BIKES[garage_idx]
	var bid: String = b["id"]
	var owned: bool = (Save.d["owned"] as Array).has(bid)
	var m := _full(ui)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	m.add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	top.add_child(_lbl("GARAGE", 44, ACC))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	top.add_child(_money_bar())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	root.add_child(body)
	# left: bike info
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.custom_minimum_size = Vector2(350, 0)
	body.add_child(left)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	left.add_child(nav)
	nav.add_child(_btn("<", func() -> void:
		garage_idx = (garage_idx + Data.BIKES.size() - 1) % Data.BIKES.size()
		show_garage(), 60))
	var nm := _lbl(b["name"], 34, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(nm)
	nav.add_child(_btn(">", func() -> void:
		garage_idx = (garage_idx + 1) % Data.BIKES.size()
		show_garage(), 60))
	var dsc := _lbl(b["desc"], 19, DIM)
	dsc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dsc.custom_minimum_size = Vector2(340, 0)
	left.add_child(dsc)
	var stt := Data.stats(bid, Save.bike_upg(bid))
	for k in stt["bars"]:
		left.add_child(_bar_row(k, stt["bars"][k]))
	var status := ""
	if Save.d["bike"] == bid:
		status = "EQUIPPED"
	elif owned:
		status = "OWNED"
	else:
		status = "$%d" % b["price"]
	left.add_child(_lbl(status, 28, GOOD if owned else ACC))
	if owned and Save.d["bike"] != bid:
		left.add_child(_btn("EQUIP", func() -> void:
			Save.d["bike"] = bid
			Save.write()
			show_garage(), 300))
	elif not owned:
		var bb := _btn("BUY  $%d" % b["price"], func() -> void:
			Save.d["money"] -= int(b["price"])
			(Save.d["owned"] as Array).append(bid)
			Save.d["bike"] = bid
			Save.write()
			Sfx.play("pickup")
			show_garage(), 300)
		bb.disabled = int(Save.d["money"]) < int(b["price"])
		left.add_child(bb)
	# middle: preview
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 8)
	body.add_child(mid)
	var pv := _make_preview(Vector2(220, 260))
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(pv)
	_set_preview(bid)
	if owned:
		var cu: Dictionary = Save.d["custom"].get(bid, {})
		mid.add_child(_lbl("PAINT", 18, DIM, HORIZONTAL_ALIGNMENT_CENTER))
		var pr := HFlowContainer.new()
		pr.alignment = FlowContainer.ALIGNMENT_CENTER
		pr.add_theme_constant_override("h_separation", 6)
		mid.add_child(pr)
		var stock := _btn("STOCK", func() -> void:
			cu.erase("paint")
			Save.d["custom"][bid] = cu
			Save.write()
			show_garage(), 0, 16)
		stock.disabled = not cu.has("paint")
		pr.add_child(stock)
		for pi in Data.PAINTS.size():
			var pb := Button.new()
			pb.custom_minimum_size = Vector2(46, 46)
			var sel := int(cu.get("paint", -1)) == pi
			for stn in ["normal", "hover", "pressed", "focus"]:
				pb.add_theme_stylebox_override(stn, _sb(Data.PAINTS[pi], Color.WHITE if sel else Color(0, 0, 0, 0.6), 4 if sel else 2, 8))
			pb.pressed.connect(func() -> void:
				cu["paint"] = pi
				Save.d["custom"][bid] = cu
				Save.write()
				Sfx.play("click")
				show_garage())
			pr.add_child(pb)
		mid.add_child(_lbl("DECAL", 18, DIM, HORIZONTAL_ALIGNMENT_CENTER))
		var dr := HFlowContainer.new()
		dr.alignment = FlowContainer.ALIGNMENT_CENTER
		dr.add_theme_constant_override("h_separation", 6)
		mid.add_child(dr)
		for di in Data.DECALS.size():
			var db := _btn(Data.DECALS[di] if Data.DECALS[di] != "" else "NONE", func() -> void:
				cu["decal"] = di
				Save.d["custom"][bid] = cu
				Save.write()
				Sfx.play("click")
				show_garage(), 0, 18)
			db.disabled = int(cu.get("decal", 0)) == di
			dr.add_child(db)
	# right: upgrades
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(430, 0)
	body.add_child(pc)
	var uv := VBoxContainer.new()
	uv.add_theme_constant_override("separation", 10)
	pc.add_child(uv)
	uv.add_child(_lbl("UPGRADES", 28, ACC))
	if not owned:
		uv.add_child(_lbl("Buy this bike to tune it.", 20, DIM))
	else:
		var upg := Save.bike_upg(bid)
		for u in Data.UPGRADES:
			var uid: String = u["id"]
			var lv := int(upg.get(uid, 0))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			var col := VBoxContainer.new()
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var nr := HBoxContainer.new()
			nr.add_theme_constant_override("separation", 14)
			nr.add_child(_lbl(u["name"], 22))
			nr.add_child(_lbl("■".repeat(lv) + "□".repeat(Data.MAX_UPGRADE - lv), 18, ACC))
			col.add_child(nr)
			col.add_child(_lbl(String(u["desc"]), 15, DIM))
			row.add_child(col)
			if lv >= Data.MAX_UPGRADE:
				row.add_child(_lbl("MAX", 22, GOOD))
			else:
				var cost := Data.upgrade_cost(lv)
				var ub := _btn("$%d" % cost, func() -> void:
					Save.d["money"] -= cost
					upg[uid] = lv + 1
					Save.write()
					Sfx.play("pickup")
					show_garage(), 120, 20)
				ub.disabled = int(Save.d["money"]) < cost
				row.add_child(ub)
			uv.add_child(row)
	root.add_child(_btn("BACK", show_menu, 160))

func apply_fps() -> void:
	Engine.max_fps = int(Save.setting("fps"))

func show_settings(back: Callable) -> void:
	gstate = "SETTINGS"
	settings_back = back
	_clear()
	rebind_action = ""
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.07, 0.96)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(dim)
	var m := _full(ui)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	m.add_child(root)
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 30)
	hdr.add_child(_btn("< BACK", func() -> void:
		confirm_reset = false
		Save.write()
		settings_back.call(), 200, 26))
	hdr.add_child(_lbl("SETTINGS", 44, ACC))
	root.add_child(hdr)
	var scr := SmoothScroll.new()
	scr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scr.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scr)
	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 40)
	scr.add_child(body)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	left.custom_minimum_size = Vector2(480, 0)
	body.add_child(left)
	for sdef in [["sfx", "Effects volume"], ["music", "Music volume"], ["shake", "Camera shake"], ["amb", "Engine & ambience volume"]]:
		var key: String = sdef[0]
		left.add_child(_lbl(sdef[1], 20, DIM))
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0 if key != "shake" else 1.5
		sl.step = 0.05
		sl.value = float(Save.setting(key))
		sl.custom_minimum_size = Vector2(440, 28)
		sl.value_changed.connect(func(val: float) -> void:
			Save.set_setting(key, val)
			Sfx.refresh_volume())
		left.add_child(sl)
	left.add_child(_lbl("Throttle", 20, DIM))
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 8)
	left.add_child(tr)
	var cur_at := int(Save.setting("autothrottle"))
	for opt in [[-1, "AUTO"], [1, "ALWAYS ON"], [0, "MANUAL"]]:
		var ov: int = opt[0]
		var ob := _btn(opt[1], func() -> void:
			Save.set_setting("autothrottle", ov)
			show_settings(settings_back), 140, 18)
		ob.disabled = cur_at == ov
		tr.add_child(ob)
	left.add_child(_lbl("Graphics", 20, DIM))
	var gr := HBoxContainer.new()
	gr.add_theme_constant_override("separation", 8)
	left.add_child(gr)
	for opt in [[1, "HIGH"], [0, "LOW (cooler)"]]:
		var qv: int = opt[0]
		var qb := _btn(opt[1], func() -> void:
			Save.set_setting("quality", qv)
			show_settings(settings_back), 140, 18)
		qb.disabled = int(Save.setting("quality")) == qv
		gr.add_child(qb)
	left.add_child(_lbl("Frame rate", 20, DIM))
	var fr := HBoxContainer.new()
	fr.add_theme_constant_override("separation", 8)
	left.add_child(fr)
	for fv in [60, 90, 120]:
		var fb := _btn("%d fps" % fv, func() -> void:
			Save.set_setting("fps", fv)
			apply_fps()
			show_settings(settings_back), 140, 18)
		fb.disabled = int(Save.setting("fps")) == fv
		fr.add_child(fb)
	left.add_child(_lbl("Difficulty", 20, DIM))
	var dr := HBoxContainer.new()
	dr.add_theme_constant_override("separation", 8)
	left.add_child(dr)
	for i in 3:
		var db := _btn(Data.DIFFICULTY[i]["name"], func() -> void:
			Save.set_setting("diff", i)
			show_settings(settings_back), 140, 18)
		db.disabled = int(Save.setting("diff")) == i
		dr.add_child(db)
	var dbg := CheckButton.new()
	dbg.text = "Debug tools (F1 overlay, F2 god, F3 skip, F4 crash, F5 nitro)"
	dbg.button_pressed = bool(Save.setting("debug"))
	dbg.toggled.connect(func(on: bool) -> void: Save.set_setting("debug", on))
	left.add_child(dbg)
	var tut := CheckButton.new()
	tut.text = "Show control hints"
	tut.button_pressed = bool(Save.setting("tutorial"))
	tut.toggled.connect(func(on: bool) -> void: Save.set_setting("tutorial", on))
	left.add_child(tut)
	# controls
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var touch := OS.get_name() == "Android" or OS.get_name() == "iOS"
	if not touch:
		right.add_child(_lbl("CONTROLS  (click a key to remap)", 22, ACC))
	for a in ([] if touch else Save.ACTIONS):
		var name: String = a[0]
		var row := HBoxContainer.new()
		var l := _lbl(a[1], 20)
		l.custom_minimum_size = Vector2(260, 0)
		row.add_child(l)
		var kb := _btn(Save.key_name(name), func() -> void: pass, 180, 20)
		kb.custom_minimum_size = Vector2(180, 38)
		kb.pressed.connect(func() -> void:
			if rebind_btn != null and is_instance_valid(rebind_btn):
				rebind_btn.text = Save.key_name(rebind_action)
			rebind_action = name
			rebind_btn = kb
			kb.text = "press a key...")
		row.add_child(kb)
		right.add_child(row)
	var rr := HBoxContainer.new()
	rr.add_theme_constant_override("separation", 10)
	right.add_child(rr)
	rr.add_child(_btn("Reset keys", func() -> void:
		Save.reset_bindings()
		show_settings(settings_back), 0, 18))
	var rs := _btn("Reset progress" if not confirm_reset else "Really reset?", func() -> void: pass, 0, 18)
	rs.pressed.connect(func() -> void:
		if confirm_reset:
			confirm_reset = false
			Save.reset()
			garage_idx = 0
		else:
			confirm_reset = true
		show_settings(settings_back))
	rr.add_child(rs)
	root.add_child(_btn("BACK", func() -> void:
		confirm_reset = false
		Save.write()
		settings_back.call(), 160))

func show_credits() -> void:
	gstate = "SETTINGS"
	settings_back = show_menu
	_clear()
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.07, 0.96)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(dim)
	var m := _full(ui)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	m.add_child(root)
	root.add_child(_lbl("CREDITS", 44, ACC))
	for line in ["Road Warriors - made with Godot Engine 4 (MIT licence)",
			"Bike art: original designs, modelled and rendered in Blender (GPL tool, output is ours)",
			"Music and sound effects: original, generated in-house for this game",
			"No third-party music, logos or trademarks are used.",
			"Real roads in the Mumbai race: (c) OpenStreetMap contributors, ODbL"]:
		root.add_child(_lbl(line, 22, DIM))
	root.add_child(_btn("BACK", show_menu, 160))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		go_back()

func go_back() -> void:
	match gstate:
		"SETTINGS":
			Save.write()
			confirm_reset = false
			rebind_action = ""
			settings_back.call()
		"PAUSED":
			resume()
		"COUNTDOWN", "RACING":
			pause()
		"GARAGE", "RACE_SELECT", "FINISHED", "GAME_OVER":
			show_menu()

func _unhandled_input(e: InputEvent) -> void:
	if rebind_action != "" and e is InputEventKey and e.pressed and not e.echo:
		var code: int = e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode
		if code != KEY_ESCAPE:
			Save.rebind(rebind_action, code)
		rebind_btn.text = Save.key_name(rebind_action)
		rebind_action = ""
		get_viewport().set_input_as_handled()
		return
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_F1 and race != null:
			hud.show_debug = not hud.show_debug
		elif e.keycode >= KEY_F2 and e.keycode <= KEY_F6 and race != null and bool(Save.setting("debug")):
			race.dbg_key(e.keycode)
	if e.is_action_pressed("pause"):
		go_back()

# ---------------------------------------------------------------- race flow
func _free_race() -> void:
	if touch != null:
		touch.release_all()
	if race != null:
		race.queue_free()
		race = null
	if hud != null:
		hud.queue_free()
		hud = null
	if touch != null:
		touch.queue_free()
		touch = null
	get_tree().paused = false
	Sfx.engine(false)

func start_race(rd: Dictionary, sim: bool) -> void:
	_free_race()
	_clear()
	_show_bg(false)
	cur_def = rd
	race = Race.new()
	race.autopilot = sim
	race.kicktest = kicktest
	add_child(race)
	race.setup(rd)
	race.ended.connect(_on_race_ended)
	hud = HUD.new()
	hud_layer.add_child(hud)
	hud.bind(race)
	hud.show_debug = bool(Save.setting("debug")) or sim_id != ""
	if DisplayServer.is_touchscreen_available():
		touch = TouchControls.new()
		hud_layer.add_child(touch)
	gstate = "COUNTDOWN"

func pause() -> void:
	Engine.time_scale = 1.0
	gstate = "PAUSED"
	get_tree().paused = true
	if touch != null:
		touch.release_all()
	_clear()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(c)
	var pc := PanelContainer.new()
	c.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pc.add_child(v)
	v.add_child(_lbl("PAUSED", 48, ACC, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_btn("RESUME", resume, 360, 28))
	v.add_child(_btn("RESTART", func() -> void: start_race(cur_def, false), 360, 28))
	v.add_child(_btn("SETTINGS", func() -> void: show_settings(pause), 360, 28))
	v.add_child(_btn("QUIT TO MENU", show_menu, 360, 28))

func resume() -> void:
	_clear()
	get_tree().paused = false
	gstate = "COUNTDOWN" if race.state == Race.RState.COUNTDOWN else "RACING"

func _on_race_ended(res: Dictionary) -> void:
	Save.d["money"] += int(res["money"])
	Save.d["rep"] += int(res["rep"])
	var rid: String = res["id"]
	var prev: Dictionary = Save.d["done"].get(rid, {})
	var e := {"win": bool(prev.get("win", false)) or bool(res["win"]), "place": int(prev.get("place", 99)), "time": float(prev.get("time", 0.0))}
	if res["win"] and (int(res["place"]) < e["place"] or (int(res["place"]) == e["place"] and (e["time"] == 0.0 or float(res["time"]) < e["time"]))):
		e["place"] = int(res["place"])
		e["time"] = float(res["time"])
	elif not prev.has("place") and e["place"] == 99:
		e["place"] = int(res["place"])
		e["time"] = float(res["time"])
	Save.d["done"][rid] = e
	if res.get("daily", false):
		var dd: Dictionary = Save.d["daily"]
		var key := int(res["date"])
		if res["win"] and int(dd.get("claimed", 0)) != key:
			var yest := int(dd.get("claimed", 0))
			dd["streak"] = int(dd.get("streak", 0)) + 1 if (yest > 0 and key - yest <= 1 + (70 if key % 100 == 1 else 0)) else 1
			dd["claimed"] = key
		var b: Dictionary = dd.get("best", {})
		if res["win"] and (int(b.get("date", 0)) != key or float(res["time"]) < float(b.get("time", 1e9))):
			dd["best"] = {"date": key, "time": float(res["time"]), "score": int(res["score"])}
		Save.d["daily"] = dd
	var gp: Array = res.get("ghost", [])
	if gp.size() >= 8:
		var old: Dictionary = Save.d["ghost"].get(str(res["ghost_id"]), {})
		if not old.has("time") or float(res["ftime"]) < float(old["time"]):
			Save.d["ghost"][str(res["ghost_id"])] = {"time": float(res["ftime"]), "pts": gp}
			print("[ghost] saved ", res["ghost_id"], " time=", res["ftime"], " samples=", gp.size() / 2)
	Save.write()
	if sim_id != "":
		var pr := res.duplicate()
		pr["ghost"] = (pr["ghost"] as Array).size()
		print("[sim] RESULT ", JSON.stringify(pr))
		for r in race.racers:
			print("[sim] ", r.rname, " finished=", r.finished, " t=", r.finish_time, " s=", r.s)
		get_tree().quit(0)
		return
	await get_tree().create_timer(1.6).timeout
	if race == null:
		return
	show_results(res)

func show_results(res: Dictionary) -> void:
	gstate = "GAME_OVER" if res["game_over"] else "FINISHED"
	if touch != null:
		touch.release_all()
		touch.visible = false
	if hud != null:
		hud.visible = false
	_clear()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(c)
	var pc := PanelContainer.new()
	c.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.custom_minimum_size = Vector2(620, 0)
	pc.add_child(v)
	var banner := "VICTORY" if res["win"] else ("GAME OVER" if res["game_over"] else "DEFEAT")
	v.add_child(_lbl(banner, 64, GOOD if res["win"] else BAD, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_lbl("%s  -  %s" % [res["name"], res["reason"]], 24, DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var s: Dictionary = res["stats"]
	var lines := []
	if res["mode"] in ["race", "rival", "knockout"]:
		lines.append("Position      P%d" % res["place"])
	lines.append("Time          %s" % _fmt_time(float(res["time"])))
	if res["mode"] == "highway":
		lines.append("Score         %d" % res["score"])
	lines.append("Top speed     %d km/h" % int(float(s["top"]) * 3.6))
	lines.append("Overtakes %d    Near misses %d    Takedowns %d    Crashes %d" % [s["overtakes"], s["near"], s["takedowns"], s["crashes"]])
	lines.append("Hits %d    Best combo x%d" % [s["hits"], s["combo"]])
	if res["mode"] == "chase":
		lines.append("Cops downed %d    Rams taken %d" % [s["cops"], s["rams"]])
	if res.get("daily", false) and res["win"]:
		lines.append("Daily reward claimed" if not res["daily_repeat"] else "Daily already claimed - reduced prize")
	if (res.get("ghost", []) as Array).size() >= 8:
		lines.append("Ghost saved")
	if res["shortcut"]:
		lines.append("Shortcut used")
	for ln in lines:
		v.add_child(_lbl(ln, 22, TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_lbl("Prize $%d  +  bonuses $%d  =  $%d" % [res["base"], res["bonus"], res["money"]], 26, ACC, HORIZONTAL_ALIGNMENT_CENTER))
	if int(res["rep"]) > 0:
		v.add_child(_lbl("+%d reputation" % res["rep"], 24, GOOD, HORIZONTAL_ALIGNMENT_CENTER))
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	v.add_child(hb)
	if not res["game_over"]:
		hb.add_child(_btn("CONTINUE", show_race_select, 0, 24))
	hb.add_child(_btn("RETRY", func() -> void: start_race(cur_def, false), 0, 24))
	hb.add_child(_btn("GARAGE", show_garage, 0, 24))
	if res["game_over"]:
		hb.add_child(_btn("MENU", show_menu, 0, 24))
