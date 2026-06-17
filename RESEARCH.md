# HYPERGRAPH — Mathematical Notes

A rigorous companion to the code. Everything here is *implemented* in `src/` and
numerically checked by `tools/reference/verify.py` (25,631 assertions) and the
in‑engine tests under `tests/`. Nothing below claims to solve an open problem;
the point is to use hard, classical mathematics as honest game systems.

Notation: the open unit disk is $\mathbb D=\{z\in\mathbb C:|z|<1\}$; we freely
identify $\mathbb R^2$ with $\mathbb C$ (a `Vector2` `(x,y)` is $x+iy$).

---

## 1. The Poincaré disk model

We model the hyperbolic plane $\mathbb H^2$ as $(\mathbb D, g)$ with the
conformal Riemannian metric of constant curvature $K=-1$:

$$ ds^2 \;=\; \frac{4\,(dx^2+dy^2)}{(1-|z|^2)^2}. $$

The induced distance has the closed form used throughout the engine
(`HyperMath.hdist`):

$$ d(u,v) \;=\; 2\,\operatorname{artanh}\!\left|\frac{u-v}{1-\bar u\,v}\right|
        \;=\; \operatorname{arcosh}\!\left(1+\frac{2|u-v|^2}{(1-|u|^2)(1-|v|^2)}\right). $$

The two forms are algebraically equal; `verify.py` checks they agree to
$10^{-6}$ over thousands of random pairs, and that $d$ is symmetric and obeys the
triangle inequality.

### 1.1 Isometry group

The orientation‑preserving isometries of $\mathbb D$ are the disk‑preserving
Möbius transformations

$$ z \;\longmapsto\; e^{i\theta}\,\frac{z-a}{1-\bar a\,z},\qquad a\in\mathbb D,\ \theta\in\mathbb R, $$

which form the group $\mathrm{PSU}(1,1)\cong \mathrm{PSL}(2,\mathbb R)$. Writing a
transformation as a matrix $\begin{psmallmatrix}\alpha&\beta\\\bar\beta&\bar\alpha\end{psmallmatrix}$
with $|\alpha|^2-|\beta|^2=1$ exhibits the group as $\mathrm{SU}(1,1)$ modulo
$\pm I$. Two special cases drive the game:

* **Recentre** $\varphi_a(z)=\dfrac{z-a}{1-\bar a z}$ (`HyperMath.recenter`) sends
  $a\mapsto 0$. Its inverse is $\varphi_a^{-1}(w)=\dfrac{w+a}{1+\bar a w}$.
  `verify.py` confirms $\varphi_a$ is a hyperbolic isometry by checking
  $d(\varphi_a x,\varphi_a y)=d(x,y)$.
* Each **client camera** is exactly the isometry $\varphi_{p}$ for that client's
  own player position $p$. This is why both players see a *correct* shared world
  through *different* isometries — the defining trick of playable hyperbolic
  games (cf. HyperRogue).

### 1.2 Geodesics and the exponential map

Geodesics of $\mathbb D$ are diameters and arcs of circles meeting
$\partial\mathbb D$ orthogonally. The unit‑speed geodesic leaving the origin in
direction $e^{i\phi}$ is $t\mapsto \tanh(t/2)\,e^{i\phi}$, so the **exponential
map** at an arbitrary base point $p$ is

$$ \exp_p(s\,\hat d)\;=\;\varphi_p^{-1}\!\big(\tanh(s/2)\,\hat d\big) $$

(`HyperMath.from_polar`). Player/enemy locomotion (`HyperMath.move`) is one Euler
step of this: travelling hyperbolic length $s$ along the geodesic in the player's
own frame. `verify.py` checks the realised step length equals $s$ to $10^{-6}$
and that motion never leaves $\mathbb D$.

**Geodesic bolts.** A projectile stores its origin $O$ and a unit launch
direction $u$ in $O$'s frame; its position at arc length $s$ is simply
$\exp_O(s\,u)$. No parallel transport is needed and the path renders as a true
circular arc (`Projectile.pos`).

