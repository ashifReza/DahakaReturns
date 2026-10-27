class_name MenuUI
## Shared look and pieces for the main menu and the pause menu: a theme, and
## the settings panel both of them show.

const MAIN_MENU := "res://scenes/main_menu.tscn"

const TEXT := Color(0.86, 0.83, 0.76)
const DIM := Color(0.55, 0.52, 0.47)
const ACCENT := Color(0.75, 0.12, 0.08)


static func theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 24
	var plain := StyleBoxFlat.new()
	plain.bg_color = Color(0, 0, 0, 0)
	plain.content_margin_left = 18
	plain.content_margin_right = 18
	plain.content_margin_top = 6
	plain.content_margin_bottom = 6
	var hover := plain.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1, 1, 1, 0.06)
	hover.border_width_left = 3
	hover.border_color = ACCENT
	for state in ["normal", "disabled"]:
		t.set_stylebox(state, "Button", plain)
	for state in ["hover", "pressed", "focus"]:
		t.set_stylebox(state, "Button", hover)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT.lightened(0.3))
	t.set_color("font_color", "Label", TEXT)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.15)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = ACCENT
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	return t


static func button(text: String, pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(pressed)
	return b


static func label(text: String, size := 24, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Mouse sensitivity, volume and fullscreen, saved as they change.
static func settings_panel(back: Callable) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.add_child(label("SETTINGS", 30))

	box.add_child(_slider_row("Mouse sensitivity", 0.25, 3.0, Settings.look_scale, func(v: float) -> void:
		Settings.look_scale = v
		Settings.save()
	))
	box.add_child(_slider_row("Volume", 0.0, 1.0, Settings.volume, func(v: float) -> void:
		Settings.volume = v
		Settings.apply()
		Settings.save()
	))
	var full := button("", func() -> void: pass)
	var show_mode := func() -> void:
		full.text = "Fullscreen:  %s" % ("On" if Settings.fullscreen else "Off")
	show_mode.call()
	full.pressed.connect(func() -> void:
		Settings.fullscreen = not Settings.fullscreen
		Settings.apply()
		Settings.save()
		show_mode.call()
	)
	box.add_child(full)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 10
	box.add_child(spacer)
	box.add_child(button("Back", back))
	return box


static func _slider_row(text: String, low: float, high: float, value: float, changed: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var name_label := label(text, 22)
	name_label.custom_minimum_size.x = 230
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(260, 24)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_ALL
	row.add_child(slider)
	var shown := label("%d%%" % roundi(value * 100.0), 20, DIM)
	shown.custom_minimum_size.x = 70
	row.add_child(shown)
	slider.value_changed.connect(func(v: float) -> void:
		shown.text = "%d%%" % roundi(v * 100.0)
		changed.call(v)
	)
	return row


## The first focusable control in a tree, so keyboard and gamepad work at once.
static func focus_first(node: Node) -> void:
	for c in node.get_children():
		if c is Control and (c as Control).focus_mode == Control.FOCUS_ALL and (c as Control).is_visible_in_tree():
			(c as Control).grab_focus()
			return
		focus_first(c)
		if node.get_viewport() and node.get_viewport().gui_get_focus_owner():
			return
