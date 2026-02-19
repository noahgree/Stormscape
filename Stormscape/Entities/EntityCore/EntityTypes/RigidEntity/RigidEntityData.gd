extends SaveData
class_name RigidEntityData

# RigidEntity Core
@export var position: Vector2
@export var sprite_frames_path: String
@export var sprite_texture_path: String
@export var inv: Array[InvItemResource]
@export var loot: LootTableResource

# Stats
@export var stat_mods: Dictionary[StringName, Dictionary]
@export var wearables: Array[Dictionary]

# Movement
@export var facing_dir: Vector2

# HealthComponent
@export var health: int
@export var shield: int
@export var armor: int

# ItemReceiverComponent
@export var pickup_range: int
