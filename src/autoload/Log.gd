extends Node
## Lightweight logging with a ring buffer that the debug overlay can read.
## Autoload singleton: `Log`.

signal line_added(line: String)

const MAX_LINES := 200
var _lines: PackedStringArray = PackedStringArray()

func _push(level: String, msg: String) -> void:
	var t := float(Time.get_ticks_msec()) / 1000.0
	var line := "[%7.2f] %s %s" % [t, level, msg]
	_lines.append(line)
	if _lines.size() > MAX_LINES:
		_lines.remove_at(0)
	print(line)
	line_added.emit(line)

func info(msg: String) -> void: _push("INFO", msg)
func warn(msg: String) -> void: _push("WARN", msg)
func error(msg: String) -> void: _push("ERR ", msg)
func net(msg: String) -> void: _push("NET ", msg)

## Most recent `n` lines, oldest first.
func recent(n: int = 12) -> PackedStringArray:
	var start := maxi(0, _lines.size() - n)
	return _lines.slice(start)
