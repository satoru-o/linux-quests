# quest-07: network-triage

前提セットアップは不要。ビルドしてすぐ挑戦できる。

## これは何か

01〜06は「壊れているものを直す」クエストだった。一度解くと答えを覚えてしまうので、二度目からは練習にならない。

これは**診断の型を身につけるためのドリル**で、性質が違う。

- `./new-case.sh`を実行するたびに、**ランダムに違う故障**が1つ仕込まれる
- やることは修理ではなく**診断**。原因を突き止めて`./answer.sh`で申告する
- 当たればFLAG。何度でも回せる

「なんとなく触ってたら直った」を防ぐために、直す前に**原因を言い当てる**形式にしてある。当てずっぽうで直すのは、実務では一番やってはいけないやつなので。

## 正常な状態

`probe`コンテナから`target`コンテナへ、HTTPで疎通できるのが正常。

```bash
docker compose exec probe curl -sS -m 5 http://target:8080/health
# 正常なら 200 で "ok" が返る
```

症例が仕込まれている間は、これが何らかの形で失敗する。

## 難易度

```bash
./new-case.sh          # 初級(8種)から1つ
./new-case.sh --hard   # 上級(6種)から1つ
./new-case.sh --all    # 全14種から1つ
```

初級は「どの層で止まったか」が観測結果に素直に出る。上級はパケットフィルタやIP制限、タイムアウトの境目など、**下の層が正常に見えるのに通らない**ものが混ざる。まず初級を一巡してから上級に進むのがおすすめ。

## 診断の型

**下の層から順に潰す。** これが型のすべてで、いきなり上を疑わないのが肝心。各段は「ここまでは正常だった」と言い切れる状態を積み上げていく作業になる。

| 段 | 問い | コマンド | 分かること |
| --- | --- | --- | --- |
| 1 | プロセスは生きているか | `docker compose ps -a` | `exited`なら以降を調べる意味がない |
| 2 | 期待どおりlistenしているか | `docker compose exec target ss -tlnp` | **どのアドレスの何番**で待っているか |
| 3 | 名前は引けるか / どこを指すか | `docker compose exec probe getent hosts target` | 引けるか、引けたとして**どのIPか** |
| 4 | TCPで繋がるか | `docker compose exec probe nc -z -w2 target 8080` | 拒否されるか、無反応か、開くか |
| 5 | アプリが正しく返すか | `docker compose exec probe curl -sSv -m 5 http://target:8080/health` | ステータス行が返るか、返るなら何番か |

ただし第2段が正常でも通らないことがある（フィルタ）。「listenしているのに届かない」を見たら、ビットではなく**経路上で落とされていないか**を疑う。

## curlのエラーで大きく分ける

まずここで候補を絞るのが早い。`curl`はエラーの種類を番号と文言で区別してくれる。

| curlの結果 | 何が起きたか | 候補 |
| --- | --- | --- |
| `(6)` / `(28) Resolving timed out` | 名前解決で止まった | `process-down` / `network-split` |
| `(7) Failed to connect ... after 1 ms` | **RSTが即座に返った**＝届いた上で拒否された | `bind-localhost` / `wrong-port` / `firewall-reject` |
| `(28) Connection timed out` | **SYNへの応答が無い**＝そもそも届いていない | `wrong-address` / `firewall-drop` |
| `(28) Operation timed out ... with 0 bytes received` | **接続はできた**が応答が来ない | `blackhole` / `slow-response` |
| `(56) Recv failure: Connection reset by peer` | 接続後に切られた | `empty-reply` |
| HTTPステータスが返る | アプリまで到達している | `app-error` / `app-notfound` / `ip-allowlist` / `wrong-host` |

`(28)`が2種類あるのが要注意。**`Connection timed out`（繋がらない）と`Operation timed out ... with 0 bytes received`（繋がったが返らない）はまったく別物**で、疑う層が1段ずれる。

## グループごとの決め手

### 名前解決で止まった

```bash
docker compose ps -a
```

`exited`なら`process-down`。`running`なのに引けないなら、相手はいるのに見えていない。所属ネットワークを直接比べる。

```bash
docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' $(docker compose ps -q probe)
docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' $(docker compose ps -q target)
```

### 即座に拒否された

```bash
docker compose exec target ss -tlnp
```

- ポート番号が想定と違う → `wrong-port`
- アドレスが`127.0.0.1` → `bind-localhost`
- **`0.0.0.0:8080`で正しく待っている** → listenは正常なのに拒否されている。フィルタを見る

```bash
docker compose exec target iptables -L INPUT -n -v
```

`REJECT`のルールがあり、パケットカウンタが増えていれば`firewall-reject`。

