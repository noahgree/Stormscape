class_name AutoDecrementer
## Manages entity-specific item cooldowns, warmups, blooming, overheating, and recharging via item identifiers.

signal cooldown_ended(item_id: StringName, cooldown_title: String) ## Emitted when any cooldown ends.
signal overheat_empty(item_id: StringName) ## Emitted when any overheat reaches 0 and is removed.
signal recharge_completed(item_id: StringName) ## Emitted when any recharge completes.

var cooldowns: Dictionary[StringName, Dictionary] = {} ## Represents any active cooldowns where the key is an item's id.
var warmups: Dictionary[StringName, Dictionary] = {} ## Represents any active warmups where the key is an item's id.
var blooms: Dictionary[StringName, Dictionary] = {} ## Represents any active blooms where the key is an item's id.
var overheats: Dictionary[StringName, Dictionary] = {} ## Represents any active overheats where the key is an item's id.
var recharges: Dictionary[StringName, Dictionary] = {} ## Represents any active recharges where the key is an item's id.
var owning_entity_is_player: bool = false ## When true, the entity owning the inv this script operates on is a Player.
var inv: InvResource ## The inventory that controls this auto decrementer.


func process(delta: float) -> void:
	_update_cooldowns(delta)
	_update_warmups(delta)
	_update_blooms(delta)
	_update_overheats(delta)
	_update_recharges(delta)

#region Cooldowns
## Adds a cooldown to the dictionary.
func add_cooldown(item_id: StringName, duration: float, title: String = "default") -> void:
	if duration <= 0:
		return

	cooldowns[item_id] = {
		&"duration" : duration,
		&"original_duration" : duration,
		&"source_title" : title
	}

	if owning_entity_is_player:
		Globals.player_node.get_node("%HotbarHUD").update_hotbar_tint_progresses()

## Called every frame to update each cooldown value.
func _update_cooldowns(delta: float) -> void:
	var to_remove: Array[StringName] = []
	for item_id: StringName in cooldowns.keys():
		var current: Dictionary = cooldowns[item_id]
		current.duration -= delta
		if current.duration <= 0:
			to_remove.append(item_id)

	for item_id: StringName in to_remove:
		var cooldown_entry: Dictionary = cooldowns[item_id]
		cooldowns.erase(item_id)
		cooldown_ended.emit(item_id, cooldown_entry.source_title)

## Returns a positive float representing the remaining cooldown or 0 if one does not exist.
func get_cooldown(item_id: StringName) -> float:
	return cooldowns.get(item_id, {}).get(&"duration", 0)

## Returns a positive float representing the original duration of an active cooldown or 0 if it does not exist.
func get_original_cooldown(item_id: StringName) -> float:
	return cooldowns.get(item_id, {}).get(&"original_duration", 0)

## Returns a string representing the cooldown source title if one exists, otherwise it returns a string of "null".
func get_cooldown_source_title(item_id: StringName) -> String:
	return cooldowns.get(item_id, {}).get(&"source_title", "null")

## Returns a float from 0 -> 1 indicating progress so far, or optionally progress remaining if specified.
## full_when_none_found means that it will return 1 (meaning 100%) if no cooldown exists for the item_id.
func get_cooldown_percent(item_id: StringName, remaining: bool, full_when_none_found: bool = true) -> float:
	if not cooldowns.has(item_id):
		if full_when_none_found or not remaining:
			return 1
		else:
			return 0

	var cooldown: float = get_cooldown(item_id)
	var original_cooldown: float = get_original_cooldown(item_id)
	var progress: float = cooldown / original_cooldown
	if remaining:
		return (1 - progress)
	return progress
#endregion

#region Warmups
## Adds a warmup to the dictionary.
func add_warmup(item_id: StringName, amount: float, decrease_rate: Curve, decrease_delay: float) -> void:
	var new_value: float
	if item_id in warmups:
		new_value = min(1, warmups[item_id].warmup_value + amount)
	else:
		new_value = min(1, amount)

	warmups[item_id] = {
		&"warmup_value" : new_value,
		&"decrease_curve" : decrease_rate,
		&"decrease_delay" : decrease_delay
	}

## Called every frame to update each warmup value and its potential delay counter.
func _update_warmups(delta: float) -> void:
	var to_remove: Array[StringName] = []
	for item_id: StringName in warmups.keys():
		var current: Dictionary = warmups[item_id]
		if current.decrease_delay <= 0:
			current.warmup_value -= delta * max(0.01, current.decrease_curve.sample_baked(current.warmup_value))
		else:
			current.decrease_delay -= delta

		if current.warmup_value <= 0:
			to_remove.append(item_id)

	for item_id: StringName in to_remove:
		warmups.erase(item_id)

## Returns a positive float representing the current warmup value or 0 if one does not exist.
func get_warmup(item_id: StringName) -> float:
	return warmups.get(item_id, {}).get(&"warmup_value", 0)
#endregion

