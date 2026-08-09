# quest-14: tls-triage

前提セットアップは不要。`./new-case.sh`を叩けばサーバが立ち上がる。

## 状況

監視からアラートが上がっている。

```
[CRITICAL] ip-10-0-5-14 : https://reports.internal への接続が検証に失敗
```

証明書の入れ替え作業が入ったらしいが、**何をしたかは聞けていない**。

**SSHで入って、原因を突き止めて復旧させること。**

```bash
./new-case.sh
```

## これは何か

[quest-10](../quest-10-disk-pressure/)〜[quest-13](../quest-13-proxy-triage/)と同じ「サーバに入って復旧する」形式のTLS版。障害はランダムに注入される。

TLSの厄介さは、**エラーメッセージが同じでも原因が正反対のことがある**点にある。サーバ側が足りないのか、クライアント側が足りないのか。証明書そのものが悪いのか、置き方が悪いのか。ここを切り分ける型を身につける。

## 入り方

```bash
ssh -i ssh/id_ed25519 -p 2226 \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  ec2-user@localhost
```

鍵は初回の`./new-case.sh`で自動生成される(`ssh/`はgit管理外)。`ec2-user`は`sudo`が使える。

## サーバの構成

```
Reports Root CA
  └─ Reports Intermediate CA
       └─ reports.internal (サーバ証明書)
```

| 項目 | 内容 |
| --- | --- |
| 公開 | `https://reports.internal/api/report` (nginx、443番) |
| nginxが読む証明書 | `/etc/nginx/tls/server.crt` と `/etc/nginx/tls/server.key` |
| PKI資材 | `/opt/tls/` |
| 信頼ストア | `/usr/local/share/ca-certificates/` → `update-ca-certificates` |
| 成果物 | `/var/lib/tls-watchdog/flag.txt` (**検証つきの接続が通っている間だけ存在する**) |

**どの証明書をどこに置くべきかは、サーバの中に書いてある。** 推測する前に読むこと。

## ゴール

**検証つきの接続**が通るようになること。

```bash
curl https://reports.internal/api/report
```

これが`-k`なしで200を返すのがゴール。

> **`curl -k`で通ることは復旧ではない。** `-k`は検証を省略するオプションで、問題を消したのではなく見なかったことにしているだけ。ただし**切り分けには非常に有効**で、`-k`で通るなら「通信路もサーバも生きていて、失敗しているのは検証だけ」と確定できる。

```bash
cat /var/lib/tls-watchdog/flag.txt
./verify.sh --status
./verify.sh 'FLAG{...}'
```

## 診断の型

**「接続の問題か、検証の問題か」を最初に分ける。**

| 段 | 問い | コマンド |
| --- | --- | --- |
| 1 | そもそも繋がるか | `curl -k https://reports.internal/api/report` |
| 2 | 検証は何と言って失敗したか | `curl -v https://reports.internal/api/report` |
| 3 | サーバは何を送ってきているか | `openssl s_client -showcerts` |
| 4 | その証明書の中身は妥当か | `openssl x509 -noout -dates -subject -ext subjectAltName` |
| 5 | クライアントは何を信頼しているか | 信頼ストアの中身 |

第1段が効く。**`-k`で通れば、443は開いていてTLSハンドシェイク自体は成立している**。そこから先は「検証」だけの話になり、見る場所が一気に絞れる。逆に`-k`でも繋がらないなら、証明書の中身以前にnginxが動いていない。

### curlのエラーで分類する

| curlのエラー | 意味 | 疑うもの |
| --- | --- | --- |
| `(7) Failed to connect` | そもそも443が開いていない | **nginxが起動していない**。設定か鍵の問題 |
| `(60) certificate has expired` | 有効期限外 | 証明書の日付、**あるいはサーバの時刻** |
| `(60) no alternative certificate subject name matches` | 名前が一致しない | 証明書のSANと、接続に使ったホスト名 |
| `(60) self-signed certificate` | 自己署名 | 本来のCAが署名した証明書に戻す |
| `(60) unable to get local issuer certificate` | **連鎖をたどれない** | 下記の2通りがある |

### `unable to get local issuer certificate`は2通りある

このエラーが一番混乱しやすい。**サーバ側の問題とクライアント側の問題の両方でまったく同じ文言が出る。**

| 実際の原因 | どちらの問題か |
| --- | --- |
| サーバが中間CA証明書を送っていない | **サーバ側**。連鎖が途中で切れている |
| クライアントがルートCAを信頼していない | **クライアント側**。連鎖の根が無い |

