# quest-06: stack-triage

前提セットアップは不要。ビルドしてすぐ挑戦できる。

## 状況

社内向けの「アクセス集計レポート基盤」を作っていた人が離任した。

引き継ぎ資料は無い。口頭で「だいたい動いてます、あとちょっとです」と言われた。動いていない。診断と修正を丸投げされたのは君だ。

前任者の説明によると、構成はこうなっているらしい。

- `server` … 集計元データを配信するAPI。ホストの`8080`番で公開しているはず
- `client` … 定期的に`server`からデータを取ってきて集計し、レポートを共有ボリューム(`/reports`)に書き出す
- `server` … 書き出されたレポートを読んで`/report`で返す

つまり **ホスト → server → client → 共有ボリューム → server** と一周する。どこか一箇所でも切れていると最後まで繋がらない。

## これは何の練習か

実際の障害対応は「1個直したら終わり」であることの方が少ない。1個直すと次の不具合が顔を出す、いわゆる玉ねぎ状態が普通で、そのたびに**どの層が壊れているのか**を切り分け直す必要がある。

このクエストは意図的に複数の層が同時に壊してある。1つ直すと次が見えるようになっていて、**FLAGは全部で3つ**、それぞれ別の層を復旧させたときに初めて手に入る。

「症状 → どの層を疑うか → 使うコマンド」を自分の中で組み立てる練習だと思って取り組んでほしい。

## 起動

```bash
docker compose up -d --build
```

いつでも今の到達状況を確認できる。

```bash
./verify.sh --status
```

最初は3つとも「まだ」のはず。

## 調査のとっかかり

まずは素直に、期待どおり動くはずのものを叩いてみるところから。

```bash
docker compose ps
curl http://localhost:8080/
docker compose logs client
```

調査に使う道具(`ss`、`curl`、`getent`など)は両方のコンテナに最初から入れてある。ホスト側から見た景色とコンテナの中から見た景色は違うので、**中に入って確認する**のが基本になる。

```bash
docker compose exec server sh
docker compose exec client sh
```

---

## 第1層：serverに繋がらない

`docker compose ps`では`Up`なのに、ホストから`curl`すると応答が返ってこない。

<details>
<summary>ヒント1-1</summary>

`Up`かつポートは公開済み、なのに繋がらない。ということはプロセスは生きているが「ホストから届く場所で待っていない」可能性がある。

コンテナの中で、実際にどのアドレスの何番を待ち受けているか確認する。

```bash
docker compose exec server ss -tlnp
```

`Local Address:Port`の欄をよく見る。
</details>

<details>
<summary>ヒント1-2(答えに近い)</summary>

`127.0.0.1:8080`で待ち受けている。これは**コンテナ自身の中からしか**繋がらないアドレス。ホストやほかのコンテナから届くようにするには、全インターフェースで待ち受ける`0.0.0.0`である必要がある。

`server/app.py`の`BIND_ADDR`がそれを決めている。ソースを直してもいいし、`docker-compose.yml`の`server`に環境変数を足してもいい。

```yaml
    environment:
      BIND_ADDR: "0.0.0.0"
```

直したら反映する。

```bash
docker compose up -d --build
```
</details>

## 第2層：clientがserverに辿り着けない

第1層が直ると、ホストからは繋がるようになる。しかし`docker compose logs client`を見ると、clientはまだ`server`に到達できていない。

<details>
<summary>ヒント2-1</summary>

ホストからは繋がるのにclientからは繋がらない。同じ宛先なのに立場によって結果が違う、ということは経路そのものが違う。

clientの中から、宛先の名前がそもそも引けているか確認する。

```bash
docker compose exec client getent hosts server
```

引けないなら、名前が間違っているか、**同じネットワークにいない**かのどちらか。

```bash
docker network ls
docker compose exec client ip addr
```
</details>

<details>
<summary>ヒント2-2(答えに近い)</summary>

`docker-compose.yml`で`server`は`backend`、`client`は`frontend`と、別々のネットワークに所属させられている。composeの自動DNSは同じネットワークにいる相手しか解決できない。

`client`を`server`と同じネットワークに載せる。

```yaml
  client:
    networks:
      - backend
```
</details>

## 第3層：レポートが受け渡せない

第2層が直ると、clientはデータを取得してレポートを書き出せるようになる。しかし`curl http://localhost:8080/report`はまだ成功しない。

<details>
<summary>ヒント3-1</summary>

レスポンスの`detail`を読む。ファイルが無いのか、あるけど読めないのかで話がまったく変わる。

書き手(client)と読み手(server)、それぞれの立場で共有ボリュームを見てみる。

```bash
docker compose exec server ls -la /reports
docker compose exec server id
docker compose exec client id
```
</details>

<details>
<summary>ヒント3-2(答えに近い)</summary>

clientは自分のUIDでレポートを書いたあと`0600`(所有者以外は読めない)を明示的に設定している。serverは別のUIDで動いているので読めない。

`client/app.py`の`os.chmod`を、読み手も読める権限にする。

```python
os.chmod(REPORT_PATH, 0o644)
```

グループを揃えて`0640`にする、という直し方でもよい。
</details>

---

## クリア確認

3つのFLAGはそれぞれ別の場所から手に入る。

```bash
curl http://localhost:8080/            # 第1層
docker compose logs client             # 第2層
curl http://localhost:8080/report      # 第3層
```

取得したFLAGが正しいか判定したい場合は`verify.sh`に引数で渡す。どの段階のものかも表示される。

```bash
./verify.sh 'FLAG{取得した値}'
```

今どこまで進んでいるかだけ見たいときはこちら。

```bash
./verify.sh --status
```

## 後片付け

```bash
./teardown.sh
```
