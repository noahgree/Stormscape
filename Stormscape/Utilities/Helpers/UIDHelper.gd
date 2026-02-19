class_name UIDHelper
## A class for generating uids for refcounted instances like resources.

static var uid_counter: int = 0 ## The uid counter.
static var multishot_uid_counter: int = 0 ## The multishot uid counter that gets reset on game load or at game start.

var multishot_reset_timer: Timer = TimerHelpers.create_repeating_autostart_timer(Globals.world_root, 100.0, func() -> void: multishot_uid_counter = 0, "MultishotIDResetTimer") ## The multishot counter reset daemon timer.


## Generates a session uid and returns it.
static func uid() -> int:
	uid_counter += 1
	return uid_counter

## Generates a multishot uid and returns it.
static func generate_multishot_uid()  -> int:
	multishot_uid_counter += 1
	return multishot_uid_counter
