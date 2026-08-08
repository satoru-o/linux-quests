# quest-08: permission-triage

前提セットアップは不要。ビルドしてすぐ挑戦できる。

## これは何か

[quest-07](../quest-07-network-triage/)と同じ**診断ドリル**の権限版。`./new-case.sh`を叩くたびにランダムな故障が1つ仕込まれ、原因を突き止めて`./answer.sh`で申告する。修理ではなく診断が目的。

権限まわりは「`Permission denied`と出た → ファイルのモードを見る → 合ってるように見える → 詰まる」という誤診が起きやすい。実際には、

- **そのファイルまで辿り着けているか**（経路のディレクトリ）
- **モードの外側に何かいないか**（ACL、拡張属性）
- **そもそも権限の話なのか**（マウントオプション）

を確かめる必要がある。そこを型にする。

## 正常な状態

`work`コンテナの中で`appuser`として、`/data`の定常業務が最後まで通るのが正常。

```bash
docker compose exec work /job.sh
```

5つの操作を順に試して、それぞれOK/NGを表示する。

| # | 操作 |
| --- | --- |
| 1 | 一覧 `ls /data` |
| 2 | 読み取り `cat /data/report.txt` |
| 3 | 書き出し `/data/out.txt` |
| 4 | 削除 `rm /data/old.txt` |
| 5 | 実行 `/data/run.sh` |

**どれが通ってどれが落ちたか**の組み合わせが、そのまま最初の手掛かりになる。

## 難易度

```bash
./new-case.sh          # 初級(8種)から1つ
./new-case.sh --hard   # 上級(6種)から1つ
./new-case.sh --all    # 全14種から1つ
```

初級はすべて`ls -l`と`namei`で説明がつく。上級は**モードを見ても説明がつかない**ものが混ざる。ACL、拡張属性、マウントオプション、シンボリックリンク、UIDのズレ。

## 診断の型

**「誰が」「何に」「どこを通って」触ろうとしているかを、順に確定させる。**

| 段 | 問い | コマンド | 分かること |
| --- | --- | --- | --- |
| 1 | 自分は誰か | `docker compose exec work id` | UID/GIDと**所属グループの一覧** |
| 2 | 対象の所有者とモードは | `docker compose exec work ls -l /data/report.txt` | 所有者・グループ・rwxビット・**`+`の有無** |
| 3 | そこまで辿れるか | `docker compose exec work namei -l /data/report.txt` | **経路上の全ディレクトリ**とリンク先 |
| 4 | エラーは何と言っているか | `/job.sh`の出力をそのまま読む | errnoの違い(下の表) |
| 5 | 権限ビットの外側は | `docker compose exec work findmnt /data` | `ro`/`noexec`などのマウントオプション |

第3段が肝心。ファイルのモードがどれだけ緩くても、**途中のディレクトリに`x`が無ければ辿り着けない**。`ls -l`だけ見て「権限は合ってるのにおかしい」となるのは、たいていこれか、後述のACL。

## エラー文の読み分け

見た目が似ていても、意味する層がまったく違う。**同じ「書き込めない」でも4種類ある。**

| エラー文 | errno | 疑うもの |
| --- | --- | --- |
| `Permission denied` | EACCES | 権限ビット。対象自身か、経路のディレクトリか、**ACL** |
| `Operation not permitted` | EPERM | ビットでは説明できない禁止。sticky、**拡張属性(immutable)** |
| `Read-only file system` | EROFS | **権限の話ではない。** マウントが読み取り専用 |
| `No such file or directory` | ENOENT | 本当に無い。あるいは経路が辿れず無いように見えている |

`Read-only file system`が出ているのに`chmod`で直そうとするのは典型的な迷走なので、ここは覚えてしまってよい。`Operation not permitted`も同様で、これが出たらモードをいくらいじっても解決しない。

## 症状の組み合わせで割る

| 一覧 | 読み取り | 書き出し | 実行 | 疑うもの |
| --- | --- | --- | --- | --- |
| OK | **NG** | OK | OK | 対象ファイル自身の問題。下の表へ |
| **NG** | OK | NG | OK | ディレクトリの`r`が無い(名前が見えないだけ) |
| NG | NG | NG | NG | ディレクトリの`x`が無い(そもそも通れない) |
| OK | OK | **NG** | OK | ディレクトリの`w`、マウント`ro`、拡張属性。**errnoで割る** |
| OK | OK | OK | **NG** | 実行の問題。`x`ビットか`noexec` |
| OK | OK | OK | OK(削除だけNG) | sticky、または他人所有 |

一覧がNGでも読み取りがOKになる、という組み合わせが存在するのが権限の面白いところ。`r`(名前を読む)と`x`(通り抜ける)が別のビットだから起きる。

### 読み取りだけ落ちるとき(候補が6つある)

ここが一番混み合う。`ls -l`と`id`と`namei`を突き合わせて絞る。

