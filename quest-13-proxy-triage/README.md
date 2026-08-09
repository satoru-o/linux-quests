# quest-13: proxy-triage

前提セットアップは不要。`./new-case.sh`を叩けばサーバが立ち上がる。

## 状況

監視から断続的なアラートが上がっている。

```
[WARN] ip-10-0-4-25 : レポート画面でエラーが出ると問い合わせあり
```

このサーバは前段の`nginx`が3台のバックエンドへ振り分けている。直前に構成変更が入ったらしいが、**何をしたかは聞けていない**。

**SSHで入って、原因を突き止めて復旧させること。**

```bash
./new-case.sh
```

## これは何か

[quest-10](../quest-10-disk-pressure/)〜[quest-12](../quest-12-service-down/)と同じ「サーバに入って復旧する」形式のリバースプロキシ版。障害はランダムに注入される。

多段構成の厄介さは、**エラーが返ってきても、それを誰が出したのか分からない**ことにある。`502`はnginxが出している。`404`はバックエンドが出している。この区別がつくと、見る場所が半分に絞れる。

## 入り方

```bash
ssh -i ssh/id_ed25519 -p 2225 \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  ec2-user@localhost
```

鍵は初回の`./new-case.sh`で自動生成される(`ssh/`はgit管理外)。`ec2-user`は`sudo`が使える。

## サーバの構成

```
利用者 ──► nginx (:80) ──┬──► backend@9001
                          ├──► backend@9002
                          └──► backend@9003
```

| 項目 | 内容 |
| --- | --- |
| プロキシ | `nginx` (`/etc/nginx/conf.d/reports.conf`) |
| バックエンド | `backend@9001` / `backend@9002` / `backend@9003` (systemdテンプレート) |
| バックエンド本体 | `/opt/backend/backend.py` (`127.0.0.1`にのみlisten) |
| 主なエンドポイント | `/api/report`(通常) / `/api/slow`(3秒かかる) |
| 成果物 | `/var/lib/proxy-watchdog/flag.txt` (**経路が安定している間だけ存在する**) |

**バックエンドが前段に何を期待しているかは、サーバの中に書いてある。** 推測する前に読むこと。

## ゴール

利用者と同じ経路(`http://127.0.0.1/`)が**安定して**通るようになること。

見張り役が`/api/report`を12回と`/api/slow`を1回、繰り返し叩いている。**全部通ったときだけ**成果物が現れる。1回たまたま通っただけでは復旧とみなされない。

```bash
cat /var/lib/proxy-watchdog/flag.txt
```

```bash
./verify.sh --status        # 今の状態を見る
./verify.sh 'FLAG{...}'     # 取得したFLAGを判定する
```

## 診断の型

**「そのステータスを誰が返したか」を最初に確定させる。**

| 返ってきたもの | 出したのは | 意味 |
| --- | --- | --- |
| 接続できない / `000` | **誰も** | nginx自体が動いていない |
| `502` | **nginx** | バックエンドに繋がらない、または不正な応答 |
| `504` | **nginx** | バックエンドが時間内に返さなかった |
| `301` `404` `200` など | **バックエンド** | 到達はしている。中身の問題 |
| `499` | **nginx** | クライアントが待ちきれずに切った |

**`5xx`のうち502と504はnginxが自分で作っている応答**で、バックエンドは何も返していない(あるいは返しきれていない)。逆に`4xx`や`3xx`が返ってきたら、**バックエンドまで届いている証拠**。そこから先はnginxの接続設定ではなく、渡しているヘッダかアプリの問題になる。

そのうえで5段。

| 段 | 問い | コマンド |
| --- | --- | --- |
| 1 | nginxは動いているか | `systemctl status nginx` |
| 2 | 経路の応答は何番か | `curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1/api/report` |
| 3 | どの台で起きているか | `sudo tail /var/log/nginx/access.log` |
| 4 | バックエンド単体では通るか | 直接叩く(下記) |
| 5 | 設定の最終形はどうなっているか | `sudo nginx -T` |

### ログにどの台が出たかが残る

このサーバのアクセスログには、**振り分け先とその応答**が記録される。

```bash
sudo tail -20 /var/log/nginx/access.log
```

```
127.0.0.1 502 "GET /api/report HTTP/1.1" upstream=127.0.0.1:9002 upstream_status=502 rt=0.000 urt=0.000
127.0.0.1 200 "GET /api/report HTTP/1.1" upstream=127.0.0.1:9003 upstream_status=200 rt=0.002 urt=0.004
```

`upstream=`を見れば**どの台が原因か**が一目で分かる。特定の台だけ失敗しているなら、その台を調べる。

