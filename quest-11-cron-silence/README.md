# quest-11: cron-silence

前提セットアップは不要。`./new-case.sh`を叩けばサーバが立ち上がる。

## 状況

運用チームから連絡が来た。

```
「日次集計の結果が今朝から更新されていません。
  サーバには入れます。cronで毎分回っているはずなんですが……」
```

`ip-10-0-2-17`では`/opt/batch/aggregate.sh`が毎分cronから呼ばれ、集計結果を`/var/lib/batch/result.json`に書き出している。それが止まっている。

**SSHで入って、原因を突き止めて復旧させること。**

```bash
./new-case.sh
```

## これは何か

[quest-10](../quest-10-disk-pressure/)と同じ「サーバに入って復旧する」形式のcron版。障害はランダムに注入される。

cronの厄介さは、**手で叩くと動くのにcronだと動かない**という形で現れることにある。原因は起きている場所がバラバラで、

- cronがそもそも動いていない
- ジョブは起動しているが失敗している
- **cronの環境が対話シェルと違う**
- スケジュールの書き方が意図と違う
- crontabの書式の落とし穴を踏んでいる

のどれか。まずどれなのかを確定させるのが型になる。

## 入り方

```bash
ssh -i ssh/id_ed25519 -p 2223 \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  ec2-user@localhost
```

鍵は初回の`./new-case.sh`で自動生成される(`ssh/`はgit管理外)。`ec2-user`は`sudo`が使える。

## サーバの構成

| 項目 | 内容 |
| --- | --- |
| バッチ本体 | `/opt/batch/aggregate.sh` |
| 集計コマンド | `/opt/batch/bin/reportcalc` (**PATHが通っている前提**) |
| 定義 | `/etc/cron.d/batch` (毎分実行) |
| ジョブの出力 | `/var/log/batch/cron.log` |
| 集計結果 | `/var/lib/batch/result.json` |
| 成果物 | `/var/lib/batch/flag.txt` (**定期実行が続いている間だけ存在する**) |

## ゴール

集計が**cronから定期的に**走る状態に戻すこと。成功すると成果物が現れる。

```bash
cat /var/lib/batch/flag.txt
```

```bash
./verify.sh --status        # 今の状態を見る
./verify.sh 'FLAG{...}'     # 取得したFLAGを判定する
```

**手で1回叩いて結果ファイルを作っても復旧にはならない。** 見張り役が更新の鮮度を見ているので、定期実行が止まれば成果物も消える。

## 診断の型

**「起動しているか」→「成功しているか」→「なぜ失敗するか」の順で潰す。**

| 段 | 問い | コマンド | 分かること |
| --- | --- | --- | --- |
| 1 | cronは動いているか | `systemctl status cron` | サービス自体が止まっていないか |
| 2 | ジョブは起動されたか | `sudo journalctl -u cron \| grep CMD` | cronが実際に叩いたコマンド |
| 3 | 起動して失敗したか | `sudo cat /var/log/batch/cron.log` | ジョブ自身のエラー |
| 4 | 定義は意図どおりか | `sudo cat /etc/cron.d/batch` | スケジュールとコマンド |
| 5 | 手で動くのにcronで動かないか | 環境を絞って再現する(下記) | PATH・環境変数の差 |

第2段が要。**`CMD`行が出ているかどうか**で、話が根本的に変わる。

| 第2段の結果 | 意味 | 次に見るもの |
| --- | --- | --- |
| `CMD`行が出ない | そもそも起動されていない | cronの状態、スケジュール欄、定義ファイルの置き場所と権限 |
| `CMD`行が出ている | 起動はされた。中で失敗している | ジョブの出力(第3段) |

### `CMD`行は「cronが実際に叩いた文字列」

ここが強力で、**crontabに書いた内容と、cronが実行した内容がズレていることがある**。

```bash
sudo cat /etc/cron.d/batch | tail -1        # 書いた内容
sudo journalctl -u cron | grep CMD | tail -1   # 実際に叩かれた内容
```

