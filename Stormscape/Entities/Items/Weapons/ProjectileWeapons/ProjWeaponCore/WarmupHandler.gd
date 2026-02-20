class_name WarmupHandler
## Handles the warmup logic for projectile weapons.

signal warmup_ended ## Used internally when the warmup timer ends to make sure any warmup animation is done first.

var weapon: ProjectileWeapon ## A reference to the weapon.
var anim_player: AnimationPlayer ## A reference to the animation player on the weapon.
var auto_decrementer: AutoDecrementer ## A reference to the auto_decrementer in the source_entity's inventory.
var warmup_timer: Timer ## The timer that delays returning control back to the caller by the current warmup time.


## Called when this script is first created to provide a reference to the owning weapon.
func _init(parent_weapon: ProjectileWeapon) -> void:
	if Engine.is_editor_hint():
		return
	weapon = parent_weapon
	anim_player = weapon.anim_player
	auto_decrementer = weapon.source_entity.inv.auto_decrementer

	warmup_timer = TimerHelpers.create_one_shot_timer(weapon, 1, _on_warmup_timer_timeout)

## The main entry point for starting warmups. Returns control back to the caller once the warmup ends.
func start_warmup() -> void:
	var warmup_time: float = _get_warmup_delay()
	if warmup_time <= 0:
		return

	if anim_player.has_animation("warmup"):
		anim_player.speed_scale = 1.0 / warmup_time
		anim_player.play("warmup")

	warmup_timer.start(warmup_time)
	await warmup_ended

## Increases current warmup level via sampling the increase curve using the current warmup.
func add_warmup() -> void:
	if weapon.ii.sc.get_stat("initial_fire_rate_delay") <= 0:
		return
	if weapon.stats.firing_mode != ProjWeaponStats.FiringType.AUTO:
		return

	var current_warmup: float = auto_decrementer.get_warmup(str(weapon.ii.uid))
	var sampled_point: float = weapon.stats.warmup_increase_rate.sample_baked(current_warmup)
	var increase_rate_multiplier: float = weapon.ii.sc.get_stat("warmup_increase_rate_multiplier")
	var increase_amount: float = max(0.01, sampled_point * increase_rate_multiplier)
	auto_decrementer.add_warmup(
		str(weapon.ii.uid),
		min(1, increase_amount),
		weapon.stats.warmup_decrease_rate,
		weapon.stats.warmup_decrease_delay
		)

## Grabs a point from the warmup curve based on current warmup level given by the auto decrementer.
func _get_warmup_delay() -> float:
	var current_warmup: float = auto_decrementer.get_warmup(str(weapon.ii.uid))
	if current_warmup > 0:
		var sampled_delay_multiplier: float = weapon.stats.warmup_delay_curve.sample_baked(current_warmup)
		var max_delay: float = weapon.ii.sc.get_stat("initial_fire_rate_delay")
		return sampled_delay_multiplier * max_delay
	else:
		return 0

## When the warmup delay is over, return control back to the caller, assuming any warmup animation has ended.
func _on_warmup_timer_timeout() -> void:
	if anim_player.is_playing() and anim_player.current_animation == "warmup":
		await anim_player.animation_finished
	warmup_ended.emit()
