# HYPERGRAPH: Non-Euclidean Duel

A 2-player LAN game prototype set inside a **procedurally generated hyperbolic
arena** (Poincaré disk). Movement, sightlines, projectiles and the map itself
obey hyperbolic geometry, while the objectives are built out of real
**advanced-math / CS systems** — graph colouring, Boolean satisfiability (SAT),
modular arithmetic, and graph pathfinding — not flavour text.

Built with **Godot 4** (GDScript), open-source under the MIT license.

> This is an experimental indie prototype / vertical slice. It is meant to be
> weird, intelligent and playable — a real game loop with serious math under the
> hood, not a static visualization.

**Look & feel:** soft, cute, MapleStory‑flavoured pastel art — a cosy
"snow‑globe" hyperbolic world with chibi characters, bouncy slime monsters and
heart fragments, designed to be played co‑op with a friend. The deep math
(hyperbolic geometry, NP‑hard puzzle gates, deterministic generation) stays
under the hood; see **[RESEARCH.md](RESEARCH.md)** for the rigorous notes.

---

## The idea

Two players spawn into a hyperbolic disk. Scattered across it is a graph of
capturable **nodes** wired together by **geodesic edges**. Several **gates** lock
away **proof fragments**, and each gate is a genuine constraint problem the
players must satisfy by capturing and recolouring nodes under pressure — while a
graph-hunting **enemy** stalks them through the geometry.

- **Co-op:** collect a shared target of proof fragments before the timer ends.
- **Duel:** race — first player to the target wins (friendly fire on).

Because the world is hyperbolic, each player's client renders the disk
**re-centred on itself** (a Möbius isometry). You always sit at the centre and
see straight paths bend; your opponent and the enemies appear to swim through
curved space. It is the same shared world — just viewed through two different
isometries.

---

## The math / CS, as real systems

| System | Where | What it actually does |
|---|---|---|
| **Hyperbolic geometry** | `src/math/HyperMath.gd` | Poincaré-disk model. Möbius isometries for movement & camera, true hyperbolic distance, exponential map, geodesic sampling. Projectiles are exact geodesics. |
| **Procedural generation** | `src/world/ArenaGenerator.gd` | Seed → deterministic "tree-with-rings" hyperbolic graph. Same seed = same arena on both peers (only the seed crosses the wire). |
| **Hyperbolic tiling** | `src/world/HyperTiling.gd` | Regular `{7,3}` tessellation drawn as the background grid via reflection-group flood-fill. |
| **Graph pathfinding** | `src/world/Graph.gd` | Dijkstra over **hyperbolic** edge weights. The enemy AI routes with it, taking shortcuts "through the middle" that look non-Euclidean. |
| **Graph colouring** | `src/puzzle/GraphColoring.gd` | A gate opens only when its induced subgraph is a **proper colouring** (no monochromatic edge). Verifier + greedy hint + chromatic estimate. |
| **SAT / CNF** | `src/puzzle/SatPuzzle.gd` | A gate is a CNF formula; switch-nodes are boolean variables. Instances are generated with a planted solution (always satisfiable) and verified live. |
| **Finite fields / modular arithmetic** | `src/math/FiniteField.gd` | A "rotor gate" opens when the sum of its dial-nodes' colour indices is `≡ target (mod m)`. |

