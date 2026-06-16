#!/usr/bin/env python3
"""
HYPERGRAPH reference verification harness.

This is NOT part of the game runtime. It is a standalone Python re-implementation
of the math/algorithm cores that are ported (1:1) to GDScript under src/. Because
Godot is not required to run this file, it lets us prove the *logic* is sound
before/independently of opening the project in the engine:

  * Poincare-disk hyperbolic geometry identities (Mobius isometries, distance,
    geodesic sampling, in-disk movement).
  * Graph k-coloring generation + verification.
  * SAT (CNF) lock generation with a planted satisfying assignment + verification.
  * Finite-field / modular-arithmetic helpers used by the rotor-gate mechanic.

Run:  python tools/reference/verify.py
Exit code 0 == all invariants hold.

The in-game determinism guarantee does NOT come from this file: it comes from both
peers running identical generation code seeded by Godot's RandomNumberGenerator
(PCG32), which is platform-deterministic. Here we only validate algorithm shape.
"""

from __future__ import annotations
import cmath
import math
import random
import sys

TOL = 1e-9
_failures: list[str] = []
_checks = 0


def check(cond: bool, msg: str) -> None:
    global _checks
    _checks += 1
    if not cond:
        _failures.append(msg)
        print(f"  [FAIL] {msg}")


def approx(a: complex | float, b: complex | float, tol: float = TOL) -> bool:
    return abs(a - b) <= tol


# ---------------------------------------------------------------------------
# 1. Hyperbolic geometry on the Poincare disk (z complex, |z| < 1)
# ---------------------------------------------------------------------------
# Mobius isometry sending point `a` to the origin:
#     phi_a(z) = (z - a) / (1 - conj(a) * z)
# Inverse (sends origin back to `a`):
#     phi_a^{-1}(w) = (w + a) / (1 + conj(a) * w)
# Hyperbolic distance:
#     d(u, v) = 2 * atanh(|phi_u(v)|)

def recenter(a: complex, z: complex) -> complex:
    return (z - a) / (1 - a.conjugate() * z)


def recenter_inv(a: complex, w: complex) -> complex:
    return (w + a) / (1 + a.conjugate() * w)


def hdist(u: complex, v: complex) -> float:
    return 2.0 * math.atanh(min(abs(recenter(u, v)), 1.0 - 1e-15))


def hdist_acosh(u: complex, v: complex) -> float:
    # Independent formula used as a cross-check of `hdist`.
    num = 2.0 * abs(u - v) ** 2
    den = (1.0 - abs(u) ** 2) * (1.0 - abs(v) ** 2)
    return math.acosh(1.0 + num / den)


def move(p: complex, direction: complex, step: float) -> complex:
    # Move from p along the geodesic in screen-space `direction` (unit) by
    # hyperbolic length `step`. In the player's recentred frame they sit at the
    # origin, so the target is tanh(step/2)*dir, mapped back to world space.
    d = direction / abs(direction)
    w = math.tanh(step / 2.0) * d
    return recenter_inv(p, w)


def geodesic_point(u: complex, v: complex, t: float) -> complex:
    # Point at hyperbolic arc-length fraction t in [0,1] along geodesic u->v.
    w = recenter(u, v)
    r = abs(w)
    if r < 1e-12:
        return u
    rt = math.tanh(t * math.atanh(min(r, 1.0 - 1e-15)))
    return recenter_inv(u, rt * (w / r))


def rand_disk(rng: random.Random, max_r: float = 0.85) -> complex:
    r = max_r * math.sqrt(rng.random())
    th = rng.uniform(0, 2 * math.pi)
    return cmath.rect(r, th)


