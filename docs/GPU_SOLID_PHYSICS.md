# GPU固体物理の設計

## 目的

YMM4-SandSimには、Direct3D 11上で動く既存のセルオートマトンがあります。
固定素材にも動きを与えるためにCPU剛体へ読み戻すと、GPUとCPUの同期や別の物理世界が必要になります。

そこで固定素材をGPU上のセル格子から切り離し、連続座標を持つ粒子として落下、回転、衝突させます。
既存のCAとの接続もGPU上で維持し、CPU readbackは行いません。

## ソルバー構成

- **表現**：1個の固体source cellを1個のGPU particleとして保持します。
  状態は`float4`で、現在位置を`xy`、直前位置を`zw`へ格納します。
- **Body同定**：GPU Connected Componentsで、同一素材・4近傍・未破断bondでつながっているsource cell群へ同じBody IDを付けます。
  離れた同素材と異素材は必ず別Bodyです。CPU readbackやCPU body graphは使用しません。
- **トポロジ**：XPBDの候補edge自体はsource imageの8近傍ですが、同じConnected Body IDの端点だけをconstraintとして解きます。
- **積分**：damped Verletとgravityを使用し、substepは固定`1/120 s`です。
- **制約**：XPBD distance constraintを使用します。
  水平と垂直のrest lengthは1、斜めは`sqrt(2)`です。
- **スケジューリング**：2×2 blockを4種類のparity phaseで処理し、1 dispatch内では書き込み先を重複させません。
  水平辺と垂直辺は重複位相を除外し、斜辺を含む8近傍の各edgeをsolver反復あたり1回だけ解きます。
  奇数の論理サイズでは、最終行と最終列も偶数パディングセルを使って拘束対象にします。
- **衝突のbroadphase**：論理cell gridそのものを使用します。
  continuous positionをgridへ投影し、`InterlockedMin`で各cellのownerを決定します。
- **衝突応答**：occupancy競合を外部接触とBody内部競合に分離します。外部接触だけをBody代表へatomic ORで集約し、床ならY、壁ならXの速度成分だけを止めます。
  接線方向の運動量は残し、同じBody内部のセル競合でBody全体を停止させません。
- **空洞**：Body IDは固体source cellにだけ存在します。内部がEmptyならそこにoccupancy/colliderは作られないため、1つの巨大Bodyでも穴や通路を維持します。
- **CAとの接続**：powder、liquid、gas passはrigid occupancyを移動不可セルとして参照します。
  rendererも同じoccupancyからrigid source idを逆引きします。

## XPBDを採用した理由

YMM4-SandSimにはすでに規則格子があるため、その構造をbroadphaseとownershipへ流用できます。
固定トポロジのXPBDなら、可変長GPUデータ構造やCPU同期を追加せず、Direct3D 11とShader Model 5の範囲で固体の変形、衝突、破断を処理できます。

## 決定性

- 同じsource cell idは常に同じowner idを持ちます。
- occupancy競合はatomic minimumで解決し、処理順に依存しません。
- solver dispatch順とphase順を固定します。
- シークとresetは既存のtimeline policyを通し、rigid stateもsourceから再初期化します。

## CAとの連携範囲

Rigid occupancyはCA移動の障害物になります。
粉体と、CAで生成された固定素材はrigid側の支持面として扱います。
液体または気体がrigid occupancyの下にある場合はCA状態を凍結して保持し、rigid通過によって質量が消えないようにします。

GPU上では、次の双方向連携を行います。

- rigidセルは、重なっている液体の密度から簡易浮力と流体抵抗を受けます。
- 火、残り火、溶岩、酸、海水を重なりセルと8近傍から参照し、固定素材の燃焼、融解、腐食、銅の酸化を処理します。
- CA反応で生成された石や氷などの固定素材は、対応するrigid source slotが空いていればXPBDへ昇格します。
- 反応後のoccupancy再構築は、新しいownership競合を作らないためclaim-only passとします。
  同じCA iterationで高価なcollision resolveを二重実行しません。

液体の体積押し出しと圧力、粉体をrigidが押し退ける処理、完全な流体と固体の接触、任意位置での新規rigid particle poolは、現在のモデルには含めていません。

## 素材別のXPBD特性

固定素材をすべて同じ固体として扱うと、金属もワックスも同じ変形と破断になります。
そこで`SandBehavior.hlsli`から、固定素材ごとに4種類の挙動パラメータを供給します。

- **Density**：XPBD projectionで使用するinverse massへ変換します。
  重力加速度そのものは質量に依存しません。
- **Compliance**：bondの柔らかさです。
  金属と鉱物は硬く、ワックスと有機素材は目に見えて変形します。
