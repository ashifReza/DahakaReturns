@tool
class_name JungleArea
extends Forest
## An open stretch of jungle to roam, instead of a corridor: trees to weave
## between, ferns and bushes everywhere, undergrowth along the edges (put
## the invisible walls there), and thick forest beyond. Landmarks and
## pickups get a clear patch with `clear_spots`.

## The walkable area, in XZ.
@export var area := Rect2()
## Kept clear of trees: each is (x, radius, z).
@export var clear_spots := PackedVector3Array()
## Chance per scatter point inside the area (a point every ~6 square metres).
@export var tree_chance := 0.075
@export var bush_chance := 0.05


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_foliage.clear()
	_foliage_rest.clear()
	_grid.clear()
	if area.size == Vector2.ZERO:
		return
	_rng.seed = grow_seed

	var trunks: Array[Transform3D] = []
	var canopies: Array[Transform3D] = []
	var bushes: Array[Transform3D] = []
	var ferns: Array[Transform3D] = []
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	var outer := area.grow(forest_depth)
	var count := int(outer.get_area() / 6.0)
	for i in count:
		var p := Vector3(_rng.randf_range(outer.position.x, outer.end.x), 0.0, _rng.randf_range(outer.position.y, outer.end.y))
		if _in_clearing(p):
			continue
		var q := Vector2(p.x, p.z)
		if area.has_point(q):
			var edge := minf(minf(q.x - area.position.x, area.end.x - q.x), minf(q.y - area.position.y, area.end.y - q.y))
			if edge < 1.6:
				# Undergrowth hiding the walls at the edge.
				bushes.append(_bush(p))
				continue
			var spot := _spot_clearance(q)
			var r := _rng.randf()
			if r < tree_chance and spot > 2.0 and edge > 2.5:
				_tree(p, trunks, canopies, body)
			elif r < tree_chance + bush_chance and spot > 1.5:
				bushes.append(_bush(p))
			elif r < 0.55:
				ferns.append(_fern(p, 0.6 if spot < 1.0 else 1.0))
		else:
			var d := _outside_distance(q)
			if d < 1.5:
				bushes.append(_bush(p))
			elif _rng.randf() < 0.32:
				_tree(p, trunks, canopies, null)
			elif _rng.randf() < 0.25:
				bushes.append(_bush(p))
	_finish(trunks, canopies, bushes, ferns)


## How far beyond the nearest clear spot's edge a point is (negative inside one).
func _spot_clearance(q: Vector2) -> float:
	var best := INF
	for s in clear_spots:
		best = minf(best, q.distance_to(Vector2(s.x, s.z)) - s.y)
	return best


func _outside_distance(q: Vector2) -> float:
	var c := q.clamp(area.position, area.end)
	return q.distance_to(c)
