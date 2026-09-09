# ab-bridge

맥에 로그인된 브라우저를 띄워두고, Tailscale로 연결된 원격 서버의 Claude가 그 브라우저를 쓰게 합니다.
자격증명은 맥에만 남습니다. 원격에는 아무것도 안 갑니다.

## 구조

```
맥                                   원격 서버
─────────────────────────────        ─────────────────────
agent-browser --headed               ab-local ──┐
  --profile ~/.agent-browser-                   │ CDP
    profiles/main                               │
        │ 127.0.0.1:<그때그때 다른 포트>          │
        │ (프로필의 DevToolsActivePort에 적힘)    │
tailscale serve --tcp 9222  ◀────────────────────┘
        (tailnet 안에서만)             ab-remote → 이 서버의 헤드리스 브라우저
```

## 설치

`jq`가 필요합니다. 맥은 `brew install jq`, 데비안·우분투는 `sudo apt install jq`.

맥:

```bash
git clone <이 리포> ~/src/ab-bridge
cd ~/src/ab-bridge && ./install.sh mac
ab-up                      # 브라우저가 뜨면 필요한 사이트에 로그인
```

원격 서버:

```bash
git clone <이 리포> ~/src/ab-bridge
cd ~/src/ab-bridge && ./install.sh remote
ab-local open https://example.com
```

`install.sh remote`는 `~/.claude/skills/ab-bridge` 링크도 걸어서 Claude가 사용법을 알게 합니다.

## 설정

`~/.config/ab-bridge/profiles.json`. 맥과 원격이 각자 하나씩 갖습니다.
`profiles.example.json`을 참고하십시오.

```json
{
  "macHost": "macbookpro",
  "profiles": {
    "main": {
      "port": 9222,
      "viewport": { "width": 1440, "height": 1080 },
      "sites": ["https://admin.example.com"]
    }
  }
}
```

`sites`는 그 프로필에 무엇이 로그인돼 있는지 적어두는 자리입니다. 원격 Claude가 `ab-profiles`로 읽습니다.

`viewport`는 **`ab-remote`가 쓰는 헤드리스 브라우저의 페이지 크기**입니다. 안 적으면 1440x1080입니다.
맥 브라우저(`ab-up`, `ab-local`)에는 안 씁니다. 거기는 창 크기를 그대로 따라갑니다.

## 알아둘 것

**CDP는 tailnet IP로만 붙습니다.** MagicDNS 이름을 쓰면 Chrome이 거절합니다.

```
$ curl http://100.x.x.x:9222/json/version
{ "Browser": "HeadlessChrome/145...", ... }

$ curl http://macbookpro.tailnet.ts.net:9222/json/version
Host header is specified and is not an IP address or localhost.
```

Chrome의 DNS 리바인딩 방어가 Host 헤더를 검사해서 IP만 통과시킵니다.
`ab-local`이 `tailscale ip -4 <macHost>`로 IP를 뽑아 쓰는 이유입니다.

**CDP 포트를 `--args`로 지정하면 안 됩니다.** agent-browser는 Chrome을
`--remote-debugging-port=0`으로 띄우고, 프로필의 `DevToolsActivePort` 파일에서
실제 포트를 읽어 붙습니다. 여기에 `--args`로 포트를 덧붙이면 Chrome이 그 파일을
만들지 않아 데몬이 브라우저를 영영 못 찾습니다. 그러면 `set viewport`나 `get url`
같은 명령이 전부 답 없이 매달리고, `ab-down`도 브라우저를 못 닫아서 창을 꺼도
데몬이 다시 띄웁니다. 고정 포트가 필요한 쪽은 tailnet뿐이라, `ab-up`이 실제 포트를
읽어 `tailscale serve`로 대외 9222에 이어 줍니다. 원격에서 쓰는 주소는 그대로입니다.

**맥 브라우저의 화면 크기는 창 크기를 그대로 따라갑니다.** 창을 키우면 페이지도 같이
넓어지고, 원격에서 찍는 스크린샷도 그 크기로 나옵니다. 따로 맞출 필요가 없습니다.

`set viewport`를 걸면 **오히려 고정됩니다.** CDP Emulation 오버라이드가 붙어서 창과
페이지가 따로 놀고, 창을 키워도 페이지는 그대로입니다. 맥 브라우저에는 쓰지 마십시오.
`ab-remote`의 헤드리스 브라우저만 예외입니다. 거기는 따라갈 창이 없어서 설정의
`viewport`로 크기를 정해줘야 하고, 안 정하면 1280x720으로 굳습니다.

**세션 쿠키는 프로필에 안 남습니다.** 만료시각 없는 쿠키는 Chromium이 디스크에 안 씁니다.
브라우저를 내리면 사라지므로, 그런 사이트는 `ab-down`을 자주 하지 마십시오.

**연결이 끊기면 `ab-local`이 알아서 한 번 다시 붙습니다.** 맥을 재부팅했거나 `ab-up`을
다시 돌린 경우입니다. 그래도 안 되면 `ab-local --reconnect <명령>`을 쓰십시오.

**데몬이 떠 있으면 옵션이 무시됩니다.** agent-browser는 실행 중에 `--profile`을 바꾸면
경고만 내고 넘어갑니다. `ab-up`이 먼저 데몬을 정리하는 이유입니다.

**브라우저는 127.0.0.1에만 바인딩합니다.** 외부 노출은 `tailscale serve`가 담당하고,
tailnet 밖에서는 안 보입니다. CDP에는 인증이 없으니 이 경계를 없애지 마십시오.
`tailscale funnel`로 인터넷에 열면 브라우저를 통째로 넘기는 것과 같습니다.
