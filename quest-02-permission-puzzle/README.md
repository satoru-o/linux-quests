# quest-02: permission-puzzle

前提セットアップは不要。ビルドしてすぐ挑戦できる。

## ミッション

コンテナの中の`/secret/flag.txt`にFLAGが書かれている。読んでみよ。

```bash
docker compose up -d --build
docker compose exec permission-puzzle sh
cat /secret/flag.txt
```

## 手順

`Permission denied`になるはず。原因を調査する。

<details>
<summary>ヒント1</summary>

```bash
ls -la /secret
id
```
所有者・グループ・パーミッションのビットをよく見る。
</details>

<details>
<summary>ヒント2</summary>

`flag.txt`は`root:flaggroup`の所有で、パーミッションは`640`(所有者rw、グループr、その他なし)。今の自分(`appuser`)はどのグループに属しているか、`id`の出力と見比べる。`docker exec -u root`で覗いて確認するのは調査としてはアリだが、それだけで終えると次に同じ状況に出会っても解決できない。
</details>

<details>
<summary>ヒント3(答えに近い)</summary>

`appuser`が`flaggroup`のメンバーになっていない。**Dockerfile自体を直して**、`USER appuser`より前にグループへ追加する行を足す。

```dockerfile
RUN adduser appuser flaggroup
```

直したら再ビルド。

```bash
docker compose up -d --build
```
</details>

## クリア確認

```bash
docker compose exec permission-puzzle cat /secret/flag.txt
```
