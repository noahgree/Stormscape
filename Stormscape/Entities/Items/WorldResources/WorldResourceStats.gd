@icon("res://Utilities/Debug/EditorIcons/world_resource_resource.png")
extends ItemStats
class_name WorldResourceStats
## The item resource subclass specific to world resources.

@export var fuel_amount: int ## How much fuel this world resource is worth. Leaving it at 0 means this does not classify as fuel.
