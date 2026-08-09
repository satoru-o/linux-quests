# quest-15: db-triage

DBが絡む障害の診断と復旧。アプリサーバにSSHで入り、そこから別サブネットのDBを叩いて直す。

## 状況

監視からアラートが上がっている。

```
[CRITICAL] ip-10-0-1-42 : レポートAPIの死活監視が失敗
```

```
  利用者 --> reportapi (ip-10-0-1-42:8080) --> reportdb.internal:5432
             アプリサブネット                   ip-10-0-101-7 / DBサブネット
             ここにSSHで入れる                  SSHは通っていない
```

直前にDB周りで何か変更が入ったらしいが、詳細は聞けていない。

## これは何か

`./new-case.sh`を叩くたびに、**12種類の障害からランダムに1つ**が仕込まれた環境が立ち上がる。何が仕込まれたかは表示されない。アプリサーバにSSHでログインし、原因を突き止めて復旧させる。

10〜14と同じ「サーバに入って直す」形式だが、壊れているのはOSではなく**DBの側**。ファイルを見て回っても答えは出てこないことが多く、**DB自身に今なにが起きているかを聞く**のが中心になる。

### DBには入れない

DBはマネージドなインスタンスのつもりで作ってある。**シェルも`postgresql.conf`も`pg_hba.conf`もサーバログのファイルも無い。** 触れるのは`psql`だけ。

ただし**SQLは好きなだけ叩ける。** マスターユーザー相当のロールが渡してあるので、`GRANT`も`ALTER ROLE`も`pg_terminate_backend`も通る。運用担当が実際にやることは全部できる。接続情報はアプリサーバの`/opt/reportdb/`にある。

```bash
./new-case.sh          # 初級・上級ぜんぶから1つ
./new-case.sh --hard   # 上級だけから1つ
```

## 入り方

```bash
./new-case.sh

ssh -i ssh/id_ed25519 -p 2227 \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  ec2-user@localhost
```

`ec2-user`は`sudo`が使える。

## 構成

**アプリサーバ `ip-10-0-1-42`** (SSH: 2227番)

| 項目 | 内容 |
| --- | --- |
| アプリ | `reportapi.service` → `http://127.0.0.1:8080` |
| アプリのソース | `/opt/reportapi/reportapi.py` |
| アプリの接続設定 | `/etc/reportapi/app.conf` |
| 保守用の接続情報 | `/opt/reportdb/maint.conf` (rootのみ) |
| **あるべき姿** | **`/opt/reportdb/README`** |
| バッチ | `conn-hog.service` / `lock-holder.service` (平常時は停止) |
| 成果物 | `/var/lib/db-watchdog/flag.txt` (**3つの機能が揃って通っている間だけ存在する**) |

**DB `ip-10-0-101-7`** (`reportdb.internal:5432`)

| 項目 | 内容 |
| --- | --- |
| PostgreSQL | 14 |
| 入り方 | `psql`のみ。SSHもシェルも無い |
| 見られないもの | `postgresql.conf` / `pg_hba.conf` / サーバログのファイル |
| 分かっている設定 | `max_connections = 30` (`/opt/reportdb/README`に記載) |

アプリは接続プールを持たず、リクエストごとに接続を張って閉じる。だからDB側の設定変更は、アプリを再起動しなくても次のリクエストから効く。

## ゴール

APIの3つの機能を全部通す。

| | 期待 |
| --- | --- |
| `GET /api/reports` | 200、かつ**1件以上**返る |
| `POST /api/reports` | 201 |
| `GET /api/summary` | 200、かつ**40件**返る |

見張り役が10秒ごとに3つとも叩いていて、全部通っている間だけ`/var/lib/db-watchdog/flag.txt`が現れる。サーバの中で取り出す。

```bash
cat /var/lib/db-watchdog/flag.txt
```

直した直後はまだ無いことがある。見張り役の巡回は10秒間隔なので、少し待ってからもう一度叩く。

> [!IMPORTANT]
> **一覧が200で返るだけでは復旧ではない。** 0件で200が返る壊れ方もある。

手元に戻って答え合わせ。

