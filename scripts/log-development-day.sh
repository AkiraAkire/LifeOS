#!/bin/zsh

# Creates and updates one Markdown development log per local calendar day.
# Usage: ./scripts/log-development-day.sh <done|todo|note> "message"

set -euo pipefail

if [[ $# -ne 2 ]]; then
  print -u2 "用法：$0 <done|todo|note> \"记录内容\""
  exit 64
fi

log_kind="$1"
message="$2"
script_dir="${0:A:h}"
project_root="${script_dir:h}"
log_dir="${project_root}/development-logs"
day="$(date +%F)"
time="$(date +%H:%M)"
log_file="${log_dir}/${day}.md"

mkdir -p "$log_dir"

if [[ ! -f "$log_file" ]]; then
  cat > "$log_file" <<EOF
# 开发日志 · ${day}

> 本文件由 \`scripts/log-development-day.sh\` 自动创建或维护。请保留完成事项、待办事项和关键记录。

## 已完成

## 待办

## 工作记录

EOF
fi

case "$log_kind" in
  done)
    heading="## 已完成"
    entry="- [x] ${time} · ${message}"
    ;;
  todo)
    heading="## 待办"
    entry="- [ ] ${time} · ${message}"
    ;;
  note)
    heading="## 工作记录"
    entry="- ${time} · ${message}"
    ;;
  *)
    print -u2 "状态必须是 done、todo 或 note。"
    exit 64
    ;;
esac

temp_file="$(mktemp "${log_file}.XXXXXX")"
trap 'rm -f "$temp_file"' EXIT

awk -v heading="$heading" -v entry="$entry" '
  $0 == heading {
    print
    print ""
    print entry
    inserted = 1
    next
  }
  { print }
  END {
    if (!inserted) {
      print ""
      print heading
      print ""
      print entry
    }
  }
' "$log_file" > "$temp_file"

mv "$temp_file" "$log_file"
trap - EXIT

print "已记录到 ${log_file}"