### 繋がらない(無反応)

```bash
docker compose exec probe getent hosts target
```

返ってきたIPが`target`のものと違えば`wrong-address`。正しいのに届かないならフィルタを疑う。

```bash
docker compose exec target iptables -L INPUT -n -v
```

`DROP`のルールでカウンタが増えていれば`firewall-drop`。**DROPは何も返さない**ので送信側からは無反応に見える、というのがREJECTとの違い。

### 繋がったが応答が来ない

タイムアウトを伸ばして、待てば返るのかを確かめる。

```bash
docker compose exec probe curl -sS -m 30 -o /dev/null \
  -w 'code=%{http_code} start=%{time_starttransfer}s\n' http://target:8080/health
```

- 待てば`200`が返る → `slow-response`（アプリは動いている。遅いだけ）
- いくら待っても返らない → `blackhole`

### ステータスが返る

| 番号 | 候補 | 次に見るもの |
| --- | --- | --- |
| `403` | `ip-allowlist` | サーバログ。送信元IPで弾かれていないか |
| `5xx` | `app-error` | アプリのログ(トレースバック) |
| `404` | `app-notfound` または `wrong-host` | 下記 |

`404`が2種類あるので、Hostヘッダを付け替えて切り分ける。

```bash
docker compose exec probe curl -sS -m 5 -o /dev/null -w '%{http_code}\n' \
  -H 'Host: reports.internal' http://target:8080/health
```

これで`200`になれば`wrong-host`（ホスト名で振り分けていた）。`404`のままなら、そもそもそのパスが無い。

## 第5段のやり方(ここで詰まりやすい)

第4段(`nc -z`)まで全部シロだった場合、残りは第5段のものしかない。ところがここは`ss`や`getent`のように「見れば分かる」出力が出ないので、**証拠の集め方を知らないと手が止まる**。

### まず二分する: ステータス行が返るか

```bash
docker compose exec probe curl -sSv -m 5 http://target:8080/health
```

`-v`を付けたときに`<`で始まる行が**1行でも返るかどうか**。

- `< HTTP/1.1 ...`が返る → アプリは応答している。あとは番号を読むだけ
- 何も返らない → 以下で詰める

### ステータス行が返らないときの詰め方

**(a) `curl -v`の3行を並べて読む**

```
* Connected to target (172.19.0.3) port 8080     ← 繋がった
* Request completely sent off                     ← 送りきった
* Operation timed out ... with 0 bytes received   ← 1バイトも返らない
```

この3つが揃っていたら経路の問題ではない。経路が悪ければ`Connected`が出ない。

**(b) 時間を分けて測る**

```bash
docker compose exec probe curl -sS -m 5 -o /dev/null \
  -w 'connect=%{time_connect}s starttransfer=%{time_starttransfer}s\n' \
  http://target:8080/health
```

`connect`が一瞬で終わっているのに`starttransfer`が`0.000000`なら、繋ぐのは即座にできていて応答だけが始まっていない。

**(c) サーバ側の接続状態を見る**

```bash
docker compose exec target ss -tn
```

- `ESTAB` … 接続が生きたまま保持されている
- `CLOSE-WAIT` … **相手は切ったのに、こちら側のアプリがまだ閉じていない**

`CLOSE-WAIT`が`curl`を叩いた回数だけ溜まっていくなら、アプリが接続を掴んだまま離していない証拠。待機中の状態を見たいならこうする。

```bash
docker compose exec -T probe curl -sS -m 10 http://target:8080/health &
sleep 1
docker compose exec target ss -tn
```

**(d) アクセスログが「無い」ことを証拠にする**

```bash
docker compose logs target
```

アクセスログは**応答を返し終えた時点で**書かれる。接続はできているのに1行も出ていないなら、応答が完了していないということ。

### 「わからん」となったときの立て直し方

証拠が足りないのではなく、**どの段まではシロだと言い切れるかを言語化していない**ことがほとんど。書き出してみる。

```
第1段 プロセス生存 : シロ (Up)
第2段 listen       : シロ (0.0.0.0:8080)
第3段 名前解決     : シロ (172.19.0.3、targetのIPと一致)
第4段 TCP          : シロ (nc succeeded)
第5段 アプリ応答   : クロ  ← 残ったのはここだけ
```

診断とは、消去法で容疑者を減らしていく作業のこと。

---

# コマンド集(カテゴリ別)

このドリルの`probe`と`target`には、以下の道具が入っている。暗記する必要はないので、ここを見ながら回してよい。

## 1. プロセスとコンテナ