| 手掛かり | 原因 |
| --- | --- |
| モードは`644`なのに読めない。`ls -l`の末尾に**`+`** | `acl-deny` |
| 所有者が名前ではなく**数字**(`1500`など)で出る | `uid-unmapped` |
| 行頭が`l`で、`-> 別のパス`が付いている | `symlink-denied`(リンク先を`namei`で追う) |
| 自分が所有者なのに`r`が無い | `no-read-bit` |
| グループ許可はあるが、`id`の一覧にそのグループが無い | `group-not-member` |
| 他人所有で、その他(other)にも許可が無い | `not-owner` |
| ファイル自体は問題ないが、`namei`で親に`x`が無い | `dir-no-exec` |

**`+`は見落としやすい。** モードが緩く見えるのに読めないときは、まず`getfacl`を叩く。

### 実行だけ落ちるとき

```bash
docker compose exec work ls -l /data/run.sh     # xビットはあるか
docker compose exec work findmnt /data          # noexecが付いていないか
```

- `x`が無い → `no-exec-bit`
- `x`はあるのに`Permission denied` → `noexec-mount`

**「xがあるのに実行できない」ならビットの外側**、というのがこのペアの学びどころ。

---

# コマンド集(カテゴリ別)

`work`コンテナには診断の道具一式が入っている。暗記する必要はないので、ここを見ながら回してよい。

## 1. 自分は誰か

```bash
docker compose exec work id                       # UID/GID/所属グループ
docker compose exec work id -u                    # UIDだけ
docker compose exec work groups                   # 所属グループ名だけ
docker compose exec work whoami
docker compose exec work getent passwd appuser    # パスワードDBの登録内容
docker compose exec work getent group analysts    # そのグループのメンバー
docker compose exec work cat /etc/group           # グループ定義の全体
```

`ls -l`のグループ名が`id`の一覧に**無ければ**、そのグループ経由の許可は自分には効かない。

## 2. 対象の状態

```bash
docker compose exec work ls -l /data/report.txt   # 基本。末尾の + に注意
docker compose exec work ls -la /data             # 隠しファイル込み
docker compose exec work ls -ld /data             # ディレクトリ自身の情報
docker compose exec work ls -ln /data             # 名前ではなく数字(UID/GID)で表示

docker compose exec work stat /data/report.txt    # 詳細(8進数のモードも出る)
docker compose exec work stat -c '%A %U:%G %n' /data/report.txt
docker compose exec work stat -c '%a %U:%G %n' /data/report.txt   # 644形式
```

`ls -ln`は`uid-unmapped`の確認に効く。名前が出ない＝そのUIDがこのコンテナに存在しない。

## 3. 経路(ディレクトリ)

```bash
docker compose exec work namei -l /data/report.txt   # 経路上の全要素を並べる
docker compose exec work namei -m /data/report.txt   # モードだけ簡潔に

docker compose exec work ls -ld / /data              # 一段ずつ見る
docker compose exec work readlink -f /data/report.txt  # シンボリックリンクの実体
docker compose exec work realpath /data/report.txt
```

**`namei -l`が権限診断の主武器。** 経路上のどこで詰まっているかが1回で分かる。シンボリックリンクも追ってくれるので、`symlink-denied`もこれで見える。

## 4. モードの外側(ACL・拡張属性)

```bash
docker compose exec work getfacl /data/report.txt      # ACLの一覧
docker compose exec work getfacl -p /data/report.txt   # パスを削らずに表示
docker compose exec work getfacl -R /data              # 配下すべて

docker compose exec work lsattr /data/report.txt       # 拡張属性(i=immutable など)
docker compose exec work lsattr -d /data               # ディレクトリ自身
docker compose exec work lsattr -R /data
```

読み方の目安。

| 見えたもの | 意味 |
| --- | --- |
| `ls -l`の末尾に`+` | ACLが付いている。`getfacl`で中身を見る |
| `user:appuser:---` | 自分だけ名指しで拒否されている |
| `mask::r--` | ACLの上限。これより広い許可は効かない |
| `lsattr`に`i` | immutable。所有者でもrootでも変更できない |
| `lsattr`に`a` | append only。追記しかできない |

## 5. マウントとファイルシステム

```bash
docker compose exec work findmnt /data            # 見やすい
docker compose exec work findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS /data
docker compose exec work mount | grep /data       # 素朴な方法
docker compose exec work cat /proc/mounts | grep /data

docker compose exec work df -h /data              # 容量
docker compose exec work df -i /data              # inode(ファイル数の上限)
```

`OPTIONS`に何が入っているかが全て。

| オプション | 意味 |
| --- | --- |
| `ro` | 読み取り専用。書き込みは`Read-only file system` |
| `noexec` | 実行禁止。`x`があっても`Permission denied` |
| `nosuid` | setuidが効かない |
| `nodev` | デバイスファイルが使えない |

