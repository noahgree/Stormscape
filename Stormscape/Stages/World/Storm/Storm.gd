extends Node2D
class_name Storm
## The base class for the moving storm's functionalities. Controls the shader parameters and effect
## application logic.

@export var auto_start: bool = true ## Whether to immediately use the first transform in the queue at game load.
@export var transform_queue: Array[StormTransform] = [] ## The queue of upcoming transforms to apply to the zone.
@export var default_storm_effect: StatusEffect ## The default effect to apply when a dynamic entity leaves the safe zone.
@export var default_storm_visuals: StormVisuals ## The default storm visuals to apply at start.

@onready var collision_shape: CollisionShape2D = $SafeZone/CollisionShape2D ## The collider that detects when something is in the safe zone.
@onready var storm_circle: ColorRect = $StormCanvas/StormCircle ## The color rect that houses the storm circle shader.

#region Local Vars
var is_enabled: bool = true ## Whether we consider the storm to be active, visible, and enabled.
var changing_enabled_status: bool = false ## Whether we are currently animating the storm being enabled/disabled.
var current_radius: float = 0: ## The current radius of the safe zone.
	set(new_radius):
		current_radius = new_radius
		collision_shape.shape.radius = new_radius
var radius_tween: Tween = null ## The tween controlling a radius change.
var location_tween: Tween = null ## The tween controlling a location change.
var storm_colors_tween: Tween = null ## The tween controlling the storm color changes.
var storm_gradient_end_tween: Tween = null ## The tween controlling the gradient end distance changes.
var glow_ring_tween: Tween = null ## The tween controlling the glow ring changes.
var storm_wind_tween: Tween = null ## The tween controlling the wind brightness changes.
var storm_rain_tween: Tween = null ## The tween controlling the rain changes.
var storm_distortion_tween: Tween = null ## The tween controlling the storm distortion changes.
var player_see_thru_distance_tween: Tween = null ## The tween that gradually changes the player's see through distance in a loop.
var storm_change_delay_timer: Timer = TimerHelpers.create_one_shot_timer(self, -1, _on_storm_change_delay_timer_timeout) ## The timer controlling the delay between a new transform has activated and it actually starting to move/resize.
var current_storm_transform_time_timer: Timer = TimerHelpers.create_one_shot_timer(self, -1, _on_current_storm_transform_time_timer_timeout) ## The timer controlling the length of the storm change. Chooses the max time between the resize and relocate time values in the resource.
var see_through_distance: float = 20.0 ## The radius of the see-thru circle for the player.
var see_through_target_distance: float ## The radius of the see-thru circle for the player.
var pulse_up: bool = true ## Tracking the changing pulse direction of the player's see thru effect.
var see_through_pulse_mult: float = 1.0 ## The current multiplier for the pulsing amount on the player's see thru effect.
var see_through_distance_mult: float = 1.0 ## The current distance multiplier for the player's see thru effect.
var using_default_visuals: bool = false ## Whether we are currently using default visuals for the storm FX.
var current_visuals: StormVisuals ## The current visuals being used.
var current_effect: StatusEffect ##  The up-to-date effect to apply to entities leaving the safe area while the zone is active.
var zone_count: int = 0 ## The number of zones we have popped off the transform queue.
var just_replaced_queue: bool = false ## Whether we just replaced the old queue with a new one and should not pop the next phase.
#endregion


#region Storm Core
## Setting up timers and checking if we should auto start the first transform in the queue.
func _ready() -> void:
	DayNightManager.time_tick.connect(_update_see_thru_on_time_change)

	storm_circle.visible = true
	visible = true

	current_radius = collision_shape.shape.radius
	current_effect = default_storm_effect
	current_visuals = default_storm_visuals

	see_through_target_distance = see_through_distance

	if auto_start:
		_process_next_transform_in_queue()
	else:
		_revert_to_default_zone()

	_tween_player_see_through_distance()

	DebugConsole.add_command("storm", func() -> void: call("enable_storm" if not is_enabled else "disable_storm"))
	DebugConsole.add_command("next_phase", force_start_next_phase)

