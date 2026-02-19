@icon("res://Utilities/Debug/EditorIcons/world_resource.png")
extends EquippableItem
class_name WorldResource
## The EquippableItem definition for WorldResource.


func _set_ii(new_ii: II) -> void:
	super._set_ii(new_ii)

	if sprite:
		sprite.texture = stats.in_hand_icon

func activate() -> void:
	pass
