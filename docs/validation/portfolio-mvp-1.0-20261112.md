# Portfolio MVP 1.0 최종 검증 — 2026-11-12

## 확정 범위

기존 온보딩·취향·테마·디지털 옷장·IndexedDB·로컬 Supabase 인증/CRUD/사진 업로드·검증·ready 표시·JPEG restart 예외 처리·카테고리별 입력 UX·분류 전환·미저장 경고를 현재 MVP로 확정한다. 새 추천 기능·WebP 자동 변환·클라우드 배포·옷장 통합은 추가하지 않았다.

이번 마무리에서는 제품 기능 코드를 수정하지 않았다. README를 현재 상태로 정리하고 전체 이전 내용을 `docs/history/development-notes.md`에 보존했다. 포트폴리오 설명·보안 검사 도구·비밀/백업 제외 규칙을 추가했고, 기존 보고서의 PC 경로와 개별 사진 식별자를 익명화했다. 로컬 테스트 도구의 고정 PC 경로는 프로젝트/환경 변수로 바꿨다. 실제 SQL·RLS·Storage 정책·Edge Function 구현은 변경하지 않았다.

## 실행한 검증

| 항목 | 이번 실행 결과 | 의미와 한계 |
|---|---|---|
| `flutter analyze` | 통과, No issues found | 기존 앱과 새 분석 도구 포함 |
| `scripts/test.ps1 --concurrency=1 --reporter=expanded` | **166 통과 / 0 실패** | flutter test 전체; 합성/가짜 저장소·전송 및 테스트 임시 디렉터리 사용 |
| 기본 release 웹 빌드 | 성공, exit 0 | `build/portfolio-finalization-20261112/web_default` |
| 로컬 개발 설정 release 웹 빌드 | 성공, exit 0 | `build/portfolio-finalization-20261112/web_dev`; 설정 값은 기록/커밋하지 않음 |
| worker·사진 작업 함수 Node 단위/계약 | **39 통과 / 0 실패 / 0 skip** | 기존 photo_worker 24 + photo_operations 15, 메모리 포트; 실제 서버 테스트 아님 |
| SQL 초안 오프라인 검사 | **4파일 파싱·4개 정적 assertion 통과** | 기존 check_draft_sql.py 사용, 출력만 build로 돌려 과거 보고서 보존. SQL 실행/카탈로그/RLS 동작 검증 아님 |
| 실제 IndexedDB 독립 프로브 | 성공 | 전용 임시 Edge 프로필·합성 DB, 실제 페이지 두 번 reload 후 바이너리/구형 읽기/수정/삭제 확인 |
| 수정한 Node 도구 구문 검사 | 통과 | browser_storage_test.cjs, browser_test_driver, auth_browser_test, photo_codec_browser_test, unsaved_guard_browser_test, integration.mjs |

기본/개발 웹 빌드에는 Flutter의 Wasm dry-run 성공 및 폰트 tree shaking 안내가 있었다. PowerShell이 stderr 안내를 NativeCommandError 형태로 로그에 포장했으나 두 명령의 실제 종료 코드는 0이고 빌드 산출물이 생성됐다. Wasm 런타임 테스트를 수행했다는 뜻은 아니다.

IndexedDB 프로브에서 확인한 실제 출력:

```text
WRITE_OK
READ_AFTER_RELOAD_OK; UPDATE_WRITTEN
UPDATED_AFTER_RELOAD_OK; LEGACY_PRESERVED; DELETE_OK
```

전체 Flutter 테스트에는 다음 회귀 범위가 포함된다.

- 기존 온보딩·설정·테마·반응형 내비게이션
- 모델 v2 직렬화·기존 문자열 호환·저장소 트랜잭션/실패 보존
- 등록·상세·수정·삭제, 계층형 필터+검색, 모바일/PC 크기
- 카테고리 변경 확인/취소, 부적합한 종류·핏 초기화, 사용자 정의 값 호환
- 최종 편집 상태 비교·직접 입력·사진 선택·계속 수정/저장 없이 나가기·저장 성공/실패/진행 중 이탈
- Supabase 인증 컨트롤러·설정 가드·DTO·revision/계정 전환 계약, ready 전 사진 비표시·업로드 실패·로그아웃 캐시/늦은 응답 처리
- JPG/PNG/WebP 입력·투명도·EXIF·리사이즈·불량 파일과 출력 코덱 검사, 합성 restart JPEG의 픽셀 손상 재현 및 예외 경로 회귀

자동 테스트가 Android 시스템 제스처, 모든 브라우저의 beforeunload 동작 또는 실제 서버 보안을 전부 검증하는 것은 아니다.

## 이번에 재실행하지 않은 사항

- **실제 Supabase HTTP 통합·DB RLS/Storage API 실행**: 미실행. 로컬 서버 폴더에서 명령/Git 작업을 하거나 SQL을 실행하지 않았다. opt-in Dart 서버 계약 도구를 이번 실행 성공 수에 포함하지 않는다.
- **브라우저 수동 앱 확인 및 실제 사용자 사진 업로드**: 미실행. 기존 사용자 확인 기록은 과거 근거이며 이번 자동 실행과 구분한다.
- **앱 전체 브라우저 E2E**: 미실행. 이번 브라우저 실행은 IndexedDB 저장소 전용 자동 프로브다.
- 실제 localhost:8080 IndexedDB 및 서버에 보관된 의류/사진 바이트: 읽거나 변경하지 않았다. 해당 실제 사진 해시가 이번에 새로 검증됐다고 주장하지 않는다.
- Android/iOS/Safari 실기기, 실제 클라우드 배포·운영 부하·quota·자동 고아 파일 정리: 미검증/미구현.

