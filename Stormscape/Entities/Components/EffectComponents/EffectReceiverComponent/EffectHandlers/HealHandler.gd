@icon("res://Utilities/Debug/EditorIcons/heal_handler.svg")
extends Node
class_name HealHandler
## A handler for using the data provided in the effect source to apply healing in different ways.

@onready var affected_entity: Entity = get_parent().affected_entity ## The entity affected by this heal handler.

var health_component: HealthComponent ## The health component to be affected by the healing.
var hot_timers: Dictionary[String, Array] = {} ## Holds references to all timers currently tracking active HOT.
var hot_delay_timers: Dictionary[String, Array] = {} ## Holds references to all timers current tracking delays for active HOT.


## Asserts that there is a valid health component on the affected entity before trying to handle healing.
func _ready() -> void:
	if not affected_entity.is_node_ready():
		await affected_entity.ready
	health_component = affected_entity.health_component
	assert(health_component, affected_entity.name + " has an effect receiver that is intended to handle healing, but no health component is connected.")

## Handles applying instant, one-shot healing to the affected entity. Returns the appropriate xp amount to apply.
func handle_instant_heal(effect_source: EffectSource, heal_affected_stats: Globals.HealAffectedStats,
							lvl: int) -> int:
	var level_mult: float = ((floori(lvl / 10.0) * effect_source.lvl_heal_scalar) / 100.0) + 1
	var heal_amount: int = ceili(effect_source.base_healing * level_mult)
	_send_handled_healing("basic_healing", heal_affected_stats, heal_amount, effect_source.multishot_id)
	return heal_amount

## Handles applying damage that is inflicted over time, whether with a delay, with burst intervals, or with both.
func handle_over_time_heal(hot_resource: HOTResource, source_type: String) -> void:
	var hot_timer: Timer = TimerHelpers.create_repeating_timer(self)
	hot_timer.set_meta("hot_resource", hot_resource)
	hot_timer.name = source_type + "_timer"
	hot_timer.timeout.connect(_on_hot_timer_timeout.bind(hot_timer, source_type))

	if hot_resource.delay_time > 0: # We have a delay before the healing starts
		var delay_timer: Timer = TimerHelpers.create_one_shot_timer(self, hot_resource.delay_time)

		hot_timer.set_meta("ticks_completed", 0)

		if not hot_resource.run_until_removed:
			hot_timer.wait_time = max(0.01, (hot_resource.healing_time / (hot_resource.heal_ticks_array.size() - 1)))
		else:
			hot_timer.wait_time = max(0.01, hot_resource.time_between_ticks)

		delay_timer.name = source_type + "_delayTimer"
		delay_timer.timeout.connect(_on_delay_hot_timer_timeout.bind(hot_timer, source_type, delay_timer))
		delay_timer.start()

		TimerHelpers.add_timer_to_cache(source_type, hot_timer, hot_timers)
		TimerHelpers.add_timer_to_cache(source_type, delay_timer, hot_delay_timers)
	else: # There is no delay needed
		hot_timer.set_meta("ticks_completed", 1)

		if not hot_resource.run_until_removed:
			hot_timer.wait_time = max(0.01, (hot_resource.healing_time / (hot_resource.heal_ticks_array.size() - 1)))
		else:
			hot_timer.wait_time = max(0.01, hot_resource.time_between_ticks)

		_send_handled_healing(source_type, hot_resource.heal_affected_stats, hot_resource.heal_ticks_array[0], -1)
		affected_entity.sprite.start_hitflash(hot_resource.hit_flash_color, true)

		TimerHelpers.add_timer_to_cache(source_type, hot_timer, hot_timers)
		hot_timer.start()

## Called externally to stop a HOT effect from proceeding.
func cancel_over_time_heal(source_type: String) -> void:
	_cancel_hot_timers(source_type)

	# Cancelling delay timers here as well
	var delay_timers: Array = hot_delay_timers.get(source_type, [])
	if not delay_timers.is_empty():
		TimerHelpers.delete_delay_timers_from_cache(delay_timers)
		if hot_delay_timers[source_type].is_empty():
			hot_delay_timers.erase(source_type)

## Cancels all (or only a specific one) timers for a matching source type.
func _cancel_hot_timers(source_type: String, specific_timer: Timer = null) -> void:
	var heal_timers: Array = hot_timers.get(source_type, [])
	if not heal_timers.is_empty():
		TimerHelpers.delete_timers_from_cache(heal_timers, specific_timer)
		if hot_timers[source_type].is_empty():
			hot_timers.erase(source_type)

## When the delay timer ends, trigger our first tick and then start the normal timer to take it from here.
func _on_delay_hot_timer_timeout(hot_timer: Timer, source_type: String, delay_timer: Timer) -> void:
	_on_hot_timer_timeout(hot_timer, source_type)
	hot_timer.start()
	delay_timer.queue_free()

## When the healing over time interval timer ends, check what sourced the timer and see if that source
## needs to apply any more healing ticks before ending.
func _on_hot_timer_timeout(hot_timer: Timer, source_type: String) -> void:
	var hot_resource: HOTResource = hot_timer.get_meta("hot_resource")
	var ticks_completed: int = hot_timer.get_meta("ticks_completed")
	var heal_affected_stats: Globals.HealAffectedStats = hot_resource.heal_affected_stats

	if hot_resource.run_until_removed:
		var healing: int = hot_resource.heal_ticks_array[0]
		_send_handled_healing(source_type, heal_affected_stats, healing, -1)
		affected_entity.sprite.start_hitflash(hot_resource.hit_flash_color, true)
		hot_timer.set_meta("ticks_completed", ticks_completed + 1)
	else:
		var max_ticks: int = hot_resource.heal_ticks_array.size()
		if ticks_completed < max_ticks:
			var healing: int = hot_resource.heal_ticks_array[ticks_completed]
			_send_handled_healing(source_type, heal_affected_stats, healing, -1)
			affected_entity.sprite.start_hitflash(hot_resource.hit_flash_color, true)
			hot_timer.set_meta("ticks_completed", ticks_completed + 1)

			if max_ticks == 1:
				_cancel_hot_timers(source_type, hot_timer)
		else:
			_cancel_hot_timers(source_type, hot_timer)

## Sends the affected entity's health component the final healing values based on what stats the heal was
## allowed to affect.
func _send_handled_healing(source_type: String, heal_affected_stats: Globals.HealAffectedStats, handled_amount: int,
							multishot_id: int) -> void:
	var positive_healing: int = max(0, handled_amount)
	match heal_affected_stats:
		Globals.HealAffectedStats.HEALTH_ONLY:
			health_component.heal_health(positive_healing, source_type, multishot_id)
		Globals.HealAffectedStats.SHIELD_ONLY:
			health_component.heal_shield(positive_healing, source_type, multishot_id)
		Globals.HealAffectedStats.HEALTH_THEN_SHIELD:
			health_component.heal_health_then_shield(positive_healing, source_type, multishot_id)
		Globals.HealAffectedStats.SIMULTANEOUS:
			health_component.heal_health(positive_healing, source_type, multishot_id)
			health_component.heal_shield(positive_healing, source_type, multishot_id)