def test_hyperbolic() -> None:
    print("[1] Hyperbolic geometry (Poincare disk)")
    rng = random.Random(1234)
    for _ in range(2000):
        a = rand_disk(rng)
        x = rand_disk(rng)
        y = rand_disk(rng)

        # recenter sends a -> 0
        check(approx(recenter(a, a), 0), "recenter(a,a) != 0")
        # inverse round-trips
        check(approx(recenter_inv(a, recenter(a, x)), x), "recenter inverse round-trip failed")
        # image stays strictly inside the disk
        check(abs(recenter(a, x)) < 1.0, "recenter pushed point outside disk")
        # Mobius map is an isometry: distances preserved under recenter
        check(approx(hdist(recenter(a, x), recenter(a, y)), hdist(x, y), 1e-7),
              "recenter is not a hyperbolic isometry")
        # two distance formulas agree
        check(approx(hdist(x, y), hdist_acosh(x, y), 1e-6), "atanh vs acosh distance mismatch")
        # symmetry
        check(approx(hdist(x, y), hdist(y, x), 1e-9), "distance not symmetric")

    # triangle inequality
    for _ in range(2000):
        a, b, c = rand_disk(rng), rand_disk(rng), rand_disk(rng)
        check(hdist(a, c) <= hdist(a, b) + hdist(b, c) + 1e-7, "triangle inequality violated")

    # movement: distance travelled == step, stays in disk
    for _ in range(2000):
        p = rand_disk(rng, 0.9)
        d = cmath.rect(1.0, rng.uniform(0, 2 * math.pi))
        step = rng.uniform(0.01, 1.5)
        q = move(p, d, step)
        check(abs(q) < 1.0, "movement left the disk")
        check(approx(hdist(p, q), step, 1e-6), "movement step length incorrect")

    # geodesic sampling: endpoints exact, monotone arc length
    for _ in range(1000):
        u, v = rand_disk(rng), rand_disk(rng)
        check(approx(geodesic_point(u, v, 0.0), u), "geodesic t=0 != u")
        check(approx(geodesic_point(u, v, 1.0), v, 1e-7), "geodesic t=1 != v")
        total = hdist(u, v)
        prev = 0.0
        ok = True
        for i in range(1, 11):
            t = i / 10.0
            dseg = hdist(u, geodesic_point(u, v, t))
            if dseg + 1e-6 < prev:
                ok = False
            prev = dseg
        check(ok, "geodesic arc length not monotone")
        check(approx(prev, total, 1e-6), "geodesic full length mismatch")
    print(f"    {2000*6 + 2000 + 2000*2 + 1000*3} checks done")


# ---------------------------------------------------------------------------
# 2. Graph k-coloring (gate-unlock constraint)
# ---------------------------------------------------------------------------

def gen_colorable_graph(rng: random.Random, n: int, k: int, density: float):
    # Plant a proper k-coloring, then only add edges between differently
    # planted-coloured nodes -> the instance is guaranteed k-colorable.
    planted = [rng.randrange(k) for _ in range(n)]
    edges = set()
    for i in range(n):
        for j in range(i + 1, n):
            if planted[i] != planted[j] and rng.random() < density:
                edges.add((i, j))
    return n, sorted(edges), planted


def verify_coloring(n: int, edges, coloring, k: int) -> bool:
    if len(coloring) != n:
        return False
    if any(c < 0 or c >= k for c in coloring):
        return False
    return all(coloring[u] != coloring[v] for (u, v) in edges)


def greedy_coloring(n: int, edges, k: int):
    adj = [set() for _ in range(n)]
    for u, v in edges:
        adj[u].add(v)
        adj[v].add(u)
    color = [-1] * n
    for v in sorted(range(n), key=lambda x: -len(adj[x])):  # largest-degree first
        used = {color[u] for u in adj[v] if color[u] >= 0}
        for c in range(k):
            if c not in used:
                color[v] = c
                break
        if color[v] == -1:
            return None
    return color


def test_coloring() -> None:
    print("[2] Graph k-coloring")
    rng = random.Random(99)
    for _ in range(500):
        k = rng.randint(2, 4)
        n = rng.randint(5, 14)
        nn, edges, planted = gen_colorable_graph(rng, n, k, 0.45)
        check(verify_coloring(nn, edges, planted, k), "planted coloring rejected by verifier")
        # break one edge -> must be rejected
        if edges:
            u, v = edges[0]
            bad = list(planted)
            bad[v] = bad[u]
            check(not verify_coloring(nn, edges, bad, k), "verifier accepted a monochromatic edge")
        # Greedy guarantees success with at most (max_degree + 1) colors -- that
        # is the real bound (NOT k+1; a k-colorable graph can have high degree).
        # In-game, greedy is only a "hint" generator; gate-unlock correctness
        # rests on verify_coloring, exercised above.
        deg = [0] * nn
        for u, v in edges:
            deg[u] += 1
            deg[v] += 1
        max_deg = max(deg) if edges else 0
        g = greedy_coloring(nn, edges, max_deg + 1)
        check(g is not None and verify_coloring(nn, edges, g, max_deg + 1),
              "greedy failed with (max_degree+1) colors")
    print("    500 instances ok")


