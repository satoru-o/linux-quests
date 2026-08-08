# quest-12: service-down

前提セットアップは不要。`./new-case.sh`を叩けばサーバが立ち上がる。

## 状況

デプロイ後、監視が落ちたままになっている。

```
[CRITICAL] ip-10-0-3-91 : orderapi が起動していません
```

直前に別のメンバーが構成変更を入れたらしいが、**何をしたかは聞けていない**。

**SSHで入って、原因を突き止めて復旧させること。**

```bash
./new-case.sh
```

## これは何か

[quest-10](../quest-10-disk-pressure/)・[quest-11](../quest-11-cron-silence/)と同じ「サーバに入って復旧する」形式のsystemd版。障害はランダムに注入される。

systemdは**失敗の理由をかなり正確に教えてくれる**。ただし、それは`systemctl status`の読み方を知っていればの話で、知らないと「起動しません」で止まってしまう。終了コードの意味と、設定の最終形の確かめ方を型にする。

## 入り方

```bash
ssh -i ssh/id_ed25519 -p 2224 \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  ec2-user@localhost
```

鍵は初回の`./new-case.sh`で自動生成される(`ssh/`はgit管理外)。`ec2-user`は`sudo`が使える。

## サーバの構成

| 項目 | 内容 |
| --- | --- |
| サービス | `orderapi.service` |
| ユニット定義 | `/lib/systemd/system/orderapi.service` |
| 本体 | `/opt/orderapi/serve.sh` |
| 設定 | `/etc/orderapi/app.conf` |
| 実行ユーザー | `orderapi` |
| 成果物 | `/var/lib/orderapi/flag.txt` (**動いている間だけ存在する**) |

## ゴール

`orderapi`が動き続ける状態に戻すこと。

```bash
cat /var/lib/orderapi/flag.txt
```

```bash
./verify.sh --status        # 今の状態を見る
./verify.sh 'FLAG{...}'     # 取得したFLAGを判定する
```

## 診断の型

**まず`systemctl status`を頭から読む。** 必要な情報のほとんどはここにある。

```
● orderapi.service - Order API
     Loaded: loaded (/lib/systemd/system/orderapi.service; enabled)     ← ①
    Drop-In: /etc/systemd/system/orderapi.service.d                     ← ②
             └─override.conf
     Active: activating (auto-restart) (Result: exit-code)              ← ③
    Process: 88 ExecStart=/opt/orderapi/server.sh (code=exited, status=203/EXEC)  ← ④
```

| # | 見るところ | 分かること |
| --- | --- | --- |
| ① | `Loaded:` | ユニットが読めているか。**`masked`ならここに出る** |
| ② | `Drop-In:` | **誰かが設定を上書きしている**。あればまずそれを疑う |
| ③ | `Active:` | 今の状態と、失敗の種別(`exit-code`/`signal`/`timeout`) |
| ④ | `Process:` | **どのコマンドが、どの終了コードで**落ちたか |

そのうえで5段。

| 段 | 問い | コマンド |
| --- | --- | --- |
| 1 | ユニットは読めているか | `systemctl status orderapi` の`Loaded:` |
| 2 | 設定の最終形はどうなっているか | `systemctl cat orderapi` |
| 3 | どこで落ちたか | `Process:`の終了コード |
| 4 | アプリは何と言っているか | `sudo journalctl -u orderapi -n 30` |
| 5 | 手で再現するとどうなるか | 同じユーザー・同じ環境で叩く |

### 終了コードで原因がほぼ決まる

systemd自身が起動に失敗したとき、**200番台の専用コード**を返す。ここを覚えておくと一発で当たる。