## Enables the storm to pick up where it left off. Re-enables all fx and the effect for current phase.
func enable_storm(from_save: bool = false) -> void:
	if changing_enabled_status:
		return
	else:
		changing_enabled_status = true

	storm_circle.visible = true
	visible = true

	if from_save:
		storm_circle.material.set_shader_parameter("override_all_alpha", 1.0)
		changing_enabled_status = false
	else:
		var tween: Tween = create_tween().set_ease(Tween.EASE_OUT)
		tween.tween_property(
			storm_circle.material,
			"shader_parameter/override_all_alpha",
			1.0,
			0.35
			)
		tween.finished.connect(func() -> void: changing_enabled_status = false)

	is_enabled = true

	storm_change_delay_timer.paused = false
	current_storm_transform_time_timer.paused = false

	if not from_save:
		if radius_tween and radius_tween.is_valid(): radius_tween.play()
		if location_tween and location_tween.is_valid(): location_tween.play()
		if storm_colors_tween and storm_colors_tween.is_valid(): storm_colors_tween.play()
		if storm_gradient_end_tween and storm_gradient_end_tween.is_valid(): storm_gradient_end_tween.play()
		if glow_ring_tween and glow_ring_tween.is_valid(): glow_ring_tween.play()
		if storm_wind_tween and storm_wind_tween.is_valid(): storm_wind_tween.play()
		if storm_rain_tween and storm_rain_tween.is_valid(): storm_rain_tween.play()
		if storm_distortion_tween and storm_distortion_tween.is_valid(): storm_distortion_tween.play()

	collision_shape.set_deferred("disabled", false)
	if not from_save:
		for i: int in range(4):
			await get_tree().physics_frame
		var entities_with_effect: Array[Node] = get_tree().get_nodes_in_group("entities_out_of_safe_area")
		for entity: Node in entities_with_effect:
			_add_effect_to_entity(entity, current_effect)

## Stops storm in its tracks and removes the current effect from entities out of the safe area.
func disable_storm(from_save: bool = false) -> void:
	if changing_enabled_status:
		return
	else:
		changing_enabled_status = true

	if from_save:
		storm_circle.material.set_shader_parameter("override_all_alpha", 0.0)
		storm_circle.visible = false
		visible = false
		changing_enabled_status = false
	else:
		var tween: Tween = create_tween().set_ease(Tween.EASE_OUT)
		tween.tween_property(
			storm_circle.material,
			"shader_parameter/override_all_alpha",
			0.0,
			0.35
			)
		tween.finished.connect(func() -> void:
			storm_circle.visible = false
			visible = false
			changing_enabled_status = false
			)

	storm_change_delay_timer.paused = true
	current_storm_transform_time_timer.paused = true
	if radius_tween: radius_tween.pause()
	if location_tween: location_tween.pause()
	if storm_colors_tween: storm_colors_tween.pause()
	if storm_gradient_end_tween: storm_gradient_end_tween.pause()
	if glow_ring_tween: glow_ring_tween.pause()
	if storm_wind_tween: storm_wind_tween.pause()
	if storm_rain_tween: storm_rain_tween.pause()
	if storm_distortion_tween: storm_distortion_tween.pause()

	collision_shape.set_deferred("disabled", true)
	var entities_with_effect: Array[Node] = get_tree().get_nodes_in_group("entities_out_of_safe_area")
	for entity: Node in entities_with_effect:
		entity.remove_from_group("entities_out_of_safe_area")
		_remove_current_effect_from_entity(entity)
	SignalBus.player_in_safe_zone_changed.emit()
	is_enabled = false

## Reverts the storm visuals and storm entity effect to the defaults. Typically called when the queue
## is empty and auto-advance was on for the previous final zone.
func _revert_to_default_zone() -> void:
	if DebugFlags.storm_phases:
		print_rich("[color=pink]*******[/color][color=purple] [b]Starting[/b] Storm Phase [/color][b]0[/b]" + " [color=gray][i](default)[/i][/color] [color=pink]*******[/color]")

	_apply_visual_overrides(default_storm_visuals)
	_swap_effect_applied_to_entities_out_of_safe_area(default_storm_effect)

