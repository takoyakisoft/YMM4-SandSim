# GPU solid physics design

## Goal

YMM4-SandSimの既存D3D11セルオートマトンを維持したまま、従来は固定されていた固体素材を、CPU readbackなしで落下・回転・衝突させる。

## Solver

- Representation: 1 solid source cell = 1 GPU particle (`float4`: current xy, previous zw).
- Topology: source imageの8近傍接続を固定トポロジとして使用する。CPU connected-components / contour extractionは行わない。
- Integration: damped Verlet + gravity, fixed `1/120 s` substep.
- Constraints: XPBD distance constraints. Horizontal/vertical rest length = 1, diagonal rest length = sqrt(2).
- Scheduling: 2×2 blockを4 parity phasesで処理し、1 dispatch内では書き込み先を重複させない。水平・垂直辺は重複位相を除外し、斜辺を含む8近傍の各edgeをsolver反復あたり1回だけ解く。奇数論理サイズの最終行・最終列も、偶数パディングセルを使って拘束対象にする。
- Collision broadphase: logical cell gridそのものを使用する。continuous positionをgridへ投影し、`InterlockedMin`で各cellのownerを決定する。
- Collision response: owner競合の敗者をprevious positionへrollbackし、そのsubstepの速度を0にする。2回resolveしたあと、最終occupancyを構築する。
- CA coupling: powder/liquid/gas passはrigid occupancyを移動不可セルとして参照する。rendererも同じoccupancyからrigid source idを逆引きする。

## Why XPBD instead of a direct AVBD port

AVBDはGPU並列剛体に適した手法だが、添付demo2dのCPU実装にはBody/contactリストと、単純な全組み合わせcollision discoveryがある。YMM4-SandSimはすでに規則格子を持つため、固定トポロジのXPBDであれば、可変長GPUデータ構造やCPU同期を増やさずD3D11/SM5へ載せられる。

## Determinism

- 同じsource cell idは、常に同じowner idを持つ。
- occupancy競合はatomic minimumで解決し、処理順に依存しない。
- solver dispatch順とphase順は固定する。
- シーク/resetは既存timeline policyを通し、rigid stateもsourceから再初期化する。

## Current interaction boundary

Rigid occupancyはCA移動の障害物になる。粉体と、CAで生成された固定素材はrigid側の支持面として扱う。液体・気体がrigid occupancyの下にある場合はCA状態を凍結して保持し、rigid通過によって質量が消えないようにする。

GPU上で次の双方向連携を行う。

- rigidセルは、重なっている液体の密度から簡易浮力と流体抵抗を受ける。
- 火・残り火・溶岩、酸、海水を重なりセルと8近傍から参照し、固定素材の燃焼・融解・腐食・銅の酸化を処理する。
- CA反応で生成された石・氷などの固定素材は、対応するrigid source slotが空いていればXPBDへ昇格する。
- 反応後のoccupancy再構築は、新規ownership競合を作らないためclaim-only passとする。同じCA iterationで高価なcollision resolveを二重実行しない。

液体の体積押し出し・圧力、粉体をrigidが押し退ける処理、完全な流体-固体接触、任意位置での新規rigid particle poolは、まだモデル化していない。

## References used as design input

- FallingSandJava: moving solid elements are projected back into a cellular matrix. Source code is not copied or translated.
- avbd-demo2d: MIT-licensed 2D reference implementation used to inspect iterative constrained rigid-body solver organization. No AVBD source is copied into these shaders.

## Material-specific XPBD properties

The rigid lattice no longer treats every fixed material as the same solid.
`SandBehavior.hlsli` supplies four behavior parameters for each fixed material:

- **Density** -> inverse mass used by XPBD projection. Gravity acceleration itself remains mass-independent.
- **Compliance** -> bond softness. Metals/minerals are stiff; wax and organics deform visibly.
- **Velocity retention** -> material damping layered on the global damping setting.
- **Tensile break strain** -> a persistent E/S/SE/SW bond fracture threshold.

Mixed-material bonds use the softer compliance and 70% of the weaker material's break strain. This makes interfaces, for example wood-to-stone, easier to tear than homogeneous material without introducing a CPU body graph.

Representative behavior:

| Group | Examples | Behavior |
| --- | --- | --- |
| Dense ductile | Metal, copper, gold | Very stiff, heavy in constraints, hard to tear |
| Hard brittle | Stone, brick, quartz, ruby | Stiff, moderate/low tensile fracture |
| Very brittle | Cobalt glass, ice | Stiff, fractures at small tensile strain |
| Porous/brittle | Sandstone, coral, permafrost | Less stiff and easier to fracture |
| Fibrous | Wood, amber | Flexible, moderately strong |
| Soft | Pink wax | Highly compliant, high strain before tearing |
| Organic | Plant, grass, moss, leaf, algae | Light, highly compliant, strongly damped |