割るには2つ見る。

**(a) サーバが何枚送ってきているか**

```bash
openssl s_client -connect reports.internal:443 -servername reports.internal </dev/null 2>/dev/null \
  | grep -E '^ *[0-9]+ s:'
```

```
 0 s:CN = reports.internal
 1 s:CN = Reports Intermediate CA      ← これが無ければサーバ側の問題
```

サーバ証明書1枚しか出てこないなら、**中間CAを含めた連鎖をnginxに設定していない**。

**(b) クライアントがルートCAを持っているか**

```bash
ls /usr/local/share/ca-certificates/
ls /etc/ssl/certs/ | grep -i reports
```

何も出てこないなら、**信頼ストアからルートCAが失われている**。

サーバが2枚送っているのに検証できないなら(b)、1枚しか送っていないなら(a)。ここで完全に割れる。

### 証明書と鍵が対応しているかを確かめる

nginxが起動しない場合、証明書と秘密鍵の組み合わせが合っていないことがよくある。**両者から取り出した係数を比べる**と一発で分かる。

```bash
sudo openssl x509 -noout -modulus -in /etc/nginx/tls/server.crt | openssl md5
sudo openssl rsa  -noout -modulus -in /etc/nginx/tls/server.key | openssl md5
```

この2つのハッシュが一致しなければ、その証明書と鍵は無関係な組み合わせ。

---

# コマンド集(カテゴリ別)

## 1. まず接続して結果を見る

```bash
curl -sS -i -m 8 https://reports.internal/api/report          # 検証つき(本番と同じ)
curl -ksS -i -m 8 https://reports.internal/api/report         # 検証を省く(切り分け用)
curl -v -m 8 https://reports.internal/api/report 2>&1 | grep -Ei 'ssl|certif|subject|issuer'
curl -sS -o /dev/null -m 8 -w '%{http_code} %{ssl_verify_result}\n' https://reports.internal/api/report

curl --cacert /opt/tls/rootCA.crt -sS -o /dev/null -m 8 \
  -w '%{http_code}\n' https://reports.internal/api/report     # CAを明示して試す
```

`--cacert`で明示して通るなら、**証明書は正しくて信頼ストアの側が問題**。

## 2. サーバが何を送っているか

```bash
openssl s_client -connect reports.internal:443 -servername reports.internal </dev/null
openssl s_client -connect reports.internal:443 -servername reports.internal </dev/null 2>/dev/null \
  | grep -E '^ *[0-9]+ s:|^ *[0-9]+ i:|Verify return code'
openssl s_client -connect reports.internal:443 -servername reports.internal -showcerts </dev/null
```

読み方。

| 行 | 意味 |
| --- | --- |
| `0 s:` | サーバ証明書の持ち主 |
| `0 i:` | それを署名した相手(発行者) |
| `1 s:` | 一緒に送られてきた中間CA。**無ければ連鎖が切れている** |
| `Verify return code: 0 (ok)` | 検証成功 |
| `Verify return code: 21` など | 検証失敗。番号で理由が分かる |

`-servername`はSNIの指定。**付け忘れると別の証明書が返ってくる**ことがあるので、常に付ける癖をつける。

## 3. 証明書の中身を読む

```bash
sudo openssl x509 -in /etc/nginx/tls/server.crt -noout -text | head -20
sudo openssl x509 -in /etc/nginx/tls/server.crt -noout -dates      # 有効期間
sudo openssl x509 -in /etc/nginx/tls/server.crt -noout -subject -issuer
sudo openssl x509 -in /etc/nginx/tls/server.crt -noout -ext subjectAltName
sudo openssl x509 -in /etc/nginx/tls/server.crt -noout -serial

# ファイルに何枚入っているか
sudo grep -c 'BEGIN CERTIFICATE' /etc/nginx/tls/server.crt

# 通信先から直接取って調べる
openssl s_client -connect reports.internal:443 -servername reports.internal </dev/null 2>/dev/null \
  | openssl x509 -noout -dates -subject -ext subjectAltName
```

| 見るところ | 何を確かめるか |
| --- | --- |
| `notBefore` / `notAfter` | 今がその範囲に入っているか(`date`と見比べる) |
| `subjectAltName` | **接続に使うホスト名が入っているか**。CNではなくこちらが見られる |
| `issuer` | 誰が署名したか。連鎖をたどる出発点 |

## 4. 連鎖を検証する

