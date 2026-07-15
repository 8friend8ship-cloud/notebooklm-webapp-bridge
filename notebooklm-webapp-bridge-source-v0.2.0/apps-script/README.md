# Apps Script 설정

Script Properties에 다음 값을 넣습니다.

- `GOOGLE_CLIENT_ID`: 프런트앱 Google OAuth Web Client ID
- `ALLOWED_EMAILS`: 허용 계정 이메일(쉼표 구분)
- `SESSION_SECRET`: 긴 임의 문자열
- `SPREADSHEET_ID`: 작업큐 스프레드시트 ID
- `TASK_SHEET_NAME`: 기본값 `NotebookLM_Task_Queue`
- `DRIVE_ROOT_FOLDER_ID`: 결과 기본 저장 폴더 ID
- `WRITER_SHARED_SECRET`: 작가 웹앱에서 작업 등록 시 사용하는 공유 비밀키

`setupNotebookLMBridge()`를 한 번 실행한 뒤 웹앱으로 배포합니다. 실행 사용자는 소유자, 접근 권한은 요구 환경에 맞게 설정하되 `ALLOWED_EMAILS` 검증을 유지합니다.
