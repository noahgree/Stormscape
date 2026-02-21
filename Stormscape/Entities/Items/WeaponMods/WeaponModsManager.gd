class_name WeaponModsManager
## A collection of static functions that handle adding, removing, and restoring weapon mods on a weapon.


## Checks if the mod can be attached to the weapon.
static func check_mod_compatibility(weapon_ii: WeaponII, weapon_mod: WeaponModStats) -> bool:
	var weapon_stats: WeaponStats = weapon_ii.stats
	if weapon_mod.id in weapon_stats.blocked_mods:
		return false
	if weapon_stats is MeleeWeaponStats and weapon_stats.melee_weapon_type not in weapon_mod.allowed_melee_wpns:
		return false
	elif weapon_stats is ProjWeaponStats and weapon_stats.proj_weapon_type not in weapon_mod.allowed_proj_wpns:
		return false
	for blocked_mutual_id: StringName in weapon_mod.blocked_mutuals:
		if weapon_ii.has_mod_by_id(blocked_mutual_id):
			return false

	var failed: bool = false
	for blocked_stat: StringName in weapon_mod.blocked_wpn_stats:
		if weapon_ii.get_nested_stat(blocked_stat, false) == weapon_mod.blocked_wpn_stats[blocked_stat]:
			failed = true
		elif weapon_mod.req_all_blocked_stats:
			failed = false
			break
	if failed:
		return false

	for required_stat: StringName in weapon_mod.required_stats:
		if weapon_ii.get_nested_stat(required_stat, false) != weapon_mod.required_stats[required_stat]:
			return false

	return true

## Returns how many mods the weapon can have on it.
static func get_max_mod_slots(weapon_stats: WeaponStats) -> int:
	if weapon_stats.max_mods_override != -1:
		return weapon_stats.max_mods_override
	else:
		return int(weapon_stats.rarity + 1)

## Gets the next open mod slot within range of the max amount of mods the weapon can have. -1 means no open slots.
static func get_next_open_mod_slot(weapon_ii: WeaponII) -> int:
	for mod_slot_index: int in range(weapon_ii.current_mods.size()):
		if weapon_ii.current_mods[mod_slot_index] == &"":
			return mod_slot_index
	return -1

## Handles an incoming added weapon mod. Removes it first if it already exists and then just re-adds it.
static func handle_weapon_mod(weapon_ii: WeaponII, weapon_mod: WeaponModStats, index: int,
						source_entity: Entity, handle_silently: bool = false) -> void:
	if not check_mod_compatibility(weapon_ii, weapon_mod):
		return
	if index > WeaponModsManager.get_max_mod_slots(weapon_ii.stats) - 1:
		push_error("\"" + weapon_ii.stats.name + "\" tried to add the mod \"" + weapon_mod.name + "\" to slot " + str(index + 1) + " / 6, but that slot is not unlocked for that weapon.")
		return

	for mod_slot_index: int in range(weapon_ii.current_mods.size()):
		if weapon_mod.id == weapon_ii.current_mods[mod_slot_index]:
			remove_weapon_mod(weapon_ii, mod_slot_index, source_entity, handle_silently)
		elif mod_slot_index == index and weapon_ii.current_mods[mod_slot_index] != &"":
			push_warning("\"" + weapon_ii.current_mods[mod_slot_index] + "\" was already in mod slot " + str(mod_slot_index) + " and will now be removed to make room for \"" + weapon_mod.get_cache_key() + "\"")
			remove_weapon_mod(weapon_ii, mod_slot_index, source_entity, handle_silently)

	_add_weapon_mod(weapon_ii, weapon_mod, index, source_entity, handle_silently)

