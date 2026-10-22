class_name RelentlessHUD
extends CanvasLayer
## Deliberately minimal: a dot, stamina only when it matters, battery, prompts.
## Also owns the full-screen fear effect and the fade to black.

var player: RelentlessPlayer

var _post: ColorRect
var _post_material: ShaderMaterial
var _canvas: Control
var _fade := 0.0
var _fade_tween: Tween


func _ready() -> void:
	_post_material = ShaderMaterial.new()
	_post_material.shader = preload("res://shaders/fear_post.gdshader")
	_post = ColorRect.new()
	_post.material = _post_material
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_post)

	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)


func _process(_delta: float) -> void:
	_post_material.set_shader_parameter("fade", _fade)
	_canvas.queue_redraw()


func set_post(vignette: float, grain: float, fringe: float, saturation: float) -> void:
	_post_material.set_shader_parameter("vignette", vignette)
	_post_material.set_shader_parameter("grain", grain)
	_post_material.set_shader_parameter("fringe", fringe)
	_post_material.set_shader_parameter("saturation", saturation)


func fade_to(target: float, seconds: float) -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "_fade", target, seconds)


func _draw_hud() -> void:
	if not is_instance_valid(player):
		return
	var size := _canvas.size
	var w := size.x
	var h := size.y
	var s := h / 1080.0

	if not player.dead:
		_canvas.draw_rect(Rect2(w * 0.5 - 1.5, h * 0.5 - 1.5, 3.0, 3.0), Color(1, 1, 1, 0.25))

		var stamina := player.get_stamina01()
		if stamina < 0.999:
			var c := Color(0.7, 0.1, 0.08, 0.8) if player.exhausted else Color(0.85, 0.85, 0.8, 0.5)
			_bar(w * 0.5 - 130.0 * s, h - 70.0 * s, 260.0 * s, 4.0 * s, stamina, c)

		var battery := player.get_battery01()
		var bc := Color(0.8, 0.2, 0.1, 0.8) if battery < 0.2 else Color(0.6, 0.8, 0.6, 0.5)
		_bar(w - 150.0 * s, h - 60.0 * s, 100.0 * s, 10.0 * s, battery, bc)

		var prompt := player.get_interact_prompt()
		if prompt != "":
			_centered_text(prompt, w * 0.5, h * 0.5 + 60.0 * s, Color(0.9, 0.9, 0.85, 0.9), s)
			var progress := player.get_interact_progress()
			if progress >= 0.0:
				_bar(w * 0.5 - 80.0 * s, h * 0.5 + 75.0 * s, 160.0 * s, 5.0 * s, progress, Color(0.9, 0.9, 0.85, 0.9))

	var hint_alpha := player.get_hint_alpha()
	if hint_alpha > 0.0 and player.get_hint_text() != "":
		_centered_text(player.get_hint_text(), w * 0.5, h * 0.78, Color(0.85, 0.85, 0.8, hint_alpha), s * 1.1)


func _centered_text(text: String, center_x: float, y: float, color: Color, s: float) -> void:
	var font := ThemeDB.fallback_font
	var font_size := int(26.0 * s)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_canvas.draw_string(font, Vector2(center_x - width * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _bar(x: float, y: float, w: float, h: float, fill: float, color: Color) -> void:
	_canvas.draw_rect(Rect2(x, y, w, h), Color(0, 0, 0, 0.4))
	_canvas.draw_rect(Rect2(x, y, w * clampf(fill, 0.0, 1.0), h), color)