この2つを**並べて見比べる**。途中で切れていたら、書式の落とし穴を踏んでいる。

### crontabの`%`は特別扱い

crontabのコマンド欄では`%`が改行として解釈され、**最初の`%`以降はコマンドではなく標準入力として扱われる**。つまり

```
* * * * * root date +%Y-%m-%d >> /var/log/batch/run.log && /opt/batch/aggregate.sh
```

は`date +`までしか実行されない。`&&`の先にある本命が丸ごと消える。しかもリダイレクトも消えるので、**エラーがどこにも残らない**。

`%`を使いたいときは`\%`とエスケープする。

### 手で動くのにcronで動かないとき

cronのジョブは**あなたのログインシェルとは違う環境**で走る。差が出やすいのは、

| 項目 | 対話シェル | cron |
| --- | --- | --- |
| `PATH` | `.bashrc`や`/etc/profile`で拡張されている | 定義ファイルの`PATH=`か、cronの既定値のみ |
| 環境変数 | ログイン時に色々設定される | **ほぼ何も無い** |
| シェル | `bash` | `/bin/sh`(既定) |
| カレントディレクトリ | 今いる場所 | 実行ユーザーのホーム |

再現するには、環境を空にして叩く。

```bash
sudo env -i /bin/sh -c '/opt/batch/aggregate.sh'
```

これで落ちれば、原因は環境の差。落ちなければ別のところを疑う。

---

# コマンド集(カテゴリ別)

## 1. cron自体の状態

```bash
systemctl status cron
systemctl is-active cron
sudo systemctl start cron
sudo systemctl restart cron
sudo journalctl -u cron -n 30 --no-pager
sudo journalctl -u cron -f                    # 追いかける(次の分を待つ)
sudo journalctl -u cron --since '10 min ago'
```

## 2. 定義がどこに書かれているか探す

cronの定義は1か所ではない。**全部見る。**

```bash
sudo cat /etc/crontab                    # システム全体
sudo ls -la /etc/cron.d/                 # 追加の定義(パッケージやアプリが置く)
sudo cat /etc/cron.d/batch
sudo crontab -l                          # rootのユーザーcrontab
sudo crontab -l -u ec2-user              # 特定ユーザーのcrontab
ls -la /var/spool/cron/crontabs/         # ユーザーcrontabの実体
sudo ls /etc/cron.hourly /etc/cron.daily /etc/cron.weekly
```

`/etc/cron.d/`のファイルには落とし穴がある。

| 条件 | 満たさないと |
| --- | --- |
| **ユーザー欄が必要** (`* * * * * root cmd`) | 書式エラーで読まれない |
| ファイル名に`.`を含めない | **無視される** |
| 所有者root・パーミッション644 | 読まれない |
| 最終行に改行がある | 読まれないことがある |

## 3. 実行されたかを確認する

```bash
sudo journalctl -u cron | grep CMD              # cronが叩いたコマンド一覧
sudo journalctl -u cron | grep CMD | tail -5
sudo journalctl -u cron | grep -i error
sudo grep CRON /var/log/syslog                  # syslogに出る環境の場合
```

**`CMD`行が無い＝起動すらしていない。** スケジュール欄、定義の置き場所、cronの状態を疑う。

## 4. ジョブの出力を捕まえる

```bash
sudo cat /var/log/batch/cron.log            # リダイレクト先
sudo tail -f /var/log/batch/cron.log
sudo ls -l /var/mail/root                   # リダイレクトしていない場合の行き先
```

cronはジョブの標準出力・標準エラーを**メールで送ろうとする**。MTAが無い環境では消える。だから定義側で

```
* * * * * root /path/to/job >> /var/log/xxx.log 2>&1
```

のようにリダイレクトしておくのが定石。**リダイレクトが無い定義は、失敗しても何も残らない。**

## 5. cronの環境を再現する

