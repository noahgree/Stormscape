@tool
extends Entity
class_name StaticEntity
## An entity without the ability to move or rotate at all and that also cannot have non HP stats like
## stamina and hunger.
##
## This would be used for things like trees or blocks or buildings that need collision and also potential health.

#region Save & Load
func _on_save_game(save_data: Array[SaveData]) -> void:
	var data: StaticEntityData = StaticEntityData.new()

	data.scene_path = scene_file_path

	data.position = global_position

	data.stat_mods = stats.stat_mods
	data.wearables = wearables

	data.sprite_frames_path = sprite.sprite_frames.resource_path

	data.health = health_component.health
	data.shield = health_component.shield
	data.armor = health_component.armor

	if inv != null:
		for item: InvItemResource in inv.inv:
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

func _is_instance_on_load_game(data: StaticEntityData) -> void:
	global_position = data.position

	Globals.world_root.add_child(self)

	stats.stat_mods = data.stat_mods
	wearables = data.wearables
	stats.reinit_on_load()

	sprite.sprite_frames = load(data.sprite_frames_path)

	health_component.just_loaded = true
	health_component.health = data.health
	health_component.shield = data.shield
	health_component.armor = data.armor

	if inv:
		inv.call_deferred("fill_inventory", data.inv)
	if item_receiver:
		item_receiver.pickup_range = data.pickup_range

	loot = data.loot
	if loot:
		loot.initialize(self)
#endregion
