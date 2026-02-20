extends HitboxComponent
class_name Projectile
## The core script for projectiles, implementing many helper scripts to track movement and behaviors on hit.

@export var in_air_only_particles: Array[CPUParticles2D] ## Any particles selected here will be emitting only while in the air.

@onready var sprite: AnimatedSprite2D = $ProjSprite ## The sprite for this projectile.
@onready var shadow: Sprite2D = $Shadow ## The shadow sprite for this projectile.
@onready var anim_player: AnimationPlayer = get_node_or_null("AnimationPlayer") ## The anim player for this projectile.
@onready var trail: Trail = get_node_or_null("Trail") ## The trail behind this projectile.
@onready var arcing_handler: ArcingHandler = ArcingHandler.new(self) ## The arcing handler helper script.
@onready var homing_handler: HomingHandler = HomingHandler.new(self) ## The homing handler helper script.

#region Local Vars
const MAX_AOE_RADIUS: float = 85.0
var stats: ProjStats ## The logic for how to operate this projectile.
var sc: StatModsCache ## The cache containing the current numerical values for firing metrics.
var lifetime_timer: Timer = TimerHelpers.create_one_shot_timer(self, -1, _on_lifetime_timer_timeout_or_reached_max_distance) ## The timer tracking how long the projectile has left to exist.
var aoe_delay_timer: Timer = TimerHelpers.create_one_shot_timer(self) ## The timer tracking how long after starting an AOE do we wait before enabling damage again.
var initial_boost_timer: Timer = TimerHelpers.create_one_shot_timer(self, -1, func() -> void: current_initial_boost = 1.0) ## The timer that tracks how long we have left in an initial boost.
var starting_proj_height: int ## The starting height the projectile is at when calculating the fake z axis.
var current_sampled_speed: float = 0 ## The current speed pulled from the speed curve.
var true_current_speed: float = 0 ## The real current speed calculated from change in position over time.
var current_initial_boost: float = 1.0 ## If we need to boost at the start, this tracks the current boost.
var cumulative_distance: float = 0 ## The cumulative distance we have travelled since spawning.
var previous_position: Vector2 ## A temp variable for holding previous position. Used in movement direction calculation.
var instantiation_position: Vector2 ## The instantiation position of this projectile. Used in calculations.
var instantiation_rotation: float ## The instantiation rotation of this projectile. Used in calculations. Updated on ricochets, though.
var resettable_starting_dir: Vector2 ## Reset upon movement change after ricochet and bounce. Used in calculations.
var resettable_starting_pos: Vector2 ## Reset upon movement change after ricochet and bounce. Used in calculations.
var pierce_count: int = 0 ## The number of times we have pierced so far.
var ricochet_count: int = 0 ## The number of times we have ricocheted so far.
var split_proj_scene: PackedScene ## The packed scene containing this projectile's scene for when we split and need to copy.
var splits_so_far: int = 0 ## The number of times this has been split so far.
var split_delay_counter: float = 0 ## The incremented delta counter for how long to wait before splitting.
var spin_dir: int = 1 ## The spin direction. -1 is left, 1 is right.
var is_in_aoe_phase: bool = false ## Whether we are currently executing an AOE sequence.
var non_sped_up_time_counter: float = 0 ## How long we have been moving so far, used in determining spin speed when added.
var bounces_so_far: int = 0 ## The number of times so far that we have bounced off the ground after an initial arc.
var played_whiz_sound: bool = false ## Whether this has already played the whiz sound once or not.
var debug_recent_hit_location: Vector2 ## The location of the most recent point we hit something.
var aoe_overlapped_receivers: Dictionary[Area2D, Timer] ## The areas that are currently in an AOE area.
var is_disabling_monitoring: bool = false ## When true, we are waiting on the deferred call to disable collision monitoring.
var about_to_free: bool = false ## This is true once we have started the impact animation and should no longer be able to hit new entities.
var multishot_id: int = 0 ## The id passed in on creation that relates the sibling projectiles spawned on the same multishot barrage.
var max_distance_random_offset: float = 0 ## Assigned upon creation to add randomization to how far each shot of a multishot firing can travel.
var shot_facing_direction: int = 1 ## When 1, the projectile was spawned on the right half of the unit circle, -1 otherwise.
#endregion


