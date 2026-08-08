# quest-09: auth-triage

前提セットアップは不要。ビルドしてすぐ挑戦できる。

## これは何か

[quest-07](../quest-07-network-triage/)・[quest-08](../quest-08-permission-triage/)と同じ**診断ドリル**の認証版。`./new-case.sh`を叩くたびにランダムな故障が1つ仕込まれ、原因を突き止めて`./answer.sh`で申告する。

認証まわりは「弾かれた」という事実だけは分かるが、**どこで弾かれたのかが見えにくい**。クライアントが送っていないのか、途中で消えたのか、届いたが中身が古いのか、届いて中身も正しいが権限が足りないのか。これらは全部別の問題なのに、手元には同じ`401`が返ってくる。そこを層ごとに切り分ける型を身につける。

## 構成

```
client  →  proxy  →  api
```

`client`から`api`を呼んで`200`が返るのが正常。

```bash
docker compose exec client /call.sh
```

## APIが期待していること

診断には「正解の状態」を知っている必要があるので、仕様は開示しておく。

| 項目 | 期待値 |
| --- | --- |
| ヘッダ | `Authorization: Bearer <JWT>` |
| 署名 | **HS256**。鍵は`docker-compose.yml`の`JWT_SECRET` |
| `aud` | `reports-api` |
| `scope` | `reports:read`を含むこと |
| `nbf` / `exp` | 現在時刻がこの範囲に入っていること |
| 失効 | 失効リストに載っていないこと |

## 難易度

```bash
./new-case.sh          # 初級(8種)から1つ
./new-case.sh --hard   # 上級(6種)から1つ
./new-case.sh --all    # 全14種から1つ
```

初級は「サーバのログを読めば、どこで弾かれたか」が分かる。上級は**サーバのログが同じになる**ものが混ざる。そこから先はトークンの中身を自分で開けて、期待値と突き合わせるしかない。

## 診断の型

**「弾かれた」で止めず、どの段で落ちたかを確定させる。**

| 段 | 問い | コマンド | 分かること |
| --- | --- | --- | --- |
| 1 | そもそも届いているか | `/call.sh`が応答を返すか | 応答が返っている時点でネットワークはシロ |
| 2 | ステータスコードは | レスポンスの1行目 | **401 / 403 / 429**のどれか(下記) |
| 3 | クライアントは何を送ったか | `docker compose exec client /call.sh` | 送信ヘッダの有無・スキーム・形 |
| 4 | サーバには何が届いたか | `docker compose logs api` | 受信ヘッダと、**どこで弾いたか** |
| 5 | トークンの中身は妥当か | `docker compose exec client /decode.sh` | ヘッダ(`alg`)とクレーム(`exp`/`nbf`/`aud`/`scope`/`sub`) |

### ステータスコードで大きく分ける

ここが認証診断の最重要ポイント。**同じ「失敗」でも意味する層が違う。**

| コード | 意味 | 含意 |
| --- | --- | --- |
| `401` | **認証**の失敗。あなたが誰か確認できない | トークンが無い・壊れている・期限外・宛先違い・失効 |
| `403` | **認可**の失敗。誰かは分かったが、その操作は許されていない | **トークン自体は有効**。期限も署名もaudも全部シロ。見るのは権限(scope)と**誰として認識されたか**(sub) |
| `429` | **どちらでもない**。回数制限 | 認証も認可も通っている。`Retry-After`を読む |

`403`が出ているのに期限や署名を疑い始めるのは完全な迷走。逆に`401`のときにscopeを眺めても意味がない。

## サーバのログで絞る

`docker compose logs api`には、**受け取ったヘッダ**と**どこで弾いたか**が残る。まずここを見る。

| サーバのログ | クライアントの送信 | 候補 |
| --- | --- | --- |
| `auth=(なし)` | 送っていない | `no-credential` |
| `auth=(なし)` | **送っている** | `proxy-strips-header` |
| `auth="Token ..."` | 送っている | `wrong-scheme` |
| `auth="Bearer Bearer ..."` | 送っている | `double-bearer` |
| `401 署名検証に失敗` | 送っている | `bad-signature` / **`wrong-algorithm`** |
| `401 クレーム検証に失敗` | 送っている | `token-expired` / `wrong-audience` / **`clock-skew`** |
| `401 トークンの形式が不正` | 送っている | `token-truncated` / `double-bearer` |
| `401 失効済みトークン` | 送っている | `revoked-token` |
| `403 スコープ不足 sub=analyst` | 送っている | `insufficient-scope` |
| `403 スコープ不足 sub=別人` | 送っている | **`proxy-overwrites-auth`** |
| `429 レート制限` | 送っている | `rate-limited` |

**ログが同じになる組が3つある。** そこから先は自分でトークンを開ける。

### 「署名検証に失敗」のとき

鍵が違うのか、アルゴリズムが違うのか。**ペイロードではなくヘッダ(第1セグメント)を見る。**

```bash
docker compose exec client /decode.sh
```

`"alg"`が`HS256`以外なら`wrong-algorithm`。`HS256`なのに失敗しているなら鍵が違う(`bad-signature`)。

