class_name HomingHandler
## Handles the homing logic for projectiles.

const FOV_RAYCAST_COUNT: int = 36
var proj: Projectile ## A reference to the projectile this handler works on.
var homing_timer: Timer ## Timer to control homing duration.
var homing_delay_timer: Timer ## Timer for homing start delay.
var is_homing_active: bool = false ## Indicates if homing is currently active.
var homing_target: Node = null ## The current homing target.
var mouse_scan_targets: Array[Node] ## The current list of targets in range of the mouse click.
var debug_homing_rays: Array[Dictionary] ## An array of debug info about the FOV homing method raycasts.


## Called when this script is first created to provide a reference to the owning projectile.
func _init(parent_proj: Projectile) -> void:
	if Engine.is_editor_hint():
		return
	proj = parent_proj
	homing_timer = TimerHelpers.create_one_shot_timer(proj, -1, on_homing_timer_timeout)
	homing_delay_timer = TimerHelpers.create_one_shot_timer(proj, -1, start_homing)

## Sets up the homing delay if one exists, otherwise begins homing immediately if we have a valid
## homing method selected.
func set_up_potential_homing_delay() -> void:
	if proj.stats.homing_method != "None":
		if proj.stats.homing_start_delay > 0:
			proj.homing_delay_timer.start(proj.stats.homing_start_delay)
		else:
			start_homing()

## Starts the homing sequence by turning it on and starting the homing timer if needed. Then calls for us
## to find a target.
func start_homing() -> void:
	is_homing_active = true
	var original_dur: float = proj.sc.get_original_stat("proj_homing_duration")
	if original_dur > -1:
		homing_timer.start(proj.sc.get_stat("proj_homing_duration"))
	find_homing_target_based_on_method()

## Choses the proper way to pick a target based on the current homing method.
func find_homing_target_based_on_method() -> void:
	if proj.stats.homing_method == "FOV":
		_find_target_in_fov()
	elif proj.stats.homing_method == "Closest":
		_find_closest_target()
	elif proj.stats.homing_method == "Mouse Position":
		if proj.splits_so_far == 0:
			_choose_from_mouse_area_targets()
		else:
			homing_target = null
			is_homing_active = false
	elif proj.stats.homing_method == "Boomerang":
		homing_target = proj.source_entity
	else:
		homing_target = null
		is_homing_active = false

## Talks to the physics server to cast rays and look for targets when using the "FOV" homing method.
func _find_target_in_fov() -> void:
	var space_state: PhysicsDirectSpaceState2D = proj.get_world_2d().direct_space_state
	var fov_radians: float = deg_to_rad(proj.stats.homing_fov_angle)
	var half_fov: float = fov_radians / 2.0
	var direction: Vector2 = Vector2.RIGHT.rotated(proj.rotation)
	var candidates: Array[Node] = []

	if DebugFlags.show_homing_rays:
		debug_homing_rays.clear()

	var step: float = fov_radians / FOV_RAYCAST_COUNT

	for i: int in range(FOV_RAYCAST_COUNT + 1):
		var angle_offset: float = -half_fov + step * i
		var cast_direction: Vector2 = direction.rotated(angle_offset)
		var from_pos: Vector2 = proj.global_position
		var to_pos: Vector2 = proj.global_position + cast_direction * proj.stats.homing_max_range

		var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.new()
		query.from = from_pos
		query.to = to_pos
		query.collision_mask = proj.effect_source.scanned_phys_layers

		var exclusion_list: Array[RID] = [proj.get_rid()]

		if not proj.effect_source.can_hit_self:
			exclusion_list.append(proj.source_entity.get_rid())

		for child: Node in proj.source_entity.get_children():
			if child is Area2D:
				exclusion_list.append(child.get_rid())

		query.exclude = exclusion_list
		query.collide_with_bodies = true
		query.collide_with_areas = false # Only collides with Entity type

		var result: Dictionary[Variant, Variant] = space_state.intersect_ray(query)

		var debug_ray_info: Dictionary[String, Variant]
		if DebugFlags.show_homing_rays:
			debug_ray_info = { "from": from_pos, "to": to_pos, "hit": false, "hit_position": to_pos }

		if result:
			var obj: Node = result.collider
			if obj and _is_valid_homing_target(obj):
				candidates.append(obj)
				if DebugFlags.show_homing_rays:
					debug_ray_info["hit"] = true
					debug_ray_info["hit_position"] = result.position
		if DebugFlags.show_homing_rays:
			debug_homing_rays.append(debug_ray_info)

	if candidates.size() > 0:
		homing_target = _select_closest_homing_target(candidates, proj.global_position)
	else:
		homing_target = null
		is_homing_active = proj.stats.can_change_target

