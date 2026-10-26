#!/usr/bin/env bash
# Fail if any debug-only marker survives anywhere inside a Release app bundle,
# and fail if the check itself cannot demonstrate that it works.
#
#   scripts/check-release-clean.sh [/path/to/Pace.app]
#
# With no argument, finds the newest Release Pace.app under DerivedData.
#
# Two properties beyond a plain grep:
#   * it searches EVERY file in the bundle, because Frameworks/shared.framework/shared
#     is a second binary and a debug string there is invisible to a check that only
#     reads the app executable;
#   * it is byte-level (grep -a), because `strings` skips UTF-8 and would silently
#     report Chinese markers as absent.
#
# The self-test: before judging the Release bundle, the same search runs against a
# Debug build, where these markers must be present. A check that reports "clean" for a
# build known to contain them is broken, and a broken check is worse than none — so it
# exits non-zero instead of quietly passing.
set -uo pipefail

MARKERS=(
  "制造一次失败"
  "调试中"
  "本机规则拆不开"
  "SCROLLDBG"
  "uiFault"
  "uiTab"
  "uiDrafts"
)

# Prints "<count> <marker>" per marker; returns 0 always, sets FOUND.
scan() {
  local bundle="$1" total=0 m n f where
  for m in "${MARKERS[@]}"; do
    n=0
    where=""
    while IFS= read -r f; do
      local k
      k=$(LC_ALL=C grep -a -o -- "$m" "$f" 2>/dev/null | wc -l | tr -d ' ')
      if [ "$k" != "0" ]; then
        n=$((n + k))
        where="$where
      $k 处  ${f#"$bundle"/}"
      fi
    done < <(find "$bundle" -type f)
    if [ "$n" -eq 0 ]; then
      printf '  %-16s 0 处\n' "$m"
    else
      printf '  %-16s %s 处  <-- 不该出现在发布包里\n%s\n' "$m" "$n" "$where"
      total=$((total + n))
    fi
  done
  FOUND=$total
}

find_app() {  # $1 = Debug|Release — newest build wins, so a stale copy never decides the answer
  {
    find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 7 -type d -name "$1-iphoneos" \
      -exec find {} -maxdepth 1 -name "Pace.app" -type d \; 2>/dev/null
    find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 7 -type d -name "$1-iphonesimulator" \
      -exec find {} -maxdepth 1 -name "Pace.app" -type d \; 2>/dev/null
  } | while IFS= read -r p; do printf '%s\t%s\n' "$(stat -f %m "$p" 2>/dev/null || echo 0)" "$p"; done \
    | sort -rn | head -1 | cut -f2-
}

APP="${1:-}"
if [ -z "$APP" ]; then
  APP=$(find_app Release)
fi
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  echo "找不到 Pace.app：先做一次 Release 构建，或把路径当第一个参数传进来。" >&2
  exit 2
fi

# --- self-test ---------------------------------------------------------------
DEBUG_APP=$(find_app Debug)

if [ -n "$DEBUG_APP" ] && [ -d "$DEBUG_APP" ]; then
  echo "自检：先用 Debug 包跑一遍（这些标记在 Debug 里必须存在）"
  echo "      $DEBUG_APP"
  scan "$DEBUG_APP" >/dev/null
  if [ "$FOUND" -eq 0 ]; then
    echo
    echo "自检失败：Debug 包里一个标记都没搜到。检查本身坏了——可能是新的构建把标记都挪走了，"
    echo "也可能是搜索方式退化了。这时「发布包是干净的」这句话不能信，先修检查。"
    exit 2
  fi
  echo "      自检通过：Debug 包里搜到 $FOUND 处。"
  # A marker missing from the Debug build too means it was renamed or removed: searching for
  # it in Release proves nothing, and calling that "clean" would be a false pass.
  missing=""
  for m in "${MARKERS[@]}"; do
    hit=0
    while IFS= read -r f; do
      k=$(LC_ALL=C grep -a -o -- "$m" "$f" 2>/dev/null | wc -l | tr -d ' ')
      hit=$((hit + k))
    done < <(find "$DEBUG_APP" -type f)
    [ "$hit" -eq 0 ] && missing="$missing $m"
  done
  if [ -n "$missing" ]; then
    echo "      注意：这些标记在 Debug 包里也不存在，可能已经改名或被删——它们在发布包里搜不到，"
    echo "      不能当作「已清除」的证据：$missing"
  fi
  echo
else
  echo "自检跳过：没有找到 Debug 包可以对照。这次的结果只证明「没搜到」，不证明「搜得对」。" >&2
  echo
fi
# ---------------------------------------------------------------------------

echo "检查整包：$APP"
echo
scan "$APP"

echo
if [ "$FOUND" -eq 0 ]; then
  echo "结果：干净。整包里一个都搜不到。"
  exit 0
fi
echo "结果：不干净。上面标出的那些要么回到 #if DEBUG 里，要么整段删掉。"
exit 1
