# quest-10: disk-pressure

前提セットアップは不要。`./new-case.sh`を叩けばサーバが立ち上がる。

## 状況

深夜、監視からアラートが上がった。

```
[CRITICAL] ip-10-0-1-42 : reportd がレポートを書き出せていません
```

`ip-10-0-1-42`は集計レポートを生成しているサーバで、`reportd`というサービスが5秒ごとにレポートを書き出している。それが書けなくなっている。

**SSHで入って、原因を突き止めて復旧させること。**

```bash
./new-case.sh
```

を実行すると、サーバが立ち上がり、ランダムに1つ障害が注入される。

## これまでのクエストとの違い

07〜09は「コンテナを外からいじって診断する」ドリルだった。これは違う。

- **サーバの中に入る。** `ssh`でログインし、そこから先は中にある道具だけで戦う。`docker`コマンドは使えない
- **診断だけでなく復旧まで**やる。原因を言い当てるのではなく、実際にサービスを生き返らせるのがゴール
- **障害は毎回ランダムに注入される。** 何度でも回せる

サーバは`systemd`で動いている本物に近い環境で、`systemctl`も`journalctl`も使える。

## 入り方

```bash
ssh -i ssh/id_ed25519 -p 2222 \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  ec2-user@localhost
```

鍵は初回の`./new-case.sh`で自動生成される(`ssh/`はgit管理外)。`ec2-user`は`sudo`が使える。

## サーバの構成

| 項目 | 内容 |
| --- | --- |
| サービス | `reportd.service` (5秒ごとにレポートを1件生成) |
| レポート置き場 | `/var/log/reportd` (専用の領域。**32MB / inode 2048**) |
| 処理ログ | `/var/log/reportd/app.log` |
| 成果物 | `/var/lib/reportd/flag.txt` (**書き出せている間だけ存在する**) |

## ゴール

`reportd`が再びレポートを書き出せるようになること。成功すると成果物が現れる。

```bash
cat /var/lib/reportd/flag.txt
```

手元に戻って答え合わせ。

```bash
./verify.sh --status        # 今の状態を見る
./verify.sh 'FLAG{...}'     # 取得したFLAGを判定する
```

**成果物は「今まさに書けている」ときにしか存在しない。** 一瞬だけ空いてすぐ埋まる直し方では通らない。

## 診断の型

ディスク逼迫は、**上から順に「何が」「どこで」「今も」を確定させる**。

| 段 | 問い | コマンド | 分かること |
| --- | --- | --- | --- |
| 1 | サービスは何と言っているか | `sudo journalctl -u reportd -n 20` | 書けないのか、別の理由か |
| 2 | 逼迫しているのは容量かinodeか | `df -h` と **`df -i`** | 両方見ないと片方を見落とす |
| 3 | 何が食っているか | `sudo du -sh /var/log/reportd/* \| sort -h` | 大きいものから順に |
| 4 | 見えない消費はないか | `df`と`du`の差、**`sudo lsof +L1`** | 消したのに解放されていない分 |
| 5 | 今も増えているか | `df -h` を数回、`systemctl list-units` | 止めないと直らない相手がいるか |

第2段を飛ばすと`inode`枯渇に永遠に気づけない。第4段を飛ばすと「消したのに減らない」で詰まる。

### 容量とinodeは別物

```bash
df -h /var/log/reportd     # 容量(バイト)
df -i /var/log/reportd     # inode(ファイル数)
```

**容量がガラガラなのに書けない**ことがある。ファイルを1つ作るにはinodeが1つ要るので、小さいファイルが大量にあると、容量を残したままファイルを作れなくなる。エラーは容量不足と同じ`No space left on device`なので、メッセージだけでは区別できない。

### `df`と`du`が食い違うとき

```bash
df -h /var/log/reportd     # 使用量が大きい
sudo du -sh /var/log/reportd   # 合計が小さい
```

