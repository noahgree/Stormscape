extends Node2D
class_name EquippableItem
## The base class for all items that can be used by the HandsComponent.
##
## In order to be equipped and shown on screen in some place other than the inventory,
## the item resource must have an associated equippable item scene.

@export var ii: II: set = _set_ii ## The resource driving the stats and type of item.
@export var sprites_to_tint: Array[Node2D] ## All sprites that should be affected by tinting during events such as "disable".

@onready var sprite: Node2D = $ItemSprite ## The main sprite for the equippable item. Should have the entity effect shader attached.
@onready var clipping_detector: Area2D = get_node_or_null("ClippingDetector") ## Used to detect when the item is overlapping with an in-game object that should block its use (i.e. a wall or tree).
@onready var audio_preloader: AudioPreloader = AudioPreloader.new(self) ## The node registering preloaded audios.

var stats: ItemStats ## Reflects the stats of the current ii driving this item.
var inv_index: int ## The slot this equippable item is in whilst equipped.
var source_entity: Entity ## The entity that is holding the equippable item.
var ammo_ui: Control ## The ui assigned by the hands component that displays the ammo. Only for the player.
var overlaps: Array[Area2D] ## Current overlapping item-blocking clipping areas.
var enabled: bool = true: ## When false, any activation or reload actions are blocked.
	set(new_value):
		enabled = new_value
		if not enabled:
			disable()
			for sprite_node: Node2D in sprites_to_tint:
				sprite_node.set_instance_shader_parameter("tint_color", Color(1, 0.188, 0.345, 0.45))
				sprite_node.set_instance_shader_parameter("final_alpha", 0.65)
		else:
			for sprite_node: Node2D in sprites_to_tint:
				sprite_node.set_instance_shader_parameter("tint_color", Color(1.0, 1.0, 1.0, 0.0))
				sprite_node.set_instance_shader_parameter("final_alpha", 1.0)
			enable()


## Creates an equippable item to be used via the inv index it is currently in.
static func create_from_inv_index(item_instance: II, entity: Entity, index: int) -> EquippableItem:
	var item: EquippableItem = item_instance.stats.item_scene.instantiate()
	item.inv_index = index
	item.source_entity = entity
	item.ii = item_instance
	return item

## Sets the item instance when changed. Can be overridden by child classes to do specific things on change.
func _set_ii(new_ii: II) -> void:
	source_entity.inv.inv[inv_index] = new_ii
	source_entity.inv.inv_data_updated.emit(inv_index, source_entity.inv.inv[inv_index])
	stats = new_ii.stats

func _ready() -> void:
	_set_ii(ii)

	if clipping_detector != null:
		clipping_detector.area_entered.connect(_on_item_enters_clipping_area)
		clipping_detector.area_exited.connect(_on_item_leaves_clipping_area)

	if source_entity is Player:
		AudioManager.play_global(ii.stats.equip_audio, 0, false, -1, self)

## Disables the item when it starts to clip. Only applies to items with clipping detectors.
func _on_item_enters_clipping_area(area: Area2D) -> void:
	if area.get_parent() != source_entity and enabled:
		enabled = false
		overlaps.append(area)

## Enables the item when it stops clipping. Only applies to items with clipping detectors.
func _on_item_leaves_clipping_area(area: Area2D) -> void:
	var area_index: int = overlaps.find(area)
	if area_index != -1:
		overlaps.remove_at(area_index)
	if overlaps.is_empty() and not enabled:
		enabled = true

## Intended to be overridden by child classes in order to specify what to do when this item is disabled.
func disable() -> void:
	pass

## Intended to be overridden by child classes in order to specify what to do when this item is enabled.
func enable() -> void:
	pass

## Intended to be overridden by child classes in order to specify what to do when this item is used.
func activate() -> void:
	pass

## Intended to be overridden by child classes in order to specify what to do when this item
## is used after a hold click.
func hold_activate(_delta: float) -> void:
	pass

## Intended to be overridden by child classes in order to specify what to do when this
## item is used after a released hold click.
func release_hold_activate() -> void:
	pass

## Intended to be overridden by child classes in order to specify what to do when this item is equipped.
func enter() -> void:
	pass

## Intended to be overridden by child classes in order to specify what to do when this item
## is unequipped. Should call super.exit() first, though.
func exit() -> void:
	set_process(false)
