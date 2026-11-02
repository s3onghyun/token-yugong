# 우공 펫: 우공 할아버지가 Claude 토큰을 퍼 나릅니다

[English](README.md)

![팝오버 속 우공 할아버지, 상태별로](docs/demo.gif)

아흔 살에 한 삽씩 산을 옮기기 시작한 옛이야기 속 우공 할아버지가 Mac 메뉴바에 살면서
Claude Code 사용량을 보여 줍니다.

- **지게 = 5시간 한도.** 지게에 흙이 쌓입니다. 가득 차면 앉아서 낮잠을 자고, 메뉴바에 다시
  퍼는 시각이 나옵니다.
- **주간 한도만 있는 계정**(인증된 Ultra): 지게는 주간 한도이고, 그걸 다 써야만 쉽니다.
  오늘 몫(주간의 1/7, 덜 쓴 날은 이월)은 속도만 정해서, 넘으면 땀을 흘리며 천천히 하자고
  합니다. 없는 5시간 미터를 지어내지 않습니다.
- **삽질 속도**(RunCat식): 이 Mac에서 토큰이 빨리 나오면 빨리 파고, 조용하면 삽에 기대
  까치와 수다를 떨고, 리셋 전에 한도에 닿을 속도면 힘에 부쳐 합니다.
- **산**은 지금까지 쓴 모든 토큰만큼 깎입니다(이 Mac에만 저장). 산 하나를 다 옮기면 하늘이
  감동해 과아씨의 두 아들이 산을 업어 가는 짧은 장면이 나오고 다음 산이 나타납니다.
- **이야기 속 사람들.** 요금제를 바꾸거나 새 주가 시작되면 할머니가 와서 "그 흙은 다 어디다
  버리려고?" 하고 묻고(산이 절반 넘게 줄면 응원합니다), 한도를 다 쓰면 지수 영감이 와서 비웃고
  할아버지가 열자의 대답으로 받아칩니다.
- **식구.** 할아버지가 맡을 AI를 고릅니다(기본 Claude). 아들, 손주, 이웃집 아이도 다른 AI를
  하나씩 맡을 수 있습니다: Codex, Gemini CLI, OpenAI·DeepSeek API(한도 대신 월 예산). 기본으로
  손주가 Codex를 맡습니다. Gemini CLI는 Mac에 한도를 남기지 않고 DeepSeek은 잔액만 알려 줘서,
  이 둘은 언제나 모른다고 합니다.
- **모르면 모른다고 합니다.** Claude Code가 한도를 알려 주기 전에는 추측하지 않습니다.

메뉴바 캐릭터부터 팝오버 장면, 앱 아이콘까지 모두 픽셀 아트입니다.

## 설치

macOS 13 이상과 Swift(Xcode 또는 Command Line Tools)가 필요합니다.

```sh
./scripts/bundle.sh          # build/YugongPet.app 생성 (ad-hoc 서명, 공증 안 됨)
open build/YugongPet.app     # 먼저 /Applications로 옮겨도 됩니다
```

처음 실행하면 짧은 안내가 나옵니다. 마지막 장의 **스니펫 복사** 버튼으로 Claude Code
상태줄을 연결합니다(아래). 종료는 팝오버에서 합니다.

번들 없이 `swift run -c release TokenPet`으로도 돌릴 수 있습니다(이때는 알림과 로그인 시
열기가 없습니다).

## Claude Code 연결

Claude Code는 상태줄 명령에 공식 한도(`rate_limits.five_hour`, `rate_limits.seven_day`: 사용
%, 리셋 시각)를 넘겨 줍니다. 브리지 스크립트는 그 객체만 `~/.claude/token-pet/limits.json`에
저장합니다. 프롬프트·경로·세션 ID는 남기지 않고 네트워크도 쓰지 않습니다.

안내(또는 설정 › 사용법과 Claude Code 연결)의 **스니펫 복사**를 누르면 브리지를
`~/.claude/token-pet/`에 넣고 아래 내용을 클립보드에 복사합니다. `~/.claude/settings.json`의
맨 바깥 객체에 직접 붙여 넣으세요. 앱은 이 파일을 고치지 않습니다.