### 全部落ちるのか、一部だけか

```bash
for i in $(seq 1 9); do
  curl -sS -o /dev/null -m 5 -w '%{http_code} ' http://127.0.0.1/api/report
done; echo
```

| 出方 | 意味 |
| --- | --- |
| 全部同じコード | プロキシの設定か、全台に共通の問題 |
| **3回に1回だけ失敗** | **特定の1台だけの問題**(3台に順番に振られているため) |

振り分け台数と失敗の周期を照らし合わせるのが基本。

### 経路を分解して叩く

nginxを飛ばしてバックエンドを直接叩けば、どちらの問題か二分できる。

```bash
curl -sS -i -m 5 http://127.0.0.1:9001/healthz          # 生きているか
curl -sS -i -m 5 http://127.0.0.1:9001/api/report       # 直接だと何が返るか
```

ここで重要なのは、**直接叩くとプロキシが付けているヘッダが無い状態になる**こと。だから直接だと違う結果になることがある。何を付ければ通るのかを確かめれば、そのままプロキシに足りないものが分かる。

```bash
curl -sS -i -m 5 -H 'Host: ...' -H 'X-Forwarded-Proto: ...' http://127.0.0.1:9001/api/report
```

何を付けるべきかは`/opt/backend/README`に書いてある。

### 通常は通るのに特定の操作だけ失敗するとき

```bash
curl -sS -o /dev/null -m 20 -w '%{http_code} %{time_total}s\n' http://127.0.0.1/api/report
curl -sS -o /dev/null -m 20 -w '%{http_code} %{time_total}s\n' http://127.0.0.1/api/slow
```

**時間のかかる処理だけ失敗する**なら、タイムアウトの設定を疑う。プロキシ側の待ち時間がアプリの処理時間より短いと、アプリは正常に動いているのにプロキシが先に諦めて`504`を返す。

---

# コマンド集(カテゴリ別)

## 1. 経路のどこまで通るか

```bash
curl -sS -i -m 5 http://127.0.0.1/api/report              # 利用者と同じ経路
curl -sS -o /dev/null -m 5 -w '%{http_code}\n' http://127.0.0.1/api/report
curl -sSv -m 5 http://127.0.0.1/api/report                # 送受信ヘッダも見る

for i in $(seq 1 9); do                                    # 何回かに1回か調べる
  curl -sS -o /dev/null -m 5 -w '%{http_code} ' http://127.0.0.1/api/report
done; echo

curl -sS -o /dev/null -m 20 \
  -w 'code=%{http_code} connect=%{time_connect}s start=%{time_starttransfer}s total=%{time_total}s\n' \
  http://127.0.0.1/api/slow
```

## 2. nginxの状態と設定

```bash
systemctl status nginx
sudo nginx -t                      # 設定の文法チェック
sudo nginx -T                      # 読み込まれる設定を全部展開して表示
sudo systemctl reload nginx        # 設定だけ読み直す(接続は切らない)
sudo systemctl restart nginx

ls -la /etc/nginx/conf.d/
sudo cat /etc/nginx/conf.d/reports.conf
sudo grep -rn 'proxy_' /etc/nginx/
```

**設定を直したら必ず`nginx -t`。** 文法エラーがあると`reload`は失敗し、古い設定のまま動き続ける(あるいは`restart`で落ちる)。

## 3. nginxのログ

```bash
sudo tail -30 /var/log/nginx/access.log
sudo tail -f /var/log/nginx/access.log
sudo tail -30 /var/log/nginx/error.log        # 接続失敗の理由はこちら
sudo grep -c ' 502 ' /var/log/nginx/access.log
sudo awk '{print $2}' /var/log/nginx/access.log | sort | uniq -c   # コード別の件数
sudo grep 'upstream=' /var/log/nginx/access.log | awk '{print $6, $2}' | sort | uniq -c
```

| ログ | 何が分かるか |
| --- | --- |
| `access.log` | どの台に振られ、そこが何を返したか、何秒かかったか |
| `error.log` | **繋がらなかった理由**(`connect() failed`、`upstream timed out` など) |

## 4. バックエンドを直接叩く

```bash
curl -sS -i -m 5 http://127.0.0.1:9001/healthz
curl -sS -i -m 5 http://127.0.0.1:9002/healthz
curl -sS -i -m 5 http://127.0.0.1:9003/healthz

# プロキシが付けるはずのヘッダを自分で付けて確かめる
curl -sS -i -m 5 -H 'Host: reports.internal' -H 'X-Forwarded-Proto: https' \
  http://127.0.0.1:9001/api/report
```

**ヘッダを付けると通り、付けないと通らない**なら、プロキシがそれを渡せていない。