A broken bond is represented by a large persistent marker in the existing `RigidLambda` texture. Normal XPBD multipliers are cleared each substep; broken markers are preserved, so no extra bond texture or GPU->CPU readback is needed. A full `ClearAndRebuild` restores all bonds. Emitter restamping preserves fracture history for existing rigid source particles to avoid asymmetric partial healing.

## CA parameter consistency

- 液体のCA浮沈順は`FluidProperties().x`と同じ順序（液体窒素 < 油 < 水 < 海水 < インク < 酸 < スライム < 溶岩）に統一する。密度差による交換は縦・斜め方向だけで行い、横方向は空セルへの拡散だけにして、界面の左右往復を防ぐ。
- 汎用インクは油と同じ可燃物として扱わず、油だけを高可燃液体とする。
- 塩とピンク岩塩は、水・海水中で同じ低確率の溶解挙動を持たせ、油中では溶解させない。

## CA boundary rules

- Backing textureは偶数サイズへ丸めるが、論理グリッド外のパディングセルだけを固定壁として扱う。奇数幅・高さの最終実セルをブロック単位で凍結しない。
- `1 × N` / `N × 1`では2×2 Margolus分割を使わず、2位相の1D pair updateで寿命・反応・縦交換・横拡散を継続する。`1 × 1`でも寿命更新を継続する。
- shifted phaseで2×2 blockの外側になる境界単独セルも、単純コピーではなく寿命を1回進める。これにより、火・煙・蒸気・残り火の寿命が画像端だけ半速になることを防ぐ。rigid occupancy下のCA状態だけは意図的に凍結する。
- 静的契約テストでは、1～9セルの偶数・奇数・退化グリッドについて、各CAフェーズで全実セルがちょうど1回書き込まれることを検査する。

## Explosion coupling

Explosions have two seed paths. Gunpowder ignition sets a one-shot metadata event. The optional YMM4 `VideoEffectController` samples an item-local center position and trigger frame, then seeds one pressure cell on the first simulation iteration that crosses the trigger. The second preview handle edits the pressure radius in cell units. Both paths converge in `SandExplosionUpdate`, which advances a GPU-resident scalar pressure field over the existing cell grid; there is no CPU body/contact/event list or GPU readback.

Timeline evaluation is classified explicitly as `Initial`, `Continuous`, or `Random`. Initial access builds state from the current input and applies only the configured bounded warm-up. Continuous access includes both a repeated evaluation of the same frame (a zero-delta no-op unless parameters invalidate it) and the next sequential frame (one advance). Random access, including seeks and rewinds, discards irreversible GPU state and rebuilds from the current input with the same bounded warm-up; it never replays from the item start.

- Pressure enters gas almost freely, is damped by liquid/powder, and is strongly attenuated by rigid material. Pink wax uses its dedicated soft-solid transmission before the generic organic branch.
- The CA reads pressure gradients after ordinary flow and can swap movable material toward lower pressure.
- `SandRigidIntegrate` reads the same gradient as an impulse. A sufficiently sharp impulse can persistently mark XPBD bonds as broken.
- Dense/thick walls therefore shield the region behind them while brittle surfaces can still fracture. Diagonal propagation also checks the two cardinal side cells, preventing a wave from teleporting through a fully closed 90-degree corner.
- Explosion pressure also seeds the render-time light field, synchronizing flash and physical response.
- A newly ignited gunpowder cell keeps its one-shot explosion event fixed in place until the pressure pass consumes it; CA reactions and all movement/swap paths treat that event-bearing cell as temporarily immovable.

## Lighting and shadow transport

The render-time light field is a GPU-resident RGB max-propagation approximation over the same logical cell grid. Fire, ember, lava, sea lantern and explosion pressure seed the field. Material transmission attenuates outgoing light, so fixed surfaces can receive light while reducing transport through their interior.

- Gas/water are relatively transmissive; smoke/ink/powder attenuate strongly.
- Cobalt glass, ice, quartz, pink wax, rose quartz, fluorite, amethyst and amber have explicit translucent-solid transmission before the generic fixed-solid fallback.
- Diagonal propagation checks both cardinal side cells and only takes the less-blocked route, preventing direct leakage through a closed corner while still allowing light to bend around an open side.
- This is not ray tracing or additive multi-light radiative transport; it is a deterministic screen-space cell approximation with bounded dispatch count.

## GPU allocation guard

Simulation buffers are allocated by feature instead of reserving the worst case unconditionally: CA state is 16 bytes/cell, XPBD adds 44, explosion pressure adds 8, and lighting adds 8, for a 76-byte/cell worst case. The state budget is about 304 MiB, and the allocator computes the allowed padded cell count from the enabled feature set. CA-only or partially enabled configurations therefore use substantially less VRAM. The processor rejects an oversized state before D3D11 allocation, and `EnsureResources` repeats the same byte-budget check defensively.
