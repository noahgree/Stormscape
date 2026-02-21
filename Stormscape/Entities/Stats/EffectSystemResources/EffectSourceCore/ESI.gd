extends Resource
class_name ESI
## ESI stands for Effect Source Instance, and it acts as a wrapper over instances of effect sources
## that originate from entities and items.

var es: EffectSource: set = _set_es ## The effect source that this wraps.
var stat_overrides: Dictionary[StringName, float] ## The overrides to use instead when accessing stats from the es.
var status_effects: Array[StatusEffect] ## The modifiable list of status effects for the effect source.
var contact_position: Vector2 ## The position of what the effect source is attached to when it makes contact with a receiver.
var movement_direction: Vector2 ## The direction vector of this effect source at contact used for knockback.
var multishot_id: int = -1 ## The id used to relate multishot projectiles with each other. -1 means it did not come from a multishot.


## Sets the new effect source by clearing the old local status effects array and copying all new status
## effects into it.
func _set_es(new_es: EffectSource) -> void:
	es = new_es
	reset_status_effects()

## Resets the modifiable status effects array back to the original ones in the es.
func reset_status_effects() -> void:
	status_effects.clear()
	if es != null:
		status_effects.assign(es.status_effects)

## Gets an existing effect index that matches the full effect key (type and source), regardless of level.
## Does not handle duplicates.
func get_existing_effect_index(full_effect_key: StringName) -> int:
	var i: int = 0
	for status_effect: StatusEffect in status_effects:
		if status_effect.get_full_effect_key() == full_effect_key:
			return i
		i += 1
	return -1

## Replaces or adds all incoming status effects depending on whether they already exist.
func replace_or_add_status_effects(new_effects: Array[StatusEffect]) -> void:
	for new_effect: StatusEffect in new_effects:
		var existing_index: int = get_existing_effect_index(new_effect.get_full_effect_key())
		if existing_index > -1:
			if (new_effect.effect_lvl > status_effects[existing_index].effect_lvl):
				status_effects[existing_index] = new_effect
		else:
			status_effects.append(new_effect)
