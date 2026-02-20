class_name ArcingHandler
## Handles the logic needing for providing arc-based movement to the projectile.

var proj: Projectile ## A reference to the projectile this handler works on.
var is_arcing: bool = false ## Whether we are currently moving in an arcing motion.
var fake_z_axis: float = 0 ## The fake z axis var for simulating height off the ground while arcing.
var updated_arc_angle: float = 0 ## The updated arcing angle for falloff since the last bounce.
var fake_previous_pos: float ## The fake previous position that ignores the change caused by simulating the fake z axis.
var arc_time_counter: float = 0 ## How long we have been arcing so far.
var starting_arc_speed: float = 0 ## The initial speed of an arc, used in kinematic equations.


## Called when this script is first created to provide a reference to the owning projectile.
func _init(parent_proj: Projectile) -> void:
	if Engine.is_editor_hint():
		return
	proj = parent_proj

## Sets up starting arcing variables like initial speed based on kinematics.
func reset_arc_logic() -> void:
	var falloff_mult: float = max(0.01, proj.stats.bounce_falloff_curve.sample_baked(1 - (proj.lifetime_timer.time_left / proj.stats.lifetime)))
	var dist_stat: float = proj.sc.get_stat("proj_arc_travel_distance")
	var dist: float = dist_stat * falloff_mult
	updated_arc_angle = proj.stats.launch_angle * falloff_mult

	starting_arc_speed = find_initial_arc_speed(dist, updated_arc_angle, proj.starting_proj_height if proj.bounces_so_far == 0 else 0)
	proj.resettable_starting_pos = proj.global_position
	arc_time_counter = 0

## Calculates the distance we will travel in our arcing motion based on speed, angle, and height.
func calculate_arc_distance(speed: float, angle: float, height: int) -> float:
	const G: float = 9.8
	var rad_angle: float = deg_to_rad(angle)
	var sin_angle: float = sin(rad_angle)
	var cos_angle: float = cos(rad_angle)

	var v_sin: float = speed * sin_angle
	var v_cos: float = speed * cos_angle
	var discriminant: float = v_sin * v_sin + 2 * G * height
	if discriminant < 0:
		return 0

	var time: float = (v_sin + sqrt(discriminant)) / G
	return v_cos * time

## Calculates the initial speed of the arcing motion based on the target distance and angle and starting height.
func find_initial_arc_speed(target_distance: float, angle: float, height: int) -> float:
	var low: float = 0
	var high: float = 100.0
	var epsilon: float = 1.0  # Precision

	while high - low > epsilon:
		var mid: float = (low + high) / 2
		var distance: float = calculate_arc_distance(mid, angle, height)

		if distance < target_distance:
			low = mid
		else:
			high = mid

	return (low + high) / 2


## This is called every phys frame to update the arcing position based on kinemtaic equations.
func do_arc_movement(delta: float) -> void:
	arc_time_counter += delta * (proj.stats.arc_speed / 90.0) * proj.current_initial_boost

	fake_z_axis = (
		starting_arc_speed * sin(deg_to_rad(updated_arc_angle)) * arc_time_counter - 0.5 * 9.8 * pow(arc_time_counter, 2)
		)

	var ground_level: float = -(proj.starting_proj_height) if proj.bounces_so_far == 0 else 0
	var bounce_stat: int = int(proj.sc.get_stat("proj_bounce_count"))

	if fake_z_axis > ground_level:
		proj.z_index = 3
		var fake_x_axis: float = starting_arc_speed * cos(deg_to_rad(proj.stats.launch_angle)) * arc_time_counter
		var new_position: Vector2 = proj.resettable_starting_pos + (proj.resettable_starting_dir * fake_x_axis)
		new_position.y -= fake_z_axis
		var fake_move_dir: Vector2 = (new_position - proj.global_position).normalized()

		proj.rotation = atan2(fake_move_dir.y, fake_move_dir.x)
		proj.rotation += proj.non_sped_up_time_counter * deg_to_rad(proj.stats.spin_speed * proj.spin_dir)

		proj.global_position = new_position

		var dist_so_far: float = (starting_arc_speed * cos(deg_to_rad(proj.stats.launch_angle)) * proj.non_sped_up_time_counter * (proj.stats.arc_speed / 90.0) * proj.current_initial_boost)
		proj.cumulative_distance += dist_so_far - fake_previous_pos ##TODO: Move this
		fake_previous_pos = dist_so_far

		proj._update_shadow(new_position, fake_move_dir)
		proj.show()
	elif bounce_stat > 0 and (proj.bounces_so_far < bounce_stat):
		proj.z_index = 0
		proj.bounces_so_far += 1
		if proj.stats.ping_pong_bounce:
			proj.resettable_starting_dir *= -1
			proj.spin_dir *= -1
		proj.non_sped_up_time_counter = 0
		reset_arc_logic()
	else:
		proj._disable_in_air_only_particles()
		proj.z_index = 0
		is_arcing = false
		if proj.stats.do_aoe_on_arc_land and (proj.stats.aoe_radius > 0):
			if not proj.is_in_aoe_phase:
				proj.lifetime_timer.stop()
				proj._handle_aoe()
		else:
			if proj.stats.grounding_free_delay > 0:
				await proj.get_tree().create_timer(proj.stats.grounding_free_delay, false, true, false).timeout
			proj._kill_projectile_on_hit()

	if fake_z_axis > proj.stats.max_collision_height:
		proj.call_deferred("_disable_collider")
	else:
		proj.call_deferred("_enable_collider")