- **Velocity retention**：global dampingへ重ねる素材別の減衰率です。
- **Tensile break strain**：E、S、SE、SW方向のbondに対する永続的な破断閾値です。

異素材間にはXPBD bondを張りません。隣接していても木と石、石と金属などは別Bodyとして衝突します。
同素材でも空洞、切断、永続破断markerによって4近傍接続が途切れれば、次のBody再構築で別Body IDへ分離します。

制御点爆発の粗い破断格子は`ExplosionRadius`から独立させ、素材別の物理スケールを使用します。ガラス/氷は小さく、石系は中程度、木や金属は大きな破片を保つ設定です。

代表的な挙動は次のとおりです。

| 分類 | 例 | 挙動 |
| --- | --- | --- |
| 高密度で延性が高い | Metal, copper, gold | 硬く、constraint上で重く、破断しにくい |
| 硬く脆い | Stone, brick, quartz, ruby | 硬いが、引張方向では比較的破断しやすい |
| 脆性が高い | Cobalt glass, ice | 硬く、小さい引張strainで破断する |
| 多孔質で脆い | Sandstone, coral, permafrost | やや柔らかく、破断しやすい |
| 繊維質 | Wood, amber | しなりがあり、中程度の強度を持つ |
| 軟質 | Pink wax | complianceが高く、大きく伸びてから破断する |
| 有機素材 | Plant, grass, moss, leaf, algae | 軽く、complianceとdampingが大きい |

破断したbondは、既存の`RigidLambda` textureに大きな永続markerとして記録します。
通常のXPBD multiplierはsubstepごとに消去しますが、破断markerは保持します。
そのため、追加のbond textureやGPUからCPUへのreadbackは必要ありません。

`ClearAndRebuild`ではすべてのbondを復元します。
Emitterのrestampでは、既存のrigid source particleが持つ破断履歴を保持し、片側だけが再接着する状態を避けます。

## CAパラメータの整合性

- 液体のCA浮沈順は`FluidProperties().x`と同じ順序（液体窒素 < 油 < 水 < 海水 < インク < 酸 < スライム < 溶岩）に統一します。
  密度差による交換は縦と斜め方向だけで行い、横方向は空セルへの拡散だけにして、界面の左右往復を防ぎます。
- 汎用インクは油と同じ可燃物として扱わず、油だけを高可燃液体とします。
- 塩とピンク岩塩は、水と海水中で同じ低確率の溶解挙動を持たせ、油中では溶解させません。

## CA境界の規則

- Backing textureは偶数サイズへ丸めますが、論理グリッド外のパディングセルだけを固定壁として扱います。
  奇数幅または奇数高さの最終実セルをブロック単位で凍結しません。
- `1 × N`と`N × 1`では2×2 Margolus分割を使わず、2位相の1D pair updateで寿命、反応、縦交換、横拡散を継続します。
  `1 × 1`でも寿命更新を継続します。
- shifted phaseで2×2 blockの外側になる境界単独セルも、単純コピーではなく寿命を1回進めます。
  火、煙、水蒸気、残り火の寿命が画像端だけ半速になることを防ぎます。
  rigid occupancy下のCA状態だけは意図的に凍結します。
- 静的契約テストでは、1～9セルの偶数、奇数、退化グリッドについて、各CA phaseで全実セルがちょうど1回書き込まれることを検査します。

## 爆発との連携

爆発には2つの経路があります。

- **火薬爆発**：火薬のone-shot metadata eventを`SandExplosionUpdate`が消費し、GPU上のscalar pressure fieldを8近傍へ伝播します。壁や素材の`ExplosionPressureTransmission`が圧力を減衰させ、火薬の連鎖、CAの飛散、XPBDへの圧力gradient、発光へ利用します。
- **制御点爆発**：YMM4の`VideoEffectController`から中心、発火フレーム、px単位の半径を受け取り、火薬pressureとは別の解析的Euclidean frontを約6出力フレームで最大半径まで進めます。大半径でもセルを1個ずつ待つ遅い同心円伝播にはしません。

制御点の中心はsigned cell座標としてGPUへ渡し、画面端へclampしません。画面外の爆心から半径の一部だけを画面内へ届かせることができます。

制御点爆発では同じConnected Bodyの全セルへ、Body代表位置から求めた共通放射方向のimpulseを加えます。これによりセルごとの速度差をXPBDが打ち消すのを抑えます。爆発後の外部接触は軸別に処理し、床に触れても横方向の運動量を保持します。

中心部は一度だけEmptyへ削り、空洞壁の狭いshellへFireをseedします。その後の木、油、硫黄、石炭などへの延焼は通常のCA隣接反応へ任せます。XPBD固定素材も`SandRigidReact`から同じ化学反応を受け取ります。