## Adds a weapon mod to the dictionary and then calls the on_added method inside the mod itself.
static func _add_weapon_mod(weapon_ii: WeaponII, weapon_mod: WeaponModStats, index: int,
							source_entity: Entity, add_silently: bool = false) -> void:
	# ----- Debug printouts -----
	if DebugFlags.weapon_mod_changes and not add_silently:
		print_rich("-------[color=green]Adding[/color][b] " + weapon_mod.name + " (" + str(weapon_mod.rarity) + ")[/b] [color=gray]to " + weapon_ii.stats.name + " (slot " + str(index) + ")" + "-------")

	# ----- Adding to the current mods array -----
	weapon_ii.current_mods[index] = StringName(weapon_mod.get_cache_key())

	# ----- Updating the stat cache & effect source overrides for normal stats -----
	for mod_resource: StatMod in weapon_mod.wpn_stat_mods:
		weapon_ii.sc.add_mods([mod_resource] as Array[StatMod])
		_update_es_overrides(weapon_ii, mod_resource.stat_id)

	# ----- Updating effect source instances with new status effects -----
	weapon_ii.normal_esi.replace_or_add_status_effects(weapon_mod.status_effects)
	if weapon_ii.charge_esi.es:
		weapon_ii.charge_esi.replace_or_add_status_effects(weapon_mod.charge_status_effects)
	if weapon_ii.aoe_esi.es:
		weapon_ii.aoe_esi.replace_or_add_status_effects(weapon_mod.aoe_status_effects)

	# ----- Debug printouts after the fact -----
	if DebugFlags.weapon_mod_changes and not add_silently:
		_debug_print_status_effect_lists(weapon_ii)

	# ----- Callbacks and resulting audio -----
	weapon_mod.on_added(weapon_ii, source_entity.hands.equipped_item if source_entity != null else null)
	if not add_silently:
		AudioManager.play_global(weapon_mod.equipping_audio)

## Removes the weapon mod from the dictionary after calling the on_removal method inside the mod itself.
static func remove_weapon_mod(weapon_ii: WeaponII, index: int, source_entity: Entity,
								remove_silently: bool = false) -> void:
	# ----- Ensuring the mod exists -----
	var mod_to_remove: WeaponModStats = Items.cached_items.get(weapon_ii.current_mods[index], null)
	if mod_to_remove == null:
		push_error("The mod at index " + str(index) + " of " + weapon_ii.stats.name + " could not be removed.")
		return

	# ----- Debug printouts -----
	if DebugFlags.weapon_mod_changes and weapon_ii.has_mod(mod_to_remove.id, index) and not remove_silently:
		print_rich("-------[color=red]Removed[/color][b] " + str(mod_to_remove.name) + " (" + str(mod_to_remove.rarity) + ")[/b] [color=gray]from " + weapon_ii.stats.name + " (slot " + str(index) + ")" + "-------")

	# ----- Updating the stat cache & effect source overrides for normal stats -----
	for mod_resource: StatMod in mod_to_remove.wpn_stat_mods:
		weapon_ii.sc.remove_mod(mod_resource.stat_id, mod_resource.mod_id)
		_update_es_overrides(weapon_ii, mod_resource.stat_id)

	# ----- Removing from the current mods array -----
	weapon_ii.current_mods[index] = &""

	# ----- Resyncing effect source instances -----
	_resync_esi_status_effects(weapon_ii)

	# ----- Debug printouts after the fact -----
	if DebugFlags.weapon_mod_changes and not remove_silently:
		_debug_print_status_effect_lists(weapon_ii)

	# ----- Callbacks and resulting audio -----
	mod_to_remove.on_removal(weapon_ii, source_entity.hands.equipped_item if source_entity != null else null)
	if not remove_silently:
		AudioManager.play_global(mod_to_remove.removal_audio)

## Adds all mods in the current_mods array to a weapon's stats.
static func add_all_mods_to_weapon(weapon_ii: WeaponII, source_entity: Entity) -> void:
	for mod_slot_index: int in range(weapon_ii.current_mods.size()):
		if weapon_ii.current_mods[mod_slot_index] != &"":
			var mod: WeaponModStats = Items.cached_items.get(weapon_ii.current_mods[mod_slot_index], null)
			remove_weapon_mod(weapon_ii, mod_slot_index, source_entity, true)
			if mod:
				handle_weapon_mod(weapon_ii, mod, mod_slot_index, source_entity, true)
			else:
				push_error("Adding all mods to " + weapon_ii.stats.name + " failed.")

