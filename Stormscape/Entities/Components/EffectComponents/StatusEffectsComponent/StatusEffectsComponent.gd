@icon("res://Utilities/Debug/EditorIcons/status_effect_component.svg")
extends Node2D
class_name StatusEffectsComponent
## The component that holds the stats and logic for how the entity should receive effects.
##
## This handles things like fire & poison damage not taking into account armor, etc.

static var cached_status_effects: Dictionary[StringName, StatusEffect] = {} ## A cache of all status effects, keyed by their file names turned into snake case.

@export var effect_receiver: EffectReceiverComponent ## The effect receiver that sends status effects to this manager to be cached and handled.
@export_subgroup("Debug")
@export var print_effect_updates: bool = false ## Whether to print when this entity has status effects added and removed.

@onready var affected_entity: Entity = owner ## The entity affected by these status effects.

var current_effects: Dictionary[StringName, StatusEffect] = {} ## Keys are general status effect ids and values are the effect resources themselves.
var effect_timers: Dictionary[StringName, Timer] = {} ## Holds references to all timers currently tracking active status effects.
var particle_fade_tweens: Dictionary[StringName, Tween] = {} ## Holds references to all particle fade out tweens so if that effect is started again while fading out, we can cancel it.


#region Debug
func _draw() -> void:
	if not Engine.is_editor_hint() and DebugFlags.show_status_effect_particle_emission_area:
		var emission_mgr: ParticleEmissionComponent = owner.emission_mgr
		var extents: Vector2 = emission_mgr.get_extents(ParticleEmissionComponent.Boxes.BELOW)
		var origin: Vector2 = emission_mgr.get_origin(ParticleEmissionComponent.Boxes.BELOW)

		var rect: Rect2 = Rect2(origin - extents, extents * 2)
		draw_rect(rect, Color(1, 0, 0, 0.5), false, 1)
#endregion


#region Core
## Assert that this node has a connected effect receiver from which it can receive status effects.
func _ready() -> void:
	assert(effect_receiver != null, owner.name + " has a StatusEffectsComponent without a connected EffectReceiverComponent.")

	if StatusEffectsComponent.cached_status_effects.is_empty():
		_cache_status_effects(Globals.status_effects_dir)

## Searches through the given top level folder and recursively finds all status effect resources for caching.
func _cache_status_effects(folder: String) -> void:
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		push_error("StatusEffectsComponent couldn't open the folder: " + folder)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()

	while file_name != "":
		if dir.current_is_dir():
			if file_name != "." and file_name != "..":
				_cache_status_effects(folder + "/" + file_name)
		elif file_name.ends_with(".tres"):
			var file_path: String = folder + "/" + file_name
			var status_effect: StatusEffect = load(file_path)
			StatusEffectsComponent.cached_status_effects[file_name.trim_suffix(".tres").to_snake_case()] = status_effect
		file_name = dir.get_next()
	dir.list_dir_end()
#endregion

## Handles an incoming status effect. It starts by adding any stat mods provided by the status effect, and then
## it passes the effect logic to the relevant handler if it exists.
func handle_status_effect(status_effect: StatusEffect) -> void:
	var effect_key: String = status_effect.get_full_effect_key()

	if DebugFlags.current_effect_changes and print_effect_updates:
		if status_effect is StormSyndromeEffect:
			print_rich("-------[color=green]Adding[/color][b] [color=pink]" + effect_key + " " + str(status_effect.effect_lvl) + "[/color][/b][color=gray] to " + affected_entity.name + "-------")
		else:
			print_rich("-------[color=green]Adding[/color][b] " + effect_key + " " + str(status_effect.effect_lvl) + "[/b][color=gray] to " + affected_entity.name + "-------")

	_handle_status_effect_mods(status_effect)