## Called externally to forcefully transition to the next phase no matter what.
## If we haven't started any zones before, don't pop off the queue, just use the first in the queue.
func force_start_next_phase() -> void:
	if not is_enabled:
		return

	if DebugFlags.storm_phases:
		print_rich("[color=pink]*******[/color][color=gray] [i]Force Ending[/i] Storm Phase[/color] [color=pink]*******[/color]")
	if zone_count == 0:
		_process_next_transform_in_queue()
	else:
		_pop_current_transform_and_check_for_next_phase()

## Clears the current transform queue and sets it to a new, passed in set of transforms.
func replace_current_queue(new_queue: Array[StormTransform]) -> void:
	transform_queue.clear()
	transform_queue = new_queue.duplicate()
	just_replaced_queue = true

func _physics_process(_delta: float) -> void:
	_set_shader_transform_params()
#endregion

#region Shader Positioning & Player See Thru
## Updates the shader's transform params with the current values.
func _set_shader_transform_params() -> void:
	var collision_radius: float = current_radius

	# Setting up needed vars to do the calculations
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	storm_circle.material.set_shader_parameter("viewport_size", viewport_size)
	var screen_center: Vector2 = _get_screen_point_from_world_coord(global_position)

	# Calculating and assigning the vars in the shader that handle keeping the storm and noise in world space
	var edge_point_world: Vector2 = global_position + Vector2(collision_radius, 0).rotated(global_rotation)
	var screen_edge: Vector2 = _get_screen_point_from_world_coord(edge_point_world)
	var noise_origin: Vector2 = _get_screen_point_from_world_coord(Vector2.ZERO)
	storm_circle.material.set_shader_parameter("circle_center_pixels", screen_center)
	storm_circle.material.set_shader_parameter("noise_world_position", noise_origin)

	# Calculating and assigning the var that sets the radius of the shader circle in respect to world space
	var radius_pixels: float = screen_edge.distance_to(screen_center)
	storm_circle.material.set_shader_parameter("radius_pixels", radius_pixels)

	# Calculating and assigning the var that controls the see-thru distance for the player
	var player_pos: Vector2 = Globals.player_node.global_position + (Globals.player_node.sprite.position / 2.0)
	var see_through_point: Vector2 = _get_screen_point_from_world_coord(player_pos)
	var see_through_point_world: Vector2 = global_position + Vector2(see_through_distance, 0).rotated(global_rotation)
	var screen_edge_see_through: Vector2 = _get_screen_point_from_world_coord(see_through_point_world)
	var radius_pixels_see_through: float = screen_edge_see_through.distance_to(screen_center)
	storm_circle.material.set_shader_parameter("see_through_radius", radius_pixels_see_through)
	storm_circle.material.set_shader_parameter("see_through_center_pixels", see_through_point)

## Converts the world coordinate to a screen position based on camera position, rotation, and zoom.
func _get_screen_point_from_world_coord(world_point: Vector2) -> Vector2:
	var camera: Camera2D = Globals.player_camera
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var relative_position: Vector2 = world_point - camera.global_position - camera.offset
	var rotated_position: Vector2 = relative_position.rotated(-camera.rotation)
	var zoomed_position: Vector2 = rotated_position * camera.zoom
	var screen_position: Vector2 = (viewport_size / 2) + zoomed_position

	return screen_position

## Tweens the player's see through distance in a looping, pulsing, fashion.
func _tween_player_see_through_distance() -> void:
	if player_see_thru_distance_tween:
		player_see_thru_distance_tween.kill()
	player_see_thru_distance_tween = create_tween().set_ease(Tween.EASE_OUT)

	var pulse_target: float = (see_through_target_distance * see_through_distance_mult) + (5.0 * see_through_pulse_mult) if pulse_up else (see_through_target_distance * see_through_distance_mult) - (5.0 * see_through_distance_mult)

	player_see_thru_distance_tween.tween_property(self, "see_through_distance", pulse_target, 1.0)
	pulse_up = !pulse_up

	player_see_thru_distance_tween.tween_callback(_tween_player_see_through_distance).set_delay(0.05)