#region Bloom
## Adds a bloom to the dictionary.
func add_bloom(item_id: StringName, amount: float, decrease_rate: Curve, decrease_delay: float) -> void:
	var new_value: float
	if item_id in blooms:
		new_value = min(1, blooms[item_id].bloom_value + amount)
	else:
		new_value = min(1, amount)

	blooms[item_id] = {
		&"bloom_value" : new_value,
		&"decrease_curve" : decrease_rate,
		&"decrease_delay" : decrease_delay
	}

## Called every frame to update each bloom value and its potential delay counter.
func _update_blooms(delta: float) -> void:
	var to_remove: Array[StringName] = []
	for item_id: StringName in blooms.keys():
		var current: Dictionary = blooms[item_id]
		if current.decrease_delay <= 0:
			current.bloom_value -= delta * max(0.01, current.decrease_curve.sample_baked(current.bloom_value))
		else:
			current.decrease_delay -= delta

		if current.bloom_value <= 0:
			to_remove.append(item_id)

	for item_id: StringName in to_remove:
		blooms.erase(item_id)

## Returns a positive float representing the current bloom value or 0 if one does not exist.
func get_bloom(item_id: StringName) -> float:
	return blooms.get(item_id, {}).get(&"bloom_value", 0)
#endregion

#region Overheats
## Adds a overheat to the dictionary.
func add_overheat(item_id: StringName, amount: float, decrease_rate: Curve, decrease_delay: float) -> void:
	var new_value: float
	if item_id in overheats:
		new_value = min(1, overheats[item_id].progress + amount)
	else:
		new_value = min(1, amount)

	overheats[item_id] = {
		&"progress" : new_value,
		&"decrease_curve" : decrease_rate,
		&"decrease_delay" : decrease_delay
	}

## Called every frame to update each overheat value and its potential delay counter.
func _update_overheats(delta: float) -> void:
	var to_remove: Array[StringName] = []
	for item_id: StringName in overheats.keys():
		var current: Dictionary = overheats[item_id]
		if current.decrease_delay <= 0:
			current.progress -= delta * max(0.01, current.decrease_curve.sample_baked(current.progress))
		else:
			current.decrease_delay -= delta

		if current.progress <= 0:
			to_remove.append(item_id)

	for item_id: StringName in to_remove:
		overheats.erase(item_id)
		overheat_empty.emit(item_id)

## Returns a positive float representing the current overheat value or 0 if one does not exist.
func get_overheat(item_id: StringName) -> float:
	return overheats.get(item_id, {}).get(&"progress", 0)
#endregion

#region Recharges
## Adds a recharge request to the dictionary.
func request_recharge(item_id: StringName, stats: WeaponStats) -> void:
	if item_id in recharges:
		recharges[item_id].stats = stats
	else:
		var auto_ammo_interval: float = stats.s_mods.get_stat("auto_ammo_interval")
		recharges[item_id] = {
			&"progress" : auto_ammo_interval,
			&"original_duration" : auto_ammo_interval,
			&"decrease_delay" : stats.auto_ammo_delay,
			&"stats" : stats
		}

## Adds a delay to the recharge.
func update_recharge_delay(item_id: StringName, delay_duration: float) -> void:
	if item_id in recharges:
		recharges[item_id].decrease_delay = delay_duration

## Called every frame to update each recharge value and its potential delay counter.
func _update_recharges(delta: float) -> void:
	var to_remove: Array[StringName] = []
	for item_id: StringName in recharges.keys():
		var current: Dictionary = recharges[item_id]
		if current.decrease_delay <= 0:
			current.progress -= delta
		else:
			current.decrease_delay -= delta

		if current.progress <= 0:
			if is_instance_valid(current.stats):
				var mag_size: int = current.stats.s_mods.get_stat("mag_size")
				var ammo_needed: int = mag_size - current.stats.ammo_in_mag
				var auto_ammo_count: int = int(current.stats.s_mods.get_stat("auto_ammo_count"))
				ammo_needed = min(ammo_needed, auto_ammo_count)

				if current.stats.recharge_uses_inv:
					if current.stats.ammo_type == ProjWeaponStats.ProjAmmoType.CHARGES:
						current.stats.ammo_in_mag += ammo_needed
					else:
						var retrieved_ammo: int = inv.get_more_ammo(ammo_needed, true, current.stats.ammo_type)
						if retrieved_ammo == 0:
							# Don't keep trying to recharge if we are out of inventory ammo
							to_remove.append(item_id)
						current.stats.ammo_in_mag += retrieved_ammo
				else:
					current.stats.ammo_in_mag = min(mag_size, current.stats.ammo_in_mag + auto_ammo_count)

				if current.stats.ammo_in_mag >= mag_size:
					# Don't keep recharging if we are at max ammo
					to_remove.append(item_id)
				else:
					# If we aren't at max ammo, reset the progress and charge up again
					current.progress = current.stats.s_mods.get_stat("auto_ammo_interval")
			else:
				# Don't keep trying to recharge if the stats are no longer valid
				to_remove.append(item_id)

			recharge_completed.emit(item_id)

	for item_id: StringName in to_remove:
		recharges.erase(item_id)

## Returns a positive float representing the current recharge progress or 0 if one does not exist.
func get_recharge(item_id: StringName) -> float:
	return recharges.get(item_id, {}).get(&"progress", 0)
#endregion
