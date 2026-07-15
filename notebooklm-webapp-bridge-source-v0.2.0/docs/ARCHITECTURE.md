# 구조

1. 작가 웹앱이 `enqueueFromWriter`로 마스터 글과 지시서를 작업큐에 등록합니다.
2. 사용자가 Vercel 프런트앱에서 Google 로그인합니다.
3. Apps Script가 Google ID token을 검증하고 8시간 세션 토큰을 발급합니다.
4. 프런트앱이 `TASK_ID`를 Chrome 확장프로그램에 전달합니다.
5. 확장프로그램은 세션 토큰과 Chrome 프로필 이메일을 Apps Script에 보내 작업을 수령합니다.
6. Apps Script는 프런트 로그인 이메일과 Chrome 프로필 이메일이 다르면 작업을 거부합니다.
7. 확장프로그램이 NotebookLM 탭을 열고 원문+지시서를 입력·실행합니다.
8. 텍스트, NotebookLM URL, 탐지된 결과 URL을 Apps Script에 반환합니다.
9. Apps Script가 결과 TXT/JSON을 지정 Drive 폴더에 저장하고 Sheet 상태를 `DONE`으로 변경합니다.
10. CALLBACK_URL이 있으면 기존 작가 웹앱에 완료 결과를 재송출합니다.

## 현재 범위

- Google 로그인과 Chrome 계정 일치 검증
- 웹앱→확장프로그램 외부 메시지 브리지
- Apps Script/Sheet 작업큐
- NotebookLM 채팅 입력 및 자동 제출
- Studio 버튼 탐색(오디오·동영상·슬라이드·퀴즈·마인드맵, 실험적)
- 텍스트/결과 링크 Drive 저장

NotebookLM DOM은 공식 API가 아니므로 UI 변경 시 선택자 보수가 필요합니다. NotebookLM이 브라우저로 다운로드한 MP3/MP4 파일의 로컬 바이트를 확장프로그램이 다시 읽어 Drive에 업로드하는 기능은 이 버전에 포함하지 않습니다. 대신 결과 링크와 TXT/JSON 매니페스트를 저장합니다.