```bash
./verify.sh --status        # 今の状態を見る
./verify.sh 'FLAG{...}'     # 取得したFLAGを判定する
```

---

## 診断の型

DBの障害は「どこまでは届いているか」を上から詰めていく。

| 段 | 問い | 見るところ |
| --- | --- | --- |
| 1 | アプリまで届いているか | `curl http://127.0.0.1:8080/api/reports` |
| 2 | エラーはDBのものか | 500の本文。DBのメッセージがそのまま出る |
| 3 | **DBまで届いているか** | `getent hosts` / `nc -z` / `pg_isready` |
| 4 | 繋げるなら、接続を拒否されているか | `FATAL:` で始まるか |
| 5 | 繋がるなら、待たされているか | `pg_stat_activity`の`state`と`wait_event` |
| 6 | 待っていないなら、何を拒否されたか | メッセージが名指ししているオブジェクト |
| 7 | エラーも無いのに結果が違うなら | 行の可視性、名前解決、セッション設定 |

3段目を飛ばさないこと。**DBの障害に見えて、そこまで届いていないだけ**ということがある。届いていない場合、DBに何を聞いても答えは返ってこない。

### 保守用の接続

```bash
export $(sudo grep -v '^#' /opt/reportdb/maint.conf | xargs)
psql
```

`libpq`の環境変数名で書いてあるので、`export`すれば`psql`に引数は要らない。このロールはマスターユーザーなので、接続枠が埋まっていても予約枠で入れる。

### 一番効く一手

**アプリと同じロールで繋ぎ直す。**

保守用ロールで調べても分からないことが多い。権限もロール設定も行の見え方も**ロールごとに違う**からで、マスターユーザーで見ている限り、ほとんどの障害は再現しない。

```bash
PGCONNECT_TIMEOUT=5 \
PGPASSWORD=$(sudo grep DB_PASSWORD /etc/reportapi/app.conf | cut -d= -f2) \
  psql -h reportdb.internal -p 5432 -U reportapi -d reportdb
```

`PGCONNECT_TIMEOUT`を付けておくこと。付けないと、経路が塞がっているときに2分以上無言で待たされる。

「保守用で見ると正常、アプリのロールで繋ぐと落ちる」なら、それだけで**ロールに紐づく問題**だと分かる。逆に両方落ちるなら、ロールより下の層(経路、DB全体の設定、オブジェクトそのもの)を疑う。**この2つを見比べるのが切り分けの主軸**になる。

### 症状で分類する

| 見え方 | 疑うところ |
| --- | --- |
| **無言でタイムアウト** | **経路**。DBまで届いていない。DBは何も答えていない |
| `Connection refused` | 届いてはいるが、そのポートで誰も待っていない |
| `FATAL:` で始まる | **接続そのもの**。認証、接続数、ロールの状態 |
| `permission denied for ...` | **権限**。名指しされたオブジェクトの種類に注目 |
| `relation "..." does not exist` | 名前解決。**テーブルが無いとは限らない** |
| `canceling statement due to statement timeout` | 時間切れ。**遅いのか、待たされているのか、上限が短いのか** |
| `cannot execute ... in a read-only transaction` | 書き込み禁止の設定がどこかに乗っている |
| エラーは無いのに0件 | 行が見えていない |

### 同じメッセージで原因が正反対のもの

このクエストには**メッセージだけでは割れない組**が2つ仕込んである。

**その1: `relation "reports" does not exist`**

テーブルは確かに存在する。それでもこう出る。

| 実際の原因 | 決め手 |
| --- | --- |
| スキーマが見えていない | `has_schema_privilege('reportapi','app','USAGE')` が **false** |
| 探しに行く場所が変わっている | `pg_roles.rolconfig` の `search_path` が違う |

```sql
SELECT has_schema_privilege('reportapi', 'app', 'USAGE');
SELECT rolname, rolconfig FROM pg_roles WHERE rolname = 'reportapi';
```

**その2: `canceling statement due to statement timeout`**

同じ問い合わせが、片方は「重すぎる」から、もう片方は「上限が短すぎる」から死ぬ。

