class_name FiringHandler
## Handles the firing logic for projectile weapons.

var weapon: ProjectileWeapon ## A reference to the weapon.
var anim_player: AnimationPlayer ## A reference to the animation player on the weapon.
var auto_decrementer: AutoDecrementer ## A reference to the auto_decrementer in the source_entity's inventory.
var firing_duration_timer: Timer ## The timer tracking how long the firing duration is, which can in certain cases be different from the animation time.
var hitscan_hands_freeze_timer: Timer ## The timer that tracks the brief moment after a semi-auto hitscan shot that we shouldn't be rotating.
const HITSCAN_HANDS_FREEZE_DURATION: float = 0.065 ## The minimum hitscan duration that requires the hands to freeze while firing the hitscans.


## Called when this script is first created to provide a reference to the owning weapon.
func _init(parent_weapon: ProjectileWeapon) -> void:
	if Engine.is_editor_hint():
		return
	weapon = parent_weapon
	anim_player = weapon.anim_player
	auto_decrementer = weapon.source_entity.inv.auto_decrementer

	firing_duration_timer = TimerHelpers.create_one_shot_timer(weapon, -1)
	hitscan_hands_freeze_timer = TimerHelpers.create_one_shot_timer(weapon, -1, _on_hitscan_hands_freeze_timer_timeout)

## The main entry point for starting the firing process. Returns control back to the caller once all animations and
## delays have ended.
func start_firing() -> void:
	if weapon.stats.one_frame_per_fire:
		# If using one frame per fire, we know it is an animated sprite
		var sprite: AnimatedSprite2D = weapon.sprite
		sprite.frame = (sprite.frame + 1) % sprite.sprite_frames.get_frame_count(sprite.animation)

	await _start_firing_animation_and_timer()
	_apply_firing_effect_to_entity()

	await _handle_bursting()
	if anim_player.is_playing() and anim_player.current_animation == "fire":
		await anim_player.animation_finished
	if not firing_duration_timer.is_stopped():
		await firing_duration_timer.timeout

	weapon.add_cooldown(weapon.ii.sc.get_stat("fire_cooldown"))

	await _start_post_firing_animation_and_fx()

## Handles the bursting logic that the weapon may have. Also just the starting point for the spawning sequence.
func _handle_bursting() -> void:
	var bursts: int = int(weapon.ii.sc.get_stat("projectiles_per_fire"))

	# If we only need to add it once, do it now, otherwise do it for every shot in the below loop
	if not weapon.stats.add_overheat_per_burst_shot:
		weapon.overheat_handler.add_overheat()
	if not weapon.stats.add_bloom_per_burst_shot:
		_add_bloom()
	if not weapon.stats.use_ammo_per_burst_proj:
		_consume_ammo()
	weapon.warmup_handler.add_warmup()
	weapon.reload_handler.restart_ammo_recharge_delay()

	for burst_index: int in range(bursts):
		if weapon.stats.add_overheat_per_burst_shot:
			weapon.overheat_handler.add_overheat()
		if weapon.stats.add_bloom_per_burst_shot:
			_add_bloom()
		if weapon.stats.use_ammo_per_burst_proj:
			_consume_ammo()

		_start_firing_fx()

		await _handle_barraging()

		if burst_index < bursts - 1:
			var burst_delay: float = weapon.stats.burst_proj_delay
			await weapon.get_tree().create_timer(burst_delay, false).timeout

## Handles the barraging logic that the weapon may have. This is called for each burst iteration.
func _handle_barraging() -> void:
	var barrage_count: int = weapon.ii.sc.get_stat("barrage_count")
	var angular_spread_rads: float = 0
	if barrage_count > 1:
		angular_spread_rads = deg_to_rad(weapon.ii.sc.get_stat("angular_spread"))

	# If the spread is close to a full circle, decrease the width between the spreads so they don't overlap near 360º
	var close_to_360_adjustment: int = 0 if angular_spread_rads > 5.41 else 1
	var spread_segment_width: float = 0
	if barrage_count > 1:
		spread_segment_width = angular_spread_rads / (barrage_count - close_to_360_adjustment)

	# Make sure each projectile/hitscan in this barrage shares the same multishot ID
	var multishot_id: int = UIDHelper.generate_multishot_uid()

	for i: int in range(barrage_count):
		# Start at the top angle of the barrage by subtracting half the total width from the current rotation
		var start_rot: float = weapon.global_rotation - (angular_spread_rads * 0.5)
		var proj_rot: float = start_rot + (i * spread_segment_width)
		if weapon.stats.do_cluster_barrage:
			proj_rot = start_rot + randf_range(0, angular_spread_rads)

		if not weapon.stats.is_hitscan:
			_spawn_projectile(proj_rot, multishot_id)
		else:
			var start_of_hitscan_rotation_offsets: float = -angular_spread_rads * 0.5
			_spawn_hitscan(i, spread_segment_width, start_of_hitscan_rotation_offsets, multishot_id)

		if (weapon.stats.barrage_proj_delay > 0) and (i < barrage_count - 1):
			await weapon.get_tree().create_timer(weapon.stats.barrage_proj_delay, false).timeout