```bash
docker compose ps -a                      # 停止済みも含めて一覧
docker compose logs target                # 標準出力/エラー
docker compose logs -f --tail=50 target   # 追いかける
docker compose top target                 # コンテナ内のプロセス一覧
docker inspect --format '{{.State.Status}} exit={{.State.ExitCode}}' \
  $(docker compose ps -aq target)         # 状態と終了コード

docker compose exec target ps aux         # 中から見たプロセス
```

## 2. リッスン状態とソケット

```bash
docker compose exec target ss -tlnp       # TCPのlisten一覧(プロセス付き)
docker compose exec target ss -ulnp       # UDP版
docker compose exec target ss -tn         # 確立済み接続の状態
docker compose exec target ss -tan        # listen+確立をまとめて
docker compose exec target ss -s          # ソケットのサマリ

docker compose exec target ss -tn state established
docker compose exec target ss -tn state close-wait
```

見るべきは`Local Address:Port`。`0.0.0.0`は全インターフェース、`127.0.0.1`は自分の中だけ、`[::]`はIPv6。

## 3. 名前解決 (DNS)

```bash
docker compose exec probe getent hosts target   # OSの解決順に従って引く(実アプリに近い)
docker compose exec probe nslookup target
docker compose exec probe dig target +short
docker compose exec probe dig target            # 応答の詳細(SERVFAIL/NXDOMAIN等)

docker compose exec probe cat /etc/hosts        # 静的な上書きが無いか
docker compose exec probe cat /etc/resolv.conf  # どのDNSに聞きに行くか
```

`getent`と`dig`は挙動が違う。`/etc/hosts`の上書きは`getent`には効くが`dig`には効かない。**アプリの挙動を再現したいなら`getent`**。

## 4. 到達性(TCP・経路)

```bash
docker compose exec probe nc -z -w2 target 8080        # TCPで繋がるかだけ試す
docker compose exec probe nc -z -w2 -v target 8080     # 理由も出す
docker compose exec probe sh -c 'time nc -z -w3 target 8080'  # 即断か時間切れか

docker compose exec probe ip addr                      # 自分のIPとインターフェース
docker compose exec probe ip route                     # 経路表
docker compose exec probe ip neigh                     # ARPテーブル
docker compose exec probe ping -c 3 target             # ICMPでの到達性
docker compose exec probe traceroute target            # 経路
```

`nc`が**即座に**失敗するか**待たされて**失敗するかは重要な情報。即座＝拒否された（届いている）、待たされる＝無反応（届いていない）。

## 5. パケットフィルタ

```bash
docker compose exec target iptables -L -n -v           # 全チェーン(カウンタ付き)
docker compose exec target iptables -L INPUT -n -v     # 受信側だけ
docker compose exec target iptables -S                 # ルールをコマンド形式で
docker compose exec target iptables -Z                 # カウンタをゼロクリア
```

**`-v`のパケットカウンタが効く。** 一度クリアしてから`curl`を1回叩き、増えたルールが犯人。

```bash
docker compose exec target iptables -Z
docker compose exec probe curl -sS -m 3 http://target:8080/health
docker compose exec target iptables -L INPUT -n -v
```

`DROP`と`REJECT`の違いも押さえておく。

| ターゲット | 送信側から見た挙動 |
| --- | --- |
| `DROP` | 何も返さない。**タイムアウトするまで無反応** |
| `REJECT --reject-with tcp-reset` | RSTを返す。**即座に「接続拒否」** |
| `REJECT`(既定) | ICMP unreachableを返す。即座に失敗 |

## 6. HTTP・アプリ層

```bash
docker compose exec probe curl -sSv -m 5 http://target:8080/health   # 詳細表示
docker compose exec probe curl -sSi -m 5 http://target:8080/health   # ヘッダ込み
docker compose exec probe curl -sS -m 5 -o /dev/null -w '%{http_code}\n' \
  http://target:8080/health                                          # コードだけ

docker compose exec probe curl -sS -m 5 -H 'Host: reports.internal' \
  http://target:8080/health                                          # Hostを差し替える
docker compose exec probe curl -sS -m 5 -X POST http://target:8080/health
docker compose exec probe curl -sSI -m 5 http://target:8080/health   # HEADだけ
docker compose exec probe curl -sSL -m 5 http://target:8080/health   # リダイレクト追従
docker compose exec probe curl -sS -m 30 http://target:8080/health   # 待ち時間を伸ばす

docker compose exec probe curl -sS --resolve target:8080:172.19.0.9 \
  -m 5 http://target:8080/health                                     # 名前解決を手で上書き
```

HTTPを喋らずに生で会話することもできる。

```bash
docker compose exec probe sh -c \
  'printf "GET /health HTTP/1.0\r\nHost: target\r\n\r\n" | nc -w 5 target 8080'
```

