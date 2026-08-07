# quest-04: dns-detective

前提セットアップは不要。ビルドしてすぐ挑戦できる。

## ミッション

`api`サービスは`db`サービスからFLAGを取ってくる係だが、うまく繋がっていない。原因を調査して直せ。

```bash
docker compose up -d --build
curl http://localhost:5000/check
```

## 手順

エラーレスポンスの`detail`に、名前解決系のエラーが出るはず。

<details>
<summary>ヒント1</summary>

`api`コンテナの中から、実際にどの名前なら解決できるか確認する。

```bash
docker compose exec api getent hosts db-server
docker compose exec api getent hosts db
```
</details>

<details>
<summary>ヒント2</summary>

`docker-compose.yml`の`api`サービスに設定されている`DB_HOST`環境変数の値と、`db`サービスの実際のサービス名を見比べる。
</details>

<details>
<summary>ヒント3(答えに近い)</summary>

直し方は2通りある。

1. `DB_HOST`の値を実際のサービス名(`db`)に合わせる
2. `db`サービス側に`networks.aliases`で`db-server`という別名を追加する

どちらでもクリアできる。1の方が単純。
</details>

## クリア確認

```bash
docker compose up -d --build
curl http://localhost:5000/check
```

`{"status":"ok","flag":"FLAG{...}"}`が返ればクリア。値はコンテナ起動のたびに変わる。
