@tool
extends PhysicsBody2D
class_name Entity
## Base class for all entities in the game.

@export var team: Globals.Teams = Globals.Teams.PLAYER ## What the effects received by this entity should consider as this entity's team.
@export var is_object: bool = false ## When true, this entity's collision logic will follow that of a world object, regardless of team. It will also not have an auto_decrementer in its inv, as it shouldn't be holding things that need one.
@export var inv: InvResource ## The inventory data resource for this entity.
@export var loot: LootTableResource ## The loot table resource for this entity.

@onready var sprite: EntitySprite = %EntitySprite ## The visual representation of the entity. Needs to have the EntityEffectShader applied.
@onready var effect_receiver: EffectReceiverComponent = get_node_or_null("EffectReceiverComponent") ## The component that handles incoming effect sources.
@onready var effects: StatusEffectsComponent = get_node_or_null("%StatusEffectsComponent") ## The node that will cache and manage all status effects for this entity.
@onready var emission_mgr: ParticleEmissionComponent = $ParticleEmissionComponent ## The component responsible for determining the extents and origins of different particle placements.
@onready var detection_component: DetectionComponent = $DetectionComponent ## The component that defines the radius around this entity that an enemy must enter for that enemy to be alerted.
@onready var health_component: HealthComponent = $HealthComponent ## The component in charge of entity health and shield.
@onready var item_receiver: ItemReceiverComponent = get_node_or_null("ItemReceiverComponent") ## The item receiver for this entity.
@onready var hands: HandsComponent = get_node_or_null("%HandsComponent") ## The hands item component for the entity.

var stats: StatModsCache = StatModsCache.new() ## The resource that will cache and work with all stat mods for this entity.
var wearables: Array[Dictionary] = [{ &"1" : null }, { &"2" : null }, { &"3" : null }, { &"4" : null }, { &"5" : null }] ## The equipped wearables on this entity.


#region Debug
## Edits editor warnings for easier debugging.
func _get_configuration_warnings() -> PackedStringArray:
	if get_node_or_null("%EntitySprite") == null or not %EntitySprite is EntitySprite:
		return [
			"This entity must have an EntitySprite typed sprite node. Make sure its name is unique with a %."
			]
	return []
#endregion

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	add_to_group("has_save_logic")

	if is_object:
		collision_layer = 0b100000
		match team:
			Globals.Teams.PLAYER:
				add_to_group("player_entities")
			Globals.Teams.ENEMY:
				add_to_group("enemy_entities")
	elif team == Globals.Teams.PLAYER:
		collision_layer = 0b10
		add_to_group("player_entities")
	elif team == Globals.Teams.ENEMY:
		add_to_group("enemy_entities")
		collision_layer = 0b100
	elif team == Globals.Teams.PASSIVE:
		collision_layer = 0b1000

	collision_mask = 0b1101111

	stats.affected_entity = self
	sprite.entity = self
	if inv:
		inv = inv.duplicate()
		inv.initialize_inventory(self)
	if loot:
		loot = loot.duplicate()
		loot.initialize(self)

func _process(delta: float) -> void:
	if not Engine.is_editor_hint() and inv and not is_object:
		inv.auto_decrementer.process(delta)