## Spawns a projectile with the given multishot id and applied rotation.
func _spawn_projectile(proj_rot: float, multishot_id: int) -> void:
	var total_proj_rot: float = proj_rot + _get_bloom_to_add_radians()
	var proj: Projectile = Projectile.create(weapon.ii, weapon.source_entity, weapon.proj_origin_node.global_position, total_proj_rot)
	proj.multishot_id = multishot_id

	if weapon is UniqueProjWeapon:
		weapon.returned = false
		proj.source_weapon_item = weapon

	if weapon.stats.projectile_logic.homing_method == "Mouse Position":
		weapon.mouse_scan_area_targets.clear()
		weapon.enable_mouse_area()

		# Let the physics server catch up with the mouse area being enabled
		var tree: SceneTree = weapon.get_tree()
		for i: int in range(3):
			await tree.physics_frame

		# Duplicate to ensure later changes don't alter the same array now attached to the projectile
		proj.mouse_scan_targets = weapon.mouse_scan_area_targets.duplicate()
		weapon.disable_mouse_area()

	Globals.world_root.add_child(proj)

## Spawns a hitscan with the given index amongst other hitscans, the width between them, and the start of
## the rotations.
func _spawn_hitscan(barrage_index: int, spread_segment_width: float, start_of_offsets: float,
					multishot_id: int) -> void:
	if weapon.is_holding_continuous_beam:
		return

	var rotation_offset: float = start_of_offsets + (barrage_index * spread_segment_width)
	if weapon.stats.do_cluster_barrage:
		rotation_offset = randf() * spread_segment_width
	rotation_offset += _get_bloom_to_add_radians()

	var hitscan: Hitscan = Hitscan.create(weapon, rotation_offset)
	hitscan.multishot_id = multishot_id
	Globals.world_root.add_child(hitscan)
	weapon.current_hitscans.append(hitscan)

	# Freezing the hand rotation during very brief hitscans
	if weapon.stats.firing_duration <= HITSCAN_HANDS_FREEZE_DURATION:
		weapon.source_entity.hands.should_rotate = false
		hitscan_hands_freeze_timer.start(HITSCAN_HANDS_FREEZE_DURATION)

## When the timer that tracks freezing the hands during a short hitscan firing ends, let the hands rotate again.
func _on_hitscan_hands_freeze_timer_timeout() -> void:
	weapon.source_entity.hands.should_rotate = true

## Grabs a point from the bloom curve based on current bloom level given by the auto decrementer.
func _get_bloom_to_add_radians() -> float:
	var current_bloom: float = auto_decrementer.get_bloom(str(weapon.ii.uid))
	if current_bloom > 0:
		var deviation: float = weapon.stats.bloom_curve.sample_baked(current_bloom)
		var random_direction: int = 1 if randf() < 0.5 else -1
		var max_current_bloom: float = deviation * weapon.ii.sc.get_stat("max_bloom")
		var random_amount_of_max_current_bloom: float = max_current_bloom * random_direction * randf()
		return deg_to_rad(random_amount_of_max_current_bloom)
	else:
		return 0

## Increases current bloom level via sampling the increase curve using the current bloom.
func _add_bloom() -> void:
	if weapon.ii.sc.get_stat("max_bloom") <= 0:
		return

	var current_bloom: float = auto_decrementer.get_bloom(str(weapon.ii.uid))
	var sampled_point: float = weapon.stats.bloom_increase_rate.sample_baked(current_bloom)
	var increase_rate_multiplier: float = weapon.ii.sc.get_stat("bloom_increase_rate_multiplier")
	var increase_amount: float = max(0.01, sampled_point * increase_rate_multiplier)
	auto_decrementer.add_bloom(
		str(weapon.ii.uid),
		min(1, (increase_amount)),
		weapon.stats.bloom_decrease_rate,
		weapon.stats.bloom_decrease_delay
		)