| 実際の原因 | 決め手 |
| --- | --- |
| 問い合わせが重くなった | 上限は変わっていない。`EXPLAIN`が全件走査になっている |
| 上限が短くされた | 計画は変わっていない。`rolconfig`の`statement_timeout`が違う |

どちらも**何秒で落ちたか**で当たりが付く。`curl -w '%{time_total}'`で測ると、上限そのものが変わっていれば落ちるまでの時間が変わる。

### `SHOW` の落とし穴

```sql
SHOW statement_timeout;
```

これは**今のセッションの値**を返す。保守用ロールで繋いだセッションで叩いても、`reportapi`に設定された値は出てこない。ロールやDBに貼られた設定はカタログを見る。

```sql
SELECT rolname, rolconfig FROM pg_roles WHERE rolconfig IS NOT NULL;
SELECT * FROM pg_db_role_setting;
```

`psql`なら`\drds`でまとめて出る。

---

# コマンド集(カテゴリ別)

## 1. どこで死んでいるかを見る

```bash
# 3つとも叩く。本文にDBのエラーがそのまま出る
for m in "GET /api/reports" "POST /api/reports" "GET /api/summary"; do
  set -- $m
  echo "== $1 $2"
  curl -sS -m 30 -X "$1" -w '\n[%{http_code} %{time_total}s]\n' "http://127.0.0.1:8080$2"
done

# アプリのログ
sudo journalctl -u reportapi -n 50 --no-pager

# サービスの生死
systemctl is-active reportapi
sudo systemctl status reportapi --no-pager
```

## 2. DBまでの経路を確かめる

上から順に、どこで止まっているかを詰める。

```bash
# 名前は引けるか
getent hosts reportdb.internal

# ポートは開いているか (2秒で諦める)
nc -z -v -w2 reportdb.internal 5432

# DBは応答するか
pg_isready -h reportdb.internal -p 5432 -t 5
```

| 結果 | 意味 |
| --- | --- |
| 名前が引けない | 名前解決の問題。`/etc/hosts`、リゾルバ |
| 名前は引けるが`nc`が**無言で固まる** | **パケットが捨てられている**。手前のファイアウォール |
| `Connection refused`が即返る | 経路は生きている。相手がそのポートで待っていない |
| `pg_isready`が`accepting connections` | 経路もDBも正常。ここから先はDBの中の話 |

**捨てられている(DROP)のと拒否されている(REJECT/refused)のは別物。** 前者は無言でタイムアウトし、後者は即座に答えが返る。

このサーバ側のフィルタを見る。

```bash
sudo iptables -L OUTPUT -n --line-numbers
sudo iptables -L -n -v            # パケットカウンタ付きで全チェイン

# 規則を消す (行番号指定 / 内容指定)
sudo iptables -D OUTPUT <行番号>
sudo iptables -D OUTPUT -p tcp --dport 5432 -j DROP
```

`-v`のカウンタが増えていれば、その規則が実際に効いている。

```bash
# 経路上の通信を眺める
sudo ss -tnp | grep 5432
```

## 3. DBのログは読めない

DBはマネージドなインスタンスなので、サーバログのファイルは見られない。`FATAL`の類は**クライアントに返るメッセージ**で読む。

```bash
sudo journalctl -u reportapi -n 50 --no-pager | grep -i 'error\|fatal'
```

`psql`で手で繋いでみるのが一番早い。接続時のエラーはそのまま画面に出る。

## 4. 今なにが起きているかをDBに聞く

```sql
SELECT pid, usename, application_name, client_addr, client_port, state,
       wait_event_type, wait_event,
       now() - xact_start AS xact_age,
       left(query, 60) AS query
  FROM pg_stat_activity
 WHERE backend_type = 'client backend'
 ORDER BY xact_start;
```

| 見るところ | 意味 |
| --- | --- |
| `state = active` | 実行中 |
| `state = idle in transaction` | **トランザクションを開いたまま放置**。ロックを握りっぱなしのことがある |
| `wait_event_type = Lock` | ロック待ち |
| `xact_age` が大きい | 長時間トランザクション |
| `application_name` | 誰が繋いでいるか。アプリが名乗っている |

