class_name ModelLib
extends RefCounted
## Shared helper for pulling the runtime Mesh resource out of an imported
## .glb PackedScene (see LevelController.FLAVOR_MODELS and
## ClubController.WHACKER_MODELS) - used by both course-piece and whacker
## model swaps so the instantiate/find/cache/free dance only lives in one
## place.


## Returns (and caches, in `cache` under `key`) the Mesh resource from
## `packed`'s first MeshInstance3D descendant. Instantiating a PackedScene
## is the normal way to get at an imported mesh's runtime resource; the
## temporary instance is freed immediately after - the Mesh itself is
## RefCounted and stays alive via the reference `cache` holds onto.
static func get_mesh(packed: PackedScene, cache: Dictionary, key: String) -> Mesh:
	if cache.has(key):
		return cache[key]
	var mesh: Mesh = null
	if packed:
		var inst: Node = packed.instantiate()
		var mesh_instance := find_mesh_instance(inst)
		if mesh_instance:
			mesh = mesh_instance.mesh
		inst.free()
	cache[key] = mesh
	return mesh


static func find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := find_mesh_instance(child)
		if found:
			return found
	return null
