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

# 프로필 이름 -> "너비 높이". 설정에 없으면 1440x1080.
ab_cfg_viewport() {
  echo "$(ab_cfg "profiles.$1.viewport.width" "1440") $(ab_cfg "profiles.$1.viewport.height" "1080")"
}

# 지금 세션이 보고 있는 페이지를 설정된 크기로 맞춥니다.
#
# Chrome의 --window-size로는 못 넘깁니다. agent-browser가 --args를 콤마로 쪼개서
# "--window-size=1440,1080"의 뒤쪽 1080이 열 URL로 해석되고 launch가 통째로 실패합니다.
# 그래서 브라우저를 띄운 뒤에 set viewport로 맞춥니다. headed 창이면 창 크기도 같이 바뀝니다.
#
# 페이지 단위 설정입니다. 나중에 tab new로 연 탭에는 안 걸립니다.
# 세션 데몬이 살아있을 때만 부르십시오. 세션이 없으면 agent-browser가
# 프로필도 CDP 연결도 없는 브라우저를 새로 띄웁니다.
ab_apply_viewport() {
  local w h
  read -r w h <<<"$(ab_cfg_viewport "$1")"
  agent-browser set viewport "$w" "$h" >/dev/null 2>&1 \
    || echo "⚠ 화면 크기를 ${w}x${h}로 맞추지 못했습니다." >&2
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