#region On Load
func _on_before_load_game() -> void:
	queue_free()
#endregion

#region Core
## Creates a projectile and assigns its needed variables in a specific order. Then it returns it.
static func create(wpn_ii: WeaponII, src_entity: Entity, pos: Vector2, rot: float) -> Projectile:
	var proj_scene: PackedScene = wpn_ii.stats.projectile_scn
	var proj: Projectile = proj_scene.instantiate()
	proj.split_proj_scene = proj_scene
	proj.global_position = pos
	proj.rotation = rot

	proj.stats = wpn_ii.stats.projectile_logic
	proj.sc = wpn_ii.sc
	if proj.stats.speed_curve.point_count == 0:
		push_error("\"" + src_entity.name + "\" has a weapon attempting to fire projectiles, but the projectile resource within the weapon has a blank speed curve.")
	proj.max_distance_random_offset = randf_range(0, 15)

	var effect_src: EffectSource = wpn_ii.stats.effect_source
	proj.effect_source = effect_src
	proj.collision_mask = effect_src.scanned_phys_layers
	proj.source_entity = src_entity
	proj.source_ii = wpn_ii
	return proj

## Used for debugging the homing system & other collisions. Draws vectors to where we have scanned during
## the "FOV" method.
func _draw() -> void:
	if DebugFlags.show_movement_dir:
		var local_movement_direction: Vector2 = movement_direction.rotated(-rotation) * 100
		draw_line(Vector2.ZERO, local_movement_direction, Color(1, 1, 1, 0.5), 0.6)

	if debug_recent_hit_location != Vector2.ZERO and DebugFlags.show_collision_points:
		z_index = 100
		draw_circle(to_local(debug_recent_hit_location), 1.5, Color(1, 1, 0, 0.35))

	if DebugFlags.show_homing_targets and homing_handler.homing_target != null:
		z_index = 100
		draw_circle(to_local(homing_handler.homing_target.global_position), 5, Color(1, 0, 1, 0.3))

	if not DebugFlags.show_homing_rays:
		return

	for ray: Dictionary[String, Variant] in homing_handler.debug_homing_rays:
		var from_pos: Vector2 = to_local(ray["from"])
		var to_pos: Vector2 = to_local(ray["hit_position"])
		var color: Color = Color(0, 1, 0, 0.4) if ray["hit"] else Color(1, 0, 0, 0.25)

		draw_line(from_pos, to_pos, color, 1)

		if ray["hit"]:
			draw_circle(to_pos, 2, color)

## Setting up z_index, hiding shadow until rotation is assigned, and initializing timers. Then this sets up
## spin and arcing logic should we need it.
func _ready() -> void:
	super._ready()
	add_to_group("has_save_logic")
	shadow.visible = false
	previous_position = global_position
	sprite.self_modulate = stats.glow_color * (1.0 + (stats.glow_strength / 100.0))

	lifetime_timer.start(stats.lifetime)

	homing_handler.set_up_potential_homing_delay()

	if stats.height_override != -1 and splits_so_far == 0:
		starting_proj_height = stats.height_override
	if stats.disable_trail and trail != null:
		trail.queue_free()

	_set_up_starting_transform_and_spin_logic()
	if stats.launch_angle > 0 and stats.homing_method == "None":
		arcing_handler.is_arcing = true
		hide()
		arcing_handler.reset_arc_logic()

	if stats.initial_boost_time > 0:
		current_initial_boost = stats.initial_boost_mult
		initial_boost_timer.start(stats.initial_boost_time)

	sprite.frame = randi_range(0, sprite.sprite_frames.get_frame_count(sprite.animation) - 1)

## Enables the main projectile collider.
func _enable_collider() -> void:
	collider.disabled = false

