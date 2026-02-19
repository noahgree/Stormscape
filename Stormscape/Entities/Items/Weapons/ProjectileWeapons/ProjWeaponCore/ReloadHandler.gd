class_name ReloadHandler
## Handles the reloading logic for projectile weapons.

signal reload_ended ## Used internally to hold up the main function until all reload animations are complete.

var weapon: ProjectileWeapon ## A reference to the weapon.
var anim_player: AnimationPlayer ## A reference to the animation player on the weapon.
var auto_decrementer: AutoDecrementer ## A reference to the auto_decrementer in the source_entity's inventory.
var reload_dur_timer: Timer ## The timer that tracks the progress of the reload as it goes along in order to keep the UI updating smoothly.
var reload_delay_timer: Timer ## The timer that delays the reload if a "before_single_reload" animation doesn't exist or we are reloading the full magazine.
var mag_reload_anim_delay_timer: Timer ## The timer that delays the start of the magazine reload animation.


## Called when this script is first created to provide a reference to the owning weapon.
func _init(parent_weapon: ProjectileWeapon) -> void:
	if Engine.is_editor_hint():
		return
	weapon = parent_weapon
	anim_player = weapon.anim_player
	auto_decrementer = weapon.source_entity.inv.auto_decrementer

	if weapon.source_entity is Player:
		weapon.source_entity.inv.auto_decrementer.recharge_completed.connect(_on_ammo_recharge_delay_completed)
	reload_dur_timer = TimerHelpers.create_one_shot_timer(weapon, -1)
	reload_delay_timer = TimerHelpers.create_one_shot_timer(weapon, -1, _on_reload_delay_timer_timeout)
	mag_reload_anim_delay_timer = TimerHelpers.create_one_shot_timer(weapon, -1, _on_mag_reload_anim_delay_timer_timeout)

## The main starting point for reloads, checks for the necessary conditions and then potentially proceeds.
## This function waits for the "reload_ended" signal before returning (unless the initial checks fail).
func attempt_reload() -> void:
	if weapon.stats.ammo_type in [ProjWeaponStats.ProjAmmoType.STAMINA, ProjWeaponStats.ProjAmmoType.SELF, ProjWeaponStats.ProjAmmoType.CHARGES]:
		return
	if _get_more_reload_ammo(1, false) == 0:
		return

	weapon.source_entity.hands.off_hand_sprite.self_modulate.a = 0.0

	_start_reload_dur_timer()
	_start_reload_delay()
	await reload_ended

## Checks to see if the mag is already full. Returns true if it is.
func mag_is_full() -> bool:
	return weapon.stats.ammo_in_mag >= weapon.stats.s_mods.get_stat("mag_size")

## Starts the timer that tracks the entire duration of the reload in order to provide the UI with
## continuous progress.
func _start_reload_dur_timer() -> void:
	# Only do these calculations and start the timer if we need it for updating the UI.
	if not weapon.source_entity is Player:
		return

	var total_reload_duration: float = weapon.stats.reload_delay
	match weapon.stats.reload_type:
		ProjWeaponStats.ReloadType.MAGAZINE:
			total_reload_duration += weapon.stats.s_mods.get_stat("mag_reload_time")
		ProjWeaponStats.ReloadType.SINGLE:
			var needed: int = _get_needed_single_reloads_count()
			var single_proj_reload_time: float = weapon.stats.s_mods.get_stat("single_proj_reload_time")
			total_reload_duration += (needed * single_proj_reload_time)

	reload_dur_timer.start(total_reload_duration)

## Ends the reload by emitting the internal signal so that the initial await condition expires.
func end_reload() -> void:
	do_post_reload_animation_cleanup()
	reload_ended.emit()