---

## 2. Rendering geodesics exactly (the orthogonal circle)

Drawing a geodesic between disk points $A,B$ (already in camera frame) reduces to
finding the circle through $A,B$ orthogonal to $\partial\mathbb D$. If its centre
is $C$ and radius $R$, orthogonality to the unit circle means $|C|^2=1+R^2$, and
$R=|C-A|=|C-B|$. Expanding $|C|^2-|C-A|^2=1$ gives the **linear** system

$$ C\cdot A=\tfrac{1+|A|^2}{2},\qquad C\cdot B=\tfrac{1+|B|^2}{2}, $$

solved in closed form (Cramer) in `PoincareView._geo`:

$$ C=\frac{1}{A_xB_y-A_yB_x}\Big(c_aB_y-c_bA_y,\;A_xc_b-B_xc_a\Big),\quad c_a=\tfrac{1+|A|^2}2,\ c_b=\tfrac{1+|B|^2}2. $$

We then emit a single `draw_arc` along the minor arc (the one inside the disk).
When $A,B,0$ are collinear the determinant vanishes and the geodesic is a
diameter, drawn as a straight chord. This replaced a 12‑sample polyline per edge
(≈2,600 transcendental evaluations/frame) and is both *exact* and ~10× cheaper —
the core of the framerate fix. The same circle‑inversion underlies the tiling
(§4): reflection in a geodesic is inversion in its orthogonal circle,
$z\mapsto C+R^2\frac{z-C}{|z-C|^2}$ (`HyperTiling._reflect_point`).

---

## 3. Why the arena feels strange: exponential growth

A hyperbolic disk of radius $r$ has circumference $2\pi\sinh r$ and area
$2\pi(\cosh r-1)$ — both grow like $e^{r}$. The arena generator
(`ArenaGenerator`) places nodes on concentric hyperbolic circles of radius
$\ell\cdot\Delta$ (layer $\ell$) using the exponential map, with per‑layer counts
chosen to track this exponential circumference. Consequences the player feels:

* there is "too much room" near the boundary; far nodes are tiny and many;
* shortest paths often cut *through the centre* rather than around — exploited by
  the enemy AI (§6);
* the recentre camera makes straight motion appear to curve (holonomy).

---

## 4. Regular {p,q} tilings and triangle groups

A regular tiling $\{p,q\}$ ($p$‑gons, $q$ around each vertex) is hyperbolic iff
$\tfrac1p+\tfrac1q<\tfrac12$. The central tile's Euclidean circumradius in
$\mathbb D$ is

$$ r_0=\sqrt{\frac{\cos\!\big(\tfrac{\pi}{p}+\tfrac{\pi}{q}\big)}{\cos\!\big(\tfrac{\pi}{p}-\tfrac{\pi}{q}\big)}}, $$

derived by placing a right‑angled fundamental triangle of the $(2,p,q)$ triangle
reflection group and using the hyperbolic law of cosines. `HyperTiling` builds
the central $p$‑gon at radius $r_0$, then flood‑fills outward by reflecting whole
tiles across their edges (a breadth‑first orbit under the reflection group),
de‑duplicating by rounded centroid. The background uses $\{7,3\}$. This is an
*approximation*: floating‑point drift accumulates a few layers out, so it is used
for decoration only and capped; gameplay structure lives in the separate graph.

---

## 5. Puzzle gates as classical hard problems

Each gate is a constraint that is *verified algorithmically every tick*. The
generators plant a solution so instances are always satisfiable, but *finding* a
solution in general is hard — that is the intended pressure.

### 5.1 Colouring gate — `GraphColoring`
Open iff the induced subgraph over the gate's nodes is **properly $k$‑coloured**
(no monochromatic edge). Deciding $k$‑colourability is **NP‑complete** for
$k\ge3$ (Karp 1972). We expose a greedy heuristic (Welsh–Powell, largest‑degree
first) using at most $\Delta+1$ colours as a *hint*, and a greedy
chromatic‑number *estimate* for the debug overlay — never for gate logic, which
rests only on the polynomial‑time verifier.

