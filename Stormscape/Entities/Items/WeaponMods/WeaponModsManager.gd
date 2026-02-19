class_name WeaponModsManager
## A collection of static functions that handle adding, removing, and restoring weapon mods on a weapon.

enum EffectSourceType { NORMAL, CHARGE, AOE } ## The kinds of effect sources that can be modified.


## Checks if the mod can be attached to the weapon.
static func check_mod_compatibility(weapon_stats: WeaponStats, weapon_mod: WeaponModStats) -> bool:
	if weapon_mod.id in weapon_stats.blocked_mods:
		return false
	if weapon_stats is MeleeWeaponStats and weapon_stats.melee_weapon_type not in weapon_mod.allowed_melee_wpns:
		return false
	elif weapon_stats is ProjWeaponStats and weapon_stats.proj_weapon_type not in weapon_mod.allowed_proj_wpns:
		return false
	for blocked_mutual: StringName in weapon_mod.blocked_mutuals:
		if weapon_stats.has_mod(blocked_mutual):
			return false

	var failed: bool = false
	for blocked_stat: StringName in weapon_mod.blocked_wpn_stats:
		if weapon_stats.get_nested_stat(blocked_stat, false) == weapon_mod.blocked_wpn_stats[blocked_stat]:
			failed = true
		elif weapon_mod.req_all_blocked_stats:
			failed = false
			break
	if failed:
		return false

	for required_stat: StringName in weapon_mod.required_stats:
		if weapon_stats.get_nested_stat(required_stat, false) != weapon_mod.required_stats[required_stat]:
			return false

	return true

## Returns how many mods the weapon can have on it.
static func get_max_mod_slots(weapon_stats: WeaponStats) -> int:
	if weapon_stats.max_mods_override != -1:
		return weapon_stats.max_mods_override
	else:
		return int(weapon_stats.rarity + 1)

## Gets the next open mod slot within range of the max amount of mods the weapon can have. -1 means no open slots.
static func get_next_open_mod_slot(weapon_stats: WeaponStats) -> int:
	var i: int = 0
	for weapon_mod_entry: Dictionary in weapon_stats.current_mods:
		if weapon_mod_entry.values()[0] == null:
			return i
		i += 1
	return -1

## Handles an incoming added weapon mod. Removes it first if it already exists and then just re-adds it.
static func handle_weapon_mod(weapon_stats: WeaponStats, weapon_mod: WeaponModStats, index: int,
						source_entity: Entity) -> void:
	if not check_mod_compatibility(weapon_stats, weapon_mod):
		return
	if index > WeaponModsManager.get_max_mod_slots(weapon_stats) - 1:
		push_error("\"" + weapon_stats.name + "\" tried to add the mod \"" + weapon_mod.name + "\" to slot " + str(index + 1) + " / 6, but that slot is not unlocked for that weapon.")
		return

	var i: int = 0
	for weapon_mod_entry: Dictionary in weapon_stats.current_mods:
		if (weapon_mod.id == weapon_mod_entry.keys()[0]) and (weapon_mod_entry.values()[0] != null):
			remove_weapon_mod(weapon_stats, weapon_mod_entry.values()[0], i, source_entity)
		elif i == index and weapon_mod_entry.values()[0] != null:
			push_warning("\"" + weapon_mod_entry.keys()[0] + "\" was already in mod slot " + str(i) + " and will now be removed to make room for \"" + weapon_mod.id + "\"")
			remove_weapon_mod(weapon_stats, weapon_mod_entry.values()[0], i, source_entity)
		i += 1

	_add_weapon_mod(weapon_stats, weapon_mod, index, source_entity)