All of the above are validated numerically — see [Verification](#verification) —
and derived rigorously in **[RESEARCH.md](RESEARCH.md)**.

---

## Requirements

- **[Godot 4.3+](https://godotengine.org/download)** (the standard GDScript
  build; the .NET build also works). Godot is a free ~50 MB download and is **not
  bundled** with this repo.
- Windows is the primary target (resizable desktop window), but the project is
  engine-portable and also runs on Linux/macOS.
- *(Optional)* Python 3.10+ to run the reference math harness.

---

## Run it

### Open the project
1. Launch Godot 4, **Import** → select this folder's `project.godot`.
2. Press **F5** (Run Project).

### Test both players on one machine
1. In Godot's top menu: **Debug → Run Multiple Instances → 2 Instances**.
2. Press **F5**. Two windows open.
3. Window A: enter a callsign → **HOST LAN GAME**.
4. Window B: leave IP as `127.0.0.1` → **JOIN BY IP**.
5. Back in Window A's lobby, pick a mode → **START MATCH**.

### Two machines on the same LAN
1. On the host PC, find its IPv4 (`ipconfig` on Windows, e.g. `192.168.1.42`).
2. Host clicks **HOST LAN GAME**.
3. The other player types the host's IPv4 → **JOIN BY IP**.
4. Host picks a mode → **START MATCH**.

Default port is **24565/UDP** — allow Godot through the firewall if prompted.

### Command line (optional)
```bash
godot --path .                          # run
godot --headless --path . tests/TestRunner.tscn   # run logic tests, exits 0/1
```

---

## Controls

| Action | Key |
|---|---|
| Move | `WASD` / Arrow keys (screen-relative) |
| Aim | Mouse |
| Fire geodesic bolt | Left mouse button |
| Cycle carried colour | `Q` |
| Capture node / collect fragment | `E` or `Space` |
| Toggle debug overlay | `F3` |
| Leave to menu | `Esc` |

**Capturing:** stand next to a node and press `E`. Normal nodes are painted with
your carried colour (`Q` to change it). SAT **switch-nodes** toggle false/true;
modular **dial-nodes** cycle through the palette. Watch a gate's status line at
the bottom of the screen and the **F3** overlay to see exactly what each gate
still needs.

---

## Project architecture

No giant monolith — systems are separated by responsibility:

```
hypergraph/
├─ project.godot              # window (resizable), autoloads, render config
├─ scenes/Main.tscn           # tiny entry scene -> src/Main.gd builds the rest in code
├─ src/
│  ├─ Main.gd                 # orchestrator: MENU/LOBBY/PLAYING/ROUND_OVER, wires signals
│  ├─ autoload/
│  │  ├─ Log.gd               # logging + ring buffer for the debug overlay
│  │  ├─ GameConfig.gd        # constants + runtime InputMap registration + palette
│  │  ├─ Net.gd               # LAN host/join, seed+roster handshake, disconnects
│  │  └─ GameState.gd         # match/round state machine, scores, timer, win check
│  ├─ math/
│  │  ├─ HyperMath.gd         # Poincaré-disk hyperbolic geometry (the core)
│  │  └─ FiniteField.gd       # GF(p) / modular arithmetic
│  ├─ world/
│  │  ├─ Graph.gd             # graph + Dijkstra over hyperbolic weights
│  │  ├─ HyperTiling.gd       # {p,q} background tessellation
│  │  ├─ ArenaData.gd         # immutable generated-arena description
│  │  └─ ArenaGenerator.gd    # seed -> ArenaData (deterministic)
│  ├─ puzzle/
│  │  ├─ GraphColoring.gd     # colouring constraint: verify / greedy / estimate
│  │  └─ SatPuzzle.gd         # CNF generation (planted-SAT) + verification
│  ├─ gameplay/
│  │  ├─ HPlayer.gd           # networked player data
│  │  ├─ Projectile.gd        # geodesic bolt
│  │  ├─ ProofFragment.gd     # collectible
│  │  └─ Gate.gd              # COLORING / SAT / MODULAR lock + verifier
│  ├─ enemy/
│  │  └─ GraphHunter.gd       # Dijkstra-routing pursuer
│  ├─ render/
│  │  └─ PoincareView.gd      # World node: hyperbolic renderer + state + RPC surface
│  └─ ui/
│     ├─ MainMenu.gd          # host/join + lobby
│     ├─ HUD.gd               # scores/timer/objective/hint/result
│     └─ DebugOverlay.gd      # seed, graph/puzzle stats, live state (F3)
├─ tests/                     # headless GDScript logic tests
└─ tools/reference/verify.py  # standalone Python validation of the math/algorithms
```

**Phase mapping** (the build order): F1 menu+window+movement → `MainMenu/Main/HPlayer`;
F2 LAN → `Net`; F3 generation → `ArenaGenerator/Graph/HyperTiling`; F4 hyperbolic
render → `HyperMath/PoincareView`; F5 graph capture/colouring → `Gate/GraphColoring`;
F6 constraint gates → `SatPuzzle/FiniteField/Gate`; F7 enemy+objective →
`GraphHunter/GameState`; F8 polish → UI + debug overlay + README.

---

## Networking & determinism model

This is a deliberate, documented set of tradeoffs (the brief asked for "deterministic
*or mostly* deterministic" and "simple but functional"):

- **Transport:** Godot high-level multiplayer over **ENet** (client/server).
  Host is peer `1` and also a player. Scoped to **2 players**, so each peer is
  directly connected to the other and broadcasts need no relay.
- **World is fully deterministic:** only the **seed** is sent; both peers run the
  identical `ArenaGenerator` seeded by Godot's platform-deterministic
  `RandomNumberGenerator` (PCG32) and produce byte-identical arenas.
- **Runtime is server-authoritative**, not lockstep: the host simulates enemies,
  resolves all combat, owns node/gate/fragment/round state and broadcasts it.
  Clients send their own player state and *request* captures/collects; the host
  validates and echoes the result. This is far more robust than fragile lockstep
  for a real-time prototype.
- **Player movement** is client-authoritative and relayed (low-latency feel). It
  is **not** anti-cheat hardened — appropriate for friendly LAN play, not ranked.

See the header comment in `src/render/PoincareView.gd` for the full RPC surface.

---

## Verification

Because the heart of the game is mathematical, the algorithms are validated two
ways.

**1. Python reference harness** (no Godot needed):
```bash
python tools/reference/verify.py
```
Re-implements the hyperbolic geometry, graph colouring, SAT generation, and
modular arithmetic and asserts their invariants over thousands of random cases
(Möbius maps are isometries, the two distance formulas agree, movement stays in
the disk and travels the requested length, geodesic endpoints are exact, planted
SAT/colourings verify, etc.). Current run: **25,631 checks pass**.

**2. In-engine GDScript tests** (exercise the real ports):
```bash
godot --headless --path . tests/TestRunner.tscn
```
Mirrors the harness against the actual `src/` code and checks
`ArenaGenerator` determinism. Exits `0` on success.

---

## Tuning

Most gameplay knobs live in `src/autoload/GameConfig.gd` (player/enemy/projectile
speeds and ranges, fire cooldown, round length, fragment target, palette).
Arena shape lives in `src/world/ArenaGenerator.gd` (`LAYERS`, `LAYER_COUNTS`,
`RING_STEP`, `RING_PROB`, `K_COLORS`).

---

## Known limitations / honest tradeoffs

- **No engine bundled.** You must install Godot 4.3+ to open/run the project.
- **2 players only.** The broadcast model assumes a direct host↔client link;
  3+ players would need the host to relay.
- **Background tiling is approximate.** The `{p,q}` reflection flood-fill
  accumulates numerical drift a few layers out; since it only draws the backdrop,
  errors are cosmetic and tiles that drift outside the disk are dropped.
- **Movement isn't authoritative.** Fine for co-op / friendly duels, not cheat-proof.
- **Chromatic number is *estimated*** with greedy colouring (the real chromatic
  number is NP-hard); it is used only for the debug readout, never for gate logic.

---

## Roadmap

- Spectator/replay from a recorded seed + input stream (enables true lockstep).
- More gate archetypes: exact-cover (Knuth's Algorithm X), small Hamiltonian/TSP
  routes, knot-crossing reduction.
- Hyperbolic minimap and node-link "rewiring" mechanic (cut/add edges live).
- Bots to play solo; more enemy archetypes that exploit holonomy.
- Windows `.exe` export preset + CI.

---

## License

MIT — see [LICENSE](LICENSE).