## Disables the main projectile collider.
func _disable_collider() -> void:
	collider.disabled = true

## Disables monitoring (the ability to detect when things enter this hitbox).
func _disable_monitoring() -> void:
	monitoring = false
	is_disabling_monitoring = false
#endregion

#region General
## Assigns a random spin direction if we need one, otherwise picks from the pre-chosen direction.
## Then it determines where to start shooting from based on how big its sprite texture is.
func _set_up_starting_transform_and_spin_logic() -> void:
	if stats.do_y_axis_reflection:
		var angle: float = wrapf(rotation, 0, TAU)
		if (angle > (PI / 2) and angle < (3 * PI / 2)):
			sprite.flip_v = true

	var hands_rot: float = fmod(source_entity.hands.hands_anchor.rotation + TAU, TAU)
	shot_facing_direction = -1 if hands_rot > PI / 2 and hands_rot < 3 * PI / 2 else 1

	if stats.spin_both_ways:
		spin_dir = -1 if randf() < 0.5 else 1
	else:
		if splits_so_far == 0:
			if stats.spin_direction == "Forward":
				spin_dir = -1 if hands_rot > PI / 2 and hands_rot < 3 * PI / 2 else 1
			else:
				spin_dir = 1 if hands_rot > PI / 2 and hands_rot < 3 * PI / 2 else -1

	var sprite_rect: Vector2 = SpriteHelpers.SpriteDetails.get_frame_rect(sprite)
	var start_offset: int = int(ceil(sprite_rect.x / (4.0 if (stats.launch_angle > 0 and stats.homing_method == "None") else 2.0)) * scale.x)
	var sprite_offset: Vector2 = Vector2(start_offset, 0).rotated(global_rotation)
	global_position += sprite_offset if splits_so_far < 1 else Vector2.ZERO

	instantiation_position = global_position
	instantiation_rotation = global_rotation
	resettable_starting_pos = global_position
	resettable_starting_dir = Vector2(cos(global_rotation), sin(global_rotation)).normalized()

## This is updating our movement direction and determining how to travel based on movement logic in
## the projectile resource.
func _physics_process(delta: float) -> void:
	non_sped_up_time_counter += delta

	previous_position = global_position

	if not is_in_aoe_phase:
		var max_dist: float = sc.get_stat("proj_max_distance")
		if (global_position - instantiation_position).length() >= (max_dist + max_distance_random_offset):
			_on_lifetime_timer_timeout_or_reached_max_distance()

		if stats.homing_method == "None":
			if not arcing_handler.is_arcing:
				_do_projectile_movement(delta)
			else:
				arcing_handler.do_arc_movement(delta)
		else:
			_do_projectile_movement(delta)

	split_delay_counter += delta
	var delay_to_use: float = ArrayHelpers.get_or_default(stats.split_delays, splits_so_far, stats.split_delays[0])
	if splits_so_far < stats.number_of_splits and split_delay_counter >= delay_to_use:
		shadow.visible = false
		_split_self()

	movement_direction = (global_position - previous_position).normalized()

	if DebugFlags.show_homing_rays or DebugFlags.show_collision_points or DebugFlags.show_homing_targets or DebugFlags.show_movement_dir:
		queue_redraw()

## This moves the projectile based on the current method, accounting for current rotation if we need to.
## It chooses speed from the speed curve based on lifetime remaining.
func _do_projectile_movement(delta: float) -> void:
	var speed: float = sc.get_stat("proj_speed")
	var sampled_point: float = stats.speed_curve.sample_baked(1 - (lifetime_timer.time_left / stats.lifetime))
	current_sampled_speed = sampled_point * speed * current_initial_boost

	if homing_handler.is_homing_active:
		homing_handler.apply_homing_movement(delta)
		if homing_handler.homing_target == null or not homing_handler.homing_target.is_inside_tree():
			homing_handler.is_homing_active = false
	else:
		rotation += deg_to_rad(stats.spin_speed * spin_dir) * delta

		if stats.move_in_rotated_dir and stats.path_type == "Default":
			position += transform.x * current_sampled_speed * delta
		else:
			_do_varied_path_movement(delta)

	var distance_change: float = previous_position.distance_to(global_position)
	cumulative_distance += distance_change
	true_current_speed = distance_change / delta

	_update_shadow(global_position, movement_direction)

