#!/usr/bin/env bash
# Fail if any debug-only marker survives anywhere inside a Release app bundle.
#
#   scripts/check-release-clean.sh [/path/to/Pace.app]
#
# With no argument, finds the newest Release Pace.app under DerivedData.
#
# Searches EVERY file in the bundle, not just the main executable: the Kotlin shared
# framework (Frameworks/shared.framework/shared) is a second binary, and a debug string
# that lives there is invisible to a check that only reads the app executable.
# Byte-level grep (-a), so UTF-8 Chinese markers are found too — `strings` skips them.
#
# Exit 0 when every marker is absent; 1 when any is found; 2 when the bundle is missing.
set -uo pipefail

APP="${1:-}"
if [ -z "$APP" ]; then
  APP=$(find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 7 -type d \
        \( -name "Release-iphoneos" -o -name "Release-iphonesimulator" \) \
        -exec find {} -maxdepth 1 -name "Pace.app" -type d \; 2>/dev/null | head -1)
fi

if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  echo "找不到 Pace.app：先做一次 Release 构建，或把路径当第一个参数传进来。" >&2
  exit 2
fi

echo "检查整包：$APP"
echo

MARKERS=(
  "制造一次失败"
  "调试中"
  "本机规则拆不开"
  "SCROLLDBG"
  "uiFault"
  "uiTab"
  "uiDrafts"
)

fail=0
for m in "${MARKERS[@]}"; do
  total=0
  where=""
  while IFS= read -r f; do
    n=$(LC_ALL=C grep -a -o -- "$m" "$f" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$n" != "0" ]; then
      total=$((total + n))
      where="$where
      $n 处  ${f#"$APP"/}"
    fi
  done < <(find "$APP" -type f)
  if [ "$total" -eq 0 ]; then
    printf '  %-16s 0 处\n' "$m"
  else
    printf '  %-16s %s 处  <-- 不该出现在发布包里\n%s\n' "$m" "$total" "$where"
    fail=1
  fi
done

echo
if [ "$fail" -eq 0 ]; then
  echo "结果：干净。整包里一个都搜不到。"
  exit 0
fi
echo "结果：不干净。上面标出的那些要么回到 #if DEBUG 里，要么整段删掉。"
exit 1