## Checks if we already have a status effect of the same name and decides what to do depending on the level.
func _handle_status_effect_mods(status_effect: StatusEffect) -> void:
	var effect_key: String = status_effect.get_full_effect_key()

	if effect_key in current_effects:
		var existing_lvl: int = current_effects[effect_key].effect_lvl

		if existing_lvl > status_effect.effect_lvl: # New effect is lower lvl
			var time_to_add: float = status_effect.mod_time * (float(status_effect.effect_lvl) / float(existing_lvl))
			_extend_effect_duration(effect_key, time_to_add)
		elif existing_lvl < status_effect.effect_lvl: # New effect is higher lvl
			_remove_status_effect(current_effects[effect_key])
			_add_status_effect(status_effect)
		else: # New effect is same lvl
			_restart_effect_duration(effect_key)
	else:
		_add_status_effect(status_effect)

## Adds a status effect to the current effects dict, starts its timer, stores its timer, and applies its mods.
func _add_status_effect(status_effect: StatusEffect) -> void:
	if status_effect.id == "untouchable":
		remove_all_bad_status_effects()

	var effect_key: String = status_effect.get_full_effect_key()
	current_effects[effect_key] = status_effect

	var mod_timer: Timer = TimerHelpers.create_one_shot_timer(self, max(0.01, status_effect.mod_time))

	if not status_effect.apply_until_removed:
		var removing_callable: Callable = Callable(self, "_remove_status_effect").bind(status_effect)
		mod_timer.timeout.connect(removing_callable)
		mod_timer.set_meta("callable", removing_callable)
	else:
		mod_timer.timeout.connect(func() -> void: mod_timer.start(status_effect.mod_time))

	mod_timer.name = effect_key + str(status_effect.effect_lvl) + "_timer"
	if mod_timer.is_inside_tree():
		mod_timer.start()

	effect_timers[effect_key] = mod_timer

	_start_effect_fx(status_effect)

	for mod_resource: StatMod in status_effect.stat_mods:
		affected_entity.stats.add_mods([mod_resource] as Array[StatMod])

## Starts the status effects' associated visual FX like particles. Checks if the receiver has the
## matching handler node first.
func _start_effect_fx(status_effect: StatusEffect) -> void:
	var effect_name: String = status_effect.particle_hander_req if status_effect.particle_hander_req != "" else status_effect.id.to_pascal_case()
	var particle_node: CPUParticles2D = get_node_or_null(effect_name + "Particles")
	if particle_node == null:
		return

	var handler_check: bool = status_effect.particle_hander_req == "" or effect_receiver.get(effect_name.to_snake_case() + "_handler") != null
	if not (status_effect.spawn_particles and handler_check):
		return

	if status_effect.make_entity_glow and handler_check:
		affected_entity.sprite.update_floor_light(status_effect.id, false)
		affected_entity.sprite.update_overlay_color(status_effect.id, false)

	var emission_shape: CPUParticles2D.EmissionShape = particle_node.get_emission_shape()
	var emission_mgr: ParticleEmissionComponent = affected_entity.emission_mgr

	if emission_shape == CPUParticles2D.EmissionShape.EMISSION_SHAPE_SPHERE_SURFACE:
		particle_node.emission_sphere_radius = emission_mgr.get_extents(ParticleEmissionComponent.Boxes.COVER).x
		particle_node.position = emission_mgr.get_origin(ParticleEmissionComponent.Boxes.COVER)
	elif emission_shape == CPUParticles2D.EmissionShape.EMISSION_SHAPE_RECTANGLE and status_effect.id not in ["burning", "frostbite", "slowness"]:
		particle_node.emission_rect_extents = emission_mgr.get_extents(ParticleEmissionComponent.Boxes.COVER)
		particle_node.position = emission_mgr.get_origin(ParticleEmissionComponent.Boxes.COVER)
	elif status_effect.id in ["burning", "slowness"]: # Because it needs to be at the floor only
		particle_node.emission_rect_extents = emission_mgr.get_extents(ParticleEmissionComponent.Boxes.BELOW)
		particle_node.position = emission_mgr.get_origin(ParticleEmissionComponent.Boxes.BELOW)
	elif status_effect.id == "frostbite": # Because it needs to be above it only
		particle_node.emission_rect_extents = emission_mgr.get_extents(ParticleEmissionComponent.Boxes.ABOVE)
		particle_node.position = emission_mgr.get_origin(ParticleEmissionComponent.Boxes.ABOVE)
	else:
		return

	var particle_fade_tween: Tween = particle_fade_tweens.get(status_effect.id, null)
	if particle_fade_tween != null:
		particle_fade_tween.kill()
		particle_fade_tweens.erase(status_effect.id)

	particle_node.modulate.a = 1.0
	particle_node.emitting = true

	if DebugFlags.show_status_effect_particle_emission_area:
		queue_redraw()

