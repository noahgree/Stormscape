extends Resource
class_name II
## "II" stands for ItemInstance, and is the wrapper for all item instances in the game. This holds a reference
## to the stats powering this item as well as unqiue properties like the uid.

signal stats_changed(new_stats: ItemStats)
signal q_changed(new_q: int)

@export_storage var uid: int = UIDHelper.uid() ## The unique id for this item resource instance.
@export var stats: ItemStats: ## The resource driving the stats and type of item this is.
	set(new_stats):
		stats = new_stats
		stats_changed.emit(stats)
@export var q: int = 1: ## The quantity associated with the inventory item.
	set(new_q):
		q = new_q
		q_changed.emit(q)

## Returns the cooldown id based on how cooldowns are determined for this item.
func get_cooldown_id() -> StringName:
	if stats.cooldowns_shared:
		return StringName(stats.id)
	else:
		return StringName(str(uid))

## Custom print logic for determining more about the item that just a randomly assigned ID.
func _to_string() -> String:
	return "(" + str(q) + ") " + str(Globals.ItemRarity.keys()[stats.rarity]) + "_" + stats.name

## Returns the quantity and the name for display purposes.
func get_pretty_string() -> String:
	return str(q) + " " + stats.name
