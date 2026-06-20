<!-- 日本語版 README。英語版は README.md を参照してください。 / Japanese README. See README.md for English. -->

# Claude Skills（クロード・スキル集）

Claude Code 用の実用的なスキル集です。マルチ LLM ワークフロー、計画・カバレッジ
チェック、文章品質、ドメイン運用などを扱います。MIT ライセンス。

> **初めての方へ** — まずは [インストール手順（日本語）](INSTALL.ja.md) をご覧ください。
> GitHub アカウントもターミナルも不要で始められます。

---

## 「スキル」とは？

**スキル**とは、Claude Code が読んで実行する、プレーンテキストの指示が入った
フォルダのことです。`/council`、`/deslop`、`/plan` のように、名前の前にスラッシュ
（`/`）を付けて入力すると呼び出せます。一部のスキルは小さな補助スクリプトも同梱
しています。

使うには [Claude Code](https://docs.claude.com/ja/docs/claude-code/overview) が
必要です。プロンプトだけで動くスキルは、インストール後すぐ使えます — ターミナルも
git もキーも不要です。一部のスキルは追加のツール・キー・モデルを使います
（下の表に「必要なもの」を記載）。

---

## 何が入っているか

| スキル | 何をするか |
| --- | --- |
| `battle` | 同じコーディング課題で AI モデルの組み合わせをベンチマーク。単体＋ペア＋順位表。 |
| `brief` | プロジェクト把握型のセッション・ブリーフィング。intel・決定事項・保留事項を読み込む。 |
| `codex-write` | 重いコード生成を Codex CLI に委譲し、Claude が指揮・レビュー。 |
| `council` | 5 モデルによる戦略アドバイザリー。役割固定の座席＋統合パス。 |
| `crawl` | 階層型 Web フェッチャー → クリーンな Markdown。直接取得（設定不要）＋任意で Cloudflare。 |
| `deslop` | 文章から「AI っぽさ」22 パターンを除去（ダッシュ多用、きれいすぎる締めなど）。 |
| `evaluate-plan` | 実装計画を要件と突き合わせるカバレッジ・チェック。 |
| `keyword-research` | Google トレンドの関心度＋関連クエリ。SEO・コンテンツ優先度づけ用。 |
| `mode` | 委譲対応スキルの単一 LLM / マルチ LLM ルーティングを切り替え。 |
| `model-scan` | プロバイダ API とドキュメントを走査し、モデル表を最新に保つ。 |
| `namecheap` | Namecheap の XML API 経由のドメイン管理（確認・登録・DNS・移管・更新）。 |
| `pair-session` | AI ペアプログラミング。Claude が構築し、第 2 のモデルが助言。3 スタイル。 |
| `plan` | リサーチ先行の計画立案。並列サブエージェントが調査し、計画書を作成。 |
| `salesforce-reports` | Analytics REST API ＋ `sf` CLI 経由で Salesforce レポートを作成・複製・実行・削除。 |
| `second-opinion` | Codex CLI による独立コードレビュー。レビュー・反証・相談の各モード。 |
| `update-machine` | brew/npm/pipx/uv の安全な並列アップグレード。罠回避ガード付き。 |

---

## 各スキルに必要なもの

ほとんどは Claude Code だけで動きます。一部は別モデル・キー・Node パッケージを使います。

| スキル | Claude Code だけで動く？ | フル機能に必要なもの |
| --- | --- | --- |
| `brief`, `deslop`, `evaluate-plan`, `mode`, `plan` | ✅ | — |
| `crawl` | ✅ 基本機能 | Node（`npx tsx`）。JS 重ページには Cloudflare キー |
| `update-machine` | ✅ | お使いのパッケージ管理（brew/npm/pipx/uv） |
| `battle` | ◑ 一部 | フルのモデル比較には Antigravity ＋ Codex CLI |
| `council` | ◑ 一部 | 他モデルへのアクセス（各 CLI または API キー） |
| `pair-session` | ◑ 一部 | 第 2 モデルの CLI（Antigravity または Codex） |
| `codex-write`, `second-opinion` | — | Codex CLI |
| `keyword-research` | — | Node ＋ `google-trends-api` パッケージ |
| `model-scan` | — | プロバイダの API キー、＋ Node |
| `namecheap` | — | Namecheap の API キー |
| `salesforce-reports` | — | `sf` CLI と Salesforce 組織 |

✅ そのまま動く ・ ◑ 動くが追加モデルがあるとより良い ・ — 上記の準備が先に必要

---

## まず試すなら（おすすめ）

ターミラル不要・設定不要で今日から試せる ✅ のスキル：

- **`/deslop`** — 文章を貼り付けて「AI っぽさ」を除去。営業メール・社内文書・提案書に。
- **`/plan`** — 「〇〇をどう進めるべき？」と相談すると、調べてから計画書を作る。
- **`/brief`** — いま作業中のプロジェクトの背景を読み込んで状況把握。

インストール方法は [INSTALL.ja.md](INSTALL.ja.md) を参照してください
（GitHub アカウント・git は不要）。

---

## 実行する前に

これらは「おもちゃ」ではなく本物のツールです。一部はお金を使ったり、システムを
変更したりできます：

- `namecheap` は**ドメインの登録・移管・更新**ができ、アカウントに課金されます。
- `salesforce-reports` は Salesforce 組織のレポートを**削除**できます。
- `update-machine` はマシンにインストール済みのパッケージをアップグレードします。

インターネット上のコードと同じように扱ってください — 実行前に、そのスキルの
`SKILL.md` と `scripts/` 配下のスクリプトに目を通しましょう。すべてのスクリプトは
`--help` を受け付け、認証情報の設定は `~/.config/claude-skills/<skill>.env` に
書き込まれます（スキル本体には書き込まれません）。

---

## ライセンス・詳細

MIT ライセンス。完全な解説・自己改善の仕組み・各スキルのクイックスタートは
英語版 [README.md](README.md) を参照してください。Copyright Emmanuel Prouveze.
