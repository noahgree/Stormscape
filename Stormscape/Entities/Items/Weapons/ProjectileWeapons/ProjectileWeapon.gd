@tool
@icon("res://Utilities/Debug/EditorIcons/projectile_weapon.png")
extends Weapon
class_name ProjectileWeapon
## Controls the operations of projectile weapons, including firing & reloading.
##
## The only script that ever checks the weapon state is this one. Not even the member scripts check it.

enum WeaponState { IDLE, FIRING, RELOADING } ## The potential weapon states.

@export var proj_origin: Vector2 = Vector2.ZERO: set = _set_proj_origin ## Where the projectile spawns from in local space of the weapon scene.
@export var casing_scene: PackedScene = preload("res://Entities/Items/Weapons/WeaponVFX/Casings/Casing.tscn")
@export var overheat_overlays: Array[TextureRect] = [] ## Any texture rect in the weapon scene that changes alpha based on the overheat progress.

@onready var proj_origin_node: Marker2D = $ProjectileOrigin ## The point at which projectiles should spawn from.
@onready var casing_ejection_point: Marker2D = get_node_or_null("CasingEjectionPoint") ## The point from which casings should eject if need be.
@onready var reload_off_hand: EntityHandSprite = get_node_or_null("ReloadOffHand") ## The off hand only shown and animated during reloads.
@onready var reload_main_hand: EntityHandSprite = get_node_or_null("ReloadMainHand") ## The main hand only shown and animated during reloads.
@onready var firing_vfx: WeaponFiringVFX = get_node_or_null("FiringVFX") ## The vfx that spawns when firing.
@onready var firing_handler: FiringHandler = FiringHandler.new(self) ## The firing handler helper script.
@onready var warmup_handler: WarmupHandler = WarmupHandler.new(self) ## The warmup handler helper script.
@onready var reload_handler: ReloadHandler = ReloadHandler.new(self) ## The reload handler helper script.
@onready var overheat_handler: OverheatHandler = OverheatHandler.new(self) ## The overheat handler helper script.

var state: WeaponState = WeaponState.IDLE ## The current weapon state.
var is_charging: bool = false ## When true, we are holding the trigger down and trying to charge up.
var mouse_scan_area_targets: Array[Node] = [] ## The array of potential targets found and passed to the proj when using the "Mouse Position" homing method.
var mouse_area: Area2D ## The area around the mouse that scans for targets when using the "Mouse Position" homing method
var requesting_reload_after_firing: bool = false ## This is flagged to true when a reload is requested during the firing animation and needs to wait until it is done.
var current_hitscans: Array[Hitscan] = [] ## The currently spawned array of hitscans to get cleaned up when we unequip this weapon.
var is_holding_continuous_beam: bool = false ## When true, we are holding down a continuous hitscan and should not recreate any new hitscan instances.
var has_released: bool = false ## Used to flag when a hitscan hold has ended but we are still in the firing phase, so we check this after the firing phase to see if we should clean up the hitscans.
var recent_holding_cooldown_check: bool = true ## Flags to false when we query the _can_activate_at_all function and the default cooldown is in progress. Prevents having to query the cooldowns dictionary from the auto decrementer twice every frame.


#region Debug
## Updates the proj origin visual node position based on the new value of the exported var "proj_origin".
func _set_proj_origin(new_proj_origin: Vector2) -> void:
	proj_origin = new_proj_origin
	if proj_origin_node: proj_origin_node.position = proj_origin
#endregion

## Called when the weapon is first added to the scene tree, notably before the enter function.
func _ready() -> void:
	if Engine.is_editor_hint():
		return
	super._ready()

	if source_entity is Player:
		# Update the ammo UI when stamina changes
		if (stats.ammo_type == ProjWeaponStats.ProjAmmoType.STAMINA) and (not stats.hide_ammo_ui):
				source_entity.stamina_component.stamina_changed.connect(
					func(_new_stamina: float, _old_stamina: float) -> void: update_ammo_ui()
					)

	_setup_firing_vfx()
	_register_preloaded_sounds()

## Any rapidly or highly used sounds in this weapon should stay in memory for the entire lifetime of this weapon
## if they aren't already.
func _register_preloaded_sounds() -> void:
	preloaded_sounds = [stats.firing_sound, stats.charging_sound, stats.reload_sound]
	AudioPreloader.register_sounds_from_ids(preloaded_sounds)

## Called when the weapon is enabled, usually because it stopped clipping with an object.
func enable() -> void:
	# When re-enabling, see if we stil are in overheat penalty and need to show the visuals again
	if source_entity.inv.auto_decrementer.get_cooldown_source_title(stats.get_cooldown_id()) == "overheat_penalty":
		overheat_handler.start_max_overheat_visuals(true)