## 5. バックエンドの状態

```bash
systemctl is-active backend@9001 backend@9002 backend@9003
systemctl status backend@9002 --no-pager
sudo systemctl start backend@9002
sudo journalctl -u backend@9002 -n 20 --no-pager
sudo journalctl -u 'backend@*' -n 30 --no-pager     # 3台まとめて

sudo ss -tlnp | grep 900                            # 実際に待ち受けているポート
sudo lsof -i :9002
```

**設定に書いてあるポートと、実際にlistenしているポートを突き合わせる。** 片方だけ見ても分からない。

## 6. ヘッダを確認する

```bash
curl -sSv -m 5 http://127.0.0.1/api/report 2>&1 | grep '^[<>]'    # 送受信ヘッダ
sudo grep -n 'proxy_set_header' /etc/nginx/conf.d/reports.conf
sudo journalctl -u 'backend@*' -n 10 --no-pager                   # 受け取った側の記録
cat /opt/backend/README                                            # 何を期待しているか
```

このバックエンドは受け取ったヘッダをログに残すので、**送った側と受け取った側を突き合わせられる**。

## 7. タイムアウトを切り分ける

```bash
sudo grep -n 'timeout' /etc/nginx/conf.d/reports.conf
curl -sS -o /dev/null -m 30 -w '%{http_code} %{time_total}s\n' http://127.0.0.1/api/slow
curl -sS -o /dev/null -m 30 -w '%{http_code} %{time_total}s\n' \
  -H 'Host: reports.internal' -H 'X-Forwarded-Proto: https' http://127.0.0.1:9001/api/slow
```

**プロキシ経由だと504、直接だと200**なら、アプリではなくプロキシの待ち時間が短い。

| 設定 | 意味 |
| --- | --- |
| `proxy_connect_timeout` | 接続確立までの待ち時間 |
| `proxy_read_timeout` | **応答を読み取る間の無通信の許容時間**。長い処理はここに引っかかる |
| `proxy_next_upstream` | 失敗したとき他の台に回すか。`off`だと1台の障害がそのまま利用者に出る |
| `max_fails` / `fail_timeout` | 失敗した台を一時的に切り離す条件。`max_fails=0`は**切り離さない** |

## 8. 復旧を確認する

```bash
for i in $(seq 1 12); do
  curl -sS -o /dev/null -m 6 -w '%{http_code} ' http://127.0.0.1/api/report
done; echo
curl -sS -o /dev/null -m 20 -w '%{http_code}\n' http://127.0.0.1/api/slow
sudo tail -5 /var/log/nginx/access.log
ls -l /var/lib/proxy-watchdog/flag.txt
```

**1回ではなく複数回叩く。** 3台のうち1台だけ壊れている場合、1回の成功では何も証明できない。

---

## 注入される障害

| 障害 | 症状 | 決め手 |
| --- | --- | --- |
| バックエンドが1台落ちている | 3回に1回`502` | `systemctl is-active`、`access.log`の`upstream=` |
| 振り分け先のポートが違う | 3回に1回`502`(**上と同じ症状**) | 台は動いているのに繋がらない。設定と`ss -tlnp`を突き合わせる |
| 読み取りタイムアウトが短い | 通常は`200`、**遅い処理だけ`504`** | 直接叩くと通る。設定の`timeout` |
| `Host`を渡していない | 全部`404` | バックエンドまで届いている。受け取ったHostをログで確認 |
| プロトコルのヘッダを渡していない | 全部`301`(リダイレクトが続く) | 同上。バックエンドの期待を読む |
| 設定に文法エラー | **接続できない** | `nginx -t`、`systemctl status nginx` |

上2つは**症状が完全に同じ**になる。片方はプロセスが死んでいて、もう片方は生きているのに繋ぎ先が違う。そこを見分けるのが練習どころ。

## 使い方

```bash
./new-case.sh                  # ランダムに1つ注入して起動
./new-case.sh <障害ID>         # 指定して注入(復習用)
./verify.sh --status           # 今の状態
./verify.sh 'FLAG{...}'        # 答え合わせ
./teardown.sh                  # 片付け
```

障害IDは`backend-down` / `wrong-upstream-port` / `timeout-short` / `missing-host-header` / `missing-proto-header` / `config-syntax`。**最初は指定せずにランダムで回すこと。**

直したあとは見張り役の次の巡回(最大10秒ほど)を待つ必要がある。

## 補足

`systemd`をコンテナで動かすため、`docker-compose.yml`では`privileged: true`を指定している。学習用の閉じた環境なので許容しているが、通常のコンテナ運用で真似する設定ではない。
