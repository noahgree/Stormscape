@tool
@icon("res://Utilities/Debug/EditorIcons/melee_weapon.png")
extends Weapon
class_name MeleeWeapon
## The base class for all melee weapons, which are based on swings.

enum WeaponState { IDLE, SWINGING } ## The states the melee weapon can be in.
enum RecentSwingType { NORMAL, CHARGED } ## The kinds of usage that could have just occurred.

@export var sprite_visual_rotation: float = 45 ## How rotated the drawn sprite is by default when imported. Straight up would be 0º, angling top-right would be 45º, etc.

@onready var hitbox_component: HitboxComponent = %HitboxComponent ## The hitbox responsible for applying the melee hit.

const MIN_HOLD_TIME: float = 0.25 ## The time it takes to consider the activation an attempt to charge up the weapon.
var state: WeaponState = WeaponState.IDLE ## The melee weapon's current state.
var recent_swing_type: RecentSwingType = RecentSwingType.NORMAL ## The most recent type of usage.


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	super()

	hitbox_component.source_entity = source_entity
	hitbox_component.source_weapon = stats
	reset_animation_state("MeleeWeaponAnimLibrary/RESET")

	if source_entity is Player:
		source_entity.stamina_component.stamina_changed.connect(
			func(_new_stamina: float, _old_stamina: float) -> void: update_ammo_ui()
			)

## Called when the weapon first enters, but after the _ready function.
func enter() -> void:
	if stats.s_mods.get_stat("pullout_delay") > 0:
		pullout_delay_timer.start(stats.s_mods.get_stat("pullout_delay"))

	update_ammo_ui()

## Called when the weapon is about to queue_free, but before the _exit_tree function.
func exit() -> void:
	super()
	source_entity.fsm.controller.reset_facing_method()

## Enables or disabled the hitbox on the weapon in a deferred manner so as to let queries flush.
func change_collider_state(collider_enabled: bool) -> void:
	hitbox_component.collider.set_deferred("disabled", not collider_enabled)

## Updates the UIs that depend on frame-by-frame updates.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if source_entity is Player:
		_update_overhead_charge_ui()
	_update_cursor_cooldown_ui()

## Checks the conditions needed to be able to start using the weapon. If they all pass, it returns true.
func _can_activate_at_all(for_charged: bool) -> bool:
	if (not pullout_delay_timer.is_stopped()) or (get_cooldown() > 0):
		return false
	match state:
		WeaponState.IDLE:
			var cost: float = stats.s_mods.get_stat("stamina_cost")
			if for_charged:
				cost = stats.s_mods.get_stat("charge_stamina_cost")
				if not stats.can_do_charge_use:
					return false
			if source_entity.stamina_component.has_enough_stamina(cost):
				return true
			MessageManager.add_msg_preset("Not Enough Stamina", MessageManager.Presets.FAIL)
			return false
		_:
			return false

## Called when a trigger is initially pressed.
func activate() -> void:
	if stats.can_do_charge_use or not _can_activate_at_all(false):
		return

	_swing()

## Called for every frame that a trigger is pressed.
func hold_activate(delta: float) -> void:
	if stats.can_do_charge_use:
		if _can_activate_at_all(true):
			if stats.auto_do_charge_use and (hold_time >= stats.s_mods.get_stat("min_charge_time")):
				if stats.reset_charge_on_use:
					hold_time = 0
				_charge_swing()
				return
		else:
			decrement_hold_time(delta)
			return
	else:
		if _can_activate_at_all(false):
			_swing()
		hold_time = 0
		return

	hold_time += delta

## Called when a trigger is released.
func release_hold_activate() -> void:
	if (hold_time >= stats.s_mods.get_stat("min_charge_time")) and _can_activate_at_all(true):
		if stats.reset_charge_on_use:
			hold_time = 0
		_charge_swing()
	elif _can_activate_at_all(false):
		if not stats.normal_use_on_fail and hold_time > MIN_HOLD_TIME:
			return
		_swing()
		hold_time = 0

## Begins the logic for doing a normal weapon swing.
func _swing() -> void:
	state = WeaponState.SWINGING
	source_entity.stamina_component.use_stamina(stats.s_mods.get_stat("stamina_cost"))
	recent_swing_type = RecentSwingType.NORMAL

	# Force no rotation during normal swings
	source_entity.fsm.controller.facing_method = FacingComponent.Method.NONE
	source_entity.hands.snap_y_scale()

	_set_hitbox_effect_source_and_collision(stats.effect_source)
	_apply_start_use_effect(false)
	add_cooldown(stats.s_mods.get_stat("use_cooldown") + stats.s_mods.get_stat("use_speed"))

	await _start_swing_anim_and_fx(false)

	state = WeaponState.IDLE
	source_entity.fsm.controller.reset_facing_method()
	_apply_post_use_effect(false)