## Adds a weapon mod to the dictionary and then calls the on_added method inside the mod itself.
static func _add_weapon_mod(weapon_stats: WeaponStats, weapon_mod: WeaponModStats, index: int,
					source_entity: Entity) -> void:
	if DebugFlags.weapon_mod_changes:
		print_rich("-------[color=green]Adding[/color][b] " + weapon_mod.name + " (" + str(weapon_mod.rarity) + ")[/b] [color=gray]to " + weapon_stats.name + " (slot " + str(index) + ")" + "-------")

	weapon_stats.current_mods[index] = { weapon_mod.id : weapon_mod }

	for mod_resource: StatMod in weapon_mod.wpn_stat_mods:
		weapon_stats.s_mods.add_mods([mod_resource] as Array[StatMod])
		_update_effect_source_stats(weapon_stats, mod_resource.stat_id)

	_update_effect_source_status_effects(weapon_stats, EffectSourceType.NORMAL, weapon_mod.status_effects)
	if weapon_stats is MeleeWeaponStats:
		_update_effect_source_status_effects(weapon_stats, EffectSourceType.CHARGE, weapon_mod.charge_status_effects)
	elif weapon_stats is ProjWeaponStats:
		_update_effect_source_status_effects(weapon_stats, EffectSourceType.AOE, weapon_mod.aoe_status_effects)

	if DebugFlags.weapon_mod_changes:
		_debug_print_status_effect_lists(weapon_stats)

	weapon_mod.on_added(weapon_stats, source_entity.hands.equipped_item if source_entity != null else null)

	AudioManager.play_global(weapon_mod.equipping_audio)

## Removes the weapon mod from the dictionary after calling the on_removal method inside the mod itself.
static func remove_weapon_mod(weapon_stats: WeaponStats, weapon_mod: WeaponModStats, index: int,
						source_entity: Entity) -> void:
	if DebugFlags.weapon_mod_changes and weapon_stats.has_mod(weapon_mod.id, index):
		print_rich("-------[color=red]Removed[/color][b] " + str(weapon_mod.name) + " (" + str(weapon_mod.rarity) + ")[/b] [color=gray]from " + weapon_stats.name + " (slot " + str(index) + ")" + "-------")

	for mod_resource: StatMod in weapon_mod.wpn_stat_mods:
		weapon_stats.s_mods.remove_mod(mod_resource.stat_id, mod_resource.mod_id)
		_update_effect_source_stats(weapon_stats, mod_resource.stat_id)

	weapon_stats.current_mods[index] = { "EmptySlot" : null }

	_remove_mod_status_effects_from_effect_source(weapon_stats, EffectSourceType.NORMAL)
	if weapon_stats is MeleeWeaponStats:
		_remove_mod_status_effects_from_effect_source(weapon_stats, EffectSourceType.CHARGE)
	elif weapon_stats is ProjWeaponStats:
		_remove_mod_status_effects_from_effect_source(weapon_stats, EffectSourceType.AOE)

	if DebugFlags.weapon_mod_changes:
		_debug_print_status_effect_lists(weapon_stats)

	weapon_mod.on_removal(weapon_stats, source_entity.hands.equipped_item if source_entity != null else null)

	AudioManager.play_global(weapon_mod.removal_audio)

## Adds all mods in the current_mods array to a weapon's stats. Useful for restoring after a save and load.
static func re_add_all_mods_to_weapon(weapon_stats: WeaponStats, source_entity: Entity) -> void:
	var i: int = 0
	for weapon_mod_entry: Dictionary in weapon_stats.current_mods:
		if weapon_mod_entry.values()[0] != null:
			handle_weapon_mod(weapon_stats, weapon_mod_entry.values()[0], i, source_entity)
		i += 1

## Copies all mods from a weapon to the new weapon, optionally deleting them from the source afterward.
static func copy_mods_between_weapons(original_wpn: WeaponStats, target_wpn: WeaponStats,
											source_entity: Entity, remove_from_orig: bool) -> void:
	var i: int = 0
	for weapon_mod_entry: Dictionary in original_wpn.current_mods:
		if weapon_mod_entry.values()[0] != null:
			handle_weapon_mod(target_wpn, weapon_mod_entry.values()[0], i, source_entity)
			if remove_from_orig:
				remove_weapon_mod(original_wpn, weapon_mod_entry.values()[0], i, source_entity)
		i += 1

## Removes all mods from a passed in weapon_stats resource.
static func remove_all_mods_from_weapon(weapon_stats: WeaponStats, source_entity: Entity) -> void:
	var i: int = 0
	for weapon_mod_entry: Dictionary in weapon_stats.current_mods:
		if weapon_mod_entry.values()[0] != null:
			remove_weapon_mod(weapon_stats, weapon_mod_entry.values()[0], i, source_entity)
		i += 1

