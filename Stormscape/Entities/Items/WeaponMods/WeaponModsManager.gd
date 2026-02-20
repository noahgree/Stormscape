class_name WeaponModsManager
## A collection of static functions that handle adding, removing, and restoring weapon mods on a weapon.

enum EffectSourceType { NORMAL, CHARGE, AOE } ## The kinds of effect sources that can be modified.


## Checks if the mod can be attached to the weapon.
static func check_mod_compatibility(weapon_ii: WeaponII, weapon_mod: WeaponModStats) -> bool:
	var weapon_stats: WeaponStats = weapon_ii.stats
	if weapon_mod.id in weapon_stats.blocked_mods:
		return false
	if weapon_stats is MeleeWeaponStats and weapon_stats.melee_weapon_type not in weapon_mod.allowed_melee_wpns:
		return false
	elif weapon_stats is ProjWeaponStats and weapon_stats.proj_weapon_type not in weapon_mod.allowed_proj_wpns:
		return false
	for blocked_mutual: StringName in weapon_mod.blocked_mutuals:
		if weapon_ii.has_mod(blocked_mutual):
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
						source_entity: Entity) -> void:
	if not check_mod_compatibility(weapon_ii, weapon_mod):
		return
	if index > WeaponModsManager.get_max_mod_slots(weapon_ii.stats) - 1:
		push_error("\"" + weapon_ii.stats.name + "\" tried to add the mod \"" + weapon_mod.name + "\" to slot " + str(index + 1) + " / 6, but that slot is not unlocked for that weapon.")
		return

	for mod_slot_index: int in range(weapon_ii.current_mods.size()):
		if weapon_mod.id == weapon_ii.current_mods[mod_slot_index]:
			remove_weapon_mod(weapon_ii, mod_slot_index, source_entity)
		elif mod_slot_index == index and weapon_ii.current_mods[mod_slot_index] != &"":
			push_warning("\"" + weapon_ii.current_mods[mod_slot_index] + "\" was already in mod slot " + str(mod_slot_index) + " and will now be removed to make room for \"" + weapon_mod.get_cache_key() + "\"")
			remove_weapon_mod(weapon_ii, mod_slot_index, source_entity)

	_add_weapon_mod(weapon_ii, weapon_mod, index, source_entity)

## Adds a weapon mod to the dictionary and then calls the on_added method inside the mod itself.
static func _add_weapon_mod(weapon_ii: WeaponII, weapon_mod: WeaponModStats, index: int,
					source_entity: Entity) -> void:
	if DebugFlags.weapon_mod_changes:
		print_rich("-------[color=green]Adding[/color][b] " + weapon_mod.name + " (" + str(weapon_mod.rarity) + ")[/b] [color=gray]to " + weapon_ii.stats.name + " (slot " + str(index) + ")" + "-------")

	weapon_ii.current_mods[index] = StringName(weapon_mod.get_cache_key())

	for mod_resource: StatMod in weapon_mod.wpn_stat_mods:
		weapon_ii.sc.add_mods([mod_resource] as Array[StatMod])
		_update_effect_source_stats(weapon_ii, mod_resource.stat_id)

	_update_effect_source_status_effects(weapon_ii.stats, EffectSourceType.NORMAL, weapon_mod.status_effects)
	if weapon_ii.stats is MeleeWeaponStats:
		_update_effect_source_status_effects(weapon_ii.stats, EffectSourceType.CHARGE, weapon_mod.charge_status_effects)
	elif weapon_ii.stats is ProjWeaponStats:
		_update_effect_source_status_effects(weapon_ii.stats, EffectSourceType.AOE, weapon_mod.aoe_status_effects)

	if DebugFlags.weapon_mod_changes:
		_debug_print_status_effect_lists(weapon_ii)

	weapon_mod.on_added(weapon_ii, source_entity.hands.equipped_item if source_entity != null else null)

	AudioManager.play_global(weapon_mod.equipping_audio)

