class_name UI
extends RefCounted
## Small UI helpers: a shared chunky, touch-friendly theme and widget builders.

static func fs(size: int) -> int:
	return int(size * 1.25) if Settings.large_text else size

static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = fs(30)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(18)
		sb.set_content_margin_all(14)
		sb.border_width_bottom = 6
		match state:
			"normal":
				sb.bg_color = Color("2f8fff"); sb.border_color = Color("1b5fc4")
			"hover", "focus":
				sb.bg_color = Color("4aa1ff"); sb.border_color = Color("1b5fc4")
			"pressed":
				sb.bg_color = Color("1b6fe0"); sb.border_color = Color("1b5fc4"); sb.border_width_bottom = 2
			"disabled":
				sb.bg_color = Color("8793a3"); sb.border_color = Color("66707e")
		t.set_stylebox(state, "Button", sb)
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color("d5dbe4"))
	t.set_color("font_outline_color", "Label", Color(0.05, 0.1, 0.2, 0.9))
	t.set_constant("outline_size", "Label", 6)
	t.set_color("font_color", "Label", Color.WHITE)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.05, 0.1, 0.2, 0.72)
	panel.set_corner_radius_all(24)
	panel.set_content_margin_all(22)
	t.set_stylebox("panel", "PanelContainer", panel)
	return t

static func button(text: String, cb: Callable, min_size := Vector2(360, 76)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.pressed.connect(func():
		Sfx.play("click")
		cb.call())
	return b

static func label(text: String, size := 30, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs(size))
	l.add_theme_color_override("font_color", color)
	return l

static func format_time(t: float) -> String:
	var m := int(t) / 60
	var s := fmod(t, 60.0)
	return "%d:%05.2f" % [m, s]