接続数まわり。

```sql
SELECT count(*) FROM pg_stat_activity WHERE backend_type = 'client backend';
SELECT usename, application_name, count(*)
  FROM pg_stat_activity GROUP BY 1, 2 ORDER BY 3 DESC;
SHOW max_connections;
SHOW superuser_reserved_connections;
```

一般ロールが使える枠は`max_connections - superuser_reserved_connections`まで。埋まってもマスターユーザーなら予約枠で入れる。

## 5. ロックと待ち

```sql
-- 誰が誰を待たせているか
SELECT pid, pg_blocking_pids(pid) AS blocked_by,
       wait_event_type, state, left(query, 60)
  FROM pg_stat_activity
 WHERE cardinality(pg_blocking_pids(pid)) > 0;

-- 取れていないロック
SELECT locktype, relation::regclass, mode, granted, pid
  FROM pg_locks WHERE NOT granted;

-- 犯人のセッションを切る
SELECT pg_cancel_backend(<pid>);     -- 実行中の問い合わせだけ止める
SELECT pg_terminate_backend(<pid>);  -- 接続ごと切る
```

> [!WARNING]
> **バックエンドを切っても、繋いでいるプロセスが生きていれば再接続してくる。** 切ったあとにもう一度`pg_stat_activity`を見ること。すぐ戻ってくるなら、止めるべきはOS側。

## 6. 接続元のOSプロセスまで辿る

`pg_stat_activity`の`client_port`と`ss`の出力を突き合わせる。

```sql
SELECT pid, application_name, client_addr, client_port FROM pg_stat_activity
 WHERE client_addr IS NOT NULL;
```

```bash
sudo ss -tnp | grep ':5432'
sudo ss -tnp 'sport = :<client_port>'

# 動いているサービスを見渡す
systemctl list-units --type=service --state=running
```

## 7. 権限

一覧で眺めるならpsqlのメタコマンド。バックスラッシュで始まるものはSQLではなく**psqlの機能**で、`;`も要らない。

```
\dn+          スキーマの権限
\dp app.*     テーブルとシーケンスの権限 (\z でも同じ)
\ds app.*     シーケンス一覧
\du           ロールの属性 (LOGIN、接続上限など。オブジェクト権限は出ない)
\ddp          デフォルト権限 (今後作られるものに自動で付く分)
```

名指しで聞くならSQL。真偽値で返るので、目で追うより確実。

```sql
SELECT has_schema_privilege('reportapi', 'app', 'USAGE');
SELECT has_table_privilege('reportapi', 'app.reports', 'SELECT'),
       has_table_privilege('reportapi', 'app.reports', 'INSERT'),
       has_table_privilege('reportapi', 'app.reports', 'UPDATE');
SELECT has_sequence_privilege('reportapi', 'app.reports_id_seq', 'USAGE');
```

`\dp`の`Access privileges`欄は`被付与ロール=権限文字列/付与したロール`という形。

| 文字 | 権限 | 文字 | 権限 |
| --- | --- | --- | --- |
| `r` | SELECT | `U` | USAGE |
| `w` | UPDATE | `C` | CREATE |
| `a` | INSERT | `c` | CONNECT |
| `d` | DELETE | `T` | TEMPORARY |
| `D` | TRUNCATE | `x` | REFERENCES |
| `t` | TRIGGER | | |

権限は階層になっている。**下だけ見ても足りない。**

```
ロール → データベース(CONNECT) → スキーマ(USAGE) → テーブル(SELECT/INSERT/...)
                                                  → シーケンス(USAGE)  ← serial列のINSERTで要る
                                                  → 行(RLS)
```

```sql
GRANT USAGE ON SCHEMA app TO reportapi;
GRANT SELECT, INSERT, UPDATE ON app.reports TO reportapi;
GRANT USAGE ON SEQUENCE app.reports_id_seq TO reportapi;
```

## 8. ロールとDBに貼られた設定

`search_path`や`statement_timeout`は権限ではなく、ロールやデータベースに**貼り付けられた設定**。接続したセッションに自動で適用される。

