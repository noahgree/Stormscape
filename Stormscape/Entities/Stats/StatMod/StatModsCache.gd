extends Resource
class_name StatModsCache
## A resource that caches and works with stat mods applied to the entity on which it is defined.

var affected_entity: Entity ## The entity that this cache resource works for. If working with a weapon, this will be null.
var stat_mods: Dictionary[StringName, Dictionary] ## The cache of mod resources currently applied to the entity's stats, keyed by the stat.
var cached_stats: Dictionary[StringName, float] ## The up-to-date and calculated stats to be used by anything that depend on them.
var base_values: Dictionary[StringName, float] ## The unchanging base values of each moddable stat, usually set by copying the exported values from the component into a dictionary that is passed into the setup function below.
var is_loading: bool = false ## Blocks print spam of changes during loads.
var associated_callables: Dictionary[StringName, Callable] ## This maps stats to a callable that should be called when they are changed.


## Sets up the base values dict and calculates initial values based on any already present mods.
func add_moddable_stats(base_valued_stats: Dictionary[StringName, float]) -> void:
	is_loading = true
	for stat_id: StringName in base_valued_stats.keys():
		var base_value: float = base_valued_stats[stat_id]
		stat_mods[stat_id] = {}
		base_values[stat_id] = base_value
		_recalculate_stat(stat_id, base_value)
	is_loading = false

## Sets up the base values dict and calculates initial values based on any already present mods.
## Also includes associated callables as the second element in an array attached to each stat StringName.
## This is the callable that gets called when that stat is changed.
func add_moddable_stats_with_associated_callables(base_valued_stats: Dictionary[StringName, Array]) -> void:
	is_loading = true
	for stat_id: StringName in base_valued_stats.keys():
		var array: Array = base_valued_stats[stat_id]
		var base_value: float = array[0]
		stat_mods[stat_id] = {}
		base_values[stat_id] = base_value
		_recalculate_stat(stat_id, base_value)

		var associated_callable: Callable = array[1]
		associated_callables[stat_id] = associated_callable

	is_loading = false

## Recalculates a cached stat. Usually called once something has changed like from an update or removal.
func _recalculate_stat(stat_id: StringName, base_value: float) -> void:
	var mods: Array = stat_mods[stat_id].values()
	mods.sort_custom(_compare_by_priority)

	var result: float = base_value
	for mod: StatMod in mods:
		if mod.override_all:
			result = mod.apply(base_value, base_value)
			break
		result = mod.apply(base_value, result)

	cached_stats[stat_id] = max(0, result)
	_update_ui_for_stat(stat_id, result)

	if DebugFlags.stat_mod_changes_during_game and not is_loading:
		var change_text: String = str(snappedf(float(cached_stats[stat_id]) / float(base_values[stat_id]), 0.001)) + "x"
		if base_values[stat_id] == 0:
			change_text = str(snappedf(cached_stats[stat_id], 0.001))
		var base_text: String = "[color=gray][i](base)[/i][/color]" if cached_stats[stat_id] == base_values[stat_id] else "[color=pink][i](" + change_text + ")[/i][/color]"
		print_rich("[color=cyan]" + stat_id + base_text + "[/color]: [b]" + str(cached_stats[stat_id]) + "[/b]")

## Updates an optionally connected UI when a watched stat changes.
func _update_ui_for_stat(stat_id: StringName, new_value: float) -> void:
	if affected_entity == null:
		return

	var callable: Variant = associated_callables.get(stat_id, null)
	if callable == null: # Usually means the stat was added normally and does not have an associated callable
		return
	if not callable.is_valid():
		push_warning("StatModsCache tried to call the callable \"" + callable.get_method() + "\" on the node \"" + affected_entity.name + "\" and failed. Make sure the source of the moddable stat \"" + stat_id + "\" is passing the correct callable and is still valid." )
	else:
		callable.call_deferred(new_value)

## Compares stats to be applied in a certain order based on priority. Useful for if you want a stat
## to multiply the base value before another stat tries to add a constant to it.
func _compare_by_priority(a: StatMod, b: StatMod) -> int:
	return a.priority - b.priority

## Updates a mod's value by a given mod_id that must exist on a given stat_id.
## This will automatically update any stacking as well.
func update_mod_by_id(stat_id: StringName, mod_id: StringName, new_value: float) -> void:
	var existing_mod: StatMod = _get_mod(stat_id, mod_id)
	if existing_mod:
		existing_mod.before_stack_value = new_value
		if existing_mod.stack_count > 1:
			_recalculate_mod_value_with_new_stack_count(existing_mod)
		else:
			existing_mod.value = existing_mod.before_stack_value

		_recalculate_stat(stat_id, base_values[stat_id])

