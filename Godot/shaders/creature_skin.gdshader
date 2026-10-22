shader_type spatial;
// Wet black obsidian with glowing cracks that pulse, and flare with rage.

uniform vec3 base_color : source_color = vec3(0.012, 0.010, 0.016);
uniform vec3 vein_color : source_color = vec3(1.0, 0.32, 0.06);
uniform vec3 rim_color : source_color = vec3(0.25, 0.12, 0.35);
uniform float vein_scale = 3.2;
uniform float rage = 0.3;
instance uniform vec3 seed = vec3(0.0);

varying vec3 object_pos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float value_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
	               mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
	               mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	// Mesh-local, so the cracks stay put on each limb as it moves.
	object_pos = VERTEX + seed;
}

void fragment() {
	vec3 p = object_pos * vein_scale;
	float n = value_noise(p) * 0.65 + value_noise(p * 2.3) * 0.35;
	// Thin bands where the noise crosses 0.5 read as cracks.
	float crack = 1.0 - smoothstep(0.0, 0.012 + 0.03 * rage, abs(n - 0.5));
	float pulse = 0.6 + 0.4 * sin(TIME * (2.0 + rage * 6.0) + n * 12.0);

	ALBEDO = base_color;
	ROUGHNESS = 0.32;
	METALLIC = 0.4;
	SPECULAR = 0.7;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = vein_color * crack * pulse * (0.05 + rage * rage * 3.0) + rim_color * rim * 0.2;
}