## 6. 実行できるか

```bash
docker compose exec work ls -l /data/run.sh       # xビットの有無
docker compose exec work /data/run.sh             # 直に実行してみる
docker compose exec work sh /data/run.sh          # shに読ませる(xが無くても動く)
docker compose exec work file /data/run.sh        # 中身の種類
docker compose exec work head -1 /data/run.sh     # shebang
```

**`sh script.sh`は動くのに`./script.sh`は動かない**、という切り分けが有効。前者は`x`を必要としないので、これで通れば原因は`x`まわり(ビットか`noexec`)に絞れる。

## 7. 実際に試して確かめる

推測で終わらせず、その場で検証する。

```bash
docker compose exec work test -r /data/report.txt && echo readable
docker compose exec work test -w /data/report.txt && echo writable
docker compose exec work test -x /data/run.sh && echo executable
docker compose exec work test -w /data && echo "ディレクトリに書ける"

# rootならどう見えるか(権限問題かどうかの切り分け)
docker compose exec -u root work cat /data/report.txt
```

**rootで読めて`appuser`で読めないなら権限の問題**、rootでも駄目なら拡張属性かマウントを疑う。これが一番速い二分法。

## 8. 権限の表記を読む

```
-rw-r--r--+ 1 root analysts 27 Aug  8 05:31 /data/report.txt
│└┬┘└┬┘└┬┘│   │    │
│ │  │  │ │   │    └─ グループ
│ │  │  │ │   └────── 所有者
│ │  │  │ └────────── ACLあり(+)
│ │  │  └──────────── other の許可
│ │  └─────────────── group の許可
│ └────────────────── owner の許可
└──────────────────── 種別 (- 通常 / d ディレクトリ / l シンボリックリンク)
```

判定は**上から1つだけ**適用される。自分が所有者なら owner の欄だけが見られ、group や other がどれだけ緩くても関係ない。「other が`r`だから読めるはず」は、自分が所有者やグループ所属だと成り立たない。

ディレクトリのビットの意味も、ファイルとは違う。

| ビット | ファイル | ディレクトリ |
| --- | --- | --- |
| `r` | 中身を読める | **名前の一覧が取れる** |
| `w` | 中身を書ける | **中にファイルを作る/消せる** |
| `x` | 実行できる | **そこを通り抜けられる** |

ファイルを消すのに必要なのは**ファイルの`w`ではなくディレクトリの`w`**。ここは間違えやすい。

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
| `not-owner` | 対象が他人の所有で、自分に許可が無い | 2 |
| `group-not-member` | グループには許可があるが、自分がそのグループに所属していない | 1と2の突き合わせ |
| `no-read-bit` | 自分が所有者だが、読み取りビットが落ちている | 2 |
| `dir-no-exec` | 親ディレクトリに`x`が無く、パスを辿れない | 3 |
| `dir-no-read` | 親ディレクトリに`r`が無く、一覧が取れない | 3 |
| `dir-no-write` | 親ディレクトリに`w`が無く、作成・削除ができない | 3 |
| `sticky-other` | stickyビットのあるディレクトリで、他人のファイルを消せない | 3 |
| `readonly-mount` | 権限ビットではなく、マウントが読み取り専用 | 5 |

### 上級

| 原因ID | 内容 | 紛らわしい相手 |
| --- | --- | --- |
| `acl-deny` | モードは緩いが、ACLで個別に拒否されている | `not-owner`(どちらも読めない。モードは緩く見える) |
| `immutable-attr` | 拡張属性(immutable)で変更が禁止されている | `dir-no-write`/`readonly-mount`(どれも書けない) |
| `no-exec-bit` | 実行しようとしたが、`x`ビットが無い | `noexec-mount`(どちらも実行時にPermission denied) |
| `noexec-mount` | `x`ビットはあるが、マウントが`noexec` | `no-exec-bit` |
| `symlink-denied` | 対象はシンボリックリンクで、リンク先が読めない | `not-owner`(見た目は同じPermission denied) |
| `uid-unmapped` | 所有者がこのコンテナに存在しないUIDになっている | `not-owner`(所有者が自分でない点は同じ) |

上級はすべて「**モードを見ても説明がつかない**」という形をしている。`ls -l`が正常に見えるとき、次にどこを見るかが問われる。

## 続け方

日を空けて何度か回すのがおすすめ。「`Permission denied`を見た瞬間に`namei`が手癖で出る」「モードが緩いのに読めなければ`getfacl`」まで来たら身についている。

## 後片付け

```bash
./teardown.sh
```

## 補足

現在の症例は`.state`にハッシュで保存してある(平文の答えは置いていない)。仕込みの実体は`fixture/entrypoint.sh`と`docker-compose.override.yml`にあるので、見ようと思えば見える。自分を騙さないように。
