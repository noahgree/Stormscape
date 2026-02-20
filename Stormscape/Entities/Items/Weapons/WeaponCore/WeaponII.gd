extends II
class_name WeaponII

const BASE_XP_FOR_LVL: int = 500
const LVL_SCALING_EXPONENT: float = 1.005
const RARITY_LEVELING_FACTOR: float = 0.1
const MAX_LEVEL: int = 40
const TINY_XP: int = 2
const SMALL_XP: int = 5
const MEDIUM_XP: int = 25
const MEDIUM_LARGE_XP: int = 50
const LARGE_XP: int = 100
const HUGE_XP: int = 250
const ENORMOUS_XP: int = 500
const EFFECT_AMOUNT_XP_MULT: float = 0.35 ## Multiplies effect src amounts (dmg, heal) before adding that amount as xp.

@export_group("Weapon Specific")
@export_custom(PROPERTY_HINT_RANGE, "1,40,1", PROPERTY_USAGE_EDITOR) var level: int = 1 ## The level for this weapon.
@export_storage var allowed_lvl: int = 1 ## The level that the xp gain has allowed this weapon to achieve, potentially pending an upgrade confirmation from the player.
@export_storage var lvl_progress: int ## Any xp gained towards the progress of the next level is stored here.
@export_custom(PROPERTY_HINT_RESOURCE_TYPE, "", PROPERTY_USAGE_ALWAYS_DUPLICATE | PROPERTY_USAGE_STORAGE) var sc: StatModsCache = null ## The cache of all up to date stats for this weapon with mods factored in.
@export var current_mods: Array[StringName] = [&"", &"", &"", &"", &"", &""] ## The current mods applied to this weapon in order, with the StringName mod ids as the values.
@export_storage var original_status_effects: Array[StatusEffect] = [] ## The original status effect list of the effect source before any mods are applied.
@export_storage var original_charge_status_effects: Array[StatusEffect] = [] ## The original status effect list of the charge effect source before any mods are applied.
@export_storage var original_aoe_status_effects: Array[StatusEffect] = [] ## The original status effect list of the aoe effect source before any mods are applied.

