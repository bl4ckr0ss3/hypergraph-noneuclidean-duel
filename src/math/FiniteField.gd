class_name FiniteField
extends RefCounted
## Modular arithmetic over GF(p) for prime p. Powers the "rotor gate" mechanic:
## a gate opens when the sum of the colour-indices of its nodes is congruent to
## a target value mod p. Inverse via Fermat's little theorem (p must be prime).
## Validated in tools/reference/verify.py.

static func mod(a: int, p: int) -> int:
	var r := a % p
	if r < 0:
		r += p
	return r

static func add(a: int, b: int, p: int) -> int:
	return mod(a + b, p)

static func sub(a: int, b: int, p: int) -> int:
	return mod(a - b, p)

static func mul(a: int, b: int, p: int) -> int:
	return mod(a * b, p)

static func powmod(base: int, exp: int, p: int) -> int:
	var result := 1
	var b := mod(base, p)
	var e := exp
	while e > 0:
		if e & 1:
			result = mod(result * b, p)
		b = mod(b * b, p)
		e >>= 1
	return result

## Multiplicative inverse of a in GF(p), p prime. Returns 0 if a == 0 (no inverse).
static func inv(a: int, p: int) -> int:
	if mod(a, p) == 0:
		return 0
	return powmod(a, p - 2, p)

static func is_prime(n: int) -> bool:
	if n < 2:
		return false
	var i := 2
	while i * i <= n:
		if n % i == 0:
			return false
		i += 1
	return true