func _do_varied_path_movement(delta: float) -> void:
	match stats.path_type:
		"Default":
			position += resettable_starting_dir * current_sampled_speed * delta
		"Sine":
			var h_offset: Vector2 = resettable_starting_dir * current_sampled_speed * delta
			var v_offset: Vector2 = Vector2(0, stats.amplitude * sin(2 * PI * stats.frequency * non_sped_up_time_counter - (PI / 2 * shot_facing_direction)))
			var offset: Vector2 = h_offset + v_offset.rotated(instantiation_rotation)
			position += offset
		"Sawtooth":
			var h_offset: Vector2 = resettable_starting_dir * current_sampled_speed * delta
			var v_offset: Vector2 = Vector2(0, stats.amplitude * sign(sin(2 * PI * stats.frequency * non_sped_up_time_counter - PI / 2)))
			var offset: Vector2 = h_offset + v_offset
			position += offset

## Updates the shadow in a realistic manner.
func _update_shadow(new_position: Vector2, movement_dir: Vector2) -> void:
	var fake_shadow_dir: Vector2
	if stats.shadow_matches_spin:
		fake_shadow_dir = movement_dir.normalized()
		shadow.rotation = atan2(fake_shadow_dir.y, fake_shadow_dir.x)
		shadow.rotation += non_sped_up_time_counter * deg_to_rad(stats.spin_speed * spin_dir)
	else:
		fake_shadow_dir = resettable_starting_dir.normalized()
		shadow.rotation = atan2(resettable_starting_dir.y, resettable_starting_dir.x)

	if arcing_handler.is_arcing:
		var displacement_vector: Vector2 = new_position - resettable_starting_pos
		var projection_length: float = displacement_vector.dot(resettable_starting_dir)
		shadow.global_position = resettable_starting_pos + (resettable_starting_dir * projection_length)
		shadow.global_position.y += starting_proj_height if bounces_so_far == 0 else 0
	else:
		shadow.global_position = new_position
		shadow.global_position.y += starting_proj_height

	shadow.visible = true

## Disables all in-air only particles.
func _disable_in_air_only_particles() -> void:
	for node: CPUParticles2D in in_air_only_particles:
		node.emitting = false
#endregion

#region Splitting, Ricocheting, Piercing
## Splits the projectile into multiple instances across a specified angle.
func _split_self() -> void:
	var split_into_count: int = ArrayHelpers.get_or_default(stats.split_into_counts, splits_so_far, stats.split_into_counts[0])
	if not (splits_so_far < stats.number_of_splits) or (split_into_count < 2):
		return

	splits_so_far += 1
	var angular_spread: float = ArrayHelpers.get_or_default(stats.angular_spreads, splits_so_far - 1, stats.angular_spreads[0])
	var split_into_count_offset_by_one: float = ArrayHelpers.get_or_default(stats.split_into_counts, splits_so_far - 1, stats.split_into_counts[0])
	var close_to_360_adjustment: int = 0 if angular_spread > 310 else 1
	var step_angle: float = (deg_to_rad(angular_spread) / (split_into_count_offset_by_one - close_to_360_adjustment))
	var start_angle: float = instantiation_rotation - (deg_to_rad(angular_spread) / 2)
	var new_multishot_id: int = UIDHelper.generate_multishot_uid()

	for i: int in range(split_into_count_offset_by_one):
		var angle: float = start_angle + (i * step_angle)
		var new_proj: Projectile = Projectile.create(source_ii, source_entity, position, angle)
		new_proj.splits_so_far = splits_so_far
		new_proj.spin_dir = spin_dir
		new_proj.multishot_id = new_multishot_id
		if stats.homing_method == "Mouse Position":
			new_proj.homing_target = homing_handler.homing_target

		get_parent().add_child(new_proj)

	AudioManager.play_2d(stats.splitting_sound, global_position)

	var split_cam_fx: CamFXResource = ArrayHelpers.get_or_default(stats.split_cam_fx, splits_so_far - 1, stats.split_cam_fx[0])
	split_cam_fx.apply_falloffs_and_activate_all(source_entity)

	queue_free()

