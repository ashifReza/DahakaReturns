class_name Greybox
## Placeholder visuals built from basic shapes, so the game runs with zero
## imported assets. Swap meshes and materials in the editor any time.

static var _materials := {}


## A plain matte material, shared between everything with the same colour.
static func material(color: Color, emission := Color.BLACK) -> StandardMaterial3D:
	var key := str(color) + str(emission)
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if emission != Color.BLACK:
		m.emission_enabled = true
		m.emission = emission
	_materials[key] = m
	return m


static func box(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _instance(mesh, color)


static func cylinder(radius: float, height: float, color: Color, top_radius := -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	return _instance(mesh, color)


static func sphere(radius: float, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	return _instance(mesh, color)


static func _instance(mesh: Mesh, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material(color)
	return mi