## This is the entry point for the sequence where we choose to either do a delay (and corresponding animation if in
## single mode), or start the reload immediately.
func _start_reload_delay() -> void:
	var delay_time: float = weapon.stats.reload_delay
	match weapon.stats.reload_type:
		ProjWeaponStats.ReloadType.MAGAZINE:
			if delay_time <= 0:
				_start_magazine_reload()
			else:
				reload_delay_timer.start(delay_time)
		ProjWeaponStats.ReloadType.SINGLE:
			if delay_time <= 0:
				_start_single_reload()
			elif anim_player.has_animation("before_single_reload"):
				_start_reload_animation("before_single_reload", delay_time)
			else:
				reload_delay_timer.start(delay_time)

## When the reload delay timer ends, start the appropriate reload method.
func _on_reload_delay_timer_timeout() -> void:
	match weapon.stats.reload_type:
		ProjWeaponStats.ReloadType.MAGAZINE:
			_start_magazine_reload()
		ProjWeaponStats.ReloadType.SINGLE:
			_start_single_reload()

## This is the entry point for starting a magazine reload sequence.
func _start_magazine_reload() -> void:
	var reload_time: float = weapon.stats.s_mods.get_stat("mag_reload_time")
	var mag_reload_anim_delay: float = min(reload_time, weapon.stats.mag_reload_anim_delay)
	if (mag_reload_anim_delay != 0) and (reload_time - mag_reload_anim_delay) > 0.05:
		mag_reload_anim_delay_timer.set_meta("anim_time", reload_time - mag_reload_anim_delay)
		mag_reload_anim_delay_timer.start(mag_reload_anim_delay)
	else:
		_start_reload_animation("mag_reload", reload_time)

## When the magazine reload animation delay timer ends, we can now start the animation with the remaining time left.
func _on_mag_reload_anim_delay_timer_timeout() -> void:
	var anim_time: float = mag_reload_anim_delay_timer.get_meta("anim_time")
	_start_reload_animation("mag_reload", anim_time)

## Starts a single reload.
func _start_single_reload() -> void:
	var reloads_needed: int = _get_needed_single_reloads_count()
	var reload_time: float = weapon.stats.s_mods.get_stat("single_proj_reload_time")
	if reloads_needed > 1:
		_start_reload_animation("single_reload", reload_time)
	elif reloads_needed == 1:
		var anim_name: String = "final_single_reload"
		if not anim_player.has_animation(anim_name):
			anim_name = "single_reload"
		_start_reload_animation(anim_name, reload_time)
	else:
		end_reload()

## Starts the requested reload animation that should last the desired duration.
func _start_reload_animation(anim_name: String, duration: float) -> void:
	# Sometimes overheat animation can mess with the scaling
	if anim_player.current_animation == "overheat":
		weapon.reset_animation_state()

	anim_player.speed_scale = 1.0 / duration

	if anim_player.animation_finished.is_connected(_on_reload_animation_finished):
		anim_player.animation_finished.disconnect(_on_reload_animation_finished)
	anim_player.animation_finished.connect(_on_reload_animation_finished, CONNECT_ONE_SHOT)
	anim_player.play(anim_name)

## When any reload animation ends, call the needed function that continues or finishes the sequence.
func _on_reload_animation_finished(anim_name: StringName) -> void:
	match anim_name:
		"mag_reload":
			_complete_mag_reload()
		"before_single_reload":
			_start_single_reload()
		"single_reload":
			_complete_single_reload()
		"final_single_reload":
			_complete_single_reload()

## This is the exit point for the magazine reload sequence.
func _complete_mag_reload() -> void:
	var mag_size: int = int(weapon.stats.s_mods.get_stat("mag_size"))
	var ammo_needed: int = mag_size - weapon.stats.ammo_in_mag
	var ammo_available: int = _get_more_reload_ammo(ammo_needed)
	weapon.update_mag_ammo(weapon.stats.ammo_in_mag + ammo_available)
	end_reload()