## Removes the weapon mod from the dictionary after calling the on_removal method inside the mod itself.
static func remove_weapon_mod(weapon_ii: WeaponII, index: int, source_entity: Entity) -> void:
	var mod_to_remove: WeaponModStats = Items.cached_items.get(weapon_ii.current_mods[index], null)
	if mod_to_remove == null:
		push_error("The mod at index " + str(index) + " of " + weapon_ii.stats.name + " could not be removed.")
		return
	if DebugFlags.weapon_mod_changes and weapon_ii.has_mod(mod_to_remove.id, index):
		print_rich("-------[color=red]Removed[/color][b] " + str(mod_to_remove.name) + " (" + str(mod_to_remove.rarity) + ")[/b] [color=gray]from " + mod_to_remove.stats.name + " (slot " + str(index) + ")" + "-------")

	for mod_resource: StatMod in mod_to_remove.wpn_stat_mods:
		weapon_ii.sc.remove_mod(mod_resource.stat_id, mod_resource.mod_id)
		_update_effect_source_stats(weapon_ii, mod_resource.stat_id)

	weapon_ii.current_mods[index] = &""

	_remove_mod_status_effects_from_effect_source(weapon_ii, EffectSourceType.NORMAL)
	if weapon_ii.stats is MeleeWeaponStats:
		_remove_mod_status_effects_from_effect_source(weapon_ii, EffectSourceType.CHARGE)
	elif weapon_ii.stats is ProjWeaponStats:
		_remove_mod_status_effects_from_effect_source(weapon_ii, EffectSourceType.AOE)

	if DebugFlags.weapon_mod_changes:
		_debug_print_status_effect_lists(weapon_ii)

	mod_to_remove.on_removal(weapon_ii, source_entity.hands.equipped_item if source_entity != null else null)

	AudioManager.play_global(mod_to_remove.removal_audio)

## Adds all mods in the current_mods array to a weapon's stats.
static func re_add_all_mods_to_weapon(weapon_ii: WeaponII, source_entity: Entity) -> void:
	for mod_slot_index: int in range(weapon_ii.current_mods.size()):
		if weapon_ii.current_mods[mod_slot_index] != &"":
			var mod: WeaponModStats = Items.cached_items.get(weapon_ii.current_mods[mod_slot_index], null)
			remove_weapon_mod(weapon_ii, mod_slot_index, source_entity)
			if mod:
				handle_weapon_mod(weapon_ii, mod, mod_slot_index, source_entity)
			else:
				push_error("Readding all mods to " + weapon_ii.stats.name + " failed.")

## Removes all mods from a passed in weapon_stats resource.
static func remove_all_mods_from_weapon(weapon_ii: WeaponII, source_entity: Entity) -> void:
	for mod_slot_index: int in range(weapon_ii.current_mods.size()):
		if weapon_ii.current_mods[mod_slot_index] != &"":
			remove_weapon_mod(weapon_ii, mod_slot_index, source_entity)