## Sets up the base values for the stat cache so that weapon mods can be added and managed properly.
func initialize_sc() -> void:
	sc = StatModsCache.new()

	if stats is ProjWeaponStats:
		var normal_moddable_stats: Dictionary[StringName, float] = {
			&"fire_cooldown" : stats.fire_cooldown,
			&"min_charge_time" : stats.min_charge_time,
			&"mag_size" : stats.mag_size,
			&"mag_reload_time" : stats.mag_reload_time,
			&"single_proj_reload_time" : stats.single_proj_reload_time,
			&"single_reload_quantity" : stats.single_reload_quantity,
			&"auto_ammo_interval" : stats.auto_ammo_interval,
			&"auto_ammo_count" : stats.auto_ammo_count,
			&"pullout_delay" : stats.pullout_delay,
			&"rotation_lerping" : stats.rotation_lerping,
			&"max_bloom" : stats.max_bloom,
			&"bloom_increase_rate_multiplier" : 1.0,
			&"bloom_decrease_rate_multiplier" : 1.0,
			&"initial_fire_rate_delay" : stats.initial_fire_rate_delay,
			&"warmup_increase_rate_multiplier" : 1.0,
			&"overheat_penalty" : stats.overheat_penalty,
			&"overheat_increase_rate_multiplier" : 1.0,
			&"projectiles_per_fire" : stats.projectiles_per_fire,
			&"barrage_count" : stats.barrage_count,
			&"angular_spread" : stats.angular_spread,
			&"base_damage" : stats.effect_source.base_damage,
			&"base_healing" : stats.effect_source.base_healing,
			&"crit_chance" : stats.effect_source.crit_chance,
			&"armor_penetration" : stats.effect_source.armor_penetration,
			&"object_damage_mult" : stats.effect_source.object_damage_mult,
			&"proj_speed" : stats.projectile_logic.speed,
			&"proj_max_distance" : stats.projectile_logic.max_distance,
			&"proj_max_pierce" : stats.projectile_logic.max_pierce,
			&"proj_max_ricochet" : stats.projectile_logic.max_ricochet,
			&"proj_max_turn_rate" : stats.projectile_logic.max_turn_rate,
			&"proj_homing_duration" : stats.projectile_logic.homing_duration,
			&"proj_arc_travel_distance" : stats.projectile_logic.arc_travel_distance,
			&"proj_bounce_count" : stats.projectile_logic.bounce_count,
			&"proj_aoe_radius" : stats.projectile_logic.aoe_radius,
			&"hitscan_effect_interval" : stats.hitscan_logic.hitscan_effect_interval,
			&"hitscan_pierce_count" : stats.hitscan_logic.hitscan_pierce_count,
			&"hitscan_max_distance" : stats.hitscan_logic.hitscan_max_distance
		}

		sc.add_moddable_stats(normal_moddable_stats)

		if stats.projectile_logic.aoe_effect_source:
			var aoe_effect_source_moddable_stats: Dictionary[StringName, float] = {
				&"proj_aoe_base_damage" : stats.projectile_logic.aoe_effect_source.base_damage,
				&"proj_aoe_base_healing" : stats.projectile_logic.aoe_effect_source.base_healing
			}
			sc.add_moddable_stats(aoe_effect_source_moddable_stats)

		if (get("ammo_in_mag") == -1) and (stats.ammo_type != ProjWeaponStats.ProjAmmoType.STAMINA):
			set("ammo_in_mag", int(sc.get_stat("mag_size")))
	else:
		var normal_moddable_stats: Dictionary[StringName, float] = {
			&"stamina_cost" : stats.stamina_cost,
			&"use_cooldown" : stats.use_cooldown,
			&"use_speed" : stats.use_speed,
			&"swing_angle" : stats.swing_angle,
			&"base_damage" : stats.effect_source.base_damage,
			&"base_healing" : stats.effect_source.base_healing,
			&"crit_chance" : stats.effect_source.crit_chance,
			&"armor_penetration" : stats.effect_source.armor_penetration,
			&"object_damage_mult" : stats.effect_source.object_damage_mult,
			&"pullout_delay" : stats.pullout_delay,
			&"rotation_lerping" : stats.rotation_lerping
		}
		var charge_moddable_stats: Dictionary[StringName, float] = {
			&"min_charge_time" : stats.min_charge_time,
			&"charge_stamina_cost" : stats.charge_stamina_cost,
			&"charge_use_cooldown" : stats.charge_use_cooldown,
			&"charge_use_speed" : stats.charge_use_speed,
			&"charge_swing_angle" : stats.charge_swing_angle,
			&"charge_base_damage" : stats.charge_effect_source.base_damage,
			&"charge_base_healing" : stats.charge_effect_source.base_healing,
			&"charge_crit_chance" : stats.charge_effect_source.crit_chance,
			&"charge_armor_penetration" : stats.charge_effect_source.armor_penetration,
			&"charge_object_damage_mult" : stats.charge_effect_source.object_damage_mult
		}

		sc.add_moddable_stats(normal_moddable_stats)
		sc.add_moddable_stats(charge_moddable_stats)

	#WeaponModsManager.re_add_all_mods_to_weapon(self, null)

## Returns the amount of xp we need to attain the next level that we aren't at yet.
static func xp_needed_for_lvl(weapon_ii: WeaponII, lvl: int) -> int:
	var rarity_mult: float = 1 + (weapon_ii.stats.rarity * RARITY_LEVELING_FACTOR)

	# Subtract one iteration at the end since we start at level 1
	return int(BASE_XP_FOR_LVL * pow(lvl, LVL_SCALING_EXPONENT) * rarity_mult) - int(BASE_XP_FOR_LVL * rarity_mult)

## Returns the percent progress to the next allowed level, 0 - 1.
static func visual_percent_of_lvl_progress(weapon_ii: WeaponII) -> float:
	if weapon_ii.level < weapon_ii.allowed_lvl:
		return 1.0
	var xp_needed: int = xp_needed_for_lvl(weapon_ii, weapon_ii.allowed_lvl + 1)
	return float(weapon_ii.lvl_progress) / float(xp_needed)

