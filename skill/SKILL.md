---
name: ab-bridge
description: 로그인 세션이 필요한 브라우저 작업을 할 때 사용합니다. 맥에 떠 있는 로그인된 브라우저(ab-local)와 이 서버의 헤드리스 브라우저(ab-remote) 중 하나를 골라 agent-browser 명령을 보냅니다. 사내 어드민 접속, 로그인이 필요한 사이트 조회, 로그인 상태로 스크린샷이나 데이터 추출이 필요할 때 씁니다.
allowed-tools: Bash(ab-local:*), Bash(ab-remote:*), Bash(ab-profiles:*)
---

# ab-bridge

브라우저 백엔드가 두 개입니다. 둘은 **로그인 상태가 서로 다릅니다.** 자동으로 갈아타지 마십시오.

| 명령 | 어디서 도는가 | 언제 쓰는가 |
|---|---|---|
| `ab-local` | 맥에 떠 있는 로그인된 브라우저 | 로그인이 필요한 사이트. 기본값으로 이쪽을 씁니다. |
| `ab-remote` | 이 서버의 헤드리스 브라우저 | 로그인이 필요 없는 공개 페이지 |

명령 형태는 `agent-browser`와 같습니다. 앞에 붙이기만 하면 됩니다.

```bash
ab-local open https://example.com
ab-local snapshot -i
ab-local click @e3
ab-local screenshot ./shot.png
```

어떤 사이트가 로그인돼 있는지는 `ab-profiles`로 확인합니다.

## 맥의 브라우저가 안 떠 있을 때

`ab-local`이 종료 코드 2로 실패하면 맥에서 브라우저가 내려간 것입니다. **원격에서는 못 고칩니다.**

이때 해야 할 일은 하나뿐입니다. 사용자에게 맥에서 아래를 실행해 달라고 요청하고 멈추십시오.

```
ab-up
```

하지 말아야 할 것:

- `ab-remote`로 대신 시도하지 마십시오. 로그인이 안 된 브라우저라 조용히 다른 결과가 나옵니다.
- 직접 `agent-browser connect`를 다시 시도하지 마십시오. `ab-local`이 이미 합니다.
- 맥을 원격에서 깨우려 하지 마십시오. 그렇게 설계하지 않았습니다.

연결은 됐는데 명령이 이상하게 실패하면 한 번만 `ab-local --reconnect <명령>`을 시도하고, 그래도 안 되면 위와 같이 사용자에게 요청하십시오.

## 로그인이 만료됐을 때

로그인 페이지로 튕기면 세션이 만료된 것입니다. 원격에서 로그인하지 마십시오. 사용자에게 맥의 브라우저 창에서 직접 로그인해 달라고 요청하십시오. 로그인은 프로필에 남아서 다음부터는 유지됩니다.

## 프로필이 여럿일 때

기본 프로필은 `main`입니다. 다른 프로필은 `--profile <이름>`으로 지정합니다.

```bash
ab-local --profile work snapshot -i
```

## agent-browser 자체 사용법

`snapshot`, `@e1` 같은 ref 다루기, 폼 입력 등 일반적인 사용법은 `agent-browser` 스킬에 있습니다. 여기서는 반복하지 않습니다.
