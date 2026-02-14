extends CanvasLayer
## A script for managing game-wide debug actions or UI.

@onready var fps_label: Label = $FPS ## The label displaying the current FPS.


func _ready() -> void:
	if DebugFlags.show_fps:
		set_process(true)
	else:
		set_process(false)
		fps_label.text = ""

func _process(_delta: float) -> void:
	if DebugFlags.show_fps:
		fps_label.text = str(int(Engine.get_frames_per_second()))
	else:
		fps_label.text = ""

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_stop"):
		assert(false)
