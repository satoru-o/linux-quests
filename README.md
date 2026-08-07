# linux-quests

「Dockerコンテナの中で何かがうまく動いていない状態」を、Linuxの力で解決してFLAGを手に入れる、小さな自習用クエスト集。

> [!NOTE]
> 個人の自習用リポジトリです。閲覧は自由ですが、Pull RequestやIssueでの提案・報告は受け付けていません。

## 設計原則(v2)

- **FLAGはランダムな文字列。** `FLAG{意味の分かる単語}`のような、答え合わせのためだけの読める文字列にはしていない。`/dev/urandom`由来のハッシュ値
- **FLAGはどのファイルにも平文で存在しない。** ビルド時または実行時に都度生成される。`Dockerfile`や`docker-compose.yml`、アプリのソースコードをそのまま読んでも答えは書かれていない
- **正規の手順を踏まないとFLAGは手に入らない。** 権限、シグナル、DNS、ポートなど、それぞれのお題の「正しい対処」を経由しないとそもそもFLAGが生成・到達しない設計
- **前提となるセットアップは`setup.sh`で自動化。** 手打ちのコマンドをうっかり忘れて「そもそも詰まらなかった」という事故を防ぐ

## 遊び方

```bash
cd quest-01-port-hunt
cat README.md          # ミッション確認
./setup.sh              # 前提セットアップ(必要なクエストのみ)
docker compose up -d --build
# うまくいかないところから調査開始
```

ヒントは各READMEの中で段階的に公開してるので、まずヒント無しで格闘してから読むのがおすすめ。

## 収録クエスト

| # | テーマ | 使う力 |
| --- | --- | --- |
| 01 | port-hunt | ポート競合の調査(`docker ps`/`ss`/`lsof`) |
| 02 | permission-puzzle | パーミッションとグループ(`ls -la`/`id`/`chown`) |
| 03 | signal-catcher | シグナルの違い(`SIGTERM`/`SIGKILL`/`docker kill -s`) |
| 04 | dns-detective | コンテナ間DNS解決の切り分け(`getent hosts`) |
| 05 | log-diving | ログからの情報抽出(`grep`) |

## 後片付け

各クエストディレクトリに`teardown.sh`(または`reset.sh`)を用意してある。

```bash
./teardown.sh
```

## 素材を直接読んでもFLAGが分からない理由(仕組みの説明)

| クエスト | FLAGの生成タイミング | 生成場所 |
| --- | --- | --- |
| 01 port-hunt | コンテナ起動時 | `serve.py`が起動直後に`secrets.token_hex`で生成してファイルに書く |
| 02 permission-puzzle | イメージビルド時 | `Dockerfile`の`RUN`内で`/dev/urandom`から都度生成、ソースには書かれない |
| 03 signal-catcher | `SIGTERM`受信時 | シグナルを正しく受け取った瞬間に初めて生成される。存在しないタイミングもある |
| 04 dns-detective | コンテナ起動時 | `db`アプリがプロセス起動時にメモリ上で生成 |
| 05 log-diving | ログ生成スクリプト実行時 | 大量のログの中にランダムなFLAGを1行だけ紛れ込ませる |

いずれも、リポジトリのファイルを`grep`しても答えは出てこない(はず)。
