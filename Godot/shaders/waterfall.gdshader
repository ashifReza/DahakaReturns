shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
// Streaks of falling water, faintly lit, for a waterfall sheet (UV.y downward).

uniform vec3 color : source_color = vec3(0.35, 0.45, 0.5);
uniform float speed = 1.6;

float hash(float x) {
	return fract(sin(x * 91.3458) * 47453.5453);
}

void fragment() {
	float column = floor(UV.x * 60.0);
	float s = hash(column);
	float v = fract(UV.y * (2.0 + s * 2.0) - TIME * speed * (0.7 + s * 0.6));
	float streak = smoothstep(0.0, 0.3, v) * (1.0 - smoothstep(0.3, 1.0, v));
	float edge = smoothstep(0.0, 0.08, UV.x) * smoothstep(1.0, 0.92, UV.x);
	float fade = smoothstep(0.0, 0.05, UV.y) * smoothstep(1.0, 0.85, UV.y);
	ALBEDO = color * streak * edge * fade * (0.5 + s);
}