### 貼られている設定を見る

psqlのメタコマンドが一番早い。

```
\drds
```

`\drds` は describe role/database settings の略で、SQLではなく**psqlの機能**。裏でカタログを引いて整形してくれる。出力はこうなる。

```
                List of settings
   Role    | Database |        Settings
-----------+----------+-------------------------
 reportapi |          | search_path=app, public+
           |          | statement_timeout=3s
```

`Database`が空ならそのロールに貼られた設定、`Role`が空ならそのデータベース全体に貼られた設定。

同じものをSQLで引くこともできる。ロールに貼られた分。

```sql
SELECT rolname, rolconfig FROM pg_roles WHERE rolconfig IS NOT NULL;
```

ロールとデータベースの組み合わせ全部。

```sql
SELECT d.datname, r.rolname, s.setconfig
  FROM pg_db_role_setting s
  LEFT JOIN pg_database d ON d.oid = s.setdatabase
  LEFT JOIN pg_roles    r ON r.oid = s.setrole;
```

### 変える・消す

```sql
ALTER ROLE reportapi SET search_path = app, public;
ALTER ROLE reportapi SET statement_timeout = '3s';
ALTER DATABASE reportdb RESET default_transaction_read_only;
```

`RESET`で消せる。**新しいセッションから効く**ので、繋ぎ直して確認する。

### 落とし穴: 読み取り専用は自分自身を消す操作も止める

データベースに`default_transaction_read_only`が貼られていると、それを消そうとした操作まで弾かれる。

```
ERROR:  cannot execute ALTER DATABASE in a read-only transaction
```

そのデータベースに繋いだセッションは、マスターユーザーであっても読み取り専用になるため。抜け道は2つある。

今のセッションだけ設定を外してから叩く。

```sql
SET default_transaction_read_only = off;
ALTER DATABASE reportdb RESET default_transaction_read_only;
```

あるいは、別のデータベースに繋いで叩く。

```bash
psql -d postgres -c "ALTER DATABASE reportdb RESET default_transaction_read_only"
```

## 9. スキーマとオブジェクト

```
\dt app.*        テーブル一覧
\di app.*        索引一覧
\d app.reports   1つのテーブルの全部 (列・索引・トリガー・RLS)
```

`\d app.reports`が一番情報量が多い。列の下に索引、その下に`Triggers:`や`Policies:`の節が続く。**節が出ていないなら、そこには何も無いということ**。

```sql
SELECT indexname, indexdef FROM pg_indexes WHERE schemaname = 'app';
SELECT current_schemas(true);   -- 今のセッションが実際に見ているスキーマ
```

## 10. 行レベルセキュリティ (RLS)

**エラーを出さずに0件を返す**という壊れ方をする。

```sql
SELECT relname, relrowsecurity, relforcerowsecurity
  FROM pg_class WHERE relnamespace = 'app'::regnamespace;

SELECT * FROM pg_policies WHERE schemaname = 'app';
```

有効なのにポリシーが1つも無ければ、所有者以外からは何も見えない。

```sql
ALTER TABLE app.reports DISABLE ROW LEVEL SECURITY;
```

マスターユーザーはRLSを素通りするので、同じ行が普通に見えてしまう。**アプリのロールで確かめること**。

## 11. トリガー

アプリが触っていないテーブルの権限エラーが出たら、裏で何かが動いている。

```sql
SELECT tgname, tgrelid::regclass AS on_table, tgfoid::regproc AS function
  FROM pg_trigger WHERE NOT tgisinternal;

SELECT prosrc FROM pg_proc WHERE proname = '<関数名>';
```

psqlなら`\d app.reports`の`Triggers:`の節にも出る。

トリガー関数は既定で**呼び出したロールの権限**で動く。関数の中で触るものにも権限が要る。

## 12. 実行計画と統計

```sql
-- タイムアウトに邪魔されないよう、調査セッションだけ外す
SET statement_timeout = 0;

EXPLAIN (ANALYZE, BUFFERS)
SELECT t.region,
       (SELECT coalesce(sum(a.amount), 0) FROM app.reports_archive a
         WHERE a.region = t.region AND a.created_at >= now() - interval '7 days')
  FROM app.report_targets t;
```

