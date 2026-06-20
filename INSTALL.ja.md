<!-- 非エンジニア向けインストール手順（日本語）。git・GitHub アカウント不要。 -->

# インストール手順（日本語・かんたん版）

> **GitHub アカウントも、git も、ターミナルの知識も要りません。**
> 必要なのは [Claude Code](https://docs.claude.com/ja/docs/claude-code/overview) が
> インストールされていることだけです。

スキルとは「Claude Code が読む指示書のフォルダ」です。所定の場所にフォルダを
置くだけで使えるようになります。方法は 3 つあります。**一番かんたんなのは方法 A** です。

---

## 方法 A — Claude Code に入れてもらう（一番かんたん・おすすめ）

ターミナルも git も使いません。Claude Code を開いて、こうお願いするだけです：

> `https://github.com/eprouveze/claude-skills` から `deslop` スキルを
> インストールして。

Claude Code がファイルを取得し、正しい場所に置いてくれます。`deslop` の部分を
使いたいスキル名に変えてください（例：`council`、`plan`、`brief`）。

入れ終わったら **Claude Code を再起動**してください（スキル一覧が読み直されます）。
そのあと、チャットで `/deslop` のように打てば使えます。

---

## 方法 B — ZIP をダウンロードする（GitHub アカウント不要）

「自分のパソコンにファイルとして置きたい」場合の方法です。

1. ブラウザで以下のリンクを開くと、ZIP が直接ダウンロードされます：
   **https://github.com/eprouveze/claude-skills/archive/refs/heads/main.zip**
   （または、リポジトリ画面の緑色の **Code** ボタン → **Download ZIP**）
2. ダウンロードした ZIP を**ダブルクリックで解凍**します。
   `claude-skills-main` というフォルダができます。
3. その中の `skills` フォルダを開き、使いたいスキルのフォルダ
   （例：`council`）を、下記の「スキル置き場」にコピーします。
4. **Claude Code を再起動**します。

### スキル置き場はどこ？

| 置き場所 | 効く範囲 | パス |
| --- | --- | --- |
| すべてのプロジェクト共通 | どこでも使える | `~/.claude/skills/` |
| 1 つのプロジェクト専用 | そのフォルダ内だけ | `<プロジェクト>/.claude/skills/` |

> **Mac で `~/.claude` フォルダが見えないときは：** Finder で `Command + Shift + G` を
> 押し、`~/.claude/skills` と入力して移動します。`skills` フォルダが無ければ作って
> ください。

コピー後のイメージ（`council` を全プロジェクト用に入れた場合）：

```
~/.claude/skills/council/SKILL.md
~/.claude/skills/council/...
```

`SKILL.md` がそのフォルダの直下に来るのが正解です（`council/council/SKILL.md` の
ように二重にならないよう注意）。

---

## 方法 C — git を使う（開発者向け）

git が使える方は、英語版 [README.md](README.md#with-git-for-developers) の
「With git」セクションを参照してください。

---

## 動作確認

1. Claude Code を再起動した。
2. チャットで `/` を打つと、入れたスキル名が候補に出る。
3. 例：`/deslop` に続けて文章を貼り付けて実行してみる。

うまく出てこないときは：

- スキルフォルダが `~/.claude/skills/<名前>/SKILL.md` の形になっているか確認。
- Claude Code を**もう一度再起動**。
- それでも出ないときは、方法 A で Claude Code 自身に入れ直してもらうのが確実です。

---

## まず試すのにおすすめの 3 つ（設定不要）

| コマンド | 何をする | 営業の使いどころ |
| --- | --- | --- |
| `/deslop` | 文章の「AI っぽさ」を除去 | 提案書・お客様向けメール・社内文書の仕上げ |
| `/plan` | 進め方を調べて計画書にする | 「この案件、どう攻める？」を整理 |
| `/brief` | プロジェクトの背景を読み込む | 作業再開時に状況をすぐ把握 |

---

## 安全に使うために

一部のスキルはお金を使ったり、システムを変更したりできます
（`namecheap` はドメイン課金、`salesforce-reports` はレポート削除、
`update-machine` はパッケージ更新）。**まず ✅ 印（設定不要）のスキルから**
試すのがおすすめです。詳細は [README.ja.md](README.ja.md) の「実行する前に」を
参照してください。
