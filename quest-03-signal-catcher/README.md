# quest-03: signal-catcher

前提セットアップは不要。ビルドしてすぐ挑戦できる。

## これは何の練習か

プロセスの終わらせ方には「お願いして終了してもらう」ものと「問答無用で消す」ものがある。後者にはプロセス側が後片付け(DB接続を閉じる、バッファを吐き出す、状態を保存する)をする猶予が一切ない。`docker kill`・`docker stop`・Kubernetesのpod終了・systemdのサービス停止・CIのタイムアウトなど、本番運用のあらゆる場面でこの違いを知らずに雑に止めると、データを失ったり中途半端な状態を残したりする事故につながる。このクエストはその感覚をコマンド一発で体験するためのもの。

## ミッション

このコンテナは、正しい終わらせ方をすればFLAGを`/flag.txt`に書き残してくれる。ただし雑に殺すと何も残らない(FLAG自体が生成されない)。

```bash
docker compose up -d --build
```

## 手順1：まず雑に殺してみる(わざと失敗させる)

```bash
docker kill signal-catcher
docker cp signal-catcher:/flag.txt .
```

`/flag.txt`が見つからない、という趣旨のエラーになるはず(正確な文言はDockerのバージョンによって異なる。例:`No such container:path`や`Could not find the file ... in container ...`など)。

<details>
<summary>ヒント1</summary>

`docker kill`はデフォルトで何のシグナルを送っているか調べてみる。

```bash
docker kill --help
```
</details>

<details>
<summary>ヒント2</summary>

`docker stop`が送るシグナルと、`docker kill`のデフォルトのシグナルは同じ`SIGKILL`。`SIGKILL`はプロセスに後片付けの猶予を与えない、問答無用の強制終了。FLAGはtrapの中で生成されるので、trapが実行されなければFLAG自体がこの世に存在しない。
</details>

## 手順2：正しいシグナルで終わらせる

コンテナを作り直してから、今度は別のシグナルを送ってみる。`docker kill -s <SIGNAL>`で任意のシグナルを指定できる。どのシグナルなら後片付けが走るか調べてみよう。

```bash
docker compose up -d --build
```

<details>
<summary>ヒント3(答えに近い)</summary>

`entrypoint.sh`の中の`trap ... TERM`が、`SIGTERM`を受け取った時だけFLAGを生成して書き出すようになっている。`docker kill -s TERM`で送ったシグナルがまさにそれ。
</details>

## クリア確認

コンテナが正常終了した後でも`docker cp`は取り出せる(停止中コンテナでも中身は残っている)。

```bash
docker cp signal-catcher:/flag.txt .
cat flag.txt
```

取得したFLAGが正しいか判定したい場合は`verify.sh`に引数で渡す。

```bash
./verify.sh 'FLAG{取得した値}'
```

一致すれば`正解!`、違えば`不正解`と表示される。
