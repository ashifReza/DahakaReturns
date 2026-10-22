shader_type spatial;
// Dark, slow river water: rippling normals and a bright specular sheen.

uniform vec3 deep_color : source_color = vec3(0.01, 0.025, 0.03);
uniform float flow_speed = 0.25;
uniform vec2 flow_direction = vec2(1.0, 0.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV * 18.0 + flow_direction * TIME * flow_speed;
	float h = noise(uv) * 0.6 + noise(uv * 2.7 + 3.1) * 0.4;
	float hx = noise(uv + vec2(0.05, 0.0)) * 0.6 + noise((uv + vec2(0.05, 0.0)) * 2.7 + 3.1) * 0.4;
	float hy = noise(uv + vec2(0.0, 0.05)) * 0.6 + noise((uv + vec2(0.0, 0.05)) * 2.7 + 3.1) * 0.4;
	NORMAL_MAP = normalize(vec3((h - hx) * 6.0, (h - hy) * 6.0, 1.0)) * 0.5 + 0.5;
	ALBEDO = deep_color;
	ROUGHNESS = 0.05;
	METALLIC = 0.2;
	SPECULAR = 0.9;
}