| コード | 名前 | 意味 |
| --- | --- | --- |
| `200/CHDIR` | CHDIR | **`WorkingDirectory=`のディレクトリが無い**、または入れない |
| `203/EXEC` | EXEC | **`ExecStart=`を実行できない。** パスが違う、実行ビットが無い、shebangが壊れている |
| `208/STDOUT` | STDOUT | 標準出力の設定に失敗 |
| `209/STDERR` | STDERR | 標準エラーの設定に失敗 |
| `217/USER` | USER | **`User=`のユーザーが存在しない** |
| `226/NAMESPACE` | NAMESPACE | サンドボックス設定(`ProtectSystem=`など)に失敗 |
| `1`などの小さい数 | — | **systemdではなくアプリ自身が返したコード。** ログを読む |

**200番台ならsystemdの設定の問題、小さい数ならアプリの問題。** この線引きが最初の分岐になる。

### `203/EXEC`は2通りある

一番よく出るコードだが、原因は分かれる。

```bash
systemctl cat orderapi | grep ExecStart      # 何を実行しようとしているか
ls -l /opt/orderapi/serve.sh                 # そのファイルは存在するか、xはあるか
head -1 /opt/orderapi/serve.sh               # shebangは正しいか
```

- パスが存在しない → 指定ミス
- 存在するが`x`が無い → 実行ビット
- 両方問題ないなら shebang を疑う

### 設定は1か所ではない

`/lib/systemd/system/xxx.service`だけ読んでも足りない。**drop-inで上書きされている**ことがある。

```bash
systemctl cat orderapi          # 元のユニット + drop-in を全部つないで表示
systemctl show orderapi | grep -E '^(ExecStart|User|WorkingDirectory)'
ls -la /etc/systemd/system/orderapi.service.d/
```

`systemctl cat`が**実際に効いている設定**。`status`の`Drop-In:`行にも出るので、そこを見落とさない。

### 起動を「拒否」されているとき

エラーではなく、そもそも起動させてもらえないことがある。

```bash
sudo systemctl start orderapi
# Failed to start orderapi.service: Unit orderapi.service is masked.
```

`masked`は`/dev/null`へのリンクで意図的に封印された状態。`systemctl status`の`Loaded:`にも出る。

```bash
systemctl is-enabled orderapi     # masked / enabled / disabled
sudo systemctl unmask orderapi
```

---

# コマンド集(カテゴリ別)

## 1. サービスの状態を見る

```bash
systemctl status orderapi --no-pager
systemctl is-active orderapi          # active / activating / inactive / failed
systemctl is-enabled orderapi         # enabled / disabled / masked
systemctl is-failed orderapi

systemctl list-units --type=service --state=failed
systemctl list-units --type=service --all | grep orderapi
systemctl --failed
```

## 2. 設定の最終形を見る

```bash
systemctl cat orderapi                        # 元のユニット + drop-in
systemctl show orderapi                       # 解決済みの全プロパティ
systemctl show -p ExecStart --value orderapi
systemctl show -p User,WorkingDirectory orderapi
systemctl show -p ExecMainStatus --value orderapi   # 直近の終了コード

ls -la /etc/systemd/system/orderapi.service.d/      # drop-in の置き場所
sudo systemd-analyze verify orderapi.service        # 書式の検証
```

**`systemctl cat`を最初に叩く癖をつける。** ファイルを直接読むと上書きを見落とす。

## 3. ログを見る

```bash
sudo journalctl -u orderapi -n 30 --no-pager
sudo journalctl -u orderapi -f
sudo journalctl -u orderapi --since '10 min ago'
sudo journalctl -u orderapi -p err
sudo journalctl -u orderapi -o cat            # 余計な前置きを消して本文だけ
sudo journalctl -xe --no-pager                # 直近の全体 + 説明つき
```

`-o cat`はアプリの出力だけを読みたいときに便利。

## 4. 実行対象そのものを確かめる

```bash
systemctl cat orderapi | grep ExecStart
ls -l /opt/orderapi/serve.sh
head -1 /opt/orderapi/serve.sh                # shebang
file /opt/orderapi/serve.sh
sudo -u orderapi /opt/orderapi/serve.sh       # 同じユーザーで手で叩く(常駐するのでCtrl-Cで抜ける)
id orderapi                                    # そのユーザーは存在するか
getent passwd orderapi
```