## Calculates the new direction of the projectile when it bounces or reflects off a collider.
func _handle_ricochet(object: Variant) -> void:
	if stats.ignore_dynamic_entities and (object is DynamicEntity or object.get_parent() is DynamicEntity):
		ricochet_count += 1
		return

	var collision_normal: Vector2 = (global_position - object.global_position).normalized()
	var direction: Vector2 = Vector2(cos(rotation), sin(rotation))

	var reflected_direction: Vector2
	if (object is TileMapLayer) or (not stats.ricochet_angle_bounce):
		reflected_direction = -direction

		resettable_starting_dir = reflected_direction.normalized()
	else:
		reflected_direction = direction.bounce(collision_normal)
		resettable_starting_dir = direction.bounce(collision_normal)

	arcing_handler.reset_arc_logic()
	instantiation_rotation = reflected_direction.angle()
	rotation = reflected_direction.angle()

	multishot_id = UIDHelper.generate_multishot_uid()

	ricochet_count += 1

	if stats.can_change_target and stats.homing_method != "Mouse Position":
		homing_handler.homing_target = null
		homing_handler.find_homing_target_based_on_method()

## Updates the number of things we have pierced through.
func _handle_pierce() -> void:
	pierce_count += 1
#endregion

#region AOE
## Begins a aoe damage sequence by checking if we have a circle collision shape to work with.
## If so, it plays any needed animations and creates the defined waits for aoe duration and delay.
func _handle_aoe() -> void:
	if collider.shape is not CircleShape2D and collider.shape is not CapsuleShape2D:
		push_error("\"" + name + "\" projectile has AOE logic but its collision shape is not a circle or capsule.")
		return

	is_in_aoe_phase = true
	is_disabling_monitoring = true
	call_deferred("_disable_monitoring")
	area_exited.connect(_on_area_exited)

	if stats.aoe_delay > 0:
		call_deferred("_disable_collider")

		aoe_delay_timer.start(stats.aoe_delay)
		await aoe_delay_timer.timeout

	if sprite.sprite_frames.has_animation("aoe"):
		var frame_count: int = sprite.sprite_frames.get_frame_count("aoe")
		sprite.sprite_frames.set_animation_speed("aoe", frame_count / stats.aoe_anim_dur)
		sprite.animation_finished.connect(_hide_sprite_after_aoe_anim_ends)
		sprite.play("aoe")
	else:
		_hide_sprite_after_aoe_anim_ends()

	var new_shape: Shape2D = collider.shape.duplicate()
	call_deferred("_assign_new_collider_shape_and_aoe_entities", new_shape)

	if stats.aoe_vfx != null:
		var radius: float = min(MAX_AOE_RADIUS, sc.get_stat("proj_aoe_radius"))
		var dur: float = stats.aoe_vfx_dur if stats.aoe_vfx_dur != 0.0 else max(0.05, stats.aoe_effect_dur)
		AreaOfEffectVFX.create(stats.aoe_vfx, Globals.world_root, self, radius, dur)
	AudioManager.play_2d(stats.aoe_sound, global_position)

	await get_tree().create_timer(max(0.05, stats.aoe_effect_dur), false, true, false).timeout
	queue_free()

## Hides the sprite and its shadow if need be.
func _hide_sprite_after_aoe_anim_ends() -> void:
	if stats.aoe_hide_sprite:
		sprite.hide()
		shadow.hide()

