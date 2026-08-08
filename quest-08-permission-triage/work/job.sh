#!/bin/sh
# /data に対する定常業務。どの操作がどう失敗したかを表示する。
# ここに出るのは「症状」であって「原因」ではない。原因は自分で診断すること。

run() {
  label="$1"
  shift
  printf '[%s] %s\n' "$label" "$*"
}

run 1 "一覧: ls /data"
if out=$(ls /data 2>&1); then
  echo "    OK: $(echo "$out" | tr '\n' ' ')"
else
  echo "    NG: $out"
fi

run 2 "読み取り: cat /data/report.txt"
if out=$(cat /data/report.txt 2>&1); then
  echo "    OK: $out"
else
  echo "    NG: $out"
fi

run 3 "書き出し: /data/out.txt"
if out=$(sh -c 'echo written > /data/out.txt' 2>&1); then
  echo "    OK"
else
  echo "    NG: $out"
fi

run 4 "後始末: rm /data/old.txt"
if out=$(rm /data/old.txt 2>&1); then
  echo "    OK"
  # 次に流したときも同じ条件になるよう戻しておく
  sh -c 'echo "先月の作業ファイル" > /data/old.txt' 2>/dev/null || true
else
  echo "    NG: $out"
fi

run 5 "実行: /data/run.sh"
if out=$(/data/run.sh 2>&1); then
  echo "    OK: $out"
else
  echo "    NG: $out"
fi
