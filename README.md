# NotebookLM WebApp Bridge v0.2.0

작가 글 웹앱의 마스터 원문과 NotebookLM 지시서를 Google Sheet 작업큐로 받아, Google 로그인된 Vercel 프런트앱이 로컬 Chrome 확장프로그램을 호출하고 NotebookLM 결과를 지정 Drive 폴더 및 기존 웹앱으로 되돌리는 통합 브리지입니다.

## 구성

- `frontend/`: Google 로그인, 작업 목록, 확장 연결, 실행 관제
- `extension/`: 외부 웹앱 메시지 수신, Chrome 계정 확인, NotebookLM DOM 실행
- `apps-script/`: 로그인 검증, Sheet 작업큐, Drive 결과 저장, Writer callback
- `shared/`: TASK 패키지 스키마
- `docs/`: 구조 및 설치 순서

## 보안 원칙

- 프런트 Google ID token은 Apps Script가 Google tokeninfo로 검증합니다.
- Apps Script는 허용 이메일과 OAuth audience를 검사합니다.
- 프런트앱은 전체 원문이 아니라 `TASK_ID`와 세션만 확장프로그램에 전달합니다.
- 확장프로그램은 Apps Script에서 작업을 다시 검증·claim한 뒤 실행합니다.
- 프런트 Google 이메일과 Chrome 프로필 이메일이 다르면 작업을 거부합니다.
- NotebookLM 또는 Google 비밀번호를 코드나 저장소에 보관하지 않습니다.

## 개발

```bash
npm test
npm run package
```

## 주의

NotebookLM 전용 공식 API를 사용하지 않고 로그인된 Chrome 화면을 조작합니다. 따라서 PC Chrome이 실행 중이어야 하고 NotebookLM UI 변경 시 선택자를 수정해야 할 수 있습니다. Studio 결과의 실제 MP3/MP4 로컬 파일 자동 재업로드는 별도 단계이며, v0.2.0은 결과 텍스트·URL·JSON 매니페스트 Drive 저장까지 제공합니다.