## Assigns the collider to a new shape and re-enables it. Takes into account scaling of the projectile itself
## to preserve aoe radius.
## This also applies the initial hit of the aoe effect source to entities in range. The handling
## function won't apply status effects as a result of this hit.
func _assign_new_collider_shape_and_aoe_entities(new_shape: Shape2D) -> void:
	var radius: float = min(MAX_AOE_RADIUS, sc.get_stat("proj_aoe_radius"))
	new_shape.radius = (radius / scale.x)
	collider.shape = new_shape
	_enable_collider()
	set_deferred("monitoring", true)

	# Handling initial hit of the aoe source. This is like how an explosion hits once but the ground burning will be separate.
	await get_tree().physics_frame
	await get_tree().physics_frame
	for area: Area2D in get_overlapping_areas():
		if (area.get_parent() == source_entity) and not stats.aoe_effect_source.can_hit_self:
			return
		elif area is EffectReceiverComponent:
			_start_being_handled(area as EffectReceiverComponent)
	for body: Node2D in get_overlapping_bodies():
		_on_body_entered(body)
#endregion

#region Lifetime & Handling
## When the lifetime ends, either start an AOE or queue free.
func _on_lifetime_timer_timeout_or_reached_max_distance() -> void:
	var original_radius: float = sc.get_original_stat("proj_aoe_radius")
	if original_radius > 0 and stats.aoe_before_freeing:
		_handle_aoe()
	else:
		queue_free()

## Overrides parent hitbox. When in AOE, we add new entities to a dictionary with an associated timer
## that applies the status effects on an interval.
func _on_area_entered(area: Area2D) -> void:
	if not is_in_aoe_phase:
		super._on_area_entered(area)
		return

	if (area.get_parent() == source_entity) and not stats.aoe_effect_source.can_hit_self:
		return

	if area is EffectReceiverComponent:
		var timer: Timer = Timer.new()
		timer.set_meta("area", area)
		timer.timeout.connect(_on_aoe_interval_timer_timeout.bind(timer))
		aoe_overlapped_receivers[area] = timer

		if stats.aoe_effects_delay > 0:
			await get_tree().create_timer(stats.aoe_effects_delay, false, true, false).timeout
			if not is_instance_valid(area) or not is_instance_valid(timer):
				return

		if area in aoe_overlapped_receivers:
			for status_effect: StatusEffect in stats.aoe_effect_source.status_effects:
				area.handle_status_effect(status_effect)

			add_child(timer)
			timer.start(stats.aoe_effect_interval)

## When the status effect interval timer ends, check if the area still exists, then apply the effects again.
func _on_aoe_interval_timer_timeout(timer: Timer) -> void:
	var area: Area2D = timer.get_meta("area")
	if area not in aoe_overlapped_receivers:
		timer.queue_free()
		return
	elif not is_instance_valid(area):
		aoe_overlapped_receivers.erase(area)
		timer.queue_free()
		return

	for status_effect: StatusEffect in stats.aoe_effect_source.status_effects:
		area.handle_status_effect(status_effect)

## When in AOE, remove the area from the dictionary and free its associated timer on exiting the AOE zone.
func _on_area_exited(area: Area2D) -> void:
	if not is_in_aoe_phase or is_disabling_monitoring:
		return

	if area is EffectReceiverComponent:
		var timer: Timer = aoe_overlapped_receivers.get(area, null)
		if timer:
			timer.queue_free()
			aoe_overlapped_receivers.erase(area)

## Overrides parent method. When we intersect with any kind of object, this processes what to do next.
func _process_hit(object: Node2D) -> void:
	var sprite_rect: Vector2 = SpriteHelpers.SpriteDetails.get_frame_rect(sprite)
	debug_recent_hit_location = global_position + Vector2(sprite_rect.x / 2, 0).rotated(rotation)
	if not is_in_aoe_phase:
		var ricochet_stat: int = int(sc.get_stat("proj_max_ricochet"))
		if stats.ricochet_walls_only and object is TileMapLayer:
			_handle_ricochet(object)
			spin_dir *= -1
			return
		if ricochet_count < ricochet_stat:
			_handle_ricochet(object)
			return

		var pierce_stat: int = int(sc.get_stat("proj_max_pierce"))
		if pierce_count < pierce_stat:
			if object is Entity or object is EffectReceiverComponent:
				_handle_pierce()
				return

		_disable_in_air_only_particles() # Since we have to be grounded at this point

		var original_radius: float = sc.get_original_stat("proj_aoe_radius")
		if original_radius > 0:
			lifetime_timer.stop()
			_handle_aoe()
			return

		_kill_projectile_on_hit()

