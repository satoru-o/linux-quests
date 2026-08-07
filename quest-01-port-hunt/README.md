# quest-01: port-hunt

## ミッション

このクエストのコンテナはポート8080でFLAGを配信する予定だが、起動しようとすると失敗する。原因を調べて解決し、FLAGを手に入れよ。

## 手順

前提セットアップをスクリプトで実行する(中身が気になる人は`setup.sh`を読んでから実行してOK)。

```bash
./setup.sh
```

その状態でクエストを起動してみる。

```bash
docker compose up -d --build
```

<details>
<summary>ヒント1</summary>

エラーメッセージをよく読む。`port is already allocated`と出ていたら、それがまさに今回のテーマ。
</details>

<details>
<summary>ヒント2</summary>

ホスト側(WSL)で、誰がポート8080を使っているか確認する方法はいくつかある。

```bash
docker ps
ss -tulnp | grep 8080
```

もし`docker`が管理しているプロセス(`docker-proxy`など)が犯人だと分かったら、OSのコマンドで直接`kill`するより、**Dockerのコマンドで正規に止める**方が安全。Dockerデーモン内部の管理状態とズレるとかえって面倒になる。
</details>

<details>
<summary>ヒント3(答えに近い)</summary>

犯人はDockerコンテナ(`quest01-port-blocker`)のはず。正規の止め方で片付ける。

```bash
docker rm -f quest01-port-blocker
docker compose up -d --build
```
</details>

## クリア確認

```bash
curl http://localhost:8080/flag.txt
```

`FLAG{...}`が返ってくれば成功。値は起動のたびに変わる(ランダム生成のため)。