## This is the ending of a single reload iteration, and can either end the sequence or start another iteration.
func _complete_single_reload() -> void:
	var mag_size: int = int(weapon.stats.s_mods.get_stat("mag_size"))
	var ammo_needed: int = mag_size - weapon.stats.ammo_in_mag
	var reload_quantity: int = int(weapon.stats.s_mods.get_stat("single_reload_quantity"))
	var ammo_available: int = _get_more_reload_ammo(min(ammo_needed, reload_quantity))
	weapon.update_mag_ammo(weapon.stats.ammo_in_mag + ammo_available)

	if ammo_available <= 0:
		end_reload()
		return

	_start_single_reload()

## Returns the number of remaining needed single reloads.
func _get_needed_single_reloads_count() -> int:
	var mag_size: int = int(weapon.stats.s_mods.get_stat("mag_size"))
	var ammo_needed: int = mag_size - weapon.stats.ammo_in_mag
	var reload_quantity: int = int(weapon.stats.s_mods.get_stat("single_reload_quantity"))
	var reloads_needed: int = ceili(float(ammo_needed) / float(reload_quantity))
	return reloads_needed

## Reshows the hand component's off hand and hides the local reload hand. Also resets the animation state.
func do_post_reload_animation_cleanup() -> void:
	reload_dur_timer.stop()
	reload_delay_timer.stop()
	weapon.source_entity.hands.off_hand_sprite.self_modulate.a = 1.0

	if weapon.reload_off_hand:
		weapon.reload_off_hand.hide()
	if weapon.reload_main_hand:
		weapon.reload_main_hand.hide()

	weapon.reset_animation_state()

## When an ammo recharge delay is finished, this is called to resync the ammo in mag with the ammo ui.
func _on_ammo_recharge_delay_completed(item_id: StringName) -> void:
	if item_id != str(weapon.stats.session_uid):
		return
	weapon.update_mag_ammo(weapon.stats.ammo_in_mag)

## Searches through the source entity's inventory for more ammo to fill the magazine.
## Can optionally be used to only check for ammo when told not to take from the inventory when found.
func _get_more_reload_ammo(max_amount_needed: int, take_from_inventory: bool = true) -> int:
	if weapon.stats.ammo_type == ProjWeaponStats.ProjAmmoType.NONE:
		return max_amount_needed
	else:
		var amount_found: int = weapon.source_entity.inv.get_more_ammo(max_amount_needed, take_from_inventory, weapon.stats.ammo_type)
		if amount_found == 0:
			MessageManager.add_msg_preset("Ammo Depleted", MessageManager.Presets.FAIL, 2.0)
		return amount_found

## When we have recently fired, we should not instantly keep recharging ammo, so we send a cooldown
## to the recharger.
func restart_ammo_recharge_delay() -> void:
	auto_decrementer.update_recharge_delay(str(weapon.stats.session_uid), weapon.stats.auto_ammo_delay)

## This is called (usually after firing) to request a new ammo recharge instance.
func request_ammo_recharge() -> void:
	if weapon.stats.ammo_type in [ProjWeaponStats.ProjAmmoType.SELF, ProjWeaponStats.ProjAmmoType.STAMINA]:
		return
	if weapon.stats.ammo_in_mag >= weapon.stats.s_mods.get_stat("mag_size"):
		return

	var recharge_dur: float = weapon.stats.s_mods.get_stat("auto_ammo_interval")
	if recharge_dur <= 0:
		return
	auto_decrementer.request_recharge(str(weapon.stats.session_uid), weapon.stats)

## Updates the overhead UI and the mouse cursor with the progress of the reload.
func update_overhead_and_cursor_ui() -> void:
	if not weapon.overhead_ui or weapon.stats.hide_reload_ui:
		return

	var total_reload: float = reload_dur_timer.wait_time
	var time_left: float = reload_dur_timer.time_left
	var progress: int = int((1.0 - (time_left / total_reload)) * 100)

	weapon.overhead_ui.update_reload_progress(progress)

	# Only show reload cursor tint if we aren't showing another cooldown
	if not auto_decrementer.get_cooldown_source_title(weapon.ii.get_cooldown_id()) in weapon.stats.shown_cooldown_fills or not weapon.stats.shown_cooldown_fills:
		CursorManager.update_vertical_tint_progress(progress)