### 「クレーム検証に失敗」のとき

期限切れか、宛先違いか、まだ有効になっていないか。**現在時刻と突き合わせる。**

| 観測 | 原因 |
| --- | --- |
| `exp` < 今 | `token-expired`(期限が過ぎた) |
| `nbf` > 今 | `clock-skew`(**まだ有効になっていない**) |
| `aud` が`reports-api`でない | `wrong-audience` |

`exp`も`nbf`も未来なのに弾かれる、という状態があり得るのがポイント。「期限内なのに通らない」ときは`nbf`を見る。

### 「トークンの形式が不正」のとき

```bash
docker compose exec client /decode.sh   # 末尾のセグメント数を見る
```

- セグメントが`3`未満 → `token-truncated`(欠けている)
- セグメントは`3`だが、サーバのログが`Bearer Bearer` → `double-bearer`

### `403`のとき

**`sub`を見る。** 自分のトークンの`sub`と、サーバが認識した`sub`が一致しているか。

| 観測 | 原因 |
| --- | --- |
| サーバの`sub`＝自分のトークンの`sub` | `insufficient-scope`(自分の権限が足りない) |
| サーバの`sub`≠自分のトークンの`sub` | `proxy-overwrites-auth`(**別人として扱われている**) |

## 経路のどこで消えたかを切り分ける

`proxy`を飛ばして`api`を直接叩けば、経路を二分できる。

```bash
docker compose exec -e TARGET=http://api:8080/reports client /call.sh
```

これが通って`proxy`経由が通らないなら、犯人は`proxy`。**送ったものと届いたものが違う**とき、その差を作っているのは必ず途中の誰か。

---

# コマンド集(カテゴリ別)

`client`コンテナには`curl`と`jq`が入っている。暗記する必要はないので、ここを見ながら回してよい。

## 1. 呼んで状態を確定させる

```bash
docker compose exec client /call.sh                    # 用意されている呼び出し
docker compose exec client curl -sS -i -m 5 \
  -H "Authorization: Bearer $(cat /creds/token)" \
  http://proxy:8080/reports                            # 手で組み立てる

docker compose exec client curl -sS -o /dev/null -w '%{http_code}\n' -m 5 \
  -H "Authorization: Bearer $(cat /creds/token)" http://proxy:8080/reports
```

`-i`でヘッダ込み、`-v`でリクエスト側のヘッダも見える。**`WWW-Authenticate`や`Retry-After`は本文ではなくヘッダに出る**ので、`-i`を付けないと見落とす。

## 2. クライアントが何を送ったか

```bash
docker compose exec client /call.sh | head -3          # 送信ヘッダを表示している
docker compose exec client curl -sSv -m 5 \
  -H "Authorization: Bearer $(cat /creds/token)" \
  http://proxy:8080/reports 2>&1 | grep '^>'           # 送信ヘッダだけ抜く

docker compose exec client cat /creds/token            # 手元のトークンそのもの
docker compose exec client sh -c 'wc -c < /creds/token'
```

`>`で始まる行が送信、`<`が受信。**送っているつもりで送っていない**が一番多い事故なので、ここは必ず目で確認する。

## 3. サーバに何が届いたか

```bash
docker compose logs api                                # 受信ヘッダと判定結果
docker compose logs -f api                             # 追いかける
docker compose logs api | grep '\[api\]' | tail -5     # 判定行だけ
docker compose logs proxy                              # 途中の経路のログ
```

第2段(送った)と第3段(届いた)を**並べて比べる**のがこのドリルの中心。差があれば犯人は経路にいる。

## 4. トークンの中身を開ける

```bash
docker compose exec client /decode.sh                  # ヘッダ+クレーム+現在時刻

# 手でやる場合(base64urlなので padding を足す必要がある)
docker compose exec client sh -c 'cut -d. -f1 /creds/token | base64 -d; echo'   # ヘッダ
docker compose exec client sh -c '
  P=$(cut -d. -f2 /creds/token | tr "_-" "/+")
  case $(( ${#P} % 4 )) in 2) P="$P==";; 3) P="$P=";; esac
  echo "$P" | base64 -d | jq .
'
```

見るべきクレーム。

| クレーム | 意味 | 突き合わせる相手 |
| --- | --- | --- |
| `alg`(ヘッダ) | 署名アルゴリズム | サーバが受け付ける値(`HS256`) |
| `sub` | 誰のトークンか | サーバのログの`sub` |
| `aud` | どのサービス宛か | `reports-api` |
| `scope` | 何をしてよいか | `reports:read` |
| `exp` | いつまで有効か | 現在時刻 |
| `nbf` | いつから有効か | 現在時刻 |
| `jti` | トークンの識別子 | 失効リスト |

**署名は手元では検証できない**(鍵が要る)。デコードで分かるのは「何を主張しているか」だけで、それが正しいかは別の話、という区別は持っておく。

## 5. 時刻を突き合わせる