## When mods are added or removed that affect the effect source stats, we use this to recalculate them.
static func _update_effect_source_stats(weapon_stats: WeaponStats, stat_id: StringName) -> void:
	match stat_id:
		&"base_damage":
			weapon_stats.effect_source.base_damage = weapon_stats.s_mods.get_stat("base_damage")
		&"base_healing":
			weapon_stats.effect_source.base_healing = weapon_stats.s_mods.get_stat("base_healing")
		&"crit_chance":
			weapon_stats.effect_source.crit_chance = weapon_stats.s_mods.get_stat("crit_chance")
		&"armor_penetration":
			weapon_stats.effect_source.armor_penetration = weapon_stats.s_mods.get_stat("armor_penetration")
		&"object_damage_mult":
			weapon_stats.effect_source.object_damage_mult = weapon_stats.s_mods.get_stat("object_damage_mult")

	# Projectile weapons don't have separate charge stats since they can only be one firing type
	if weapon_stats is MeleeWeaponStats:
		match(stat_id):
			&"charge_base_damage":
				weapon_stats.charge_effect_source.base_damage = weapon_stats.s_mods.get_stat("charge_base_damage")
			&"charge_base_healing":
				weapon_stats.charge_effect_source.base_healing = weapon_stats.s_mods.get_stat("charge_base_healing")
			&"charge_crit_chance":
				weapon_stats.charge_effect_source.crit_chance = weapon_stats.s_mods.get_stat("charge_crit_chance")
			&"charge_armor_penetration":
				weapon_stats.charge_effect_source.armor_penetration = weapon_stats.s_mods.get_stat("charge_armor_penetration")
			&"charge_object_damage_mult":
				weapon_stats.charge_effect_source.object_damage_mult = weapon_stats.s_mods.get_stat("charge_object_damage_mult")

	# Melee weapons don't have separate aoe stats since they cannot produce areas of effect
	elif weapon_stats is ProjWeaponStats:
		match(stat_id):
			&"proj_aoe_base_damage":
				weapon_stats.projectile_logic.aoe_effect_source.base_damage = weapon_stats.s_mods.get_stat("proj_aoe_base_damage")
			&"proj_aoe_base_healing":
				weapon_stats.projectile_logic.aoe_effect_source.base_healing = weapon_stats.s_mods.get_stat("proj_aoe_base_healing")

## Updates the effect source status effect lists based on an incoming stat mod.
## Handles duplicates by keeping the highest level.
static func _update_effect_source_status_effects(weapon_stats: WeaponStats, type: EffectSourceType,
											new_effects: Array[StatusEffect]) -> void:
	var effect_source: EffectSource
	match type:
		EffectSourceType.NORMAL:
			effect_source = weapon_stats.effect_source
		EffectSourceType.CHARGE when weapon_stats is MeleeWeaponStats:
			effect_source = weapon_stats.charge_effect_source
		EffectSourceType.AOE when weapon_stats is ProjWeaponStats and weapon_stats.projectile_logic.aoe_effect_source:
			effect_source = weapon_stats.projectile_logic.aoe_effect_source

	if effect_source == null:
		return
	for new_effect: StatusEffect in new_effects:
		var existing_effect_index: int = effect_source.check_for_effect_and_get_index(new_effect.get_full_effect_key())
		if existing_effect_index != -1:
			if new_effect.effect_lvl > effect_source.status_effects[existing_effect_index].effect_lvl:
				effect_source.status_effects[existing_effect_index] = new_effect
		else:
			effect_source.status_effects.append(new_effect)