**`User=`に書かれたユーザーで手で実行してみる**のが最短の再現方法。

## 5. 設定変更を反映する

```bash
sudo systemctl daemon-reload                  # ユニットを書き換えたら必須
sudo systemctl restart orderapi
sudo systemctl start orderapi
sudo systemctl stop orderapi
```

**ユニットファイルやdrop-inをいじったら`daemon-reload`。** これを忘れると、直したのに反映されない。

## 6. 起動を妨げているものを外す

```bash
sudo systemctl unmask orderapi                # 封印を解く
sudo rm -rf /etc/systemd/system/orderapi.service.d   # drop-inを消す
sudo systemctl daemon-reload

sudo systemctl reset-failed orderapi          # 失敗回数をリセット
```

`Restart=`が効いていると短時間に何度も失敗し、**`start-limit-hit`**で起動を拒否されるようになる。原因を直したあとに起動しないときは`reset-failed`を挟む。

## 7. 依存関係を追う

```bash
systemctl list-dependencies orderapi
systemctl list-dependencies --reverse orderapi
systemctl show -p Requires,After,Wants orderapi
```

## 8. 設定の中身が分からないとき

消えた設定を作り直すなら、**ひな形が残っていないか**をまず探す。

```bash
ls -la /etc/orderapi/                        # .example や .dist が無いか
cat /etc/orderapi/app.conf.example
find /etc /opt -name '*.example' -o -name '*.dist' 2>/dev/null | head
grep -n 'app.conf\|LISTEN_PORT' /opt/orderapi/serve.sh   # 何を読んでいるか
```

**アプリが何を必要としているかは、アプリの実装に書いてある。** 設定ファイルを消してしまったときの復旧は、ひな形か実装のどちらかから組み立てる。

## 9. 復旧を確認する

```bash
systemctl is-active orderapi
systemctl status orderapi --no-pager | head -5
sudo journalctl -u orderapi -n 5 --no-pager
ls -l /var/lib/orderapi/flag.txt
cat /var/lib/orderapi/flag.txt
```

**数秒待ってからもう一度見る。** 起動直後だけ`active`で、すぐ落ちて再起動を繰り返していることがある(`Active:`が`activating (auto-restart)`ならそれ)。

---

## 注入される障害

| 障害 | 出るコード | 決め手 |
| --- | --- | --- |
| `ExecStart`のパスが違う | `203/EXEC` | `systemctl cat`で指定を確認、`ls -l`で存在確認 |
| 実行ビットが無い | `203/EXEC` | `ls -l`。**上と同じコードなので見分けが要る** |
| `User=`が存在しない | `217/USER` | `id <user>`で確認 |
| `WorkingDirectory=`が無い | `200/CHDIR` | `systemctl cat`で指定を確認 |
| ユニットが封印されている | (コードではなく`masked`) | `Loaded:`行、`is-enabled` |
| 設定ファイルが消えている | `1`(アプリ自身) | `journalctl -u`でアプリのエラーを読む |

## 使い方

```bash
./new-case.sh                  # ランダムに1つ注入して起動
./new-case.sh <障害ID>         # 指定して注入(復習用)
./verify.sh --status           # 今の状態
./verify.sh 'FLAG{...}'        # 答え合わせ
./teardown.sh                  # 片付け
```

障害IDは`bad-execstart-path` / `not-executable` / `wrong-user` / `missing-workdir` / `unit-masked` / `missing-config`。**最初は指定せずにランダムで回すこと。**

## 補足

`systemd`をコンテナで動かすため、`docker-compose.yml`では`privileged: true`を指定している。学習用の閉じた環境なので許容しているが、通常のコンテナ運用で真似する設定ではない。