## Stops and frees the projectile on hit when it cannot pierce, ricochet, or AOE anymore.
## Meant to be overridden by child classes where necessary.
func _kill_projectile_on_hit() -> void:
	set_physics_process(false)

	if about_to_free: # To handle when it hits more than one thing
		return
	about_to_free = true

	if sprite.sprite_frames.has_animation("impact"):
		if stats.rand_impact_rot:
			sprite.rotation_degrees = randi_range(0, 360)
		sprite.animation_finished.connect(queue_free)
		sprite.play("impact")
	else:
		queue_free()

## Overrides parent method. When we overlap with an entity who can accept effect sources, pass the
## effect source to that entity's handler. Note that the effect source is duplicated on hit so that
## we can include unique info like move dir.
func _start_being_handled(handling_area: EffectReceiverComponent) -> void:
	if about_to_free:
		return

	if not is_in_aoe_phase:
		effect_source = effect_source.duplicate()
		var modified_effect_src: EffectSource = _get_effect_source_adjusted_for_falloff(effect_source, handling_area, false)
		modified_effect_src.multishot_id = multishot_id
		modified_effect_src.movement_direction = movement_direction
		modified_effect_src.contact_position = global_position
		handling_area.handle_effect_source(modified_effect_src, source_entity, source_ii)
	else:
		if stats.aoe_effect_source == null:
			stats.aoe_effect_source = effect_source
		var modified_effect_src: EffectSource = _get_effect_source_adjusted_for_falloff(stats.aoe_effect_source, handling_area, true)
		modified_effect_src.contact_position = global_position
		handling_area.handle_effect_source(modified_effect_src, source_entity, source_ii, false) # Don't reapply status effects.

## When we hit a handling area during an AOE, we need to apply falloff based on distance from the center of the AOE.
func _get_effect_source_adjusted_for_falloff(effect_src: EffectSource, handling_area: EffectReceiverComponent,
												is_aoe: bool = false) -> EffectSource:
	var dist_to_center: float = handling_area.get_parent().global_position.distance_to(global_position)
	var falloff_effect_src: EffectSource = effect_src.duplicate()
	var falloff_mult: float
	var apply_to_bad: bool
	var apply_to_good: bool

	if is_aoe:
		apply_to_bad = stats.bad_effects_aoe_falloff
		apply_to_good = stats.good_effects_aoe_falloff
		var radius: float = min(MAX_AOE_RADIUS, sc.get_stat("proj_aoe_radius"))
		falloff_mult = max(0.05, stats.aoe_effect_falloff_curve.sample_baked(dist_to_center / radius))
	else:
		apply_to_bad = stats.bad_effects_falloff
		apply_to_good = stats.good_effects_falloff
		var point_to_sample: float = 1.0 - (max(0, float(stats.point_of_max_falloff) - cumulative_distance) / stats.point_of_max_falloff)
		var sampled_point: float = stats.effect_falloff_curve.sample_baked(point_to_sample)
		falloff_mult = max(0.05, sampled_point)

	if apply_to_bad:
		falloff_effect_src.base_damage = int(min(falloff_effect_src.base_damage, ceil(falloff_effect_src.base_damage * falloff_mult)))

	if apply_to_good:
		falloff_effect_src.base_healing = int(min(falloff_effect_src.base_healing, ceil(falloff_effect_src.base_healing * falloff_mult)))

	return falloff_effect_src
#endregion
