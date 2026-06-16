class_name SatPuzzle
extends RefCounted
## Boolean-satisfiability (CNF) locks used by SAT gates. We generate instances
## that are guaranteed satisfiable by planting a hidden assignment first, then
## forcing every clause to contain at least one literal true under it. Players
## toggle switch-nodes (false/true) to find *a* satisfying assignment; the gate
## verifies the formula algorithmically in real time. Validated in verify.py.
##
## Encoding:
##   literal  = Vector2i(var_index, want)   want in {0,1}: the value that
##              satisfies this literal.
##   clause   = Array[Vector2i]             disjunction (OR) of its literals.
##   formula  = Array[clause]               conjunction (AND) of its clauses.
## Variable indices are LOCAL (0..n-1); a gate maps them to nodes via gate.nodes.

## Deterministic generation from a seeded RNG. Returns
## { "clauses": Array, "planted": PackedByteArray }.
static func generate(rng: RandomNumberGenerator, n: int, m: int, k: int = 3) -> Dictionary:
	var planted := PackedByteArray()
	planted.resize(n)
	for i in range(n):
		planted[i] = 1 if rng.randf() < 0.5 else 0

	var clauses: Array = []
	var ksize := mini(k, n)
	for _c in range(m):
		# partial Fisher-Yates to choose `ksize` distinct variables
		var idx := range(n)
		for i in range(ksize):
			var j := rng.randi_range(i, n - 1)
			var tmp = idx[i]
			idx[i] = idx[j]
			idx[j] = tmp
		var clause: Array = []
		for t in range(ksize):
			var v: int = idx[t]
			var want := 1 if rng.randf() < 0.5 else 0
			clause.append(Vector2i(v, want))
		# guarantee the clause is satisfied by the planted assignment
		if not _clause_sat_planted(clause, planted):
			var fix := rng.randi_range(0, clause.size() - 1)
			var vv: int = clause[fix].x
			clause[fix] = Vector2i(vv, int(planted[vv]))
		clauses.append(clause)
	return { "clauses": clauses, "planted": planted }

static func _clause_sat_planted(clause: Array, planted: PackedByteArray) -> bool:
	for lit in clause:
		if int(lit.y) == int(planted[lit.x]):
			return true
	return false

## assignment: PackedByteArray of 0/1 per variable. True iff all clauses hold.
static func eval(clauses: Array, assignment: PackedByteArray) -> bool:
	for clause in clauses:
		if not clause_satisfied(clause, assignment):
			return false
	return true

static func clause_satisfied(clause: Array, assignment: PackedByteArray) -> bool:
	for lit in clause:
		var v: int = lit.x
		if v < 0 or v >= assignment.size():
			return false
		if int(assignment[v]) == int(lit.y):
			return true
	return false

## How many clauses are currently satisfied (for partial-progress UI).
static func satisfied_count(clauses: Array, assignment: PackedByteArray) -> int:
	var c := 0
	for clause in clauses:
		if clause_satisfied(clause, assignment):
			c += 1
	return c