## When mods are added or removed that affect the effect source stats, we use this to recalculate them.
static func _update_effect_source_stats(weapon_ii: WeaponII, stat_id: StringName) -> void:
	match stat_id:
		&"base_damage":
			weapon_ii.stats.effect_source.base_damage = weapon_ii.sc.get_stat("base_damage")
		&"base_healing":
			weapon_ii.stats.effect_source.base_healing = weapon_ii.sc.get_stat("base_healing")
		&"crit_chance":
			weapon_ii.stats.effect_source.crit_chance = weapon_ii.sc.get_stat("crit_chance")
		&"armor_penetration":
			weapon_ii.stats.effect_source.armor_penetration = weapon_ii.sc.get_stat("armor_penetration")
		&"object_damage_mult":
			weapon_ii.stats.effect_source.object_damage_mult = weapon_ii.sc.get_stat("object_damage_mult")

	# Projectile weapons don't have separate charge stats since they can only be one firing type
	if weapon_ii.stats is MeleeWeaponStats:
		match(stat_id):
			&"charge_base_damage":
				weapon_ii.stats.charge_effect_source.base_damage = weapon_ii.sc.get_stat("charge_base_damage")
			&"charge_base_healing":
				weapon_ii.stats.charge_effect_source.base_healing = weapon_ii.sc.get_stat("charge_base_healing")
			&"charge_crit_chance":
				weapon_ii.stats.charge_effect_source.crit_chance = weapon_ii.sc.get_stat("charge_crit_chance")
			&"charge_armor_penetration":
				weapon_ii.stats.charge_effect_source.armor_penetration = weapon_ii.sc.get_stat("charge_armor_penetration")
			&"charge_object_damage_mult":
				weapon_ii.stats.charge_effect_source.object_damage_mult = weapon_ii.sc.get_stat("charge_object_damage_mult")

	# Melee weapons don't have separate aoe stats since they cannot produce areas of effect
	elif weapon_ii.stats is ProjWeaponStats:
		match(stat_id):
			&"proj_aoe_base_damage":
				weapon_ii.stats.projectile_logic.aoe_effect_source.base_damage = weapon_ii.sc.get_stat("proj_aoe_base_damage")
			&"proj_aoe_base_healing":
				weapon_ii.stats.projectile_logic.aoe_effect_source.base_healing = weapon_ii.sc.get_stat("proj_aoe_base_healing")

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
static func _remove_mod_status_effects_from_effect_source(weapon_ii: WeaponII,
															type: EffectSourceType) -> void:
	var stats: WeaponStats = weapon_ii.stats
	var effect_source: EffectSource
	var orig_array: Array[StatusEffect]
	match type:
		EffectSourceType.NORMAL:
			effect_source = stats.effect_source
			orig_array = weapon_ii.original_status_effects
		EffectSourceType.CHARGE when stats is MeleeWeaponStats:
			effect_source = stats.charge_effect_source
			orig_array = weapon_ii.original_charge_status_effects
		EffectSourceType.AOE when stats is ProjWeaponStats and stats.projectile_logic.aoe_effect_source:
			effect_source = stats.projectile_logic.aoe_effect_source
			orig_array = weapon_ii.original_aoe_status_effects

	if effect_source == null:
		return
	effect_source.status_effects = orig_array.duplicate()

	for mod_slot_index: int in range(weapon_ii.current_mods.size()):
		var mod: WeaponModStats = Items.cached_items.get(weapon_ii.current_mods[mod_slot_index], null)
		if mod != null:
			var mod_status_effects: Array[StatusEffect]
			match type:
				EffectSourceType.NORMAL:
					mod_status_effects = mod.status_effects
				EffectSourceType.CHARGE when stats is MeleeWeaponStats:
					mod_status_effects = mod.charge_status_effects
				EffectSourceType.AOE when stats is ProjWeaponStats:
					mod_status_effects = mod.aoe_status_effects

			_update_effect_source_status_effects(stats, type, mod_status_effects)

#region Debug
## Formats the updated lists of status effects and prints them out.
static func _debug_print_status_effect_lists(weapon_ii: WeaponII) -> void:
	var weapon_stats: WeaponStats = weapon_ii.stats
	var is_normal_base: bool = true if weapon_stats.effect_source.status_effects == weapon_ii.original_status_effects else false
	print_rich("[color=cyan]Normal Effects[/color]" + ("[color=gray][i](base)[/i][/color]" if is_normal_base else "") + ": [b]"+ str(weapon_stats.effect_source.status_effects) + "[/b]")
	if weapon_stats is MeleeWeaponStats:
		var is_normal_charge: bool = true if weapon_stats.charge_effect_source.status_effects == weapon_ii.original_charge_status_effects else false
		print_rich("[color=cyan]Charge Effects[/color]" + ("[color=gray][i](base)[/i][/color]" if is_normal_charge else "") + ": [b]"+ str(weapon_stats.charge_effect_source.status_effects) + "[/b]")
	if weapon_stats is ProjWeaponStats and weapon_stats.projectile_logic.aoe_radius > 0:
		var is_normal_aoe: bool = true if weapon_stats.projectile_logic.aoe_effect_source.status_effects == weapon_ii.original_aoe_status_effects else false
		print_rich("[color=cyan]AOE Effects[/color]" + ("[color=gray][i](base)[/i][/color]" if is_normal_aoe else "") + ": [b]"+ str(weapon_stats.projectile_logic.aoe_effect_source.status_effects) + "[/b]")
#endregion