## Begins the logic for doing a charged swing.
func _charge_swing() -> void:
	state = WeaponState.SWINGING
	source_entity.stamina_component.use_stamina(stats.s_mods.get_stat("charge_stamina_cost"))
	recent_swing_type = RecentSwingType.CHARGED

	# Follow the rotation of the swing during charged swings, since it will likely spin all the way around
	source_entity.fsm.controller.facing_method = FacingComponent.Method.ITEM_ROT
	source_entity.hands.snap_y_scale()

	_set_hitbox_effect_source_and_collision(stats.charge_effect_source)
	_apply_start_use_effect(true)
	add_cooldown(stats.s_mods.get_stat("charge_use_cooldown") + stats.s_mods.get_stat("charge_use_speed"))

	await _start_swing_anim_and_fx(true)

	state = WeaponState.IDLE
	source_entity.fsm.controller.reset_facing_method()
	_apply_post_use_effect(true)

## Sets the hitbox's effect source and collision mask (what to hit) for the swing.
func _set_hitbox_effect_source_and_collision(new_effect_source: EffectSource) -> void:
	hitbox_component.effect_source = new_effect_source
	hitbox_component.collision_mask = new_effect_source.scanned_phys_layers

## Starts the swing animation and plays any associated fx. Awaits the animation ending and returns control
## to the caller.
func _start_swing_anim_and_fx(for_charged: bool) -> void:
	AudioManager.play_2d(stats.charge_use_sound if for_charged else stats.use_sound, source_entity.global_position)
	var anim_to_play: String

	if (stats.use_anim == "" and not for_charged) or (stats.charge_use_anim == "" and for_charged):
		var library: AnimationLibrary = anim_player.get_animation_library("MeleeWeaponAnimLibrary")
		var anim: Animation = library.get_animation("charge_use" if for_charged else "use")
		var angle_radians: float = deg_to_rad(stats.s_mods.get_stat("charge_swing_angle" if for_charged else "swing_angle"))
		var main_sprite_track: int = anim.find_track("ItemSprite:rotation", Animation.TYPE_VALUE)
		anim.track_set_key_value(main_sprite_track, 1, angle_radians)
		anim_to_play = "MeleeWeaponAnimLibrary/charge_use" if for_charged else "MeleeWeaponAnimLibrary/use"
	else:
		anim_to_play = stats.charge_use_anim if for_charged else stats.use_anim

	var use_speed: float = stats.s_mods.get_stat("charge_use_speed" if for_charged else "use_speed")
	if use_speed > 0:
		anim_player.speed_scale = 1.0 / use_speed
		anim_player.play(anim_to_play)
		await anim_player.animation_finished

## Spawns a ghosting effect of the weapon sprite to immitate a fast whoosh.
func _spawn_ghost() -> void:
	var sprite_texture: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	var fade_time: float = stats.ghost_fade_time
	if recent_swing_type == RecentSwingType.CHARGED:
		fade_time = stats.charge_ghost_fade_time

	var adjusted_transform: Transform2D = sprite.global_transform
	var ghost_instance: SpriteGhost = SpriteGhost.create(adjusted_transform, sprite.scale, sprite_texture, fade_time)

	ghost_instance.scale = Vector2(1, -1) if source_entity.hands.current_x_direction != 1 else Vector2(1, 1)
	ghost_instance.flip_h = sprite.flip_h
	ghost_instance.offset = sprite.offset
	ghost_instance.make_white()

	Globals.world_root.add_child(ghost_instance)

## Applies a status effect to the source entity at the start of use.
func _apply_start_use_effect(was_charge_fire: bool = false) -> void:
	var effect: StatusEffect = stats.use_start_effect if not was_charge_fire else stats.chg_use_start_effect
	if effect != null:
		source_entity.effect_receiver.handle_status_effect(effect)

## Applies a status effect to the source entity after use.
func _apply_post_use_effect(was_charge_fire: bool = false) -> void:
	var effect: StatusEffect = stats.post_use_effect if not was_charge_fire else stats.post_chg_use_effect
	if effect != null:
		source_entity.effect_receiver.handle_status_effect(effect)

## If a connected ammo UI exists (i.e. for a player), update it with the new ammo available.
## Typically just reflects the stamina.
func update_ammo_ui() -> void:
	if ammo_ui == null or stats.hide_ammo_ui:
		return
	ammo_ui.update_mag_ammo_ui(str(floori(source_entity.stamina_component.stamina)))

## Updates the mouse cursor's cooldown progress based on active cooldowns.
func _update_cursor_cooldown_ui() -> void:
	if not source_entity is Player:
		return
	if source_entity.inv.auto_decrementer.get_cooldown_source_title(stats.get_cooldown_id()) in stats.shown_cooldown_fills:
		var tint_progress: float = source_entity.inv.auto_decrementer.get_cooldown_percent(stats.get_cooldown_id(), true)
		CursorManager.update_vertical_tint_progress(tint_progress * 100.0)
