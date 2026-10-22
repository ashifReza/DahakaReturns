class_name CreatureBody
extends Node3D
## The pursuer's look: a tall, hunched, obsidian-black figure with glowing
## cracks, a crown of swept-back horns, arms far too long, and tendrils that
## whip from its back. Trails smoke and embers. Built from basic shapes and
## animated procedurally, so no imported assets are needed. Faces -Z, with its
## origin at the feet.

const HIP_HEIGHT := 1.42
const TENDRIL_COUNT := 6
const TENDRIL_SEGMENTS := 7

var _skin: ShaderMaterial
var _eye_material: StandardMaterial3D
var _spine: Node3D
var _head: Node3D
var _jaw: Node3D
var _eye_glow: OmniLight3D
var _shoulders: Array[Node3D] = []
var _elbows: Array[Node3D] = []
var _hips: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _ankles: Array[Node3D] = []
var _tendrils: Array = []  # each: Array[Node3D] of segment pivots
var _tendril_phase: Array[float] = []
var _smoke: GPUParticles3D
var _embers: GPUParticles3D
var _phase := 0.0
var _time := 0.0
var _rage := 0.3
var _seed_counter := 0


func _ready() -> void:
	_skin = ShaderMaterial.new()
	_skin.shader = preload("res://shaders/creature_skin.gdshader")
	_eye_material = StandardMaterial3D.new()
	_eye_material.albedo_color = Color.BLACK
	_eye_material.emission_enabled = true
	_eye_material.emission = Color(1.0, 0.35, 0.08)
	_eye_material.emission_energy_multiplier = 6.0
	_build_legs()
	_build_torso()
	_build_head()
	_build_arms()
	_build_tendrils()
	_build_particles()


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