```json
"statusLine": {
  "type": "command",
  "command": "sh ~/.claude/token-pet/statusline-bridge.sh"
}
```

이미 상태줄을 쓰고 있다면 그대로 두고 그 스크립트 첫 줄을
`input=$(cat); printf '%s' "$input" | sh ~/.claude/token-pet/statusline-bridge.sh >/dev/null`
로 바꾼 뒤 JSON은 `$input`에서 읽으세요.

브리지는 `jq`가 있으면 쓰고(macOS 15부터 기본 포함), 없으면 `plutil`을 씁니다.
Codex는 설정할 것이 없습니다. Codex 기록(`~/.codex/sessions`)에 한도가 들어 있습니다.
Gemini CLI도 설정할 것이 없습니다(`~/.gemini/tmp`에서 토큰을 읽음).

**API 예산.** OpenAI API는 설정 › 식구에서 누군가에게 OpenAI를 맡기고, 월 예산(USD)을 넣고
**관리자(Admin) 키**를 붙여 넣습니다(OpenAI는 비용을 관리자 키에만 알려 줍니다). 미터는 이번 달
쓴 돈 ÷ 예산이고 15분마다 묻습니다. DeepSeek은 API 키를 넣으면 잔액이 보입니다. DeepSeek은 쓴
돈을 알려 주지 않아서 미터는 "모름"입니다. 키는 로그인 키체인에만 저장됩니다. 앱이 네트워크를
쓰는 건 이 두 경우뿐입니다.

## 메뉴바가 꽉 찼을 때

macOS는 메뉴바에 자리가 없는 아이콘을 말없이 숨기거나 카메라 노치 뒤에 둡니다. 할아버지는
이것을 알아채고 알림으로 한 번 알린 뒤 작은 떠 있는 창으로 옮겨 옵니다(끌어서 옮기고, 오른쪽
클릭으로 숨김). 설정 › 작은 창: *메뉴바가 꽉 찼을 때*(기본), *항상*, *끔*. 앱을 다시 열면
언제든 나타납니다.

## 설정

팝오버의 톱니바퀴: 언어(시스템, 한국어, English), 메뉴바 숫자(사용한 %, 리셋까지 남은 시간,
리셋 시각, 없음)와 그 옆 할아버지 보이기, 식구(누가 어떤 AI를 맡나, OpenAI 예산, API 키), 작은 창, 로그인할 때
열기(기본 꺼짐, 직접 켤 때만), 사용법 안내. 모두 UserDefaults 도메인 `TokenPet`에 저장되고
`defaults delete TokenPet`으로 산 진행까지 초기화됩니다.

## 숫자가 할아버지가 되는 방법

모든 규칙은 [LOGIC.md](LOGIC.md) 한 장에 있고 규칙마다 단위 테스트가 있습니다(`./test.sh`).
요약하면 공식 한도만 쓰고, 리셋 시각이 지나면 새 구간으로 보고, 주간 전용 계정의 하루 몫은
저장 상태 없이 계산하므로 재시작이나 여러 Mac에서도 같은 답이 나옵니다.

## 개발용

`swift run -c release TokenPet`의 플래그와 `TOKENPET_PREFS`는 [README.md](README.md#for-development)에 있습니다.
캐릭터 시트: `swift run -c release YugongSheet <폴더> [--scenes] [--family] [--visitors]`.

## 라이선스

- 앱 코드(`Sources/`, `bridge/`, `scripts/`, `Tests/`): MIT, [LICENSE](LICENSE).
- 우공 할아버지와 `assets/` 아래 전부(`docs/demo.gif` 포함): 모든 권리 보유, 개인 사용 허락.
  [assets/LICENSE.md](assets/LICENSE.md), [assets/PROVENANCE.md](assets/PROVENANCE.md) 참고.

[변경 기록](CHANGELOG.md)