この差は、**削除されたがプロセスに開かれたままのファイル**であることが多い。`rm`しても、そのファイルを開いているプロセスがいる限り領域は解放されない。ファイル名は消えているので`ls`にも`du`にも出てこない。

```bash
sudo lsof +L1
```

`NLINK`が`0`のものがそれ。`(deleted)`と表示される。解放するには、

- 掴んでいるプロセスを再起動する(`sudo systemctl restart <service>`)
- あるいは開いているfdを直接切り詰める(`sudo truncate -s 0 /proc/<PID>/fd/<FD>`)

ログをローテートしたつもりで`rm`だけして、デーモンを再起動していない、という事故が現場では非常に多い。

### 消してもすぐ戻るとき

削除した直後は空くのに、しばらくすると元に戻る場合、**まだ書き続けている犯人がいる**。ファイルを消す前に、書いている相手を止める。

```bash
df -h /var/log/reportd          # 数秒おきに叩いて増えているか見る
systemctl list-units --type=service --state=running
sudo lsof /var/log/reportd      # 今開いているプロセス
sudo fuser -v /var/log/reportd  # 同上
```

---

# コマンド集(カテゴリ別)

サーバの中で使う道具。暗記する必要はないので、ここを見ながら回してよい。

## 1. 空きを確認する

```bash
df -h                          # 全ファイルシステムの容量
df -h /var/log/reportd         # 特定のパスが属するfs
df -i                          # inode
df -i /var/log/reportd
df -hT                         # ファイルシステムの種類も出す

findmnt /var/log/reportd       # どこに何がマウントされているか
mount | grep reportd
```

**`df`は「パス」ではなく「そのパスが属するファイルシステム」を見る。** `/var/log/reportd`が別マウントなら、`/`がガラガラでもそこだけ満杯ということが起きる。

## 2. 何が食っているか探す

```bash
sudo du -sh /var/log/reportd            # 合計
sudo du -sh /var/log/reportd/* | sort -h   # 直下を大きい順に
sudo du -ah /var/log/reportd | sort -h | tail -20   # ファイル単位で上位20
sudo du -h --max-depth=1 /var/log       # 1階層だけ

ls -lSh /var/log/reportd | head         # 大きいファイル順
ls -la /var/log/reportd                 # 隠しファイル込み

sudo find /var/log/reportd -type f -size +10M      # 10MB超のファイル
sudo find /var/log/reportd -type f -mtime +7       # 7日より古いファイル
sudo find /var/log/reportd -type f | wc -l         # ファイル数(inode枯渇の確認)
```

`du`は**ファイル名が存在するもの**しか数えない。ここが`df`との差を生む。

## 3. 見えない消費を暴く

```bash
sudo lsof +L1                      # 削除済みなのに開かれているファイル
sudo lsof +L1 /var/log/reportd     # 対象を絞る
sudo lsof /var/log/reportd         # そのディレクトリを開いているプロセス
sudo fuser -v /var/log/reportd     # 同上(見た目が違う)

sudo ls -l /proc/<PID>/fd          # そのプロセスが開いているfd一覧
```

読み方の目安。

| 見えたもの | 意味 |
| --- | --- |
| `(deleted)` かつ `NLINK` が `0` | 名前は消えたが実体が残っている。掴んでいるプロセスを止めれば解放される |
| `df`は満杯、`du`は少ない | まさに上記。あるいはマウント配下に隠れたファイル |
| `df -i`だけ満杯 | 小さいファイルが大量。容量ではなく数の問題 |

## 4. 増え続けているか調べる

```bash
df -h /var/log/reportd; sleep 5; df -h /var/log/reportd   # 2回叩いて比べる
watch -n 2 df -h /var/log/reportd                          # 継続監視(Ctrl-Cで抜ける)

sudo du -sh /var/log/reportd; sleep 5; sudo du -sh /var/log/reportd
```

**消す前に、増えているかを先に見る。** 増えているなら、消しても無駄。

## 5. 誰が書いているか特定する