## Adds mods to a stat. Handles logic for stacking if the mod can stack.
func add_mods(mod_array: Array[StatMod]) -> void:
	for mod: StatMod in mod_array:
		if mod.stat_id in stat_mods:
			var existing_mod: StatMod = stat_mods[mod.stat_id].get(mod.mod_id, null)
			if existing_mod and existing_mod.max_stack_count > 1:
				if existing_mod.stack_count < existing_mod.max_stack_count:
					existing_mod.stack_count += 1
					_recalculate_mod_value_with_new_stack_count(existing_mod)
				else:
					continue
			else:
				mod.stack_count = 1
				mod.before_stack_value = mod.value
				stat_mods[mod.stat_id][mod.mod_id] = mod

				_recalculate_stat(mod.stat_id, base_values[mod.stat_id])
		else:
			_push_mod_not_found_warning(mod.stat_id, mod.mod_id)

## Removes a mod from a stat. If it has been stacked, it removes the number of instances specified by the count.
## A count of "-1" removes all of them.
func remove_mod(stat_id: StringName, mod_id: StringName, count: int = 1) -> void:
	var existing_mod: StatMod = _get_mod(stat_id, mod_id)
	if existing_mod:
		if count == -1:
			stat_mods[stat_id].erase(mod_id)
		else:
			existing_mod.stack_count = max(0, existing_mod.stack_count - count)

			if existing_mod.stack_count <= 0:
				stat_mods[stat_id].erase(mod_id)
			else: # Otherwise it will multiply by 0 and set the mod's value to 0
				_recalculate_mod_value_with_new_stack_count(existing_mod)

		_recalculate_stat(stat_id, base_values[stat_id])

## Recalculates the cached stat value based on the updated stack count of that mod on that stat.
func _recalculate_mod_value_with_new_stack_count(mod: StatMod) -> void:
	if mod.operation == "*" or mod.operation == "/":
		mod.value = pow(mod.before_stack_value, mod.stack_count)
	else:
		mod.value = mod.before_stack_value * mod.stack_count

## Undoes any stacking applied to a mod, setting it back to as if there was only one instance active.
func undo_mod_stacking(stat_id: StringName, mod_id: StringName) -> void:
	var existing_mod: StatMod = _get_mod(stat_id, mod_id)
	if existing_mod:
		existing_mod.stack_count = 1
		existing_mod.value = existing_mod.before_stack_value

		_recalculate_stat(stat_id, base_values[stat_id])

## Gets the current cached value of a stat.
func get_stat(stat_id: StringName) -> float:
	var value: float = cached_stats.get(stat_id, null)
	assert(value != null, stat_id + " was null when trying to be retrieved from a stat mods cache.")
	return value

## Returns the original cached value of a stat before any modifications.
func get_original_stat(stat_id: StringName) -> float:
	var value: float = base_values.get(stat_id, null)
	assert(value != null, stat_id + " was null when trying to be retrieved from a stat mods cache.")
	return value

## Returns true or false depending on whether the cache contains a stat at all.
func has_stat(stat_id: StringName) -> bool:
	return base_values.has(stat_id)

## Gets the StatMod for the stat_id based on the mod_id. Pushes an error if it can't be found.
func _get_mod(stat_id: StringName, mod_id: StringName) -> StatMod:
	if stat_id in stat_mods and mod_id in stat_mods[stat_id]:
		return stat_mods[stat_id].get(mod_id, null)
	else:
		_push_mod_not_found_warning(stat_id, mod_id)
		return null

#region Debug
## Adds a mod from scratch.
func add_mod_from_scratch(stat_id: StringName, operation: String, value: float, rounding: String = "Exact") -> void:
	var mod: StatMod = StatMod.new()
	mod.stat_id = stat_id
	mod.mod_id = "debug"
	if operation in ["+%", "-%", "+", "-", "*", "/", "="]:
		mod.operation = operation
	else:
		printerr("Not a valid operation for the mod.")
		return
	mod.value = value
	if rounding in ["Exact", "Round Up", "Round Down", "Round Closest"]:
		mod.rounding = rounding
	else:
		printerr("Not a valid rounding method for the mod.")
		return

	add_mods([mod])
	print("\"debug\" mod added. Use that id to remove mod if needed.")

## Pushes an error to the console with the stat id and the mod id for the mod that could not be found.
func _push_mod_not_found_warning(stat_id: StringName, mod_id: StringName) -> void:
	if DebugFlags.mod_not_in_cache:
		push_warning("The mod for stat \"" + stat_id + "\"" + " with mod_id of: \"" + mod_id + "\" was not in the cache: \"" + str(self) + "\".")
#endregion