## Called when the weapon is disabled, usually because it started clipping with an object.
func disable() -> void:
	source_entity.hands.should_rotate = true
	if stats.charging_stat_effect != null:
		source_entity.effects.request_effect_removal_by_source(stats.charging_stat_effect.id, Globals.StatusEffectSourceType.FROM_SELF)
	is_charging = false
	_delay_clean_up_hitscans()

## Called when the weapon first enters, but after the _ready function.
func enter() -> void:
	if stats.s_mods.get_stat("pullout_delay") > 0:
		pullout_delay_timer.start(stats.s_mods.get_stat("pullout_delay"))
		pullout_delay_timer.timeout.connect(_on_pullout_delay_timer_timeout)

	reload_handler.request_ammo_recharge()
	if source_entity is Player:
		_setup_mouse_area_scanner()
		update_ammo_ui()

	# When entering, see if we stil are in overheat penalty and need to show the visuals again
	if source_entity.inv.auto_decrementer.get_cooldown_source_title(stats.get_cooldown_id()) == "overheat_penalty":
		overheat_handler.start_max_overheat_visuals(true)

## Called when the weapon is about to queue_free, but before the _exit_tree function.
func exit() -> void:
	set_process(false)
	super.exit()

	source_entity.hands.should_rotate = true
	reload_handler.do_post_reload_animation_cleanup()

	if mouse_area:
		mouse_area.queue_free()

	if stats.charging_stat_effect != null:
		source_entity.effects.request_effect_removal_by_source(stats.charging_stat_effect.id, Globals.StatusEffectSourceType.FROM_SELF)

	source_entity.hands.smoke_particles.emitting = false
	source_entity.hands.smoke_particles.visible = false

	_clean_up_hitscans()

## When the pullout timer ends, see if we need to automatically reload.
func _on_pullout_delay_timer_timeout() -> void:
	if not ensure_enough_ammo():
		reload()

## Enables the homing mouse area.
func enable_mouse_area() -> void:
	if mouse_area:
		mouse_area.get_child(0).disabled = false

## Disables the homing mouse area.
func disable_mouse_area() -> void:
	if mouse_area:
		mouse_area.get_child(0).disabled = true

## Chooses to either delay cleaning up the hitscans by flagging for the need to (since we are still firing), or
## immediately clean them up.
func _delay_clean_up_hitscans() -> void:
	if state == WeaponState.FIRING:
		has_released = true
	else:
		_clean_up_hitscans()

## When hitscans have ended or we swap off the weapon, free the hitscan itself.
func _clean_up_hitscans() -> void:
	is_holding_continuous_beam = false
	has_released = false
	for hitscan: Variant in current_hitscans:
		if is_instance_valid(hitscan):
			hitscan.queue_free()
	current_hitscans.clear()

## Updates continuous hitscans with new multishot IDs each time the firing sequence is triggered.
func _update_hitscans_with_new_multishot_id() -> void:
	for hitscan: Variant in current_hitscans:
		if is_instance_valid(hitscan):
			hitscan.multishot_id = UIDHelper.generate_multishot_uid()

## If we are set to do mouse position-based homing, we set up the mouse area and its signals and add it as a child.
func _setup_mouse_area_scanner() -> void:
	if stats.is_hitscan:
		return
	if stats.projectile_logic.homing_method != "Mouse Position":
		return

	mouse_area = Area2D.new()
	mouse_area.name = "HomingMouseArea2D"
	var collision_shape: CollisionShape2D = CollisionShape2D.new()
	var circle_shape: CircleShape2D = CircleShape2D.new()

	mouse_area.collision_layer = 0
	mouse_area.collision_mask = stats.effect_source.scanned_phys_layers
	mouse_area.area_entered.connect(func(area: Area2D) -> void: mouse_scan_area_targets.append(area))
	mouse_area.body_entered.connect(func(body: Node2D) -> void: mouse_scan_area_targets.append(body))

	circle_shape.radius = stats.projectile_logic.mouse_target_radius
	collision_shape.shape = circle_shape
	collision_shape.disabled = true
	mouse_area.add_child(collision_shape)
	mouse_area.global_position = CursorManager.get_cursor_mouse_position()

	Globals.world_root.add_child(mouse_area)

## Sets up the firing vfx's positioning and offset to work with y sorting.
func _setup_firing_vfx() -> void:
	if firing_vfx == null:
		return

	# Getting it to show above the projectiles in y-sort order
	firing_vfx.position = proj_origin + Vector2(0, 3)
	firing_vfx.offset = Vector2(0, -3)

	# By default it will be centered at the proj origin, but we want it to have its left side at that point
	firing_vfx.position.x += SpriteHelpers.SpriteDetails.get_frame_rect(firing_vfx, true).x / 2.0

