extends AudioStreamPlayer
class_name PooledAudioPlayer
## An extension of the default global player to add data that tracks the validity and status of the instance.

var valid: bool = false ## Whether this is still playing the sound and not fading.
var sound_id: String ## The id of the sound being played.
var finish_callables: Array[Callable] ## All callables that should be called when the sound ends.
var loops_completed: int = 0 ## How many loops that have been completed so far.


func _ready() -> void:
	finished.connect(AudioManager._on_player_finished_playing.bind(self))
	tree_exiting.connect(AudioManager._open_audio_resource_spot.bind(self, false))

## Resets all custom attributes.
func reset() -> void:
	valid = false
	finish_callables.clear()
	remove_from_group(sound_id)
	remove_from_group("ACTIVE_SOUNDS")
	sound_id = ""
	loops_completed = 0