## Checks if the homing target is something we are even allowed to target.
func _is_valid_homing_target(obj: Node) -> bool:
	print(obj)
	if obj is Entity:
		if obj.team != proj.source_entity.team and obj.team != Globals.Teams.PASSIVE:
			return true
	return false

## Give the possible targets, this selects the closest one using a faster 'distance squared' method.
func _select_closest_homing_target(targets: Array[Node], to_position: Vector2) -> Node:
	var closest_target: Node = null
	var closest_distance_squared: float = INF
	for target: Node in targets:
		var distance_squared: float = to_position.distance_squared_to(target.global_position)
		if distance_squared < closest_distance_squared:
			closest_distance_squared = distance_squared
			closest_target = target
	return closest_target

## Gets all the options in the appropriate scene tree group. Used for the "closest" homing method.
func _find_closest_target() -> void:
	var candidates: Array[Node] = []
	var group_name: String = "enemy_entities" if proj.source_entity.team == Globals.Teams.PLAYER else "player_entities"
	var max_range_squared: float = proj.stats.homing_max_range * proj.stats.homing_max_range

	for entity: Node in proj.get_tree().get_nodes_in_group(group_name):
		if entity != proj.source_entity and _is_valid_homing_target(entity):
			var distance_squared: float = proj.global_position.distance_squared_to(entity.global_position)
			if distance_squared <= max_range_squared:
				candidates.append(entity)

	if candidates.size() > 0:
		homing_target = _select_closest_homing_target(candidates, proj.global_position)
	else:
		homing_target = null
		is_homing_active = false

## Isolates valid candidates from the mouse area scan and passes them on to have the closest one chosen.
func _choose_from_mouse_area_targets() -> void:
	var candidates: Array[Node] = []
	for obj: Node in mouse_scan_targets:
		if obj and _is_valid_homing_target(obj):
			candidates.append(obj)

	if candidates.size() > 0:
		homing_target = _select_closest_homing_target(candidates, CursorManager.get_cursor_mouse_position())
	else:
		homing_target = null
		is_homing_active = false

## When the amount of time we are allowed to spend homing is over, turn off homing entirely.
func on_homing_timer_timeout() -> void:
	is_homing_active = false
	homing_target = null

## Gradually move and turn towards the target. If the target doesn't exist, attempt to retarget if we can.
func apply_homing_movement(delta: float) -> void:
	if not homing_target or not homing_target.is_inside_tree():
		homing_target = null
		if proj.stats.can_change_target:
			find_homing_target_based_on_method()
		else:
			is_homing_active = false
		return

	var target_dir: Vector2 = (homing_target.global_position - proj.global_position).normalized()
	var current_dir: Vector2 = Vector2(cos(proj.rotation), sin(proj.rotation)).normalized()
	var angle_to_target: float = current_dir.angle_to(target_dir)
	var turn_stat: float = proj.sc.get_stat("proj_max_turn_rate")
	var max_turn_rate: float = deg_to_rad(turn_stat * proj.stats.turn_rate_curve.sample_baked((proj.stats.lifetime - proj.lifetime_timer.time_left) / proj.stats.lifetime)) * delta

	angle_to_target = clamp(angle_to_target, -max_turn_rate, max_turn_rate)
	proj.rotation += angle_to_target
	proj.sprite.rotation += deg_to_rad(proj.stats.spin_speed * proj.spin_dir) * delta

	var move_dir: Vector2 = Vector2(cos(proj.rotation), sin(proj.rotation)).normalized()
	var displacement: Vector2 = move_dir * (proj.current_sampled_speed * proj.stats.homing_speed_mult) * delta
	proj.position += displacement
	proj.movement_direction = displacement.normalized()

	if proj.stats.homing_method == "Boomerang":
		if proj.lifetime_timer.time_left <= max(0, proj.stats.lifetime - 0.35): # So that the return distance doesn't trigger on throw
			if proj.global_position.distance_squared_to(proj.source_entity.global_position) < pow(proj.stats.boomerang_home_radius, 2):
				proj.queue_free()
