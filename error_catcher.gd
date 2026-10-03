extends Logger
## Listens to every error Godot reports and hands it to ErrorLog.
## (Kept in its own file so older Godot versions without Logger don't break.)

var sink = null


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array) -> void:
	if sink == null:
		return
	var kind = "WARNING" if error_type == ERROR_TYPE_WARNING else "ERROR"
	var message = rationale if rationale != "" else code
	var where = "%s:%d in %s()" % [file, line, function]
	# For errors raised from scripts, point at the script line instead of Godot's C++ code
	if not file.begins_with("res://"):
		for bt in _script_backtraces:
			for i in range(bt.get_frame_count()):
				var f = bt.get_frame_file(i)
				if f != "" and not f.ends_with("ErrorLog.gd"):
					where = "%s:%d in %s()" % [f, bt.get_frame_line(i), bt.get_frame_function(i)]
					break
			break
	sink.record(kind, message, where)


func _log_message(_message: String, _error: bool) -> void:
	pass
