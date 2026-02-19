@tool
extends Entity
class_name RigidEntity
## An entity that can move and rotate with physics and that also cannot have non-HP stats like stamina and hunger.
##
## This would be used for things like blocks that respond to explosions and that also need potential health.
## This should not be used for static environmental entities like trees and also not for players
## or moving enemies.

@export var immovable: bool = false ## When true, this will not be able to be moved around by impulse forces.

@onready var anim_tree: AnimationTree = $AnimationTree ## The animation tree controlling this entity's animation states.
@onready var facing_component: FacingComponent = $FacingComponent ## The component in charge of choosing the entity animation directions.


#region Save & Load
func _on_save_game(save_data: Array[SaveData]) -> void:
	var data: RigidEntityData = RigidEntityData.new()

	data.scene_path = scene_file_path

	data.position = global_position

	data.stat_mods = stats.stat_mods
	data.wearables = wearables

	data.sprite_frames_path = sprite.sprite_frames.resource_path

	data.health = health_component.health
	data.shield = health_component.shield
	data.armor = health_component.armor

	data.facing_dir = facing_component.facing_dir

	if inv != null:
		for item: InvItemStats in inv.inv:
			if item != null and item.stats is WeaponStats:
				item.stats.weapon_mods_need_to_be_readded_after_save = true
		data.inv = inv.inv
	if item_receiver != null:
		data.pickup_range = item_receiver.pickup_range

	data.loot = loot.duplicate() if loot else null

	save_data.append(data)

func _on_before_load_game() -> void:
	# In case we try to drop inventory on death
	if inv:
		inv.clear_inventory()
	queue_free()

func _is_instance_on_load_game(data: RigidEntityData) -> void:
	global_position = data.position

	Globals.world_root.add_child(self)

	stats.stat_mods = data.stat_mods
	wearables = data.wearables
	stats.reinit_on_load()

	sprite.sprite_frames = load(data.sprite_frames_path)

	facing_component.facing_dir = data.facing_dir

	health_component.just_loaded = true
	health_component.health = data.health
	health_component.shield = data.shield
	health_component.armor = data.armor

	if inv != null:
		inv.call_deferred("fill_inventory", data.inv)
	if item_receiver != null:
		item_receiver.pickup_range = data.pickup_range

	loot = data.loot
	if loot:
		loot.initialize(self)
#endregion

## Edits editor warnings for easier debugging.
func _get_configuration_warnings() -> PackedStringArray:
	if get_node_or_null("%EntitySprite") == null or not %EntitySprite is EntitySprite:
		return [
			"This entity must have an EntitySprite typed sprite node. Make sure its name is unique with a %."
			]
	return []

## Making sure we know we have save logic, even if not set in editor. Then set up rigid body physics.
func _ready() -> void:
	super()

	self.mass = 3
	self.linear_damp = 4.5
	var phys_material: PhysicsMaterial = PhysicsMaterial.new()
	phys_material.friction = 1.0
	phys_material.rough = true
	self.physics_material_override = phys_material
	if immovable:
		self.freeze = true