## Changes the see through distance for the player.
func update_player_see_through_distance(change_amount: float) -> void:
	see_through_target_distance += change_amount

#endregion

#region Handling Transforms
## Adds a new transform resource to the end of the queue, and if it is the only one in the queue,
## it starts the transform immediately.
func add_storm_transform_to_queue(new_transform: StormTransform) -> void:
	transform_queue.append(new_transform.duplicate())
	if transform_queue.size() == 1:
		_process_next_transform_in_queue()

## Pops the current zone transform off the queue. If it was successful, it calls to process
## the next transform in the queue, regardless of whether the queue is now empty.
## If it was unsuccessful, it reverts fx and the entity effect to the default zone.
## This should really only be called at the end of the last phase by the timer's timeout or when we
## force advance the zone from an external request.
func _pop_current_transform_and_check_for_next_phase() -> void:
	if not transform_queue.is_empty():
		if not just_replaced_queue:
			transform_queue.pop_front()
		else:
			just_replaced_queue = false

		_process_next_transform_in_queue()
	else:
		_revert_to_default_zone()

## If the queue is empty, revert everything to default. Otherwise, get the details of the next
## transform and start a potential delay.
func _process_next_transform_in_queue() -> void:
	_kill_current_motion_tweens_and_timers()

	if transform_queue.is_empty():
		_revert_to_default_zone()
	else:
		zone_count += 1

		var new_transform: StormTransform = transform_queue[0]
		var delay: float = max(new_transform.time_to_resize, new_transform.time_to_move)

		current_storm_transform_time_timer.wait_time = delay

		_check_for_transform_delay(new_transform)

## Stops and kills the active tweens and timers related to the current phase.
func _kill_current_motion_tweens_and_timers() -> void:
	storm_change_delay_timer.stop()
	current_storm_transform_time_timer.stop()

	if radius_tween: radius_tween.kill()
	if location_tween: location_tween.kill()

## Kills the current storm sequence and checks if we need to delay before starting the next one.
## Starts the next zone if we don't have a delay, otherwise starts the delay timer.
func _check_for_transform_delay(new_transform: StormTransform) -> void:
	if DebugFlags.storm_phases:
		var dur: float = max(new_transform.time_to_resize, new_transform.time_to_move)
		var effect: String = "Keep Previous"
		if new_transform.effect_setting == StormTransform.UpdateTypes.OVERRIDE:
			effect = new_transform.status_effect.get_full_effect_key() + " " + str(new_transform.status_effect.effect_lvl)
		elif new_transform.effect_setting == StormTransform.UpdateTypes.REVERT_TO_DEFAULT:
			effect = "Reverted to Default: " + default_storm_effect.get_full_effect_key() + " " + str(default_storm_effect.effect_lvl)
		print_rich("[color=pink]*******[/color][color=purple] [b]Starting[/b] Storm Phase [/color][b]" + str(zone_count) + "[/b][i] [delay = " + str(new_transform.delay) + "] [duration = " + str(dur) + "] " + "[effect = " + effect + "] [/i] [color=pink]*******[/color]")

	# Starting delay timer if we have any delay. Otherwise start applying the new zone transform.
	if new_transform.delay > 0:
		storm_change_delay_timer.set_meta("storm_params", new_transform)
		storm_change_delay_timer.start(new_transform.delay)
	else:
		_start_zone(new_transform)

## When the delay before the next transform ends, cue the new zone phase.
func _on_storm_change_delay_timer_timeout() -> void:
	var params: StormTransform = storm_change_delay_timer.get_meta("storm_params")
	_start_zone(params)