```bash
systemctl list-units --type=service --state=running    # 動いているサービス
systemctl list-units --type=service --all | grep -i debug
sudo systemctl status <service>                        # 何を実行しているか

ps aux --sort=-%cpu | head                             # プロセス一覧
ps -ef | grep -v grep | grep <keyword>
sudo lsof /var/log/reportd
```

見覚えのないサービスが動いていたら、それが何をしているか`systemctl status`と`journalctl -u`で確認する。

## 6. 安全に空ける

```bash
sudo rm -f /var/log/reportd/<不要なファイル>       # 名前を消す
sudo truncate -s 0 /var/log/reportd/app.log        # 中身だけ空にする(fdは保ったまま)
sudo truncate -s 0 /proc/<PID>/fd/<FD>             # 削除済みファイルを掴んだまま切り詰める

sudo systemctl restart reportd                     # 掴んでいるプロセスを入れ替える
sudo systemctl stop <暴走しているサービス>
```

`rm`と`truncate`の違いは重要。

| 方法 | 名前 | 実体 | 掴んでいるプロセス |
| --- | --- | --- | --- |
| `rm` | 消える | **開いている間は残る** | 書き続けるが、もう見えない |
| `truncate -s 0` | 残る | **即座に解放** | そのまま書き続けられる |

**稼働中のログを空けたいなら`rm`より`truncate`。** `rm`はプロセスを再起動しないと領域が戻らない。

## 7. サービスの状態とログ

```bash
systemctl status reportd
systemctl is-active reportd
sudo journalctl -u reportd -n 30 --no-pager        # 直近30行
sudo journalctl -u reportd -f                      # 追いかける
sudo journalctl -u reportd --since '5 min ago'
sudo journalctl -p err -n 20                       # エラー以上だけ
sudo journalctl -k                                 # カーネルメッセージ
```

**まずサービスのログを読む。** 何に失敗しているかを本人が言っていることが多い。

## 8. 復旧を確認する

```bash
df -h /var/log/reportd; df -i /var/log/reportd     # 空きが戻ったか
systemctl status reportd                            # 動いているか
sudo journalctl -u reportd -n 5 --no-pager          # エラーが止まったか
ls -l /var/lib/reportd/flag.txt                     # 成果物が出たか
cat /var/lib/reportd/flag.txt
```

**数秒待ってからもう一度確認する。** すぐ埋まり直すなら、原因を止められていない。

---

## 注入される障害

どれが来るかはランダム。一覧を見ておくと「何を疑うか」の枠が作れる。

| 障害 | 症状 | 復旧に必要なこと |
| --- | --- | --- |
| 巨大なログが残っている | 容量が満杯。`du`で素直に見つかる | 消す |
| 消したのに解放されない | `df`は満杯、`du`は空。`ls`にも出ない | 掴んでいるプロセスを入れ替える |
| inodeが枯渇 | 容量は空いているのに書けない | 大量の小さいファイルを消す |
| 世代がたまりすぎ | ローテート済みログが積み上がっている | 古い世代を消す |
| 書き続けている犯人がいる | 消しても数秒で元に戻る | **先に止めてから**消す |

## 使い方

```bash
./new-case.sh                  # ランダムに1つ注入して起動
./new-case.sh <障害ID>         # 指定して注入(復習用)
./verify.sh --status           # 今の状態
./verify.sh 'FLAG{...}'        # 答え合わせ
./teardown.sh                  # 片付け
```

障害IDは`big-log` / `deleted-open` / `inode-exhausted` / `many-rotated` / `runaway-writer`。**最初は指定せずにランダムで回すこと。**

## 後片付け

```bash
./teardown.sh
```

SSHの鍵(`ssh/`)は残るので、次回も同じ鍵で入れる。

## 補足

`systemd`をコンテナで動かすため、`docker-compose.yml`では`privileged: true`を指定している。学習用の閉じた環境なので許容しているが、通常のコンテナ運用で真似する設定ではない。
