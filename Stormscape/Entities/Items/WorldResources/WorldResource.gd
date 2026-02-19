@icon("res://Utilities/Debug/EditorIcons/world_resource.png")
extends EquippableItem
class_name WorldResource
## The EquippableItem definition for WorldResource.


func _set_stats(new_stats: ItemStats) -> void:
	super._set_stats(new_stats)

	if sprite:
		sprite.texture = stats.in_hand_icon

func activate() -> void:
	pass
