extends RefCounted
class_name ItemInstance

@export var stats: ItemStats


# Unique Properties #
@export_storage var session_uid: int: ## The unique id for this resource instance that is relevant only for the current game load.
	## Sets the session uid based on the new value. If it is negative, it means we want to keep the old
	## suid and can simply absolute value it and decrement the UIDHelper's var since it will have
	## already triggered the increment once before on the duplication call. Otherwise, we generate a new one.
	set(new_value):
		if new_value >= 0:
			session_uid = UIDHelper.generate_session_uid()
		else:
			session_uid = abs(new_value)
			UIDHelper.session_uid_counter -= 1