func _part(mesh: Mesh, parent: Node3D, pos: Vector3, rot_deg := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _skin
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	_seed_counter += 1
	mi.set_instance_shader_parameter("seed", Vector3(_seed_counter * 3.7, _seed_counter * 1.3, _seed_counter * 5.1))
	parent.add_child(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3, rot_deg := Vector3.ZERO) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	p.rotation_degrees = rot_deg
	parent.add_child(p)
	return p


static func _limb(radius: float, length: float, tip_radius := -1.0) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius if tip_radius < 0.0 else tip_radius
	m.height = length
	m.radial_segments = 10
	m.rings = 1
	return m


static func _ball(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 16
	m.rings = 8
	return m


static func _cone(radius: float, length: float) -> CylinderMesh:
	# Points along +Y.
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = radius
	m.height = length
	m.radial_segments = 8
	m.rings = 1
	return m


func _build_legs() -> void:
	# Digitigrade: thigh forward, shin back, long foot.
	for side in [-1.0, 1.0]:
		var hip := _pivot(self, Vector3(0.2 * side, HIP_HEIGHT, 0.0))
		_part(_limb(0.13, 0.72, 0.09), hip, Vector3(0, -0.36, 0))
		var knee := _pivot(hip, Vector3(0, -0.72, 0))
		_part(_ball(0.1), knee, Vector3.ZERO)
		_part(_limb(0.09, 0.66, 0.05), knee, Vector3(0, -0.33, 0))
		var ankle := _pivot(knee, Vector3(0, -0.66, 0))
		_part(_limb(0.05, 0.3, 0.03), ankle, Vector3(0, -0.02, -0.14), Vector3(-90, 0, 0))
		for toe in [-1.0, 0.0, 1.0]:
			_part(_cone(0.025, 0.14), ankle, Vector3(0.04 * toe, -0.03, -0.32), Vector3(-90, toe * 12.0, 0))
		_hips.append(hip)
		_knees.append(knee)
		_ankles.append(ankle)


func _build_torso() -> void:
	_part(_ball(0.5), self, Vector3(0, HIP_HEIGHT + 0.02, 0.02), Vector3.ZERO, Vector3(0.5, 0.3, 0.38))
	_spine = _pivot(self, Vector3(0, HIP_HEIGHT, 0), Vector3(-28, 0, 0))
	_part(_limb(0.24, 0.6, 0.18), _spine, Vector3(0, 0.3, 0))           # waist
	_part(_ball(0.5), _spine, Vector3(0, 0.85, 0.0), Vector3(0, 0, 0), Vector3(1.05, 0.85, 0.55))  # chest
	for side in [-1.0, 1.0]:  # ribs showing under the skin
		for k in 3:
			_part(_limb(0.025, 0.4, 0.025), _spine, Vector3(0.22 * side, 0.55 + 0.12 * k, -0.18), Vector3(0, 0, 90 + 20 * side))
	# Ridge of spines down the back.
	for i in 7:
		var t := i / 6.0
		_part(_cone(0.05 + 0.03 * (1.0 - t), 0.2 + 0.18 * (1.0 - absf(t - 0.4))), _spine,
			Vector3(0, 0.25 + 0.85 * t, 0.2 + 0.08 * sin(t * PI)), Vector3(55, 0, 0))


func _build_head() -> void:
	var neck := _pivot(_spine, Vector3(0, 1.12, -0.12), Vector3(18, 0, 0))
	_part(_limb(0.09, 0.3, 0.12), neck, Vector3(0, 0.08, -0.06), Vector3(-50, 0, 0))
	_head = _pivot(neck, Vector3(0, 0.18, -0.2), Vector3(12, 0, 0))
	_part(_ball(0.5), _head, Vector3(0, 0.02, -0.08), Vector3.ZERO, Vector3(0.34, 0.36, 0.52))   # skull
	_part(_ball(0.5), _head, Vector3(0, -0.04, -0.3), Vector3.ZERO, Vector3(0.22, 0.2, 0.26))    # snout
	_jaw = _pivot(_head, Vector3(0, -0.08, -0.08))
	_part(_ball(0.5), _jaw, Vector3(0, -0.04, -0.18), Vector3(0, 0, 0), Vector3(0.22, 0.08, 0.34))
	for side in [-1.0, 1.0]:
		# Teeth along the jaw line.
		for k in 3:
			_part(_cone(0.012, 0.06), _jaw, Vector3(0.05 * side, 0.0, -0.22 - 0.05 * k), Vector3(0, 0, 0))
		var eye := MeshInstance3D.new()
		eye.mesh = _ball(0.03)
		eye.material_override = _eye_material
		eye.position = Vector3(0.085 * side, 0.06, -0.29)
		eye.scale = Vector3(1.4, 0.6, 1.0)
		_head.add_child(eye)
		# Crown: a great horn sweeping back in three curving pieces, plus smaller spikes.
		var horn := _pivot(_head, Vector3(0.12 * side, 0.14, -0.04), Vector3(30, 0, -30 * side))
		var r := 0.1
		for seg in 3:
			var length := 0.42 - seg * 0.06
			_part(_limb(r * 0.65, length, r), horn, Vector3(0, length * 0.5, 0))
			horn = _pivot(horn, Vector3(0, length, 0), Vector3(30, 0, 8 * side))
			r *= 0.65
		_part(_cone(r, 0.2), horn, Vector3(0, 0.1, 0))
		for k in 2:
			_part(_cone(0.03, 0.18), _head, Vector3(0.07 * side, 0.18, 0.05 + 0.08 * k), Vector3(60 + 15 * k, 0, -15 * side))

	_eye_glow = OmniLight3D.new()
	_eye_glow.position = Vector3(0, 0.05, -0.45)
	_eye_glow.light_color = Color(1.0, 0.3, 0.08)
	_eye_glow.omni_range = 2.2
	_eye_glow.light_energy = 1.2
	_head.add_child(_eye_glow)


func _build_arms() -> void:
	for side in [-1.0, 1.0]:
		var shoulder := _pivot(_spine, Vector3(0.5 * side, 0.92, -0.02))
		_part(_ball(0.13), shoulder, Vector3.ZERO)
		_part(_cone(0.06, 0.25), shoulder, Vector3(0.04 * side, 0.12, 0.04), Vector3(30, 0, -35 * side))
		_part(_limb(0.08, 0.72, 0.06), shoulder, Vector3(0, -0.36, 0))
		var elbow := _pivot(shoulder, Vector3(0, -0.72, 0))
		_part(_ball(0.065), elbow, Vector3.ZERO)
		_part(_limb(0.065, 0.78, 0.04), elbow, Vector3(0, -0.39, 0))
		var hand := _pivot(elbow, Vector3(0, -0.8, 0))
		_part(_ball(0.5), hand, Vector3.ZERO, Vector3.ZERO, Vector3(0.12, 0.1, 0.14))
		# Long hooked claws.
		for k in 4:
			var a := (k - 1.5) * 14.0
			var claw := _pivot(hand, Vector3(0.03 * (k - 1.5), -0.03, -0.03), Vector3(170, a, 0))
			_part(_cone(0.018, 0.3), claw, Vector3(0, 0.15, 0))
		_shoulders.append(shoulder)
		_elbows.append(elbow)


func _build_tendrils() -> void:
	for i in TENDRIL_COUNT:
		var side := -1.0 if i % 2 == 0 else 1.0
		var row := i / 2
		var root := _pivot(_spine, Vector3(0.14 * side + 0.08 * row * side, 0.95 - row * 0.2, 0.22),
			Vector3(-150 + row * 12, 0, -12 * side - row * 6 * side))
		var chain: Array[Node3D] = []
		var parent := root
		var r := 0.075
		for s in TENDRIL_SEGMENTS:
			var length := 0.34 - s * 0.025
			var seg := _pivot(parent, Vector3(0, 0.0 if s == 0 else chain.back().get_meta("length"), 0))
			seg.set_meta("length", length)
			_part(_limb(r * 0.78, length, r), seg, Vector3(0, length * 0.5, 0))
			chain.append(seg)
			parent = seg
			r *= 0.8
		_part(_cone(r * 1.6, 0.12), parent, Vector3(0, parent.get_meta("length") + 0.06, 0))
		_tendrils.append(chain)
		_tendril_phase.append(randf() * TAU)


func _build_particles() -> void:
	var puff := GradientTexture2D.new()
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	puff.gradient = g

	_smoke = _make_particles(40, 1.8, puff, Color(0.0, 0.0, 0.0, 0.55), false, 0.7)
	var smoke_process: ParticleProcessMaterial = _smoke.process_material
	smoke_process.emission_box_extents = Vector3(0.35, 0.8, 0.3)
	smoke_process.gravity = Vector3(0, 0.5, 0)
	smoke_process.initial_velocity_min = 0.1
	smoke_process.initial_velocity_max = 0.5
	smoke_process.scale_min = 0.6
	smoke_process.scale_max = 1.5
	_smoke.position = Vector3(0, 1.5, 0.1)
	add_child(_smoke)

	_embers = _make_particles(18, 1.4, puff, Color(1.0, 0.4, 0.1, 1.0), true, 0.06)
	var ember_process: ParticleProcessMaterial = _embers.process_material
	ember_process.emission_box_extents = Vector3(0.3, 0.7, 0.25)
	ember_process.gravity = Vector3(0, 0.8, 0)
	ember_process.initial_velocity_min = 0.2
	ember_process.initial_velocity_max = 0.8
	ember_process.spread = 60.0
	_embers.position = Vector3(0, 1.6, 0.1)
	add_child(_embers)


static func _make_particles(amount: int, lifetime: float, texture: Texture2D, color: Color, glow: bool, size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.direction = Vector3(0, 1, 0)
	process.spread = 35.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 1))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	p.process_material = process

	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.albedo_texture = texture
	if glow:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = color * 3.0
	quad.material = m
	p.draw_pass_1 = quad
	return p


# ---------------------------------------------------------------------------
# Animation
# ---------------------------------------------------------------------------

func get_head_position() -> Vector3:
	return _head.global_position


## Clears trailing smoke, e.g. after teleporting.
func reset_particles() -> void:
	_smoke.restart()
	_embers.restart()


func animate(delta: float, state: int, state_time: float, speed: float) -> void:
	_time += delta
	var swing := clampf(speed / 6.0, 0.0, 1.0)
	_phase += delta * (speed / 0.9 + 0.5)
	var s := sin(_phase)

	# Defaults: a loping, hunched run with arms dragging.
	var arm := [s * 45.0 * swing + 10.0, -s * 45.0 * swing + 10.0]
	var elbow := [-25.0 - 20.0 * swing, -25.0 - 20.0 * swing]
	var head_roll := 0.0
	var head_pitch := 0.0
	var jaw := 8.0
	var lean := -14.0 - 12.0 * swing
	var rage := 0.25 + 0.25 * swing
	var reach := swing  # tendrils reach forward while chasing
	var whip := 1.0 + 2.0 * swing
	var eyes := 1.0

	match state:
		Pursuer.State.BASHING:
			arm = [140.0 + sin(state_time * 10.0) * 50.0, 140.0 + sin(state_time * 10.0 + PI) * 50.0]
			elbow = [-60.0, -60.0]
			jaw = 30.0
			rage = 0.9
			reach = 1.0
			whip = 4.0
		Pursuer.State.STUNNED:
			# Shielding its face from the light.
			arm = [150.0, 140.0]
			elbow = [-110.0, -100.0]
			head_roll = Chase.perlin(state_time * 20.0) * 30.0
			head_pitch = 25.0
			lean = -10.0
			jaw = 40.0
			rage = 1.0
			reach = -0.6
			whip = 6.0
		Pursuer.State.FEEDING:
			arm = [95.0, 95.0]
			elbow = [-70.0, -70.0]
			jaw = 45.0
			lean = -35.0
			rage = 1.0
			reach = 1.3
			whip = 3.0
		Pursuer.State.LOST:
			arm = [60.0 + sin(state_time * 6.0) * 30.0, 60.0 + sin(state_time * 6.0 + 1.0) * 30.0]
			head_roll = sin(state_time * 3.0) * 20.0
			rage = 0.6
			reach = 0.5
			whip = 2.5
		Pursuer.State.STALKING:
			# Perfectly still, watching. Only the tendrils move.
			arm = [5.0, 5.0]
			elbow = [-15.0, -15.0]
			head_pitch = -10.0
			head_roll = 12.0
			lean = -8.0
			rage = 0.12
			reach = -0.3
			whip = 0.6
			eyes = 2.5  # two points of light in the trees

	var t := clampf(delta * 10.0, 0.0, 1.0)
	for i in 2:
		# Arm angles are relative to hanging straight down, whatever the lean.
		_shoulders[i].rotation_degrees.x = lerpf(_shoulders[i].rotation_degrees.x, arm[i] - _spine.rotation_degrees.x, t)
		_shoulders[i].rotation_degrees.z = (-12.0 if i == 0 else 12.0)
		_elbows[i].rotation_degrees.x = lerpf(_elbows[i].rotation_degrees.x, -elbow[i], t)

	# Legs: thigh swing, knee folds back on the forward stroke.
	for i in 2:
		var leg := s if i == 0 else -s
		_hips[i].rotation_degrees.x = 14.0 + leg * 38.0 * swing
		_knees[i].rotation_degrees.x = -30.0 - maxf(0.0, -leg) * 55.0 * swing
		_ankles[i].rotation_degrees.x = 18.0 + leg * 15.0 * swing

	_spine.rotation_degrees.x = lerpf(_spine.rotation_degrees.x, lean, t)
	# Bent knees lower the hips a little.
	_spine.position.y = HIP_HEIGHT - 0.06 + absf(s) * 0.07 * swing
	# Keep the face level whatever the lean (the neck adds 18 degrees), then tilt.
	_head.rotation_degrees.x = lerpf(_head.rotation_degrees.x, -_spine.rotation_degrees.x - 18.0 + head_pitch, t)
	_head.rotation_degrees.z = lerpf(_head.rotation_degrees.z, head_roll, t)
	_jaw.rotation_degrees.x = lerpf(_jaw.rotation_degrees.x, jaw + sin(_time * 7.0) * 3.0, t)

	# Tendrils: a travelling wave down each chain, curled forward over the
	# shoulders when it reaches for you.
	for i in _tendrils.size():
		var chain: Array = _tendrils[i]
		var ph: float = _tendril_phase[i]
		for k in chain.size():
			var seg: Node3D = chain[k]
			var wave := sin(_time * whip * 2.2 - k * 0.8 + ph)
			var wave2 := cos(_time * whip * 1.7 - k * 0.6 + ph * 1.3)
			var curl := -14.0 * reach * (1.0 if k > 0 else 0.0)
			seg.rotation_degrees.x = lerpf(seg.rotation_degrees.x, curl + wave * (10.0 + 6.0 * whip), t)
			seg.rotation_degrees.z = wave2 * (8.0 + 4.0 * whip)

	_rage = Chase.finterp(_rage, rage, delta, 4.0)
	_skin.set_shader_parameter("rage", _rage)
	_eye_material.emission_energy_multiplier = (3.0 + _rage * 8.0) * eyes
	_eye_glow.light_energy = (0.6 + _rage * 2.0) * eyes
	_smoke.amount_ratio = 0.5 + 0.5 * _rage
