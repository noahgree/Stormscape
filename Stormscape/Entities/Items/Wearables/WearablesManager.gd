class_name WearablesManager
## A collection of static functions that handle adding, removing, and validating wearables on an entity.


## Checks the compatibility of a wearable with the entity who wants to equip it.
static func check_wearable_compatibility(entity: Entity, wearable: WearableStats) -> bool:
	for wearable_entry: Dictionary in entity.wearables:
		if wearable_entry.values()[0] != null:
			if wearable_entry.keys()[0] in wearable.blocked_mutuals:
				return false

	return true

## Handles an incoming wearable, checking its compatibility and eventually adding it if it can.
static func handle_wearable(entity: Entity, wearable: WearableStats, index: int) -> void:
	if not check_wearable_compatibility(entity, wearable):
		return

	var i: int = 0
	for wearable_dict: Dictionary in entity.wearables:
		if wearable_dict.values()[0] != null:
			if wearable_dict.keys()[0] == wearable.id:
				remove_wearable(entity, wearable_dict.values()[0], i)
			elif i == index and wearable_dict.values()[0] != null:
				push_warning("\"" + wearable_dict.keys()[0] + "\" was already in wearable slot " + str(i) + " and will now be removed to make room for \"" + wearable.id + "\"")
				remove_wearable(entity, wearable_dict.values()[0], i)
		i += 1

	add_wearable(entity, wearable, index)

## Adds a wearable to the dictionary.
static func add_wearable(entity: Entity, wearable: WearableStats, index: int) -> void:
	if DebugFlags.wearable_changes:
		print_rich("-------[color=green]Adding[/color][b] " + str(wearable.name) + " (" + str(wearable.rarity) + ")[/b][color=gray] to " + entity.name + " (slot " + str(index) + ")" + "-------")

	entity.wearables[index] = { wearable.id : wearable }

	for mod_resource: StatMod in wearable.stat_mods:
		entity.stats.add_mods([mod_resource] as Array[StatMod])

	AudioManager.play_global(wearable.equipping_audio)

## Removes the wearable from the dictionary.
static func remove_wearable(entity: Entity, wearable: WearableStats, index: int) -> void:
	if DebugFlags.wearable_changes and WearablesManager.has_wearable(entity, wearable.id, index):
		print_rich("-------[color=red]Removed[/color][b] " + str(wearable.name) + " (" + str(wearable.rarity) + ")[/b][color=gray] from " + entity.name + " (slot " + str(index) + ")" + "-------")

	for mod_resource: StatMod in wearable.stat_mods:
		entity.stats.remove_mod(mod_resource.stat_id, mod_resource.mod_id)

	entity.wearables[index] = { "EmptySlot" : null }

	AudioManager.play_global(wearable.removal_audio)

## Removes all wearables from the entity.
static func removal_all_wearables(entity: Entity) -> void:
	var i: int = 0
	for wearable_dict: Dictionary in entity.wearables:
		if wearable_dict.values()[0] != null:
			remove_wearable(entity, wearable_dict.values()[0], i)
		i += 1

## Adds all wearables in an entity's wearables array back on to it. (i.e. readds all mods from them).
static func re_add_all_wearables(entity: Entity) -> void:
	var i: int = 0
	for wearable_dict: Dictionary in entity.wearables:
		if wearable_dict.values()[0] != null:
			add_wearable(entity, wearable_dict.values()[0], i)
		i += 1

## Checks to see if the entity has the passed in wearable already, regardless of level.
static func has_wearable(entity: Entity, wearable_id: StringName, index: int = -1) -> bool:
	var i: int = 0
	for wearable_entry: Dictionary in entity.wearables:
		if wearable_entry.values()[0] != null:
			if wearable_entry.keys()[0] == wearable_id:
				if index != -1:
					if i == index:
						return true
					else:
						i += 1
						continue
				return true
		i += 1
	return false