## Updates the UIs that depend on frame-by-frame updates.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if state == WeaponState.RELOADING:
		reload_handler.update_overhead_and_cursor_ui()
	elif overhead_ui:
		overhead_ui.reload_bar.hide()
	overheat_handler.update_overlays_and_overhead_ui()
	_update_cursor_cooldown_ui()
	_update_overhead_charge_ui()

## Updates the homing mouse area every physics frame if it exists.
func _physics_process(_delta: float) -> void:
	if mouse_area:
		mouse_area.global_position = CursorManager.get_cursor_mouse_position()

## Checks the conditions needed to be able to start firing the weapon. If they all pass, it returns true.
func _can_activate_at_all() -> bool:
	recent_holding_cooldown_check = true

	if not pullout_delay_timer.is_stopped():
		return false
	if get_cooldown() > 0:
		if source_entity.inv.auto_decrementer.get_cooldown_source_title(stats.get_cooldown_id()) == "default":
			recent_holding_cooldown_check = false
		return false
	match state:
		WeaponState.IDLE:
			if ensure_enough_ammo():
				return true
			reload()
			return false
		WeaponState.RELOADING:
			if stats.reload_type == ProjWeaponStats.ReloadType.SINGLE and not stats.must_reload_fully:
				if ensure_enough_ammo():
					return true
			return false
		WeaponState.FIRING:
			return false
		_:
			return false

## Called when a trigger is initially pressed.
func activate() -> void:
	if not _can_activate_at_all():
		if source_entity is Player and stats.ammo_in_mag == 0 and state == WeaponState.IDLE:
			AudioManager.play_2d(stats.empty_mag_sound, global_position)
		return

	if stats.firing_mode == ProjWeaponStats.FiringType.SEMI_AUTO:
		start_firing_sequence()

## Called for every frame that a trigger is pressed.
func hold_activate(delta: float) -> void:
	if not _can_activate_at_all():
		if not state == WeaponState.FIRING:
			if not stats.dec_charge_on_cooldown and recent_holding_cooldown_check == false:
				return
			decrement_hold_time(delta)
		return

	hold_time += delta

	match stats.firing_mode:
		ProjWeaponStats.FiringType.SEMI_AUTO:
			hold_time = 0
		ProjWeaponStats.FiringType.AUTO:
			hold_time = 0
			start_firing_sequence()
		ProjWeaponStats.FiringType.CHARGE:
			if (not is_charging) and (stats.charging_stat_effect != null):
				var effect: StatusEffect = stats.charging_stat_effect.duplicate()
				effect.mod_time = 100000000
				source_entity.effect_receiver.handle_status_effect(effect)
			is_charging = true

			if stats.auto_do_charge_use and hold_time >= stats.s_mods.get_stat("min_charge_time"):
				if stats.reset_charge_on_fire:
					hold_time = 0
				start_firing_sequence()

## Called when a trigger is released.
func release_hold_activate() -> void:
	_delay_clean_up_hitscans()

	if not _can_activate_at_all():
		return

	if stats.firing_mode == ProjWeaponStats.FiringType.CHARGE:
		if stats.charging_stat_effect != null:
			source_entity.effects.request_effect_removal_by_source(stats.charging_stat_effect.id, Globals.StatusEffectSourceType.FROM_SELF)
		is_charging = false

		if hold_time >=  stats.s_mods.get_stat("min_charge_time"):
			if stats.reset_charge_on_fire:
				hold_time = 0
			start_firing_sequence()

## Starts the main firing sequence that awaits at the needed steps each stage.
func start_firing_sequence() -> void:
	# ---Cancel Any Current Reload---
	if state == WeaponState.RELOADING:
		reload_handler.end_reload()

	# ---Warmup Phase---
	state = WeaponState.FIRING
	await warmup_handler.start_warmup()
	if not ensure_enough_ammo():
		_clean_up_hitscans()
		reload()
		return

	# ---Spawning Projectile Phase---
	if is_holding_continuous_beam:
		_update_hitscans_with_new_multishot_id()
	await firing_handler.start_firing()
	state = WeaponState.IDLE
	if stats.hitscan_logic.continuous_beam:
		is_holding_continuous_beam = true

	# ---Overheating Check---
	if overheat_handler.check_is_overheated():
		_clean_up_hitscans()

	# ---Hitscan Release Check---
	if stats.is_hitscan:
		if stats.firing_mode == ProjWeaponStats.FiringType.CHARGE and stats.reset_charge_on_fire:
			_clean_up_hitscans()
		elif not stats.hitscan_logic.continuous_beam or has_released or stats.firing_mode == ProjWeaponStats.FiringType.SEMI_AUTO:
			_clean_up_hitscans()

	# ---Check Ammo Again---
	if not ensure_enough_ammo() or requesting_reload_after_firing:
		requesting_reload_after_firing = false
		reload()
		_clean_up_hitscans()