## Starts the next zone sequence using a new passed in storm transform resource.
func _start_zone(new_transform: StormTransform) -> void:
	# Check if we need to override visuals or reset them to default
	if new_transform.visuals_setting == StormTransform.UpdateTypes.OVERRIDE:
		_apply_visual_overrides(new_transform.storm_visuals)
	elif new_transform.visuals_setting == StormTransform.UpdateTypes.REVERT_TO_DEFAULT:
		_apply_visual_overrides(default_storm_visuals)

	# Start the actual zone movement and resize
	_tween_to_new_zone_position_and_radius(new_transform)

	# Check if we need to override the status effect or reset it to default
	if new_transform.effect_setting == StormTransform.UpdateTypes.OVERRIDE:
		_swap_effect_applied_to_entities_out_of_safe_area(new_transform.status_effect)
	elif new_transform.effect_setting == StormTransform.UpdateTypes.REVERT_TO_DEFAULT:
		_swap_effect_applied_to_entities_out_of_safe_area(default_storm_effect)

	# Giving the transform timer the data it needs to determine what to do on timeout, then starting the transform timer.
	current_storm_transform_time_timer.set_meta("auto_advance", new_transform.auto_advance)
	current_storm_transform_time_timer.start()

## Starts the tweens that will move the zone and resize its radius.
func _tween_to_new_zone_position_and_radius(new_transform: StormTransform) -> void:
	radius_tween = create_tween().set_ease(Tween.EASE_IN)

	var new_radius: float = new_transform.new_radius
	if new_transform.offset_radius: new_radius = current_radius + new_transform.new_radius

	radius_tween.tween_property(self, "current_radius", new_radius, new_transform.time_to_resize)

	location_tween = create_tween().set_ease(Tween.EASE_IN)

	var new_location: Vector2 = new_transform.new_location
	if new_transform.offset_location: new_location = global_position + new_transform.new_location

	location_tween.tween_property(self, "global_position", new_location, new_transform.time_to_move)

## When the current transform ends and that transform had auto advance turned on, tell the popping
## method to check for next phase.
func _on_current_storm_transform_time_timer_timeout() -> void:
	if DebugFlags.storm_phases:
		print_rich("[color=pink]*******[/color][color=gray] [i]End of[/i] Storm Phase [/color][b]" + str(zone_count) + "[/b] [color=pink]*******[/color]")
	var auto_advance: bool = current_storm_transform_time_timer.get_meta("auto_advance")
	if auto_advance:
		_pop_current_transform_and_check_for_next_phase()
#endregion

#region Visual Changes
## Applies all new visual overrides in the new storm visuals resource. If we are already using
## default visuals and another request comes in to transition to them, ignore it.
func _apply_visual_overrides(new_visuals: StormVisuals) -> void:
	current_visuals = new_visuals
	if (new_visuals == default_storm_visuals) and using_default_visuals:
		return
	elif (new_visuals == default_storm_visuals):
		using_default_visuals = true
	else:
		using_default_visuals = false

	for i: int in range(4):
		_tween_storm_colors(new_visuals)
	_tween_storm_gradient_end(new_visuals)
	_tween_glow_ring(new_visuals)
	_tween_wind(new_visuals)
	_tween_rain(new_visuals)
	_tween_distortion(new_visuals)
	storm_circle.material.set_shader_parameter("pulse_speed", new_visuals.ring_pulse_speed)
	see_through_pulse_mult = new_visuals.see_through_pulse_mult
	see_through_distance_mult = new_visuals.see_thru_dist_mult

## Tween all storm coloring parameters.
func _tween_storm_colors(new_visuals: StormVisuals) -> void:
	if storm_colors_tween: storm_colors_tween.kill()
	storm_colors_tween = create_tween().set_parallel(true)

	for i: int in range(4):
		storm_colors_tween.tween_property(
		storm_circle.material,
		"shader_parameter/color" + str(i + 1),
		new_visuals.storm_gradient_colors[i],
		new_visuals.viusal_change_time
		)

