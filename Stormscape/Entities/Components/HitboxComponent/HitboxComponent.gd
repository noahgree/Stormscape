@icon("res://Utilities/Debug/EditorIcons/hitbox_component.svg")
extends Area2D
class_name HitboxComponent
## The area2d that defines where an effect source comes from.

@export_group("Standalone Hitbox Properties") # Only set these manually if using this as a standalone hitbox and not attached to a projectile or other weapon
@export var effect_source: EffectSource ## The effect to be applied when this hitbox hits an effect receiver.
@export var source_entity: Entity ## The entity that the effect was produced by.
@export var use_self_position: bool = false ## When using the hitbox as a standalone area2d, make this property true so that it uses its own position to handle effects like knockback.

@onready var collider: CollisionShape2D = $CollisionShape2D ## The collision shape for this hitbox.

var movement_direction: Vector2 = Vector2.ZERO ## The current movement direction for this hitbox.
var source_weapon: WeaponStats ## The reference to the weapon that produced this effect source, if any.


## Setup the area detection signal and turn on monitorable just in case it was toggled off somewhere. It needs
## to be on or for some reason it cannot detect bodies (it'll still detect areas, just not bodies).
## Also set collision mask to the matching flags.
func _ready() -> void:
	self.area_entered.connect(_on_area_entered)
	self.body_entered.connect(_on_body_entered)
	collision_layer = 0
	if effect_source:
		collision_mask = effect_source.scanned_phys_layers

## When detecting an area, start having it handled. This method can be overridden in subclasses.
func _on_area_entered(area: Area2D) -> void:
	if (area.get_parent() == source_entity):
		if not effect_source or not effect_source.can_hit_self:
			return

	if area is EffectReceiverComponent:
		_start_being_handled(area as EffectReceiverComponent)

	_process_hit(area)

## If we hit a body, process it. Any body you wish to make block or handle attacks should be given an effect
## receiver.
func _on_body_entered(body: Node2D) -> void:
	if body is TileMapLayer:
		_process_hit(body)

	# If the body is an entity that doesn't receive effect sources, it still has collision and should stop projectiles
	if body is Entity:
		if body.effect_receiver == null:
			_process_hit(body)

## Meant to interact with an EffectReceiverComponent that can handle effects supplied by this instance.
## This version of the method handles the general case, but specific behaviors defined in certain
## weapon hitboxes may want to override it.
func _start_being_handled(handling_area: EffectReceiverComponent) -> void:
	effect_source = effect_source.duplicate()

	if effect_source.source_type == Globals.EffectSourceSourceType.FROM_PROJECTILE:
		effect_source.movement_direction = movement_direction
	if not use_self_position:
		effect_source.contact_position = get_parent().global_position
	else:
		effect_source.contact_position = global_position

	if handling_area.absorb_full_hit:
		collider.set_deferred("disabled", true) # Does not apply to hitscans
	handling_area.handle_effect_source(effect_source, source_entity, source_weapon)

## Meant to be overridden by subclasses to determine what to do after hitting an object.
func _process_hit(_object: Node2D) -> void:
	pass