## Called from the hands component when we press the reload key.
func reload() -> void:
	if reload_handler.mag_is_full():
		return
	hold_time = 0

	match state:
		WeaponState.IDLE:
			state = WeaponState.RELOADING
			await reload_handler.attempt_reload()
			state = WeaponState.IDLE
		WeaponState.FIRING:
			requesting_reload_after_firing = true

## Checks that the weapon has enough ammo to initiate the next firing sequence.
func ensure_enough_ammo() -> bool:
	var has_needed_ammo: bool = false

	var ammo_needed: int = int(stats.s_mods.get_stat("projectiles_per_fire"))
	if not stats.use_ammo_per_burst_proj:
		ammo_needed = 1

	match stats.ammo_type:
		ProjWeaponStats.ProjAmmoType.STAMINA:
			var stamina_needed: float = ammo_needed * stats.stamina_use_per_proj
			has_needed_ammo = source_entity.stamina_component.has_enough_stamina(stamina_needed)
		ProjWeaponStats.ProjAmmoType.SELF:
			has_needed_ammo = true
		_:
			has_needed_ammo = (stats.ammo_in_mag >= ammo_needed)

	if has_needed_ammo:
		return true
	return false

## Updates the ammo in the weapon's magazine and then calls to update the ammo UI.
func update_mag_ammo(new_amount: int) -> void:
	stats.ammo_in_mag = new_amount
	update_ammo_ui()

## Updates the ammo UI with the ammo in the magazine.
func update_ammo_ui() -> void:
	if ammo_ui == null or stats.hide_ammo_ui:
		return

	var count_str: String
	match stats.ammo_type:
		ProjWeaponStats.ProjAmmoType.SELF:
			if source_entity.inv.inv[inv_index] == null or source_entity.inv.inv[inv_index].stats == null:
				count_str = ""
			else:
				count_str = str(source_entity.inv.inv[inv_index].quantity)
		ProjWeaponStats.ProjAmmoType.STAMINA:
			count_str = str(floori(source_entity.stamina_component.stamina))
		ProjWeaponStats.ProjAmmoType.NONE when stats.dont_consume_ammo:
			count_str = "∞"
		_:
			count_str = str(stats.ammo_in_mag)
	ammo_ui.update_mag_ammo_ui(count_str)
	ammo_ui.calculate_inv_ammo()

## Updates the mouse cursor's cooldown progress and coloration based on active cooldowns and/or overheats.
func _update_cursor_cooldown_ui() -> void:
	if not source_entity is Player:
		return
	if not stats.show_cursor_cooldown and not state == WeaponState.RELOADING:
		CursorManager.update_vertical_tint_progress(100.0)
		return

	if source_entity.inv.auto_decrementer.get_cooldown_source_title(stats.get_cooldown_id()) in stats.shown_cooldown_fills:
		var tint_progress: float = source_entity.inv.auto_decrementer.get_cooldown_percent(stats.get_cooldown_id(), true)
		CursorManager.update_vertical_tint_progress(tint_progress * 100.0)

## Spawns a simulated ejected casing to fall to the ground. Requires a Marker2D in the scene called
## "CasingEjectionPoint". Must be called by the animation player due to varying timing of when it should
## spawn per weapon.
func _eject_casing(per_used_ammo: bool = false) -> void:
	if not casing_ejection_point:
		return

	for i: int in range((stats.s_mods.get_stat("mag_size") - stats.ammo_in_mag) if per_used_ammo else 1):
		var casing: Node2D = casing_scene.instantiate()
		var casing_rand_offset: Vector2 = Vector2(randf_range(-1, 1), randf_range(-1, 1))
		casing.global_position = casing_ejection_point.global_position + casing_rand_offset
		casing.global_rotation = global_rotation
		casing.sound = stats.casing_sound

		Globals.world_root.add_child(casing)

		casing.sprite.texture = stats.casing_texture
		if stats.casing_tint != Color.WHITE:
			casing.sprite.modulate = stats.casing_tint

## Ease of use method for triggering sounds from within the animation player.
func play_reload_sound(index: int, use_reverb: bool = false) -> void:
	if source_entity is Player:
		AudioManager.play_global(stats.reload_sound, 0, false, index, self)
	else:
		AudioManager.play_2d(stats.reload_sound, global_position, 0, use_reverb, index, self)