```bash
sudo env -i /bin/sh -c '/opt/batch/aggregate.sh'         # 環境を空にして実行
sudo env -i PATH=/usr/bin:/bin /bin/sh -c '/opt/batch/aggregate.sh'

# cronが実際に見ているPATHを調べる(1分待つ)
printf '* * * * * root echo "PATH=[$PATH]" >> /tmp/p.log\n' | sudo tee /etc/cron.d/zz-check
sudo chmod 644 /etc/cron.d/zz-check
sleep 65; cat /tmp/p.log; sudo rm -f /etc/cron.d/zz-check

which reportcalc                    # 対話シェルでは見つかるか
command -v reportcalc
echo $PATH                          # 自分のPATH
```

**「自分の環境では動く」は証拠にならない。** cronの環境で動くかを確かめる。

## 6. 書式の落とし穴

```bash
sudo cat -A /etc/cron.d/batch      # 不可視文字(タブ・改行)を可視化
sudo cat /etc/cron.d/batch | tail -1
```

| 落とし穴 | 症状 |
| --- | --- |
| `%`をエスケープしていない | **そこから先が実行されない** |
| `/etc/cron.d`でユーザー欄が無い | 読まれない |
| ファイル名に`.`がある | 無視される |
| スケジュール欄の桁数違い | 読まれない、または意図しない時刻 |
| 相対パスでコマンドを書いた | `command not found` |

## 7. スケジュールと時刻

```bash
sudo cat /etc/cron.d/batch          # スケジュール欄を読む
date                                # サーバの現在時刻
timedatectl                         # タイムゾーン
```

スケジュール欄の読み方。

```
┌─ 分 (0-59)
│ ┌─ 時 (0-23)
│ │ ┌─ 日 (1-31)
│ │ │ ┌─ 月 (1-12)
│ │ │ │ ┌─ 曜日 (0-7)
* * * * *  root  コマンド
```

`0 3 * * *`は「毎日3時0分」であって毎分ではない。**「動かない」ではなく「まだその時刻になっていない」だけ**ということがある。

## 8. 復旧を確認する

```bash
sudo journalctl -u cron -f                    # 次の実行を待って見届ける
sudo tail -f /var/log/batch/cron.log
ls -l /var/lib/batch/result.json              # 更新時刻を見る
stat -c '%y %n' /var/lib/batch/result.json
cat /var/lib/batch/flag.txt
```

**1分待って、次の実行が通ることを確認する。** 一度手で叩いて動いただけでは、直ったことにならない。

---

## 注入される障害

| 障害 | 症状 | 見るべきところ |
| --- | --- | --- |
| cronが止まっている | `CMD`行が一切出ない | `systemctl status cron` |
| PATHが通っていない | `command not found` | 定義の`PATH=`行、`env -i`で再現 |
| 実行ビットが無い | `Permission denied` | `ls -l`、ジョブの出力 |
| `%`が未エスケープ | **`CMD`行が途中で切れている** | 定義と`CMD`行の見比べ |
| 環境変数が無い | スクリプトが変数未設定で落ちる | ジョブの出力、定義の環境変数行 |
| スケジュールが違う | `CMD`行が出ない | 定義のスケジュール欄 |

## 使い方

```bash
./new-case.sh                  # ランダムに1つ注入して起動
./new-case.sh <障害ID>         # 指定して注入(復習用)
./verify.sh --status           # 今の状態
./verify.sh 'FLAG{...}'        # 答え合わせ
./teardown.sh                  # 片付け
```

障害IDは`cron-stopped` / `path-missing` / `not-executable` / `percent-unescaped` / `env-missing` / `wrong-schedule`。**最初は指定せずにランダムで回すこと。**

毎分実行なので、直したあとは**次の実行まで最大1分待つ**必要がある。焦って何度も直さないこと。

## 補足

`systemd`をコンテナで動かすため、`docker-compose.yml`では`privileged: true`を指定している。学習用の閉じた環境なので許容しているが、通常のコンテナ運用で真似する設定ではない。