## Extends the duration of the timer associated with some current effect.
func _extend_effect_duration(effect_key: String, time_to_add: float) -> void:
	var timer: Timer = effect_timers.get(effect_key, null)
	if timer != null:
		var new_time: float = timer.get_time_left() + time_to_add
		timer.stop()
		timer.wait_time = new_time
		timer.start()

## Restarts the timer associated with some current effect.
func _restart_effect_duration(effect_key: String) -> void:
	var timer: Timer = effect_timers.get(effect_key, null)
	if timer != null:
		timer.stop()
		timer.start()

## Removes the status effect from the current effects dict and removes all its mods. Additionally removes its
## associated timer from the timer dict.
func _remove_status_effect(status_effect: StatusEffect) -> void:
	var effect_key: String = status_effect.get_full_effect_key()

	if DebugFlags.current_effect_changes and print_effect_updates:
		if status_effect is StormSyndromeEffect:
			print_rich("-------[color=red]Removed[/color][b] [color=pink]" + effect_key + " " + str(status_effect.effect_lvl) + "[/color][/b][color=gray] from " + affected_entity.name + "-------")
		else:
			print_rich("-------[color=red]Removed[/color][b] " + effect_key + " " + str(status_effect.effect_lvl) + "[/b][color=gray] from " + affected_entity.name + "-------")

	for mod_resource: StatMod in status_effect.stat_mods:
		affected_entity.stats.remove_mod(mod_resource.stat_id, mod_resource.mod_id)

	current_effects.erase(effect_key)

	var timer: Timer = effect_timers.get(effect_key, null)
	if timer != null:
		if timer.has_meta("callable"): # So we can cancel any pending callables before freeing
			var callable: Callable = timer.get_meta("callable")
			timer.timeout.disconnect(callable)
			timer.set_meta("callable", null)
		timer.stop()
		timer.queue_free()
		effect_timers.erase(effect_key)

	_stop_effect_fx(status_effect.id, false)

## Stops the status effects' associated visual FX like particles. Pass in only the effect id, not its source type.
func _stop_effect_fx(effect_id: String, force: bool = false) -> void:
	affected_entity.sprite.update_floor_light(effect_id, true)
	affected_entity.sprite.update_overlay_color(effect_id, true)

	if not force:
		var count: int = 0
		for effect_key: String in current_effects:
			if effect_key.begins_with(effect_id + ":"):
				count += 1
		if count >= 1:
			return

	var particle_node: CPUParticles2D = get_node_or_null(effect_id.to_pascal_case() + "Particles")
	if particle_node != null:
		particle_node.emitting = false

		var tween: Tween = create_tween()
		particle_fade_tweens[effect_id] = tween
		tween.tween_property(particle_node, "modulate:a", 0.0, 0.35)
		tween.tween_callback(func() -> void: particle_fade_tweens.erase(effect_id))

## Returns if any effect (no matter the level) of the passed in name is active. Can optionally check only for
## a single source type.
@warning_ignore("int_as_enum_without_match", "int_as_enum_without_cast")
func check_if_has_effect(id: String, source_type: Globals.StatusEffectSourceType = -1) -> bool:
	if source_type != -1:
		return current_effects.has(id + ":" + str(Globals.StatusEffectSourceType.keys()[source_type]).to_lower())
	else:
		for effect_key: StringName in current_effects:
			if effect_key.begins_with(id + ":"):
				return true
		return false