## Tween the storm gradient's end position.
func _tween_storm_gradient_end(new_visuals: StormVisuals) -> void:
	if storm_gradient_end_tween: storm_gradient_end_tween.kill()
	storm_gradient_end_tween = create_tween()

	storm_gradient_end_tween.tween_property(
		storm_circle.material,
		"shader_parameter/gradient_end",
		new_visuals.final_color_distance,
		new_visuals.viusal_change_time
		)

## Tween all glow ring parameters.
func _tween_glow_ring(new_visuals: StormVisuals) -> void:
	if glow_ring_tween: glow_ring_tween.kill()
	glow_ring_tween = create_tween().set_parallel(true)

	glow_ring_tween.tween_property(
		storm_circle.material,
		"shader_parameter/glow_color",
		new_visuals.ring_glow_color,
		new_visuals.viusal_change_time
		)
	glow_ring_tween.tween_property(
		storm_circle.material,
		"shader_parameter/ring_thickness",
		new_visuals.ring_glow_intensity,
		new_visuals.viusal_change_time
		)

## Tween all wind parameters.
func _tween_wind(new_visuals: StormVisuals) -> void:
	if storm_wind_tween: storm_wind_tween.kill()
	storm_wind_tween = create_tween()

	storm_wind_tween.tween_property(
		storm_circle.material,
		"shader_parameter/noise_brightness",
		0.0,
		new_visuals.viusal_change_time / 2.0
		)

	storm_wind_tween.chain().tween_callback(storm_circle.material.set_shader_parameter.bind("bottom_noise_speed", new_visuals.ground_wind_speed))

	storm_wind_tween.chain().tween_callback(storm_circle.material.set_shader_parameter.bind("top_noise_speed", new_visuals.top_wind_speed))

	storm_wind_tween.parallel().tween_callback(storm_circle.material.set_shader_parameter.bind("reverse_intensity", new_visuals.wind_reversal_factor))

	storm_wind_tween.parallel().tween_callback(storm_circle.material.set_shader_parameter.bind("swirl_intensity", new_visuals.wind_spiral_factor))

	storm_wind_tween.chain().tween_property(
		storm_circle.material,
		"shader_parameter/noise_brightness",
		new_visuals.wind_brightness,
		new_visuals.viusal_change_time / 2.0
		)

## Tween all rain parameters.
func _tween_rain(new_visuals: StormVisuals) -> void:
	if storm_rain_tween: storm_rain_tween.kill()
	storm_rain_tween = create_tween()

	storm_rain_tween.tween_property(
		storm_circle.material,
		"shader_parameter/count",
		0,
		new_visuals.viusal_change_time / 2.0
		)

	storm_rain_tween.chain().tween_callback(storm_circle.material.set_shader_parameter.bind("slant", new_visuals.rain_slant))

	storm_rain_tween.parallel().tween_callback(storm_circle.material.set_shader_parameter.bind("speed", new_visuals.rain_speed))

	storm_rain_tween.parallel().tween_callback(storm_circle.material.set_shader_parameter.bind("rain_color", new_visuals.rain_color))

	storm_rain_tween.parallel().tween_callback(storm_circle.material.set_shader_parameter.bind("size", new_visuals.rain_size))

	storm_rain_tween.chain().tween_property(
		storm_circle.material,
		"shader_parameter/count",
		new_visuals.rain_amount,
		new_visuals.viusal_change_time / 2.0
		)