## Updates the status effect lists after removing a mod (by not using the old mod's status effects anymore).
static func _remove_mod_status_effects_from_effect_source(weapon_stats: WeaponStats,
															type: EffectSourceType) -> void:
	var effect_source: EffectSource
	var orig_array: Array[StatusEffect]
	match type:
		EffectSourceType.NORMAL:
			effect_source = weapon_stats.effect_source
			orig_array = weapon_stats.original_status_effects
		EffectSourceType.CHARGE when weapon_stats is MeleeWeaponStats:
			effect_source = weapon_stats.charge_effect_source
			orig_array = weapon_stats.original_charge_status_effects
		EffectSourceType.AOE when weapon_stats is ProjWeaponStats and weapon_stats.projectile_logic.aoe_effect_source:
			effect_source = weapon_stats.projectile_logic.aoe_effect_source
			orig_array = weapon_stats.original_aoe_status_effects

	if effect_source == null:
		return
	effect_source.status_effects = orig_array.duplicate()

	for weapon_mod_entry: Dictionary in weapon_stats.current_mods:
		var mod: WeaponModStats = weapon_mod_entry.values()[0]
		if mod != null:
			var mod_status_effects: Array[StatusEffect]
			match type:
				EffectSourceType.NORMAL:
					mod_status_effects = mod.status_effects
				EffectSourceType.CHARGE when weapon_stats is MeleeWeaponStats:
					mod_status_effects = mod.charge_status_effects
				EffectSourceType.AOE when weapon_stats is ProjWeaponStats:
					mod_status_effects = mod.aoe_status_effects

			_update_effect_source_status_effects(weapon_stats, type, mod_status_effects)

## Resets the original (non-modded) status effects for the weapon after a save so that they correctly reflect
## the effects not provided by mods. This then removes and then readds all the weapon mods from the save.
static func reset_original_arrays_after_save(weapon_stats: WeaponStats, source_entity: Entity) -> void:
	var mods_copy: Array[Dictionary] = weapon_stats.current_mods.duplicate()

	weapon_stats.original_status_effects.clear()
	if weapon_stats is MeleeWeaponStats:
		weapon_stats.original_charge_status_effects.clear()
	elif weapon_stats is ProjWeaponStats and weapon_stats.projectile_logic.aoe_effect_source:
		weapon_stats.projectile_logic.aoe_effect_source.status_effects.clear()
	remove_all_mods_from_weapon(weapon_stats, source_entity)

	weapon_stats.original_status_effects = weapon_stats.effect_source.status_effects
	if weapon_stats is MeleeWeaponStats:
		weapon_stats.original_charge_status_effects = weapon_stats.charge_effect_source.status_effects
	elif weapon_stats is ProjWeaponStats and weapon_stats.projectile_logic.aoe_effect_source:
		weapon_stats.projectile_logic.aoe_effect_source.status_effects = weapon_stats.original_aoe_status_effects

	weapon_stats.current_mods = mods_copy
	re_add_all_mods_to_weapon(weapon_stats, source_entity)

#region Debug
## Formats the updated lists of status effects and prints them out.
static func _debug_print_status_effect_lists(weapon_stats: WeaponStats) -> void:
	var is_normal_base: bool = true if weapon_stats.effect_source.status_effects == weapon_stats.original_status_effects else false
	print_rich("[color=cyan]Normal Effects[/color]" + ("[color=gray][i](base)[/i][/color]" if is_normal_base else "") + ": [b]"+ str(weapon_stats.effect_source.status_effects) + "[/b]")
	if weapon_stats is MeleeWeaponStats:
		var is_normal_charge: bool = true if weapon_stats.charge_effect_source.status_effects == weapon_stats.original_charge_status_effects else false
		print_rich("[color=cyan]Charge Effects[/color]" + ("[color=gray][i](base)[/i][/color]" if is_normal_charge else "") + ": [b]"+ str(weapon_stats.charge_effect_source.status_effects) + "[/b]")
	if weapon_stats is ProjWeaponStats and weapon_stats.projectile_logic.aoe_radius > 0:
		var is_normal_aoe: bool = true if weapon_stats.projectile_logic.aoe_effect_source.status_effects == weapon_stats.original_aoe_status_effects else false
		print_rich("[color=cyan]AOE Effects[/color]" + ("[color=gray][i](base)[/i][/color]" if is_normal_aoe else "") + ": [b]"+ str(weapon_stats.projectile_logic.aoe_effect_source.status_effects) + "[/b]")
#endregion