### 5.2 SAT gate — `SatPuzzle`
Open iff a CNF formula is satisfied by the current switch‑node truth values.
Boolean satisfiability is the canonical **NP‑complete** problem (Cook 1971,
Levin 1973). Instances are generated by planting a random assignment and forcing
each $k$‑clause to contain a literal true under it, guaranteeing satisfiability;
`verify.py` confirms the planted assignment satisfies every generated formula
over 1,000 random instances.

### 5.3 Rotor gate — `FiniteField`
Open iff $\sum_i c_i \equiv t \pmod m$ over the dial nodes' colour indices,
i.e. a linear equation in the additive group $\mathbb Z/m\mathbb Z$. With $m$
prime this is the additive structure of the finite field $\mathrm{GF}(m)$;
`FiniteField` also implements multiplicative inverses via Fermat
($a^{-1}=a^{m-2}$), validated for $m\in\{5,7,11,13,97\}$.

(Road‑mapped: exact cover via Knuth's Algorithm X / Dancing Links, and a
Hamiltonian/TSP route gate — both NP‑complete, same plant‑then‑verify pattern.)

---

## 6. Enemy AI: shortest paths in the hyperbolic metric

The "graph hunter" runs **Dijkstra** (`Graph.dijkstra`, $O(V^2)$, $V$ small and
fixed so it is deterministic) where each edge weight is the *true hyperbolic
length* $d(u,v)$ of its geodesic. Because the metric rewards routes through the
dense centre, the hunter takes paths that look like non‑Euclidean shortcuts
rather than Euclidean straight lines. It re‑plans on a fixed think interval and
walks geodesic segments between consecutive path nodes.

---

## 7. Determinism and networking

* **World generation is exactly reproducible.** Only a 32‑bit seed crosses the
  wire; both peers run identical generation seeded by Godot's
  `RandomNumberGenerator` (PCG32, a platform‑deterministic permuted‑congruential
  generator, O'Neill 2014). Identical code + identical seed + identical IEEE‑754
  float arithmetic ⇒ byte‑identical arenas. The in‑engine test asserts this.
* **Runtime is server‑authoritative, not lockstep.** The host simulates enemies,
  resolves combat and owns node/gate/fragment/round state; clients send their own
  player state and *request* captures/collects which the host validates and
  echoes. Remote entities are position‑interpolated for smoothness. This is the
  robust, low‑latency choice for a 2‑player LAN prototype; the tradeoff (movement
  is not cheat‑proof) is acceptable for friendly co‑op.

---

## 8. Numerical hygiene

All maps clamp to the open disk ($|z|\le 1-10^{-5}$) to avoid the coordinate
singularity at $\partial\mathbb D$; $\operatorname{artanh}$ is evaluated as
$\tfrac12\ln\frac{1+x}{1-x}$ on a clamped argument. The hot render path inlines
the Möbius recentre to avoid per‑call overhead. These choices keep the
simulation stable arbitrarily far from the origin in hyperbolic distance even
though Euclidean coordinates crowd toward the rim.

---

## References

1. J. W. Cannon, W. J. Floyd, R. Kenyon, W. R. Parry, *Hyperbolic Geometry*, in
   *Flavors of Geometry*, MSRI 31 (1997).
2. A. F. Beardon, *The Geometry of Discrete Groups*, Springer GTM 91.
3. H. S. M. Coxeter, *Crystal symmetry and its generalizations* (regular
   honeycombs / triangle groups).
4. S. A. Cook, *The complexity of theorem‑proving procedures* (1971);
   R. M. Karp, *Reducibility among combinatorial problems* (1972).
5. D. E. Knuth, *Dancing Links* (2000).
6. M. E. O'Neill, *PCG: A Family of Simple Fast Space‑Efficient Statistically
   Good Algorithms for Random Number Generation* (2014).
7. HyperRogue (Kopczyński et al.) — prior art for playable hyperbolic rendering.
