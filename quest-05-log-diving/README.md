# quest-05: log-diving

前提セットアップは不要。ビルドしてすぐ挑戦できる。

## ミッション

このコンテナは起動時に、大量のログを`/var/log/app/access.log`に吐き出す。その中の1行にだけFLAGが混ざっている。見つけよ。

```bash
docker compose up -d --build
docker compose exec log-diving wc -l /var/log/app/access.log
```

4000行くらいある。1行ずつ目視は現実的じゃない。

<details>
<summary>ヒント1</summary>

「特定の文字列を含む行だけ抽出する」コマンドといえば。
</details>

<details>
<summary>ヒント2(答えに近い)</summary>

```bash
docker compose exec log-diving grep FLAG /var/log/app/access.log
```
</details>

## クリア確認

取得したFLAGが正しいか判定したい場合は`verify.sh`に引数で渡す。

```bash
./verify.sh 'FLAG{取得した値}'
```

一致すれば`正解!`、違えば`不正解`と表示される。

## 発展

- `grep -c`で「何行ヒットしたか」を数えてみる
- `awk '{print $4}' access.log | sort | uniq -c | sort -nr`で、どのエンドポイントに一番アクセスが多いか集計してみる(FLAG探しとは別の実務寄りの練習)
