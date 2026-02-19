extends Resource
class_name II
## "II" stands for ItemInstance, and is the wrapper for all item instances in the game. This holds a reference
## to the stats powering this item as well as unqiue properties like the uid.

@export_storage var uid: int ## The unique id for this item resource instance.
@export_storage var stats: ItemStats ## The resource driving the stats and type of item this is.
@export var q: int = 1 ## The quantity associated with the inventory item.
