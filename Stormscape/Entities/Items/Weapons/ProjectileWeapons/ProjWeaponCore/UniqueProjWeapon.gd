@tool
@icon("res://Utilities/Debug/EditorIcons/projectile_weapon.png")
extends ProjectileWeapon
class_name UniqueProjWeapon
## A subclass of projectile weapon that adds extra logic for handling unique projectiles. These cannot hitscan.

var returned: bool = true: set = _set_returned ## Whether the unique projectile has come back yet. Gets reset when dropped, but any cooldowns are saved.


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	super._ready()

	if not returned:
		sprite.hide()

func _set_returned(new_value: bool) -> void:
	if Engine.is_editor_hint():
		return

	if (not returned) and (new_value == true):
		add_unique_proj_cooldown(stats.fire_cooldown)

	returned = new_value
	sprite.visible = returned

func _can_activate_at_all() -> bool:
	if not returned:
		return false
	return super._can_activate_at_all()

func _exit_tree() -> void:
	super._exit_tree()

	if not returned:
		add_unique_proj_cooldown(stats.fire_cooldown)

## Overrides the normal add_cooldown method to do nothing so that we can add our own here
func add_cooldown(_duration: float, _title: String = "default") -> void:
	pass

func add_unique_proj_cooldown(duration: float, title: String = "default") -> void:
	source_entity.inv.auto_decrementer.add_cooldown(stats.get_cooldown_id(), duration, title)