## Attempts to remove any effect of the matching id and source type (which is given as an Enum value).
## It also cancels any active DOTs and HOTs for it.
func request_effect_removal_by_source(id: StringName, source_type: Globals.StatusEffectSourceType) -> void:
	var source_string: StringName = StringName((Globals.StatusEffectSourceType.keys()[source_type]).to_lower())
	request_effect_removal_by_source_string(id, source_string)

## Attempts to remove any effect of the matching id and source type (which is given as a StringName).
## It also cancels any active DOTs and HOTs for it.
func request_effect_removal_by_source_string(id: StringName, source_string: StringName) -> void:
	var key_to_remove: String = id + ":" + source_string
	var existing_effect: StatusEffect = current_effects.get(key_to_remove, null)
	if existing_effect:
		_remove_status_effect(existing_effect)
	_cancel_over_time_effects(key_to_remove)

## Attempts to remove all effects of the matching id, regardless of source type.
## It also cancels all active DOTs and HOTs for each of them.
func request_effect_removal_for_all_sources(id: String) -> void:
	var to_erase: Array[StatusEffect] = []
	for effect_key: StringName in current_effects:
		if effect_key.begins_with(id + ":"):
			to_erase.append(current_effects[effect_key])
			_cancel_over_time_effects(effect_key)

	for effect: StatusEffect in to_erase:
		_remove_status_effect(effect)

## Sends the cancellation requests for a composite effect key to the damage and heal handlers if they exist.
func _cancel_over_time_effects(key_to_cancel: String) -> void:
	if effect_receiver.dmg_handler != null:
		effect_receiver.dmg_handler.cancel_over_time_dmg(key_to_cancel)
	if effect_receiver.heal_handler != null:
		effect_receiver.heal_handler.cancel_over_time_heal(key_to_cancel)

## Removes all bad status effects except for an optional exception effect that may be specified.
## The optional kept effect should be given only as its effect id, not including its source type.
func remove_all_bad_status_effects(effect_to_keep_id: String = "") -> void:
	for status_effect_key: StringName in current_effects:
		if effect_to_keep_id == StringHelpers.get_before_colon(status_effect_key):
			continue
		elif current_effects[status_effect_key].is_bad_effect:
			request_effect_removal_for_all_sources(StringHelpers.get_before_colon(status_effect_key))

## Removes all good status effects except for an optional exception effect that may be specified.
## The optional kept effect should be given only as its effect id, not including its source type.
func remove_all_good_status_effects(effect_to_keep_id: String = "") -> void:
	for status_effect_key: StringName in current_effects:
		if effect_to_keep_id == StringHelpers.get_before_colon(status_effect_key):
			continue
		elif not current_effects[status_effect_key].is_bad_effect:
			request_effect_removal_for_all_sources(StringHelpers.get_before_colon(status_effect_key))

## Removes all status effects.
func remove_all_status_effects() -> void:
	for status_effect: StatusEffect in current_effects.values():
		_remove_status_effect(status_effect)

## Returns true if there is an "untouchable" effect in the current effects.
func is_untouchable() -> bool:
	for status_effect: StatusEffect in current_effects.values():
		if status_effect.id == "untouchable":
			return true
	return false

## Returns a dictionary of arrays, grouped by the effect id. This abstracts out the source types.
func get_current_effects_grouped_by_id() -> Dictionary[StringName, Array]:
	var results: Dictionary[StringName, Array]
	for effect: StringName in current_effects:
		var effect_id: StringName = effect.split(":")[0]
		if effect_id in results:
			results[effect_id].append(current_effects[effect])
		else:
			results[effect_id] = [current_effects[effect]]
	return results