これで返事が無ければ、curlの問題ではなくサーバが返していない。

## 7. パケットを直接見る

どうしても分からないときの最終手段。「送ったのに返ってこない」のか「そもそも出ていない」のかが確定する。

```bash
docker compose exec target tcpdump -n -i any port 8080          # targetに届いているか
docker compose exec probe  tcpdump -n -i any port 8080          # probeから出ているか
docker compose exec target tcpdump -n -i any -c 10 'tcp port 8080'
docker compose exec target tcpdump -nn -i any 'tcp port 8080 and tcp[tcpflags] & tcp-syn != 0'
```

読み方の目安。

| 見えたもの | 意味 |
| --- | --- |
| `S`のみが繰り返される | SYNを送っているが応答が無い。届いていないか捨てられている |
| `S` → `R`(RST) | 届いた上で拒否されている |
| `S` → `S.` → `.` | ハンドシェイク成立。以降はアプリの問題 |
| ハンドシェイク後に無音 | アプリが応答していない |

別ターミナルで`tcpdump`を回しながら`curl`を叩くと分かりやすい。

## 8. 計測とタイミング

```bash
docker compose exec probe curl -sS -m 10 -o /dev/null -w '
  dns=%{time_namelookup}s
  connect=%{time_connect}s
  starttransfer=%{time_starttransfer}s
  total=%{time_total}s
  code=%{http_code}
' http://target:8080/health
```

どの区間で時間を食っているかで、疑う層が決まる。

| 遅い区間 | 疑うもの |
| --- | --- |
| `time_namelookup` | DNS |
| `time_connect` | 経路、フィルタ、相手の受け入れ |
| `time_starttransfer` | **アプリの処理時間**(ネットワークではない) |

`starttransfer`が`0.000000`のまま終わったら、応答が一度も始まっていないということ。

---

## 使い方

```bash
./new-case.sh          # 初級から1つ
./new-case.sh --hard   # 上級から1つ
./new-case.sh --all    # 全部から1つ
```

型に沿って診断する。分かったら申告する。

```bash
./answer.sh --list     # 申告できる原因の一覧
./answer.sh <原因ID>   # 申告する
./answer.sh --giveup   # 降参して答えを見る
```

## 申告できる原因

### 初級

| 原因ID | 内容 | 該当する段 |
| --- | --- | --- |
| `process-down` | プロセス/コンテナ自体が動いていない | 1 |
| `bind-localhost` | `127.0.0.1`でlistenしていて外から届かない | 2 |
| `wrong-port` | 想定と違うポートでlistenしている | 2 |
| `network-split` | 相手と別のネットワークにいて名前が引けない | 3 |
| `wrong-address` | 名前は引けるが、想定と違うアドレスを指している | 3 |
| `blackhole` | TCPは繋がるが応答が返ってこない | 4と5の境目 |
| `app-error` | HTTPは通るがアプリがエラーを返す(5xx) | 5 |
| `app-notfound` | HTTPは通るがそのパスが存在しない(4xx) | 5 |

### 上級

| 原因ID | 内容 | 紛らわしい相手 |
| --- | --- | --- |
| `firewall-drop` | パケットフィルタが黙って捨てている | `wrong-address`(どちらも無反応) |
| `firewall-reject` | パケットフィルタがRSTで拒否している | `bind-localhost`/`wrong-port`(どちらも即拒否) |
| `slow-response` | 応答は返るが、クライアントのタイムアウトより遅い | `blackhole`(既定の待ち時間では区別できない) |
| `empty-reply` | 接続直後に切られ、応答が空で返る | `blackhole`(どちらも中身が返らない) |
| `ip-allowlist` | 送信元IPで弾かれている(403) | `app-error`(どちらもアプリが返す) |
| `wrong-host` | Hostヘッダが想定と違い、振り分け先を間違えている | `app-notfound`(どちらも404) |

上級はすべて「**下の層が正常に見えるのに通らない**」という形をしている。`ss`が正常、`getent`が正常、それでも駄目なときに何を見るかが問われる。

## 続け方

日を空けて何度か回すのがおすすめ。初級をノーヒントで型どおりに処理できるようになったら`--hard`へ。

余裕があれば、申告したあとに**実際に直して**`curl`が200を返すところまでやるとより実践的になる(仕込みは`docker-compose.override.yml`に書かれている)。

## 後片付け

```bash
./teardown.sh
```

## 補足

現在の症例は`.state`にハッシュで保存してある(平文の答えは置いていない)。とはいえ`docker-compose.override.yml`を見れば仕込みは分かるので、自分を騙さないように。