| 計画に出る語 | 意味 |
| --- | --- |
| `Index Scan` / `Index Only Scan` | 索引が効いている |
| `Seq Scan` | 全件走査。**行数が多ければここが犯人** |
| `loops=40` | その節点が40回まわっている。1回が遅いと40倍効く |
| `rows=... actual rows=...` | 見積もりと実測の乖離。統計が古い疑い |

```sql
ANALYZE app.reports_archive;
SELECT relname, n_live_tup, n_dead_tup, last_analyze, last_autovacuum
  FROM pg_stat_user_tables WHERE schemaname = 'app';
```

---

## 注入される障害

### 初級

| 障害 | 見え方 | 該当する段 | 決め手 |
| --- | --- | --- | --- |
| 経路の遮断 | **無言でタイムアウト**。DBは何も答えない | 3 | `nc -z`が固まる。`iptables -L -n -v`のカウンタ |
| 接続枠の占有 | `FATAL: remaining connection slots are reserved...` | 4 | `pg_stat_activity`の`application_name`。**切っても戻ってくる** |
| ロック待ち | 登録だけ`statement timeout`。`relation "counters"`と出る | 5 | `pg_blocking_pids()` |
| テーブル権限の剥奪 | `permission denied for table reports` | 6 | `\dp app.reports` |
| シーケンス権限の剥奪 | `permission denied for sequence reports_id_seq` | 6 | 読めるのに書けない。`\ds`と`has_sequence_privilege` |
| DBが読み取り専用 | `cannot execute INSERT in a read-only transaction` | 6 | `pg_db_role_setting` |

### 上級

| 障害 | 見え方 | 紛らわしい相手 | 決め手 |
| --- | --- | --- | --- |
| 索引の削除 | `canceling statement due to statement timeout` | 上限の短縮(**同じ文言**) | `EXPLAIN`が`Seq Scan`。上限は3sのまま |
| 上限の短縮 | `canceling statement due to statement timeout` | 索引の削除(**同じ文言**) | 計画は変わらず。`rolconfig`の`statement_timeout` |
| スキーマ権限の剥奪 | `relation "reports" does not exist` | `search_path`の変更(**同じ文言**) | `has_schema_privilege`が false |
| `search_path`の変更 | `relation "reports" does not exist` | スキーマ権限の剥奪(**同じ文言**) | `rolconfig`の`search_path` |
| RLSの有効化 | **エラー無しで0件** | 権限の剥奪(どちらも「見えない」) | `pg_class.relrowsecurity`と`pg_policies` |
| 監査トリガーの追加 | `permission denied for table audit_log` | テーブル権限の剥奪(どちらも権限エラー) | `pg_trigger`。アプリが触っていないテーブル |

上級は「**エラー文だけでは割れない**」という形をしている。メッセージが同じか、そもそもエラーが出ないので、カタログを引くか計画を見るまで確定できない。

---

## 使い方

```bash
./new-case.sh                     # ランダムに1つ
./new-case.sh --hard              # 上級だけ
./new-case.sh index-dropped       # 指定して出題

./verify.sh --status              # 今の状態
./verify.sh 'FLAG{...}'           # 答え合わせ

./teardown.sh                     # 後片付け
```

## 補足

- 成果物は見張り役が**通っている間だけ**置く。1回通しただけでは残らないし、直したつもりで失敗に戻ればすぐ消える
- `verify.sh`は成果物の更新時刻も見ている。古いFLAGを持ち出しても通らない
- DBのデータはイメージに焼いてあるので、`./new-case.sh`を叩き直せば毎回まっさらな状態から始まる
- 経路が塞がれている間は**保守用のpsqlも繋がらない**。DBに何かを聞く前に、まず経路を通すこと
- 経路の遮断はアプリサーバ側のファイアウォールとして実装してある。本物のセキュリティグループはクラウド側の設定でサーバから直せないが、それだとクエストにならないので手元で直せる位置に置いた
