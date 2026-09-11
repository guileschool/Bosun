# Bosun 구조

## 구성

- `Sources/main.swift`: 앱 시작과 명령줄 진단 진입점.
- `Sources/BosunApp.swift`: 메뉴, 권한, 음성 인식 세션, 명령 실행 연결.
- `Sources/Commands.swift`: 명령어 목록, 인식 모드, 타이밍, 삭제 복원 상태.
- `Sources/Accessibility.swift`: macOS Accessibility 접근과 입력창 모델.
- `Sources/ChatGPTControl.swift`: 대상 입력창 탐색, 버튼 실행, 전사 대기와 입력 편집.
- `Sources/Localization.swift`: 언어 리소스 로딩.
- `Sources/MenuHeaderView.swift`: 메뉴 헤더 표시.
- `Sources/Probe.swift`: 사용자가 요청한 마이크 진단.

## 동작

기기 내 영어 음성 인식으로 명령어를 감지한다. 단독 명령어 모드와 `please` 복합어 모드를 지원한다. 대상 입력창과 버튼은 Accessibility 정보로 탐색하며, 버튼 초점을 확인한 뒤 키보드로 활성화한다.

Send는 녹음 중이면 먼저 정지하고 전사를 기다린다. 말끝 명령어 정리 결과를 확인한 다음 보내기 버튼을 실행한다. Break는 진행 중인 전송 절차를 취소하거나 응답 생성을 중단한다.

Undo는 Bosun의 직전 Delete 또는 Clear에 한정된다. 같은 입력창에서 내용이 바뀌지 않은 경우 한 번 복원한다.

## 권한과 진단

마이크, 음성 인식, 손쉬운 사용 권한이 필요하다. 오디오는 파일로 저장하지 않는다. 단계 로그와 진단 파일은 macOS 임시 폴더에 생성된다. 인식한 말이나 입력 내용이 포함될 수 있으므로 저장소에 넣지 않는다.

```sh
/Applications/Bosun.app/Contents/MacOS/Bosun --dump
/Applications/Bosun.app/Contents/MacOS/Bosun --probe
```

`--dump`는 입력창 상태를 읽는다. `--probe`는 권한이 있을 때 마이크 진단을 실행한다. 대상 앱의 UI 변경은 버튼 탐색과 실행에 영향을 줄 수 있다. 실제 검증 범위는 [VALIDATION.md](VALIDATION.md)에 기록한다.
