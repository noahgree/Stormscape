extends Resource
class_name LootTableEntry

@export var item: ItemStats = null
@export var quantity: int = 1
@export var weighting: float = 1.0


# Unique Properties #
@export_storage var last_used: int = 0
@export_storage var spawn_count: int = 0
