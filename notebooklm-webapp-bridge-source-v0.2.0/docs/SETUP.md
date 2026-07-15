# 설치 순서

1. Google Cloud에서 OAuth 2.0 Web client를 만들고 Vercel 주소를 Authorized JavaScript origin에 추가합니다.
2. `frontend/config.js`에 Google Client ID, Apps Script URL, 확장프로그램 ID를 입력합니다.
3. `apps-script/Code.gs`, `appsscript.json`을 Apps Script 프로젝트에 넣고 Script Properties를 설정합니다.
4. `setupNotebookLMBridge()` 실행 후 Apps Script를 웹앱으로 배포합니다.
5. `extension/` 폴더를 Chrome 개발자 모드에서 압축해제 설치합니다.
6. 확장프로그램 ID를 `frontend/config.js`에 입력하고 프런트앱을 Vercel에 재배포합니다.
7. 확장프로그램 사이드패널에서 Apps Script URL과 정확한 Vercel Origin을 저장합니다.
8. 작가 웹앱에서 `enqueueFromWriter`로 작업을 등록하고 프런트앱에서 실행합니다.