強い制御点爆発は永続bond markerを素材別の破断スケールで設定します。Connected Componentsは次のBody再構築時に破断済み軸bondを接続として使わないため、同素材でも切断された島は別Bodyになります。

CPU側のbody/contact/event list、GPU simulation stateのreadback、blocking synchronizationは使用しません。

Timeline evaluationは`Initial`、`Continuous`、`Random`へ明示的に分類します。
Initial accessでは現在の入力から状態を構築し、設定された上限内のwarm-upだけを適用します。
Continuous accessには、同一フレームの再評価と次の連続フレームを含みます。
同一フレームはパラメータ変更がなければzero-delta no-opとなり、次フレームだけ1回進めます。
Random accessにはシークと巻き戻しを含み、不可逆なGPU状態を破棄して現在入力から再構築します。
アイテム先頭からの全フレーム再生は行いません。

- 圧力は気体をほぼ自由に通過し、液体と粉体では減衰し、rigid materialでは強く減衰します。
  Pink waxはgeneric organic branchへ入る前に専用のsoft-solid transmissionを使用します。
- CAは通常flowのあとにpressure gradientを読み、移動可能な素材を低圧側へswapできます。
- 火薬由来の爆発では`SandRigidIntegrate`がpressure gradientをimpulseとして読みます。制御点爆発ではConnected Body代表からのEuclidean放射方向を使用します。
  どちらも`RigidProperties`の密度を反映し、十分に鋭いimpulseはXPBD bondへ永続的な破断markerを設定できます。
- 厚く密度の高い壁ほど背後の圧力を弱めますが、脆い表面は破断する可能性があります。
  斜め伝播では2つのcardinal side cellも確認し、完全に閉じた90度角をwaveが斜めに通過することを防ぎます。
- 火薬pressureと制御点の解析的frontはrender-time light fieldもseedし、暖色のshock ringとして波面のflashと物理応答を同期します。
- 着火直後のgunpowder cellは、pressure passがone-shot eventを消費するまでその位置へ固定します。
  CA reactionとmovement、swapは、そのeventを持つcellを一時的に移動不可として扱います。

## ライティングと影の伝播

render-time light fieldは、同じ論理cell grid上に置いたGPU-resident RGB max-propagation近似です。
Fire、ember、lava、sea lantern、explosion pressureがlight fieldをseedします。
素材ごとのtransmissionで外向きの光を減衰させるため、固定表面は光を受けつつ、その内部を通る光は弱くなります。

- Gasとwaterは比較的光を通し、smoke、ink、powderは強く減衰します。
- Cobalt glass、ice、quartz、pink wax、rose quartz、fluorite、amethyst、amberは、generic fixed-solid fallbackより前に専用のtranslucent-solid transmissionを使用します。
- 斜め伝播では両側のcardinal cellを確認し、より遮蔽の少ない経路だけを採用します。
  閉じた角を直接漏れることを防ぎつつ、片側が開いていれば角を回り込めます。

この処理はray tracingでも、複数光源を加算するradiative transportでもありません。
dispatch回数に上限を持つ、決定的なscreen-space cell近似です。

## 性能計測とD3D11 state

Connected Componentsは複数のunion/compress dispatchを必要とします。各roundでshader/SRV/UAVを再bindせず、同じstateを保持してconstant bufferだけ更新します。これによりGPUアルゴリズムを変えずにCPU/driver側のstate changeを減らします。

`YMM4SANDSIM_LOG_LEVEL=Information`を明示した場合だけ、120回単位でsimulation/renderの`cpuSubmitMs`とCompute Shader dispatch数をログへ集計します。`cpuSubmitMs`はCPUがD3D11コマンドを発行する時間であり、GPU実行時間ではありません。

設計ルールのGPU readback禁止を守るため、timestamp queryをCPUへ回収する内蔵GPU profilerは追加しません。GPU時間を調べる場合はPIX/RenderDocなど外部ツールを使用します。

## GPUメモリの上限

Simulation bufferは、最悪構成を常時確保せず、機能ごとに必要な場合だけ確保します。
CA stateは16 byte/cell、XPBDはBody label/contactを含め52 byte/cell、explosion pressureは8 byte/cell、lightingは8 byte/cellを追加し、全機能有効時は84 byte/cellです。

state budgetは約304 MiBです。
allocatorは有効な機能のbyte/cellから、パディング後に許容できるcell countを計算します。
CAだけ、または一部機能だけを有効にした構成では、全機能有効時よりVRAM使用量を抑えられます。

許容サイズを超える場合、processorはD3D11 resourceを確保する前に状態生成を拒否します。
`EnsureResources`でも同じbyte budgetを再検査し、防御的に上限を維持します。