# ---------------------------------------------------------------------------
# 3. SAT / CNF locks (constraint puzzle)
# ---------------------------------------------------------------------------
# Literal encoding: variable index i (0..n-1), polarity sign. We store a literal
# as (var, want) where want is the bool value that satisfies the literal.

def gen_sat(rng: random.Random, n: int, m: int, k: int = 3):
    planted = [rng.random() < 0.5 for _ in range(n)]
    clauses = []
    for _ in range(m):
        vars_ = rng.sample(range(n), min(k, n))
        clause = [(v, rng.random() < 0.5) for v in vars_]
        # force satisfiability under the planted assignment: at least one literal true
        if not any(want == planted[v] for (v, want) in clause):
            idx = rng.randrange(len(clause))
            v, _ = clause[idx]
            clause[idx] = (v, planted[v])
        clauses.append(clause)
    return n, clauses, planted


def sat_eval(clauses, assignment) -> bool:
    return all(any(assignment[v] == want for (v, want) in clause) for clause in clauses)


def sat_clause_satisfied(clause, assignment) -> bool:
    return any(assignment[v] == want for (v, want) in clause)


def test_sat() -> None:
    print("[3] SAT / CNF locks")
    rng = random.Random(7)
    for _ in range(1000):
        n = rng.randint(3, 8)
        m = rng.randint(2, 10)
        nn, clauses, planted = gen_sat(rng, n, m)
        check(sat_eval(clauses, planted), "planted assignment does not satisfy generated CNF")
        # the all-true and all-false assignments should not be trivially forced
        # (sanity: verifier returns a bool and is consistent with per-clause check)
        a = [rng.random() < 0.5 for _ in range(nn)]
        per = all(sat_clause_satisfied(c, a) for c in clauses)
        check(per == sat_eval(clauses, a), "per-clause check disagrees with full eval")
    print("    1000 instances ok")


# ---------------------------------------------------------------------------
# 4. Finite field GF(p) (rotor-gate modular mechanic)
# ---------------------------------------------------------------------------

def gf_inv(a: int, p: int) -> int:
    return pow(a % p, p - 2, p)  # Fermat, p prime


def test_finite_field() -> None:
    print("[4] Finite field GF(p)")
    for p in (5, 7, 11, 13, 97):
        for a in range(1, p):
            check((a * gf_inv(a, p)) % p == 1, f"GF({p}): {a} has wrong inverse")
        # additive rotor cycles back to identity after p steps
        x = 3 % p
        acc = 0
        for _ in range(p):
            acc = (acc + x) % p
        check(acc == (p * x) % p == 0, f"GF({p}) rotor did not cycle")
    print("    primes {5,7,11,13,97} ok")


# ---------------------------------------------------------------------------
# 5. Deterministic generation (conceptual: same seed -> same structure)
# ---------------------------------------------------------------------------

def test_determinism() -> None:
    print("[5] Deterministic generation (same seed -> same arena structure)")
    def build(seed: int):
        rng = random.Random(seed)
        n = 12
        pts = [rand_disk(rng) for _ in range(n)]
        _, edges, planted = gen_colorable_graph(rng, n, 3, 0.4)
        _, clauses, _ = gen_sat(rng, 6, 8)
        return pts, edges, planted, clauses
    a = build(0xC0FFEE)
    b = build(0xC0FFEE)
    c = build(0xBADBEEF)
    check(a == b, "same seed produced different arenas")
    check(a != c, "different seeds produced identical arenas")
    print("    seed reproducibility ok")


def main() -> int:
    print("=" * 60)
    print("HYPERGRAPH reference verification")
    print("=" * 60)
    test_hyperbolic()
    test_coloring()
    test_sat()
    test_finite_field()
    test_determinism()
    print("-" * 60)
    if _failures:
        print(f"RESULT: {len(_failures)} FAILURES out of {_checks} checks")
        for f in _failures[:20]:
            print("  -", f)
        return 1
    print(f"RESULT: ALL {_checks} CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
