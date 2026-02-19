class_name InitializationHelpers


## Sets up the base values for the stat mod cache so that weapon mods can be added and managed properly.
static func initialize_proj_wpn_stats_resource(stats_resource: ProjWeaponStats) -> void:
	stats_resource.s_mods = stats_resource.s_mods.duplicate()
	stats_resource.effect_source = stats_resource.effect_source.duplicate()
	stats_resource.original_status_effects = stats_resource.effect_source.status_effects.duplicate()

	stats_resource.original_aoe_status_effects = []
	if stats_resource.projectile_logic.aoe_effect_source:
		stats_resource.original_aoe_status_effects = stats_resource.projectile_logic.aoe_effect_source.status_effects.duplicate()

	var normal_moddable_stats: Dictionary[StringName, float] = {
		&"fire_cooldown" : stats_resource.fire_cooldown,
		&"min_charge_time" : stats_resource.min_charge_time,
		&"mag_size" : stats_resource.mag_size,
		&"mag_reload_time" : stats_resource.mag_reload_time,
		&"single_proj_reload_time" : stats_resource.single_proj_reload_time,
		&"single_reload_quantity" : stats_resource.single_reload_quantity,
		&"auto_ammo_interval" : stats_resource.auto_ammo_interval,
		&"auto_ammo_count" : stats_resource.auto_ammo_count,
		&"pullout_delay" : stats_resource.pullout_delay,
		&"rotation_lerping" : stats_resource.rotation_lerping,
		&"max_bloom" : stats_resource.max_bloom,
		&"bloom_increase_rate_multiplier" : 1.0,
		&"bloom_decrease_rate_multiplier" : 1.0,
		&"initial_fire_rate_delay" : stats_resource.initial_fire_rate_delay,
		&"warmup_increase_rate_multiplier" : 1.0,
		&"overheat_penalty" : stats_resource.overheat_penalty,
		&"overheat_increase_rate_multiplier" : 1.0,
		&"projectiles_per_fire" : stats_resource.projectiles_per_fire,
		&"barrage_count" : stats_resource.barrage_count,
		&"angular_spread" : stats_resource.angular_spread,
		&"base_damage" : stats_resource.effect_source.base_damage,
		&"base_healing" : stats_resource.effect_source.base_healing,
		&"crit_chance" : stats_resource.effect_source.crit_chance,
		&"armor_penetration" : stats_resource.effect_source.armor_penetration,
		&"object_damage_mult" : stats_resource.effect_source.object_damage_mult,
		&"proj_speed" : stats_resource.projectile_logic.speed,
		&"proj_max_distance" : stats_resource.projectile_logic.max_distance,
		&"proj_max_pierce" : stats_resource.projectile_logic.max_pierce,
		&"proj_max_ricochet" : stats_resource.projectile_logic.max_ricochet,
		&"proj_max_turn_rate" : stats_resource.projectile_logic.max_turn_rate,
		&"proj_homing_duration" : stats_resource.projectile_logic.homing_duration,
		&"proj_arc_travel_distance" : stats_resource.projectile_logic.arc_travel_distance,
		&"proj_bounce_count" : stats_resource.projectile_logic.bounce_count,
		&"proj_aoe_radius" : stats_resource.projectile_logic.aoe_radius,
		&"hitscan_effect_interval" : stats_resource.hitscan_logic.hitscan_effect_interval,
		&"hitscan_pierce_count" : stats_resource.hitscan_logic.hitscan_pierce_count,
		&"hitscan_max_distance" : stats_resource.hitscan_logic.hitscan_max_distance
	}

	stats_resource.s_mods.add_moddable_stats(normal_moddable_stats)

	if stats_resource.projectile_logic.aoe_effect_source:
		var aoe_effect_source_moddable_stats: Dictionary[StringName, float] = {
			&"proj_aoe_base_damage" : stats_resource.projectile_logic.aoe_effect_source.base_damage,
			&"proj_aoe_base_healing" : stats_resource.projectile_logic.aoe_effect_source.base_healing
		}
		stats_resource.s_mods.add_moddable_stats(aoe_effect_source_moddable_stats)

	if (stats_resource.ammo_in_mag == -1) and (stats_resource.ammo_type != ProjWeaponStats.ProjAmmoType.STAMINA):
		stats_resource.ammo_in_mag = int(stats_resource.s_mods.get_stat("mag_size"))

	if stats_resource.weapon_mods_need_to_be_readded_after_save:
		WeaponModsManager.reset_original_arrays_after_save(stats_resource, null)
		stats_resource.weapon_mods_need_to_be_readded_after_save = false

## Sets up the base values for the stat mod cache so that weapon mods can be added and managed properly.
static func initialize_melee_wpn_stats_resource(stats_resource: MeleeWeaponStats) -> void:
	stats_resource.s_mods = stats_resource.s_mods.duplicate()
	stats_resource.effect_source = stats_resource.effect_source.duplicate()
	stats_resource.charge_effect_source = stats_resource.charge_effect_source.duplicate()
	stats_resource.original_status_effects = stats_resource.effect_source.status_effects.duplicate()
	stats_resource.original_charge_status_effects = stats_resource.charge_effect_source.status_effects.duplicate()

	var normal_moddable_stats: Dictionary[StringName, float] = {
		&"stamina_cost" : stats_resource.stamina_cost,
		&"use_cooldown" : stats_resource.use_cooldown,
		&"use_speed" : stats_resource.use_speed,
		&"swing_angle" : stats_resource.swing_angle,
		&"base_damage" : stats_resource.effect_source.base_damage,
		&"base_healing" : stats_resource.effect_source.base_healing,
		&"crit_chance" : stats_resource.effect_source.crit_chance,
		&"armor_penetration" : stats_resource.effect_source.armor_penetration,
		&"object_damage_mult" : stats_resource.effect_source.object_damage_mult,
		&"pullout_delay" : stats_resource.pullout_delay,
		&"rotation_lerping" : stats_resource.rotation_lerping
	}
	var charge_moddable_stats: Dictionary[StringName, float] = {
		&"min_charge_time" : stats_resource.min_charge_time,
		&"charge_stamina_cost" : stats_resource.charge_stamina_cost,
		&"charge_use_cooldown" : stats_resource.charge_use_cooldown,
		&"charge_use_speed" : stats_resource.charge_use_speed,
		&"charge_swing_angle" : stats_resource.charge_swing_angle,
		&"charge_base_damage" : stats_resource.charge_effect_source.base_damage,
		&"charge_base_healing" : stats_resource.charge_effect_source.base_healing,
		&"charge_crit_chance" : stats_resource.charge_effect_source.crit_chance,
		&"charge_armor_penetration" : stats_resource.charge_effect_source.armor_penetration,
		&"charge_object_damage_mult" : stats_resource.charge_effect_source.object_damage_mult
	}

	stats_resource.s_mods.add_moddable_stats(normal_moddable_stats)
	stats_resource.s_mods.add_moddable_stats(charge_moddable_stats)

	if stats_resource.weapon_mods_need_to_be_readded_after_save:
		WeaponModsManager.reset_original_arrays_after_save(stats_resource, null)
		stats_resource.weapon_mods_need_to_be_readded_after_save = false
