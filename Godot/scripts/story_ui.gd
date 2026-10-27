class_name StoryUI
extends CanvasLayer
## Everything the story puts on screen: title cards, spoken lines and
## thoughts, the current objective, the note, and fades to black. The waits
## are coroutines, so the director can read like a script:
##   await ui.line("Hale", "Copy that.")

## While true, every wait is cut to a blink (automated playtests).
var fast := false

var _black: ColorRect
var _card: Label
var _subtitle: RichTextLabel
var _subtitle_back: ColorRect
var _objective: Label
var _note_panel: ColorRect
var _note_text: Label
var _note_hint: Label
var _skip_hint: Label
var _skip := false
var _black_tween: Tween


func _ready() -> void:
	layer = 5
	var font_color := Color(0.88, 0.86, 0.8)

	_objective = Label.new()
	_objective.position = Vector2(36, 28)
	_objective.add_theme_font_size_override("font_size", 20)
	_objective.add_theme_color_override("font_color", Color(0.85, 0.82, 0.7, 0.85))
	_objective.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	add_child(_objective)

	_subtitle_back = ColorRect.new()
	_subtitle_back.color = Color(0, 0, 0, 0.45)
	_subtitle_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle_back.anchor_left = 0.18
	_subtitle_back.anchor_right = 0.82
	_subtitle_back.anchor_top = 0.8
	_subtitle_back.anchor_bottom = 0.92
	_subtitle_back.visible = false
	add_child(_subtitle_back)
	_subtitle = RichTextLabel.new()
	_subtitle.bbcode_enabled = true
	_subtitle.fit_content = true
	_subtitle.scroll_active = false
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle.set_anchors_preset(Control.PRESET_FULL_RECT)
	_subtitle.offset_left = 18
	_subtitle.offset_right = -18
	_subtitle.offset_top = 12
	_subtitle.add_theme_font_size_override("normal_font_size", 24)
	_subtitle.add_theme_font_size_override("italics_font_size", 24)
	_subtitle.add_theme_font_size_override("bold_font_size", 24)
	_subtitle.add_theme_color_override("default_color", font_color)
	_subtitle_back.add_child(_subtitle)

	_note_panel = ColorRect.new()
	_note_panel.color = Color(0.82, 0.77, 0.64)
	_note_panel.anchor_left = 0.27
	_note_panel.anchor_right = 0.73
	_note_panel.anchor_top = 0.08
	_note_panel.anchor_bottom = 0.92
	_note_panel.visible = false
	add_child(_note_panel)
	_note_text = Label.new()
	_note_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_note_text.offset_left = 38
	_note_text.offset_right = -38
	_note_text.offset_top = 34
	_note_text.offset_bottom = -60
	_note_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_text.add_theme_font_size_override("font_size", 21)
	_note_text.add_theme_color_override("font_color", Color(0.16, 0.1, 0.07))
	_note_panel.add_child(_note_text)
	_note_hint = Label.new()
	_note_hint.text = "[E] Put it down"
	_note_hint.anchor_top = 1.0
	_note_hint.anchor_bottom = 1.0
	_note_hint.anchor_right = 1.0
	_note_hint.offset_top = -44
	_note_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note_hint.add_theme_font_size_override("font_size", 18)
	_note_hint.add_theme_color_override("font_color", Color(0.3, 0.2, 0.15))
	_note_panel.add_child(_note_hint)

	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 1)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_black)

	_card = Label.new()
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.offset_left = 120
	_card.offset_right = -120
	_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card.add_theme_font_size_override("font_size", 30)
	_card.add_theme_color_override("font_color", font_color)
	_card.modulate.a = 0.0
	add_child(_card)

	_skip_hint = Label.new()
	_skip_hint.text = "[Enter] Skip"
	_skip_hint.anchor_left = 1.0
	_skip_hint.anchor_right = 1.0
	_skip_hint.anchor_top = 1.0
	_skip_hint.anchor_bottom = 1.0
	_skip_hint.offset_left = -150
	_skip_hint.offset_top = -46
	_skip_hint.add_theme_font_size_override("font_size", 16)
	_skip_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	_skip_hint.visible = false
	add_child(_skip_hint)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("skip_dialog") or (_note_panel.visible and event.is_action_pressed("interact")):
		_skip = true
	elif _card.modulate.a > 0.0 and (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
		_skip = true


func set_objective(text: String) -> void:
	_objective.text = text


## Fades the screen to black (1) or back to the game (0).
func fade(to: float, seconds: float) -> void:
	if _black_tween:
		_black_tween.kill()
	if fast:
		_black.color.a = to
		return
	_black_tween = create_tween()
	_black_tween.tween_property(_black, "color:a", to, seconds)
	await _black_tween.finished


## A paragraph on the black screen. Any key moves on.
func card(text: String, seconds := 0.0) -> void:
	if seconds <= 0.0:
		seconds = 2.5 + text.length() * 0.045
	_card.text = text
	_skip_hint.visible = true
	await _tween_card(1.0, 0.8)
	await wait(seconds, true)
	await _tween_card(0.0, 0.6)
	_skip_hint.visible = false


func _tween_card(to: float, seconds: float) -> void:
	if fast:
		_card.modulate.a = to
		return
	var t := create_tween()
	t.tween_property(_card, "modulate:a", to, seconds)
	await t.finished


## A spoken line (speaker given) or a thought (speaker empty, in italics).
func line(speaker: String, text: String, seconds := 0.0) -> void:
	if seconds <= 0.0:
		seconds = 1.6 + text.length() * 0.055
	if speaker == "":
		_subtitle.text = "[i]%s[/i]" % text
	else:
		_subtitle.text = "[color=#c9b37e][b]%s:[/b][/color] %s" % [speaker, text]
	_subtitle_back.visible = true
	await wait(seconds, true)
	_subtitle_back.visible = false


## Several lines in a row: each entry is [speaker, text].
func lines(entries: Array) -> void:
	for e in entries:
		await line(e[0], e[1])


## Shows the note until E or Enter is pressed.
func read_note(text: String) -> void:
	_note_text.text = text
	_note_panel.visible = true
	await wait(0.6, false)
	_skip = false
	while not _skip and not fast:
		await get_tree().process_frame
	_note_panel.visible = false


func is_reading() -> bool:
	return _note_panel.visible


## Waits `seconds`, or until skipped if `skippable`.
func wait(seconds: float, skippable: bool) -> void:
	if fast:
		seconds = minf(seconds, 0.05)
	_skip = false
	var t := 0.0
	while t < seconds and not (skippable and _skip):
		await get_tree().process_frame
		t += get_process_delta_time()
	_skip = false