## Calls to consume a single ammo iteration.
func _consume_ammo() -> void:
	if weapon.stats.dont_consume_ammo:
		return

	match weapon.stats.ammo_type:
		ProjWeaponStats.ProjAmmoType.STAMINA:
			weapon.source_entity.stamina_component.use_stamina(weapon.stats.stamina_use_per_proj)
		ProjWeaponStats.ProjAmmoType.SELF:
			weapon.source_entity.inv.remove_item(weapon.inv_index, 1)
			weapon.update_ammo_ui()
		_:
			weapon.update_mag_ammo(weapon.ii.ammo_in_mag - 1)
			weapon.reload_handler.request_ammo_recharge()

## Starts the main firing animation if one exists, potentially waiting for it to end before returning control back
## to the main firing sequence.
func _start_firing_animation_and_timer() -> void:
	var firing_duration: float = weapon.stats.firing_duration
	if firing_duration > 0:
		firing_duration_timer.start(firing_duration)

	if anim_player.has_animation("fire"):
		var anim_time: float = firing_duration
		if weapon.stats.fire_anim_dur > 0:
			anim_time = min(weapon.stats.firing_duration, weapon.stats.fire_anim_dur)
		if anim_time > 0:
			anim_player.speed_scale = 1.0 / anim_time
			anim_player.play("fire")

			if weapon.stats.spawn_after_fire_anim:
				await anim_player.animation_finished
				await weapon.get_tree().process_frame

				if weapon.stats.is_hitscan and ((firing_duration - anim_time) <= 0.03):
					push_warning("Hitscans will appear to not fire at all if they must wait until after the firing animation and that \nanimation is the nearly the time as the entire firing duration. Make sure to set the fire_anim_dur to something nonzero and noticeably smaller (-0.04 or more) than the firing_duration in this case.")

## Start the sounds and vfx that should play when firing.
func _start_firing_fx() -> void:
	if weapon.stats.firing_cam_fx:
		weapon.stats.firing_cam_fx.apply_falloffs_and_activate_all(weapon.source_entity)
	if weapon.firing_vfx:
		weapon.firing_vfx.start()

	AudioManager.play_2d(weapon.stats.firing_sound, weapon.global_position, 0)
	var mag_size: int = int(weapon.ii.sc.get_stat("mag_size"))
	var ammo_left: int = weapon.ii.ammo_in_mag
	if weapon.source_entity is Player:
		if (mag_size > 8) and (ammo_left <= 10) and (float(ammo_left) / float(mag_size) <= 0.25):
			AudioManager.play_2d(weapon.stats.mag_almost_empty_sound, weapon.global_position, 0)

## Starts the post-firing animation and sounds if they exist, waiting for the delay (at the very least) and also the
## animation itself to end before returning control back to the main firing sequence.
func _start_post_firing_animation_and_fx() -> void:
	if not anim_player.has_animation("post_fire"):
		if not weapon.ensure_enough_ammo():
			# If we don't have a post-fire anim, wait this small amount so the start of the reload isn't so jarring
			await weapon.get_tree().create_timer(0.07, false).timeout
		return

	var firing_cooldown: float = weapon.ii.sc.get_stat("fire_cooldown")
	var post_fire_anim_delay: float = weapon.stats.post_fire_anim_delay
	var available_time: float = firing_cooldown - post_fire_anim_delay
	if available_time <= 0:
		return

	await weapon.get_tree().create_timer(post_fire_anim_delay, false).timeout

	var anim_time: float = available_time
	if weapon.stats.post_fire_anim_dur > 0:
		anim_time = min(available_time, weapon.stats.post_fire_anim_dur)
	if anim_time > 0:
		anim_player.speed_scale = 1.0 / anim_time
		weapon.source_entity.hands.off_hand_sprite.self_modulate.a = 0.0
		anim_player.animation_finished.connect(_show_off_hand_after_post_fire_animation, CONNECT_ONE_SHOT)
		anim_player.play("post_fire")
		AudioManager.play_2d(weapon.stats.post_fire_sound, weapon.source_entity.global_position)

		await anim_player.animation_finished

## Shows the entity's off hand again after the post-firing animation.
func _show_off_hand_after_post_fire_animation(anim_name: StringName) -> void:
	if anim_name == "post_fire":
		weapon.source_entity.hands.off_hand_sprite.self_modulate.a = 1.0

## Applies a status effect to the source entity when firing starts.
func _apply_firing_effect_to_entity() -> void:
	if weapon.stats.firing_stat_effect != null:
		weapon.source_entity.effect_receiver.handle_status_effect(weapon.stats.firing_stat_effect)
