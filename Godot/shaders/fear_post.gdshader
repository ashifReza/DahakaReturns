shader_type canvas_item;
// Full-screen fear effects driven by the chase's danger value: vignette,
// film grain, colour fringing, desaturation, and the fade to black on death.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float vignette = 0.45;
uniform float grain = 0.15;
uniform float fringe = 0.0;
uniform float saturation = 0.9;
uniform float fade = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 from_center = uv - 0.5;
	vec2 shift = from_center * fringe * 0.004;
	vec3 c = vec3(
		texture(screen_texture, uv + shift).r,
		texture(screen_texture, uv).g,
		texture(screen_texture, uv - shift).b);

	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(luma), c, saturation);

	float edge = smoothstep(0.25, 0.85, length(from_center * vec2(1.3, 1.0)));
	c *= 1.0 - clamp(vignette * edge, 0.0, 1.0);

	float n = hash(floor(FRAGCOORD.xy) + fract(TIME) * 100.0) - 0.5;
	c += n * grain * 0.12;

	COLOR = vec4(mix(c, vec3(0.0), fade), 1.0);
}
