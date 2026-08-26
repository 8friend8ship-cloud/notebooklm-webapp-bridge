# NotebookLM + Flow 최적화 명령 변환 설명서

## 목적
중앙에이전트가 사용자의 한 문장 작업지시를 그대로 실행하지 않고, 누락·중복·충돌을 줄인 표준 작업 계약으로 변환한 뒤 NotebookLM, Flow, Apps Script 큐, GitHub Local Agent에 동일한 의미로 전달한다.

## 기본 흐름
1. 사용자 상위 명령 수신
2. projectKey / goal / sourceRefs 추출
3. 필요한 결과물 체크리스트 생성
4. 각 결과물별 설정값/변형값 생성
5. 같은 project+outputType+variant 중복 제거
6. 서로 다른 outputType은 병렬 허용
7. 같은 Chrome 세션/렌더러/파일명 충돌만 직렬화
8. NotebookLM_Task_Queue 26열로 변환
9. CLAIMED 후 60초 이내 START/RUNNING 확인
10. 미디어 길이/파일 변화 기반 진행 판단
11. RESULT_SAVED + RESULT_READBACK까지 완료 판정
12. 중앙 History/Library/작업지시/Workflow에 evidence 기록

## 상위 명령 예시
`프로젝트 A 자료로 한국어 오디오, 3분 설명 영상, PDF 브리핑, 마인드맵을 만들고 Flow에서는 같은 장면을 낮/밤 두 버전으로 만들어 저장 검증까지 진행`

## 자동 변환 예시
- NOTEBOOKLM_AUDIO / ko-KR / focus=핵심요약
- NOTEBOOKLM_VIDEO / durationSec=180 / style=설명형
- NOTEBOOKLM_REPORT_PDF / reportType=brief / depth=standard
- NOTEBOOKLM_MIND_MAP / depth=standard
- FLOW_SCENE / variant=DAY
- FLOW_SCENE / variant=NIGHT

각 child task는 parentCommandId를 유지한다. 따라서 결과는 다시 한 상위 명령의 결과 세트로 묶을 수 있다.

## 설정값 원칙
- 사용자 명시값이 최우선이다.
- 비핵심 누락값은 안전 기본값을 적용하고 기록한다.
- sourceRefs 같은 핵심 입력이 없으면 임의 생성하지 않고 HOLD_MISSING_SOURCE 처리한다.
- 같은 outputType이라도 설정이 다르면 덮어쓰지 않고 variant로 보존한다.
- 동일 variant 중복은 실행 전에 제거한다.

## NotebookLM 최적화
NotebookLM은 한 프로젝트에서 AUDIO, VIDEO, REPORT/PDF, MIND_MAP 같은 서로 다른 결과를 개별 작업으로 분리한다. 프로젝트 전체를 잠그지 않는다. 각 outputType마다 START/PROGRESS/RESULT를 독립 측정한다.

## Flow 최적화
Flow는 장면 자체와 장면 변형을 분리한다. prompt, ingredients, frames, camera, lighting, style, aspectRatio, durationSec를 명시적 settings로 보존한다. 동일 scene의 낮/밤, 카메라, 스타일, 캐릭터 차이는 variant로 생성한다.

## Apps Script 큐 변환
대상 시트: NotebookLM_Task_Queue
필수 26열은 기존 표준을 유지한다.
SOURCE_TEXT에는 parentCommandId/projectKey/outputType/variantKey/settings/sourceRefs를 JSON으로 저장한다.
INSTRUCTION에는 goal/successCriteria/savePolicy/readbackPolicy를 사람이 읽을 수 있게 저장한다.

## 완료 기준
코드 생성/큐 등록/CLAIMED만으로 완료하지 않는다.
완료는 최소 다음을 모두 요구한다.
- START 또는 RUNNING 실제 증거
- 진행 또는 결과파일 변화 증거
- RESULT_SAVED
- RESULT_READBACK
- 기대 outputType 일치
- 중복/충돌 없음

실패 시 동일 작업을 무작정 재시도하지 않고 ROOT_CAUSE → MINIMUM_FIX → SAME_FIXTURE_RETEST를 적용한다.

## 중앙에이전트 작업지시 기본 규칙
앞으로 NotebookLM/Flow 관련 사용자의 자연어 지시는 직접 실행문으로 쓰지 않고 먼저 config/notebooklm-flow-command-template-v1.json 계약으로 normalize한다. 그 결과를 Apps Script/GitHub/Local Agent가 공통으로 사용한다.