```bash
docker compose exec client date -u                     # 現在時刻(UTC)
docker compose exec client date +%s                    # epoch

docker compose exec client sh -c 'echo 1786171662 | jq "todate"'   # epoch → ISO
docker compose exec client sh -c 'date -u -d @1786171662'          # 同上

# 残り時間を出す
docker compose exec client sh -c '
  P=$(cut -d. -f2 /creds/token | tr "_-" "/+")
  case $(( ${#P} % 4 )) in 2) P="$P==";; 3) P="$P=";; esac
  EXP=$(echo "$P" | base64 -d | jq -r .exp)
  NBF=$(echo "$P" | base64 -d | jq -r .nbf)
  NOW=$(date +%s)
  echo "now=$NOW nbf=$NBF exp=$EXP"
  echo "有効まで: $((NBF-NOW))秒 / 期限まで: $((EXP-NOW))秒"
'
```

**両方が正の数なら「まだ始まっていない」**、期限だけ負なら「切れている」。符号で読むと速い。

## 6. 経路を二分する

```bash
docker compose exec -e TARGET=http://api:8080/reports client /call.sh   # proxyを飛ばす
docker compose exec client curl -sS -i -m 5 \
  -H "Authorization: Bearer $(cat /creds/token)" http://api:8080/reports

docker compose exec client curl -sS -i -m 5 http://proxy:8080/reports   # 認証情報なしで
```

直接なら通る／経由すると駄目、が確認できれば、原因の場所は確定する。

## 7. HTTPステータスの読み分け

```bash
docker compose exec client curl -sS -i -m 5 \
  -H "Authorization: Bearer $(cat /creds/token)" \
  http://proxy:8080/reports | head -8                  # ステータス行とヘッダ
```

| コード | 名前 | 認証は | 意味 |
| --- | --- | --- | --- |
| `200` | OK | 成功 | 通っている |
| `400` | Bad Request | — | リクエストの組み立てがおかしい |
| `401` | Unauthorized | **失敗** | 実際には「未認証」。誰か分からない |
| `403` | Forbidden | **成功** | 誰かは分かった。その操作が許されていない |
| `429` | Too Many Requests | 成功 | 回数制限。`Retry-After`を見る |
| `5xx` | — | — | サーバ側の障害。認証の話ではない |

`401`と`403`の名前は紛らわしいが、**「401＝あなたが誰か分からない」「403＝あなたのことは分かったが駄目」**と覚えると間違えない。

## 8. 資格情報を差し替えて試す

推測で終わらせず、その場で検証する。

```bash
# わざと外して、症状が変わるか見る
docker compose exec client curl -sS -i -m 5 http://api:8080/reports

# スキームを変えて試す
docker compose exec client sh -c \
  'curl -sS -i -m 5 -H "Authorization: Token $(cat /creds/token)" http://api:8080/reports | head -1'

# 別のトークンで試す(proxy用のものが置いてある症例もある)
docker compose exec client sh -c 'ls -l /creds'
```

**症状が変わるかどうか**が情報になる。外しても同じ結果なら、そもそも送ったものが使われていない。

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
| `no-credential` | クライアントが認証情報を送っていない | 3 |
| `proxy-strips-header` | クライアントは送っているが、途中の経路で消えている | 3と4の差分 |
| `wrong-scheme` | スキームが`Bearer`ではない | 4 |
| `bad-signature` | 署名が合わない(鍵違いか改ざん) | 4 |
| `revoked-token` | 形式は正しいが失効済み | 4 |
| `token-expired` | 有効期限が切れている | 5 |
| `wrong-audience` | 別のサービス宛(`aud`違い)のトークン | 5 |
| `insufficient-scope` | 認証は通っているがスコープが足りない | 2 |

### 上級

| 原因ID | 内容 | 紛らわしい相手 |
| --- | --- | --- |
| `clock-skew` | 時計のズレで、まだ有効になっていない | `token-expired`(ログが同じ「クレーム検証に失敗」) |
| `wrong-algorithm` | 署名アルゴリズムが想定と違う | `bad-signature`(ログが同じ「署名検証に失敗」) |
| `double-bearer` | スキームが二重(`Bearer Bearer ...`) | `token-truncated`(ログが同じ「形式が不正」) |
| `token-truncated` | トークンが途中で欠けている | `double-bearer` |
| `proxy-overwrites-auth` | 途中の経路が別の資格情報で上書きしている | `insufficient-scope`(どちらも403) |
| `rate-limited` | 認証は通っているが回数制限(429) | — (コードで一発だが、401/403と混同しやすい) |

上級はすべて「**サーバのログまで見ても、まだ2つに割れない**」という形をしている。そこから先はトークンを開けて、期待値と突き合わせるしかない。

## 続け方

日を空けて何度か回すのがおすすめ。「401を見たらまず送信側と受信側を突き合わせる」「403を見たら期限を疑わない」「期限内なのに弾かれたら`nbf`を見る」が手癖になったら身についている。

## 後片付け

```bash
./teardown.sh
```

## 補足

現在の症例は`.state`にハッシュで保存してある(平文の答えは置いていない)。仕込みの実体は`docker-compose.override.yml`と`fixture/make_token.py`にあるので、見ようと思えば見える。自分を騙さないように。