## Removes all mods from a passed in weapon_stats resource.
static func remove_all_mods_from_weapon(weapon_ii: WeaponII, source_entity: Entity) -> void:
	for mod_slot_index: int in range(weapon_ii.current_mods.size()):
		if weapon_ii.current_mods[mod_slot_index] != &"":
			remove_weapon_mod(weapon_ii, mod_slot_index, source_entity)

## When mods are added or removed that affect the effect source stats, we use this to recalculate them.
static func _update_es_overrides(weapon_ii: WeaponII, stat_id: StringName) -> void:
	if stat_id in [&"base_damage", &"base_healing", &"crit_chance", &"armor_penetration", &"object_damage_mult"]:
			weapon_ii.stat_overrides[stat_id] = weapon_ii.sc.get_stat(stat_id)
	elif weapon_ii.stats is MeleeWeaponStats:
		if stat_id in [&"charge_base_damage", &"charge_base_healing", &"charge_crit_chance", &"charge_armor_penetration", &"charge_object_damage_mult"]:
			weapon_ii.stat_overrides[stat_id] = weapon_ii.sc.get_stat(stat_id)
	elif weapon_ii.stats is ProjWeaponStats:
		if stat_id in [&"proj_aoe_base_damage", &"proj_aoe_base_healing"]:
			weapon_ii.stat_overrides[stat_id] = weapon_ii.sc.get_stat(stat_id)

## Resyncs the status effect lists for all effect source instances on a weapon instance after mods were
## removed. Must be done to restore any status effects from the original effect source that were
## previously replaced.
static func _resync_esi_status_effects(weapon_ii: WeaponII) -> void:
	weapon_ii.normal_esi.reset_status_effects()
	if weapon_ii.charge_esi.es:
		weapon_ii.charge_esi.reset_status_effects()
	if weapon_ii.aoe_esi.es:
		weapon_ii.aoe_esi.reset_status_effects()

	for wpn_mod: WeaponModStats in weapon_ii.get_all_mods_as_stats():
		weapon_ii.normal_esi.replace_or_add_status_effects(wpn_mod.status_effects)
		if weapon_ii.charge_esi.es:
			weapon_ii.charge_esi.replace_or_add_status_effects(wpn_mod.charge_status_effects)
		if weapon_ii.aoe_esi.es:
			weapon_ii.aoe_esi.replace_or_add_status_effects(wpn_mod.aoe_status_effects)

#region Debug
## Formats the updated lists of status effects and prints them out.
static func _debug_print_status_effect_lists(weapon_ii: WeaponII) -> void:
	var is_normal_base: bool = true if weapon_ii.normal_esi.status_effects == weapon_ii.normal_esi.es.status_effects else false
	print_rich("[color=cyan]Normal Effects[/color]" + ("[color=gray][i](base)[/i][/color]" if is_normal_base else "") + ": [b]"+ str(weapon_ii.normal_esi.status_effects) + "[/b]")
	if weapon_ii.stats is MeleeWeaponStats:
		var is_normal_charge: bool = true if weapon_ii.charge_esi.status_effects == weapon_ii.charge_esi.es.status_effects else false
		print_rich("[color=cyan]Charge Effects[/color]" + ("[color=gray][i](base)[/i][/color]" if is_normal_charge else "") + ": [b]"+ str(weapon_ii.charge_esi.status_effects) + "[/b]")
	if weapon_ii.stats is ProjWeaponStats and weapon_ii.stats.projectile_logic.aoe_radius > 0:
		var is_normal_aoe: bool = true if weapon_ii.aoe_esi.status_effects == weapon_ii.aoe_esi.es.status_effects else false
		print_rich("[color=cyan]AOE Effects[/color]" + ("[color=gray][i](base)[/i][/color]" if is_normal_aoe else "") + ": [b]"+ str(weapon_ii.aoe_esi.status_effects) + "[/b]")
#endregion
