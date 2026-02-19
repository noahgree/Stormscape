extends SaveData
class_name DynamicEntityData

# DynamicEntity Core
@export var position: Vector2
@export var sprite_frames_path: String
@export var sprite_texture_path: String
@export var inv: Array[InvItemResource]
@export var loot: LootTableResource

# Stats
@export var stat_mods: Dictionary[StringName, Dictionary]
@export var wearables: Array[Dictionary]

# Movement
@export var velocity: Vector2
@export var snare_factor: float
@export var snare_time_left: float
@export var facing_dir: Vector2
@export var knockback_vector: Vector2

# HealthComponent
@export var health: int
@export var shield: int
@export var armor: int

# StaminaComponent
@export var stamina: float
@export var can_use_stamina: bool
@export var stamina_to_hunger_count: float
@export var hunger_bars: int
@export var can_use_hunger_bars: bool

# ItemReceiverComponent
@export var pickup_range: int

#region Player Only Data
# Player Core
@export var is_player: bool = false

# HotbarHUD
@export var active_slot_index: int
#endregion
