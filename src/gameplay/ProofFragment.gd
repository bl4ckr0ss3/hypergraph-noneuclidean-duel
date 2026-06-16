class_name ProofFragment
extends RefCounted
## A collectible "proof fragment". Free fragments can be grabbed immediately;
## gated fragments only become collectible once their guarding gate is open.

var id: int = 0
var pos: Vector2 = Vector2.ZERO
var gate_id: int = -1        # -1 == free (no gate)
var collected: bool = false
var collected_by: int = -1   # slot that collected it

func is_available(gates: Array) -> bool:
	if collected:
		return false
	if gate_id < 0:
		return true
	return gates[gate_id].is_open