## Whether the weapon is the same as another weapon when called externally to compare.
## Overrides base method to also compare weapon mods and SUID if cooldowns are based on it.
func is_same_as(other_item: ItemStats) -> bool:
	var initial_checks: bool = (str(self) == str(other_item)) and (self.current_mods == other_item.current_mods)
	if not stats.cooldowns_shared:
		return (self.session_uid == other_item.session_uid) and initial_checks
	return initial_checks

## Checks to see if the weapon has the passed in mod already, regardless of level. Leaving index as -1 means check
## every slot, otherwise only check a certain slot index.
func has_mod(mod_id: StringName, index: int = -1) -> bool:
	for mod_slot_index: int in range(current_mods.size()):
		if current_mods[mod_slot_index] == mod_id:
			if index != -1:
				if mod_slot_index == index:
					return true
				else:
					continue
			else:
				return true
	return false

## Returns true if this weapon resource has any mods at all.
func has_any_mods() -> bool:
	for mod_slot_index: int in range(current_mods.size()):
		if current_mods[mod_slot_index] != &"":
			return true
	return false

## Adds xp to the weapon, potentially leveling it up if it has reached enough accumulation of xp. Returns true
## if a level up occurred as a result of the added xp.
func add_xp(amount: int) -> bool:
	if stats.no_levels:
		return false

	var allowed_leveled_up: bool = false

	lvl_progress += amount
	while allowed_lvl < MAX_LEVEL:
		var xp_needed: int = xp_needed_for_lvl(self, allowed_lvl + 1)
		if lvl_progress >= xp_needed and xp_needed > 0:
			lvl_progress -= xp_needed
			allowed_lvl += 1
			allowed_leveled_up = true
		else:
			break

	if allowed_lvl == MAX_LEVEL:
		lvl_progress = 0

	if allowed_leveled_up:
		if allowed_lvl == MAX_LEVEL:
			MessageManager.add_msg("[color=white]" + stats.name + "[/color] Can Now Become[color=white] MAX LEVEL[/color]!", Globals.ui_colors.ui_glow_strong_success, stats.inv_icon)
		else:
			MessageManager.add_msg("[color=white]" + stats.name + "[/color] Upgrade Available!", Globals.ui_colors.ui_glow_strong_success, stats.inv_icon)

	if Globals.player_node.hands.do_these_stats_match_equipped_item(stats):
		var idx: int = Globals.player_node.hands.equipped_item.inv_index
		Globals.player_node.inv.inv_data_updated.emit(idx, Globals.player_node.inv.inv[idx])

	if DebugFlags.weapon_xp_updates:
		var xp_needed_now: int = xp_needed_for_lvl(self, allowed_lvl + 1)
		print("AMOUNT: ", amount, " | PROGRESS: ", lvl_progress, " | LEVEL: ", level, " | ALLOWED LEVEL: ", allowed_lvl, " | REMAINING_NEEDED: ", xp_needed_now - lvl_progress)

	return allowed_leveled_up

## Returns if the item can level up.
func can_level_up() -> bool:
	return (allowed_lvl > level)

## Levels up the weapon and returns the new level.
func level_up() -> int:
	level += 1
	var max_lvl_msg: String = "MAX LEVEL" if level == MAX_LEVEL else ("Level " + str(level))
	var stats_msg: String = ". Stats Increased!" if level % 10 == 0 else ""
	MessageManager.add_msg(stats.name + " is now [color=white]" + max_lvl_msg  + "[/color]" + stats_msg, Globals.ui_colors.ui_glow_strong_success, stats.inv_icon)
	return level

#region DEBUG
## prints the total needed xp for each level up to the requested level.
func print_total_needed(for_level: int) -> void:
	print("-------------------------------------------------------------------------")
	var total: int = 0
	for lvl: int in range(1, for_level + 1):
		var xp: int = xp_needed_for_lvl(self, lvl)
		total += xp
		print("LVL: ", lvl, " | LVL_XP: ", xp, " | TOTAL: ", total)
#endregion
