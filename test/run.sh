#!/usr/bin/env bash
# ab-bridge 회귀 테스트
#   실행: ./test/run.sh
#
# 세션 데몬이 답하지 않는 상황을 스텁으로 흉내 냅니다. 그때 ab-up과 ab-down이
# 터미널을 붙잡은 채 멈추지 않는지, ab-down이 데몬을 확실히 내리는지 봅니다.
# 실제 브라우저는 띄우지 않습니다.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
LIMIT=15          # 이 안에 끝나야 통과
FAKE_PORT=19733   # 가짜 CDP 포트

export PATH="$HERE/stub:$PATH"
export AB_BRIDGE_CONFIG="$HERE/fixtures/profiles.json"
pass=0; fail=0
ok() { printf '  ✓ %s\n' "$1"; pass=$((pass + 1)); }
no() { printf '  ✗ %s\n' "$1"; fail=$((fail + 1)); }

# 브라우저가 떠 있는 것처럼 보이게 합니다.
python3 "$HERE/fakecdp.py" >/dev/null 2>&1 &
FAKE_PID=$!
mkdir -p "$HOME/.agent-browser-profiles/test"
printf '%s\n/devtools/browser/fake\n' "$FAKE_PORT" > "$HOME/.agent-browser-profiles/test/DevToolsActivePort"
cleanup() {
  kill "$FAKE_PID" 2>/dev/null
  pkill -f "$HERE/stub/agent-browser" 2>/dev/null
  rm -rf "$HOME/.agent-browser-profiles/test"
  rm -f "$HOME/.agent-browser/ab-test.pid"
}
trap cleanup EXIT
sleep 1.5

echo "── 데몬이 답하지 않을 때 ab-up이 제한시간 안에 끝나는가"
start=$(date +%s)
perl -e 'alarm shift; exec @ARGV' "$LIMIT" bash "$REPO/mac/ab-up" test </dev/null >"$HERE/.t1.out" 2>&1
rc=$?; echo "     rc=$rc, $(($(date +%s) - start))초"
pkill -f "$HERE/stub/agent-browser" 2>/dev/null; sleep 0.3
[ "$rc" -ne 142 ] && ok "매달리지 않고 끝남" || no "${LIMIT}초 제한까지 매달림"
grep -q '준비됐습니다' "$HERE/.t1.out" && ok "마지막 안내까지 출력함" || no "끝까지 못 감"

echo "── 데몬이 답하지 않아도 ab-down이 데몬을 확실히 내리는가"
# pidfile이 가리키는 프로세스가 죽어야 kill 단계에 도달했다는 뜻입니다.
sleep 300 & dummy=$!
mkdir -p "$HOME/.agent-browser"; echo "$dummy" > "$HOME/.agent-browser/ab-test.pid"
start=$(date +%s)
perl -e 'alarm shift; exec @ARGV' "$LIMIT" bash "$REPO/mac/ab-down" test </dev/null >"$HERE/.t2.out" 2>&1
rc=$?; echo "     rc=$rc, $(($(date +%s) - start))초"
pkill -f "$HERE/stub/agent-browser" 2>/dev/null; sleep 1
[ "$rc" -ne 142 ] && ok "매달리지 않고 끝남" || no "${LIMIT}초 제한까지 매달림"
if kill -0 "$dummy" 2>/dev/null; then no "데몬이 아직 살아있음"; kill -9 "$dummy" 2>/dev/null
else ok "데몬을 확실히 내림"; fi

echo "── 되풀이하면 안 되는 함정"
# CDP 포트를 --args로 넘기면 Chrome이 DevToolsActivePort를 만들지 않습니다.
# 그러면 데몬이 브라우저를 영영 못 찾고 모든 명령이 답 없이 매달립니다.
if grep 'args' "$REPO/mac/ab-up" | grep -q 'remote-debugging-port'; then
  no "ab-up이 --args로 CDP 포트를 넘김"
else ok "ab-up이 --args로 CDP 포트를 넘기지 않음"; fi
# 맥 headed 브라우저에 viewport를 걸면 창 크기를 안 따라갑니다.
if grep -q 'ab_apply_viewport' "$REPO/mac/ab-up" "$REPO/remote/ab-local"; then
  no "headed 경로에서 viewport를 고정함"
else ok "headed 경로는 viewport를 고정하지 않음"; fi

rm -f "$HERE/.t1.out" "$HERE/.t2.out"
echo; echo "결과: 통과 $pass, 실패 $fail"
[ "$fail" -eq 0 ]
