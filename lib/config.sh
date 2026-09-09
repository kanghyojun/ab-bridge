# ab-bridge 설정 읽기. 각 스크립트에서 source 합니다.
# 설정 파일: ~/.config/ab-bridge/profiles.json (AB_BRIDGE_CONFIG로 변경 가능)
# jq가 필요합니다. macOS는 brew install jq, 데비안 계열은 apt install jq.

AB_CONFIG="${AB_BRIDGE_CONFIG:-$HOME/.config/ab-bridge/profiles.json}"

# jq가 없으면 설정을 못 읽습니다. 조용히 기본값으로 넘어가면 엉뚱한 포트에 붙으므로
# source 하는 시점에 멈춥니다. ab_cfg 안에서 멈추면 $(...) 서브셸만 죽고
# 호출한 스크립트는 빈 값을 받은 채 그냥 굴러갑니다.
if ! command -v jq >/dev/null 2>&1; then
  echo "✗ jq가 없어서 설정을 읽을 수 없습니다. (brew install jq / sudo apt install jq)" >&2
  exit 1
fi

# ab_cfg <점으로 구분한 경로> [기본값]
# 값이 배열이면 한 줄에 하나씩 출력합니다.
# 설정이 없거나 깨졌거나 경로가 안 맞으면 기본값을 씁니다.
ab_cfg() {
  local out=""
  if [ -f "$AB_CONFIG" ]; then
    out="$(jq -r --arg p "$1" '
      getpath($p / ".")
      | select(. != null)
      | if type == "array" then .[] else . end
    ' "$AB_CONFIG" 2>/dev/null || true)"
  fi
  printf '%s\n' "${out:-${2:-}}"
}

# 설정 파일이 없으면 기본값으로 만듭니다.
ab_cfg_init() {
  [ -f "$AB_CONFIG" ] && return 0
  mkdir -p "$(dirname "$AB_CONFIG")"
  cat > "$AB_CONFIG" <<'JSON'
{
  "macHost": "macbookpro",
  "profiles": {
    "main": {
      "port": 9222,
      "description": "일상 로그인 보관용 프로필",
      "viewport": { "width": 1440, "height": 1080 },
      "sites": []
    }
  }
}
JSON
  echo "• 설정 파일을 만들었습니다: $AB_CONFIG" >&2
}

# 프로필 이름 -> 포트. 설정에 없으면 9222.
ab_cfg_port() { ab_cfg "profiles.$1.port" "9222"; }

# ab_timeout <초> <명령...>
# 명령에 제한시간을 겁니다. 제한을 넘기면 명령을 죽이고 124로 끝냅니다.
# agent-browser는 세션 데몬에 요청을 보내고 답을 기다립니다. 데몬이 먹통이면
# 답이 영영 안 오고, 제한이 없으면 스크립트가 터미널을 붙잡은 채 멈춥니다.
# 맥에는 timeout이 없어서 쓸 수 있는 것을 순서대로 고릅니다.
ab_timeout() {
  local lim="$1" rc; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$lim" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$lim" "$@"
  elif command -v perl >/dev/null 2>&1; then
    # alarm은 exec를 넘어 살아남으므로 제한이 실제 명령에 그대로 걸립니다.
    # rc를 || 로 받습니다. 그냥 두면 set -e가 다음 줄 전에 스크립트를 끝냅니다.
    rc=0
    perl -e 'alarm shift; exec @ARGV' "$lim" "$@" || rc=$?
    # SIGALRM(128+14=142)을 timeout과 같은 124로 맞춥니다.
    [ "$rc" -eq 142 ] && return 124
    return "$rc"
  else
    # 제한을 걸 수단이 없습니다. 매달릴 수 있다는 것을 알리고 그냥 실행합니다.
    echo "⚠ timeout도 perl도 없어서 제한시간을 못 겁니다: $*" >&2
    "$@"
  fi
}

# ab_kill <pid>
# TERM으로 먼저 청하고, 5초 안에 안 내려가면 KILL로 확실히 내립니다.
# 데몬이 남으면 브라우저를 닫아도 다시 띄우므로 여기서 반드시 끝내야 합니다.
ab_kill() {
  local pid="$1" i
  [ -n "$pid" ] || return 0
  kill -0 "$pid" 2>/dev/null || return 0
  kill "$pid" 2>/dev/null || true
  for i in 1 2 3 4 5; do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 1
  done
  kill -9 "$pid" 2>/dev/null || true
}

# 프로필 이름 -> "너비 높이". 설정에 없으면 1440x1080.
ab_cfg_viewport() {
  echo "$(ab_cfg "profiles.$1.viewport.width" "1440") $(ab_cfg "profiles.$1.viewport.height" "1080")"
}

# 지금 세션이 보고 있는 페이지를 설정된 크기로 맞춥니다.
#
# 헤드리스 전용입니다. ab-remote만 씁니다. 거기는 따라갈 창이 없어서
# 크기를 정해주지 않으면 agent-browser 기본값 1280x720으로 굳습니다.
#
# 맥의 headed 브라우저에는 쓰지 마십시오. 거기서는 viewport가 창 크기를 그대로
# 따라가는데, 이걸 걸면 CDP Emulation 오버라이드가 붙어 창과 어긋난 크기로 고정됩니다.
# 창을 키워도 페이지가 안 넓어집니다.
#
# 페이지 단위 설정입니다. 나중에 tab new로 연 탭에는 안 걸립니다.
# 세션 데몬이 살아있을 때만 부르십시오. 세션이 없으면 agent-browser가
# 프로필도 CDP 연결도 없는 브라우저를 새로 띄웁니다.
ab_apply_viewport() {
  local w h rc
  read -r w h <<<"$(ab_cfg_viewport "$1")"
  rc=0
  ab_timeout "${AB_VIEWPORT_TIMEOUT:-5}" agent-browser set viewport "$w" "$h" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ] && return 0
  if [ "$rc" -eq 124 ]; then
    echo "⚠ 화면 크기를 ${w}x${h}로 맞추지 못했습니다. 세션 데몬이 ${AB_VIEWPORT_TIMEOUT:-5}초 안에 답하지 않습니다." >&2
    echo "  브라우저는 그대로 쓸 수 있습니다. 계속 이러면  ab-down $1 && ab-up $1" >&2
  else
    echo "⚠ 화면 크기를 ${w}x${h}로 맞추지 못했습니다." >&2
  fi
  # 화면 크기는 부가 기능입니다. 여기서 실패해도 나머지는 계속 갑니다.
  return 0
}

# tailscale CLI 경로. PATH를 먼저 보고, 없으면 macOS 앱 번들을 씁니다.
# App Store판 바이너리는 번들 밖에서 호출하면 죽으므로 심볼릭 링크를 걸지 마십시오.
ab_ts() {
  if command -v tailscale >/dev/null 2>&1; then
    echo tailscale
    return 0
  fi
  local mac_ts="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
  if [ -x "$mac_ts" ]; then
    echo "$mac_ts"
    return 0
  fi
  return 1
}
