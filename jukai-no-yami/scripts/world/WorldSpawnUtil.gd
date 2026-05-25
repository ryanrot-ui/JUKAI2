extends RefCounted
## Spawner helpers — set exports on script, then add_child (never the reverse).

const _TREE := preload("res://scripts/world/TreeSpawner.gd")
const _GRASS := preload("res://scripts/world/GrassSpawner.gd")
const _RIBBON := preload("res://scripts/world/RibbonSpawner.gd")
const _ROCK := preload("res://scripts/world/LavaRockSpawner.gd")
const _LANDMARK := preload("res://scripts/world/LandmarkSpawner.gd")


static func add_tree_spawner(parent: Node3D, pos: Vector3, cfg: Dictionary) -> Node3D:
	return _attach(parent, _TREE, pos, cfg)


static func add_grass_spawner(parent: Node3D, pos: Vector3, cfg: Dictionary) -> Node3D:
	return _attach(parent, _GRASS, pos, cfg)


static func add_ribbon_spawner(parent: Node3D, pos: Vector3, cfg: Dictionary) -> Node3D:
	return _attach(parent, _RIBBON, pos, cfg)


static func add_rock_spawner(parent: Node3D, pos: Vector3, cfg: Dictionary) -> Node3D:
	return _attach(parent, _ROCK, pos, cfg)


static func add_landmark_spawner(parent: Node3D, cfg: Dictionary) -> Node3D:
	return _attach(parent, _LANDMARK, Vector3.ZERO, cfg)


static func _attach(parent: Node3D, script: Script, pos: Vector3, cfg: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.position = pos
	node.set_script(script)
	_apply_cfg(node, cfg)
	parent.add_child(node)
	return node


static func _apply_cfg(node: Object, cfg: Dictionary) -> void:
	for key in cfg:
		if key in node:
			node.set(key, cfg[key])
