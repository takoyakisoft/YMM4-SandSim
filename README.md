# YMM4-SandSim

[![CI](https://github.com/takoyakisoft/YMM4-SandSim/actions/workflows/public-ci.yml/badge.svg)](https://github.com/takoyakisoft/YMM4-SandSim/actions/workflows/public-ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](#ライセンス)
[![.NET](https://img.shields.io/badge/.NET-10.0-purple.svg)](#動作環境)

ゆっくりMovieMaker4（YMM4）の映像や画像を、砂、液体、気体、固体として動かす映像エフェクトプラグインです。
入力の色と透明度を保ったままシミュレーションでき、57種類の物理素材、固体の変形と破断、燃焼、爆発、発光、影に対応しています。

## インストール方法

1. [GitHub Releases](https://github.com/takoyakisoft/YMM4-SandSim/releases)から最新の`YMM4SandSim-vX.Y.Z.zip`をダウンロードします。
2. ZIPを展開し、`YMM4SandSim-vX.Y.Z.ymme`を開きます。
3. YMM4の案内に従ってプラグインをインストールします。
4. YMM4が起動中の場合は再起動します。

## 使い方

1. YMM4で映像または画像のアイテムを用意します。
2. 映像エフェクトから「サンドシミュレーション」を追加します。
3. `素材割り当て`で、入力色から素材を自動判定するか、全体を1種類の素材として扱うかを選びます。
4. 必要に応じて`入力モード`、`粒サイズ`、固体物理、爆発、照明を調整します。

最初は`粒サイズ=4 px`、`更新回数=4回`のまま試すことを推奨します。
細かい表現が必要な場合は粒サイズを小さくし、処理が重い場合は大きくしてください。

### 素材と表示色

`素材割り当て`では、入力色を55色のパレットへ分類して対応する物理素材へ変換する方法と、画像全体を指定した単一素材へ変換する方法を選べます。
シミュレーションでは合計57種類の物理素材を扱います。

`表示色`では、素材ごとの色で表示するか、元の映像や画像の色を維持するかを選べます。

### 入力モード

- **初期フレームを素材化**：最初に取り込んだ状態からシミュレーションします。崩壊や落下など、通常の演出向けです。
- **空きセルに毎フレーム追加**：現在空いている場所へ、毎フレームの入力から素材を追加します。文字や映像を継続的な発生源として使えます。
- **選択位置へ毎フレーム再配置**：入力で選択された位置を毎フレーム再配置し、それ以外のシミュレーション状態は維持します。

### 固体物理

`固体物理`を有効にすると、石、木、金属などの固定素材も落下、変形、衝突、破断するようになります。
固体物理にはGPU上のXPBD（Extended Position Based Dynamics）を使用しています。

### 爆発

爆発グループの`制御点`を有効にすると、プレビュー上で爆発位置と半径を調整できます。
中央の制御点で`中心X/Y`、右側の制御点で`半径`を変更し、`発火フレーム`で爆発するタイミングを指定します。

制御点爆発では円形の衝撃波が広がり、粉体や液体の飛散、固体への衝撃と破断、発光が連動します。
火薬へ着火した場合は、素材を伝わる圧力によって連鎖爆発します。

### 照明

火、残り火、溶岩、シーランタン、爆発は周囲を照らします。
素材による遮蔽も反映されるため、壁や固体の背後にはソフトな影ができます。

既定の`環境光=100%`では元の映像の明るさを保ったまま発光を加えます。

## 主な機能

- 砂、液体、気体、固定素材を同じセル世界でシミュレーション
- 57種類の物理素材と55色の自動判定パレット
- 入力色と透明度の維持
- GPU XPBDによる固体の落下、変形、衝突、破断、浮力
- 燃焼、融解、腐食、酸化などの素材反応
- 制御点から発生する円形衝撃波と火薬の連鎖爆発
- 火や溶岩などの発光と素材によるソフトシャドウ
- 同一フレームの再評価やシークを考慮したタイムライン状態管理

## 動作環境

- Windows 10 / 11（64 bit）
- .NET 10対応版のゆっくりMovieMaker4
- DirectX 11対応GPU

シミュレーションはGPUで処理します。
高解像度や小さい粒サイズで処理が重い場合は、まず`粒サイズ`を大きくしてください。

## 注意事項

- シーク、逆再生、大きなフレームジャンプなどでは、その位置の入力映像からシミュレーション状態を再構築します。
- 過去の全フレームを再計算して同じ履歴を再現する方式ではありません。
- シミュレーション範囲は入力画像の矩形内です。
- 固体と流体の接触、影、爆発などはリアルタイム映像エフェクト向けの近似です。

## トラブルシューティング

プラグインのログは次の場所に出力されます。

```text
<YMM4Dir>\user\plugin\YMM4SandSim\YMM4SandSim.log
```

問題が発生した場合は、このログと再現手順を確認してください。

## 開発者向け

主要なシミュレーション処理はDirect3D 11 Compute Shader上で実行し、セル状態をCPUへ読み戻さずGPU上に保持します。
CA、GPU XPBD、爆発、照明の設計詳細は[GPU_SOLID_PHYSICS.md](docs/GPU_SOLID_PHYSICS.md)を参照してください。

### リポジトリ構成

- `YMM4SandSim`：YMM4プラグイン本体
- `YMM4SandSim/Shaders`：Direct3D 11 Compute Shader / Pixel Shader
- `YMM4SandSim.Tests`：xUnitテストと静的契約テスト
- `docs/GPU_SOLID_PHYSICS.md`：GPUシミュレーションの設計文書
- `packaging/Readme.txt`：配布ZIPに同梱する利用者向けReadme
- `scripts/dev.ps1`：ビルド、検証、配布物生成

### ビルド環境

- Windows 10 / 11 x64
- .NET 10 SDK
- YMM4本体フォルダー内の参照DLL一式
- Windows SDKの`fxc.exe`
- Direct3D Feature Level 11_0以上のGPU

ローカル固有のパスは`Directory.Build.props`だけに設定します。
`Directory.Build.props.sample`をコピーして使用してください。

```powershell
Copy-Item .\Directory.Build.props.sample .\Directory.Build.props
notepad .\Directory.Build.props
```

`YMM4DirPath`、`FxcPath`、`DotnetPath`、`PythonPath`を設定します。

### 開発コマンド

```powershell
.\scripts\dev.ps1             # Release/x64ビルドとYMM4への配置
.\scripts\dev.ps1 test        # 静的契約テストとxUnit
.\scripts\dev.ps1 fmt         # 整形
.\scripts\dev.ps1 lint        # style/analyzer検証
.\scripts\dev.ps1 check       # fmt + lint + test
.\scripts\dev.ps1 clean       # 生成物を削除
.\scripts\dev.ps1 publish     # 配布用ZIPを生成
```

シェーダーは通常の開発・テストでは高速な`/O0 /WX`、配布用`publish`では`/O3 /WX`でコンパイルします。

### リリースと翻訳

リリース番号は[Directory.Build.targets](Directory.Build.targets)の`YMM4SandSimVersion`で一元管理します。
同じ番号の`v<version>`タグをpushすると、GitHub Actionsが配布用ZIPを生成してGitHub Releasesへ登録します。

UI翻訳は`YMM4SandSim/Localization/Translate.csv`を編集します。
`YukkuriMovieMaker.Generator`がビルド時に`.resx`を生成するため、生成済み`.resx`は直接編集しません。

初回取得時はサブモジュールも取得してください。

```powershell
git submodule update --init --recursive
```

## ライセンス

このソフトウェアはMITライセンスで公開されています。
詳細は[LICENSE.txt](LICENSE.txt)を参照してください。

第三者ライセンスの表示が必要なものは`LICENSES`フォルダーに収録しています。

## 謝辞

- [YukkuriMovieMaker4](https://manjubox.net/ymm4/)：饅頭遣い様
- EP01_SandSim

本プラグインの開発に利用・参照した第三者成果物のライセンスは`LICENSES`フォルダーを参照してください。