## 보안·파일 검토

작업 시작 시 git status, diff, diff --stat, 최근 커밋과 사용자 설정을 확인했다. 기존 스테이징은 비어 있었다. Git 원격 주소는 사용자가 지정한 저장소와 로컬 설정상 일치하며 네트워크 Git 작업을 하지 않았다. 기존 Git 사용자 이름/이메일을 사용하고 임의 설정하지 않는다.

- 선별 목록으로 소스·테스트·예시 설정·문서만 스테이징한다. `git add .`/`git add -A`는 사용하지 않는다.
- 최종 Git index 전체(기존 추적 파일 포함)를 `scripts/audit_staged.py`로 검사한다. 실제 비밀 설정 값과 일치하는 문자열, JWT/secret/private key/키 형태, 개인 이메일·절대 경로·긴 Base64/이미지 삽입·DB/빌드 파일을 검사한다.
- 바이너리는 기본 앱 아이콘과 출처가 기록된 합성 `test/fixtures/synthetic_restart_422.jpg`만 허용한다. 사용자 사진을 fixture로 사용하지 않는다.
- `git diff --cached --check`와 staged diff/stat 검토 후 커밋한다. 검사 결과는 [검증 요약 JSON](portfolio-mvp-1.0-results-20261112.json)에 기록한다.
- 정규식 검사와 수동 선별은 모든 형태의 비밀을 탐지한다는 보장은 아니다. 필요 시 push 전에 전용 secret scanner와 원격 이력 검토를 추가할 수 있다.

Git에서 제외된 실제 기기 설정 `config/supabase.local.json`, `config/supabase.crud.local.json`은 그대로 두었다. `.env`, 키 파일, DB/백업, build/cache, private data 및 개별 사용자 사진 진단 JSON을 제외하도록 .gitignore를 보완했다. 예시 JSON에는 placeholder만 있다.

초기 index 검사에서 브라우저 테스트 도구의 파일 끝 빈 줄 1건을 정리했다. 보안 스캔의 URL 사용자정보 패턴은 인증 테스트의 의도적 URL 스푸핑 거부 입력 1건을 검출했으나 실제 자격증명이 아니었다. 해당 파일·정확한 합성 입력만 명시적으로 예외 처리했고, 실제 키/토큰에 대한 예외는 추가하지 않았다. 최종 검사를 다시 수행한다.

## MVP 커밋에 포함하지 않는 로컬 파일

다음 자료는 삭제하지 않는다. 개별 진단 JSON은 .gitignore로 보호하며, 나머지는 미추적 상태로 남긴다.

| 파일 | 이유 |
|---|---|
| `docs/supabase/jpeg-restart-results-20261109.json` | 개별 실제 사진 이름·fingerprint가 있는 개인 진단 기록, ignore |
| `scripts/jpeg_readonly_edge_diagnostic.mjs` | 특정 개인 파일 전용 진단 |
| `tool/jpeg_pixel_diagnostic_test.dart` | 개인 파일 opt-in 진단 |
| `tool/fit_illustration_preview_test.dart` | 별도 PC 폰트를 참조하는 보조 렌더링 실험 |
| `docs/supabase/webp-feasibility-20261111.md` | 별도 WebP 타당성 연구 |
| `docs/supabase/webp-feasibility-20261111/results.json` | WebP 측정 자료 |
| `docs/supabase/webp-feasibility-20261111/comparison-crops.png` | 합성 WebP 비교표 |
| `docs/supabase/webp-feasibility-20261111/comparison-overview.png` | 합성 WebP 비교표 |
| `scripts/webp_benchmark_browser.mjs` | WebP 연구 도구 |
| `scripts/webp_benchmark_contact_sheet.mjs` | WebP 연구 도구 |
| `scripts/webp_benchmark_report.mjs` | WebP 연구 도구 |
| `scripts/webp_benchmark_worker.mjs` | WebP 연구 도구 |
| `tool/webp_benchmark_app.dart` | WebP 연구 도구 |
| `tool/webp_benchmark_core.dart` | WebP 연구 도구 |
| `tool/webp_benchmark_vm.dart` | WebP 연구 도구 |

추가로 build 산출물·로그·임시 브라우저 프로필·문서 익명화 전 비공개 원본은 기존 무시되는 build 폴더에만 있다. 이 파일들은 커밋하지 않는다. 로컬 Supabase 별도 프로젝트와 실제 앱 저장 데이터는 이번 Git 작업 대상이 아니다.

## 커밋과 남은 작업

검증과 index 검사가 통과한 후 `feat: finalize My Closet portfolio MVP`로 로컬 커밋한다. 커밋 해시는 커밋 후 `git log -1 --format="%H %s"`로 확인하며 자기 참조 해시를 이 문서에 넣지 않는다. Git push, 클라우드 연결/배포, 기존 데이터 초기화·자동 이전은 하지 않는다.

실제 원격 반영 전에는 커밋 diff를 별도로 검토하고, 필요 시 합성 계정으로 HTTP 통합과 브라우저 수동 회귀를 다시 실행한다. 포트폴리오에는 [현재 소개·기여·화면 추천](../portfolio-mvp-1.0.md)을 사용하고 AI 추천이나 모바일 출시를 완료 기능으로 표기하지 않는다.
