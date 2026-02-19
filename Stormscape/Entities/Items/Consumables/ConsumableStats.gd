@icon("res://Utilities/Debug/EditorIcons/consumable_resource.png")
extends ItemStats
class_name ConsumableStats

@export_group("General Consumable Details")
@export var effect_source: EffectSource = EffectSource.new() ## The resource that defines what happens to the entity that consumes this consumable. Includes things like damage and status effects.
@export var hunger_bar_gain: int = 1 ## How many hunger bars this consumable grants.
@export var hunger_bar_deduction: int = 0 ## How many hunger bars this consumable takes away.
@export_custom(PROPERTY_HINT_NONE, "suffix:seconds") var consumption_time: float = 1.0 ## How long this takes to consume.
@export_custom(PROPERTY_HINT_NONE, "suffix:seconds") var consumption_cooldown: float = 0.35 ## How long after a consumption must we wait before another consumption can occur.

@export_subgroup("FX")
@export var particles_color: Color = Color(1, 1, 1) ## The color of the particles during consumption.
@export var consumption_sound: String = "" ## The sound to play during consumption.
@export var post_consumption_sound: String = "" ## The sound to play once consumption ends.