## Tween all storm distortion parameters.
func _tween_distortion(new_visuals: StormVisuals) -> void:
	if storm_distortion_tween: storm_distortion_tween.kill()
	storm_distortion_tween = create_tween()

	storm_distortion_tween.tween_property(
		storm_circle.material,
		"shader_parameter/reflection_thickness",
		0.0,
		new_visuals.viusal_change_time / 2.0
		)

	storm_distortion_tween.chain().tween_callback(storm_circle.material.set_shader_parameter.bind("reflection_intensity", new_visuals.reflection_intensity))
	storm_distortion_tween.parallel().tween_callback(storm_circle.material.set_shader_parameter.bind("turbulence_intensity", new_visuals.turbulence))
	storm_distortion_tween.parallel().tween_callback(storm_circle.material.set_shader_parameter.bind("ripple_intensity", new_visuals.ripple_intensity))
	storm_distortion_tween.parallel().tween_callback(storm_circle.material.set_shader_parameter.bind("ripple_frequency", new_visuals.ripple_frequency))
	storm_distortion_tween.parallel().tween_callback(storm_circle.material.set_shader_parameter.bind("ripple_speed", new_visuals.ripple_speed))

	storm_distortion_tween.chain().tween_property(
		storm_circle.material,
		"shader_parameter/reflection_thickness",
		new_visuals.reflection_thickness,
		new_visuals.viusal_change_time / 2.0
		)

## Updates the player see through distance based on the time of day.
func _update_see_thru_on_time_change(_day: int, hour: int, minute: int) -> void:
	var result: float
	var factor: float

	if hour >= 5 and hour < 7:
		# Transition from night to day: 5 AM to 7 AM
		factor = (float(hour - 5) + float(minute) / 60.0) / 2.0
		result = lerp(current_visuals.night_see_thru, current_visuals.day_see_thru, factor)
	elif hour >= 7 and hour < 18:
		# Daytime: 7 AM to 6 PM
		result = current_visuals.day_see_thru
	elif hour >= 18 and hour < 20:
		# Transition from day to night: 6 PM to 8 PM
		factor = (float(hour - 18) + float(minute) / 60.0) / 2.0
		result = lerp(current_visuals.day_see_thru, current_visuals.night_see_thru, factor)
	else:
		# Nighttime: 8 PM to 5 AM
		result = current_visuals.night_see_thru

	storm_circle.material.set_shader_parameter("see_through_opacity", result / 100.0)
#endregion

#region Current Effect & Cam Shake
## When a dynamic entity enters the inner circle, we remove the current storm effect.
func _on_safe_zone_body_entered(body: Node2D) -> void:
	if body is DynamicEntity:
		_remove_current_effect_from_entity(body)
		body.remove_from_group("entities_out_of_safe_area")
	if body is Player:
		SignalBus.player_in_safe_zone_changed.emit()

## When a dynamic entity exits the inner safe circle, we apply the current storm effect.
func _on_safe_zone_body_exited(body: Node2D) -> void:
	if body is DynamicEntity:
		var health_component: HealthComponent = body.get_node_or_null("HealthComponent")
		if health_component and health_component.is_dying:
			return

		if is_enabled:
			_add_effect_to_entity(body, current_effect)
		body.add_to_group("entities_out_of_safe_area")
	if body is Player:
		SignalBus.player_in_safe_zone_changed.emit()

## Removes the current effect from entities out of the safe area and applies the new one.
## The new one will be the default effect if we have no upcoming zone, otherwise it will be the effect
## for the new transform.
func _swap_effect_applied_to_entities_out_of_safe_area(new_effect: StatusEffect) -> void:
	for entity: Node in get_tree().get_nodes_in_group("entities_out_of_safe_area"):
		_remove_current_effect_from_entity(entity)
		_add_effect_to_entity(entity, new_effect)
	current_effect = new_effect

## Removes the effect held in the current effect variable from all affected entities.
func _remove_current_effect_from_entity(body: DynamicEntity) -> void:
	var effects_manager: StatusEffectsComponent = body.effects
	if effects_manager != null:
		effects_manager.request_effect_removal_by_source(current_effect.id, current_effect.source_type)

## Adds the passed in effect to the passed in entity.
func _add_effect_to_entity(body: DynamicEntity, effect_to_add: StatusEffect) -> void:
	var receiver: EffectReceiverComponent = body.get_node_or_null("EffectReceiverComponent")
	if receiver != null and not body.effects.check_if_has_effect(effect_to_add.id, effect_to_add.source_type):
		receiver.handle_status_effect(effect_to_add)
#endregion