```bash
sudo openssl verify -CAfile /opt/tls/rootCA.crt \
  -untrusted /opt/tls/intermediate.crt /opt/tls/server.crt

sudo openssl verify -CAfile /opt/tls/rootCA.crt /opt/tls/server.crt   # 中間なしだと失敗する
sudo openssl verify -CAfile /opt/tls/rootCA.crt /opt/tls/intermediate.crt
```

**中間CAを`-untrusted`で渡すと通り、渡さないと通らない**なら、その中間CAをサーバが送る必要がある。

## 5. 証明書と鍵の対応

```bash
sudo openssl x509 -noout -modulus -in /etc/nginx/tls/server.crt | openssl md5
sudo openssl rsa  -noout -modulus -in /etc/nginx/tls/server.key | openssl md5
sudo openssl rsa -in /etc/nginx/tls/server.key -check -noout      # 鍵自体が壊れていないか
```

ハッシュが一致しなければ組み合わせが間違っている。

## 6. クライアント側の信頼ストア

```bash
ls -la /usr/local/share/ca-certificates/          # 追加したCAの置き場所
ls /etc/ssl/certs/ | grep -i reports              # 反映されているか
sudo update-ca-certificates                       # 追加を反映する
sudo update-ca-certificates --fresh               # 作り直す

openssl x509 -in /usr/local/share/ca-certificates/reports-root.crt -noout -subject
curl --cacert /opt/tls/rootCA.crt -sS -o /dev/null -w '%{http_code}\n' \
  https://reports.internal/api/report
```

**CAファイルを置いただけでは効かない。** `update-ca-certificates`で反映して初めて`curl`や各種ライブラリが見るようになる。

## 7. nginxの設定とログ

```bash
sudo nginx -t
sudo nginx -T | grep -A5 'ssl_certificate'
sudo grep -n 'ssl_' /etc/nginx/conf.d/reports.conf
sudo systemctl status nginx --no-pager
sudo journalctl -u nginx -n 20 --no-pager
sudo tail -20 /var/log/nginx/error.log
sudo ss -tlnp | grep 443
```

**証明書を差し替えたら`reload`が必要。** ファイルを置いただけでは反映されない。`nginx -t`で先に文法と読み込みを確認する。

## 8. 時刻とPKI資材の確認

```bash
date                                    # サーバの時刻がずれていないか
sudo openssl x509 -in /etc/nginx/tls/server.crt -noout -dates

ls -la /opt/tls/                        # 正規の資材が何であるか
cat /opt/tls/README                     # 構成の説明
sudo grep -c 'BEGIN CERTIFICATE' /opt/tls/fullchain.crt   # 連鎖入りは2枚
```

「期限切れ」と出たとき、**証明書が古いのか、サーバの時計が進んでいるのか**は別の話。両方確かめる。

---

## 注入される障害

| 障害 | curlのエラー | 決め手 |
| --- | --- | --- |
| 証明書の期限切れ | `certificate has expired` | `-dates`と`date`を見比べる |
| 別ホスト名の証明書 | `no alternative certificate subject name matches` | `subjectAltName`を見る |
| 中間CAを送っていない | `unable to get local issuer certificate` | **`s_client`で送られる枚数が1枚** |
| 信頼ストアにCAが無い | `unable to get local issuer certificate` | **枚数は2枚。信頼ストア側が空** |
| 自己署名証明書 | `self-signed certificate` | `issuer`が自分自身 |
| 証明書と鍵が不一致 | `Failed to connect`(nginxが起動しない) | `modulus`のハッシュ比較 |

3番目と4番目は**エラーメッセージが完全に同じ**になる。サーバ側の問題とクライアント側の問題という正反対の原因なので、ここを取り違えると延々と間違った側をいじることになる。

## 使い方

```bash
./new-case.sh                  # ランダムに1つ注入して起動
./new-case.sh <障害ID>         # 指定して注入(復習用)
./verify.sh --status           # 今の状態
./verify.sh 'FLAG{...}'        # 答え合わせ
./teardown.sh                  # 片付け
```

障害IDは`cert-expired` / `wrong-san` / `missing-chain` / `ca-untrusted` / `key-mismatch` / `self-signed`。**最初は指定せずにランダムで回すこと。**

直したあとは見張り役の次の巡回(最大10秒ほど)を待つ必要がある。

## 補足

`systemd`をコンテナで動かすため、`docker-compose.yml`では`privileged: true`を指定している。学習用の閉じた環境なので許容しているが、通常のコンテナ運用で真似する設定ではない。
