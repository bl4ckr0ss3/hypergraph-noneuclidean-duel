extends Node
## Match/round state machine + scores + timer.
## Autoload singleton: `GameState`.
##
## These values are authoritative on the host and pushed to the client as
## snapshots by the World node; the client treats them as read-only display
## state. UI reacts to the signals below.

signal state_changed(new_state: int)
signal score_changed
signal timer_changed(seconds_left: float)
signal round_over(result: String)

enum S { MENU, LOBBY, PLAYING, ROUND_OVER }
enum Mode { CO_OP, DUEL }

var state: int = S.MENU
var mode: int = Mode.CO_OP
var seconds_left := 0.0
var fragment_target := GameConfig.FRAGMENT_TARGET
var scores := {0: 0, 1: 0}   # slot -> fragments collected
var team_total := 0
var last_result := ""

func set_state(s: int) -> void:
	if state == s:
		return
	state = s
	state_changed.emit(s)

func reset_match(m: int) -> void:
	mode = m
	seconds_left = GameConfig.ROUND_SECONDS
	fragment_target = GameConfig.FRAGMENT_TARGET
	scores = {0: 0, 1: 0}
	team_total = 0
	last_result = ""
	score_changed.emit()
	timer_changed.emit(seconds_left)

func add_score(slot: int, amount: int = 1) -> void:
	scores[slot] = int(scores.get(slot, 0)) + amount
	team_total += amount
	score_changed.emit()

func tick_timer(delta: float) -> void:
	if state != S.PLAYING:
		return
	seconds_left = maxf(0.0, seconds_left - delta)
	timer_changed.emit(seconds_left)

## Apply a snapshot received from the host (client side).
func apply_snapshot(snap: Dictionary) -> void:
	seconds_left = float(snap.get("t", seconds_left))
	scores = snap.get("scores", scores)
	team_total = int(snap.get("team", team_total))
	score_changed.emit()
	timer_changed.emit(seconds_left)

func make_snapshot() -> Dictionary:
	return { "t": seconds_left, "scores": scores, "team": team_total }

## Returns "" while the round is ongoing, otherwise a human-readable result.
func check_win() -> String:
	if mode == Mode.CO_OP:
		if team_total >= fragment_target:
			return "TEAM CLEARED THE ARENA"
		if seconds_left <= 0.0:
			return "TIME UP - THE ARENA HOLDS"
	else:
		if int(scores.get(0, 0)) >= fragment_target:
			return "PLAYER 1 WINS"
		if int(scores.get(1, 0)) >= fragment_target:
			return "PLAYER 2 WINS"
		if seconds_left <= 0.0:
			var a := int(scores.get(0, 0))
			var b := int(scores.get(1, 0))
			if a == b:
				return "DRAW"
			return "PLAYER 1 WINS" if a > b else "PLAYER 2 WINS"
	return ""

func declare_over(result: String) -> void:
	last_result = result
	set_state(S.ROUND_OVER)
	round_over.emit(result)
