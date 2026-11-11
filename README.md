# My Closet — Portfolio MVP 1.0

**기능 확정일: 2026-11-12.** 개인의 옷을 사진과 정보로 정리하고 취향에 맞게 관리하는 Flutter 디지털 옷장입니다. 한국어 UI, 세 가지 테마와 PC·모바일 반응형 화면을 제공합니다. AI 코디 추천은 향후 계획이며 현재 구현된 기능이 아닙니다.

기본 앱은 브라우저 IndexedDB에 옷과 사진을 저장합니다. 별도 로컬 개발 모드에서는 Supabase 인증·의류 CRUD·비공개 사진 업로드와 서버 검증을 사용할 수 있으며, 두 옷장은 분리되어 있습니다. 자동 업로드·이전·통합이나 실제 클라우드 연결은 하지 않습니다.

- [포트폴리오 소개·기술 문제·기여 구분](docs/portfolio-mvp-1.0.md)
- [최종 검증·보안 점검·커밋 제외 항목](docs/validation/portfolio-mvp-1.0-20261112.md)
- [이전 개발 기록](docs/history/development-notes.md): 단계별 과거 결과이며 현재 기능 명세와 구분합니다.

## 구현된 기능

- 온보딩, 패션 취향·체감온도 설정, 미니멀/러블리/모던 테마와 로컬 설정 유지
- 사진 카드 옷장, 등록·상세·수정·삭제, 대분류→소분류 필터와 이름 검색
- 모델 v2: 사용자 정의 종류·색상·핏, 소재/계절/스타일 복수 선택, 두께 1~5, 기존 데이터 호환
- 직접 그린 소재 질감·카테고리별 핏 실루엣, 아우터/스커트 등을 구분한 설명
- 카테고리 변경 시 부적합한 종류·핏 정리, 기존 의류는 확인 후 임시 편집 상태만 변경
- 최종 편집 상태 비교에 의한 미저장 변경사항 경고, 미적용 직접 입력·사진 선택도 감지
- IndexedDB의 메타데이터·사진 바이너리 트랜잭션 저장; 사진 Base64를 shared_preferences에 저장하지 않음
- 로컬 Supabase 이메일 인증·세션 복원·의류 CRUD, 서버 UUID/local_id 분리, revision 조건부 수정
- 비공개 Storage 예약 업로드→client_confirmed→서버 실제 파일 검증→ready→인증 다운로드
- 사진 교체 실패 시 기존 사진 유지, 보호 기간 이후 명시적 정리, 로그아웃 시 서버 사진 캐시 제거
- JPEG restart 경계의 디코더 호환성 문제에 한정한 Flutter 기본 코덱 예외 처리

서버 사진 삭제·의류 삭제는 활성 사진/업로드 예약/retired 보호 정책을 따릅니다. 모든 사진을 즉시 삭제하는 기능이나 자동 정리 스케줄러가 아닙니다. 상세 정책은 [사진 연동 문서](docs/supabase/photo-upload-local-20261102.md)를 참고하세요.

## 실행

검증 기준 SDK: Flutter 3.47.8 / Dart 3.13.7, Windows. 의존성 버전은 `pubspec.lock`을 사용합니다.

```powershell
flutter pub get
flutter run -d chrome --web-hostname=localhost --web-port=8080
```

브라우저 저장소는 origin(프로토콜·호스트·포트)별로 분리됩니다. 기존 옷을 보려면 같은 주소·브라우저 프로필을 사용하고, 테스트 목적으로 브라우저 데이터를 지우지 마세요.

### 선택적 로컬 Supabase 개발 모드

실행 중인 별도 로컬 Supabase와 기존 DB/Storage/Edge Function 구성이 필요합니다. 이 저장소를 실행하는 것만으로 서버를 만들거나 SQL을 적용하지 않습니다. SQL 초안은 검토 없이 클라우드에 실행하면 안 됩니다.

1. `config/supabase.crud.local.example.json`을 Git에서 제외된 `config/supabase.crud.local.json`으로 복사합니다.
2. 해당 로컬 서버의 **publishable key만** 입력합니다. service_role/secret/S3 키는 Flutter 설정에 넣지 않습니다.
3. 기본 옷장과 분리된 개발 포트에서 실행합니다.

```powershell
flutter run -d edge --web-hostname=localhost --web-port=8081 --dart-define-from-file=config/supabase.crud.local.json
```

앱은 개발 설정에서 `http://127.0.0.1:54321`과 localhost/127.0.0.1:8081만 허용합니다. 마이페이지에서 로그인하고 **서버 개발 옷장**을 엽니다. 로컬 옷장은 사진 필수, 서버는 사진 없는 pending 의류도 지원합니다. 로컬 Mailpit의 기본 주소는 `http://127.0.0.1:54324`입니다.

## 검증 명령

메모리 사용을 줄이기 위해 아래 명령은 순차 실행합니다.

```powershell
flutter analyze
flutter test --concurrency=1
flutter build web --release --output=build/web_default
flutter build web --release --dart-define-from-file=config/supabase.crud.local.json --output=build/web_dev
node --experimental-strip-types --test supabase/tests/photo_worker.test.ts supabase/tests/photo_operations.test.ts
```

Windows의 비ASCII 임시 경로에서 테스트 엔진이 시작되지 않으면 `scripts/test.ps1 --concurrency=1`을 사용합니다. 해당 명령은 테스트 프로세스의 TEMP/TMP만 변경하고 복원합니다. 개발 빌드는 비공개 로컬 설정이 있어야 가능하며, 기본 빌드는 Supabase 설정이 필요 없습니다.

SQL 카탈로그/RLS/Storage HTTP 테스트와 실제 서버 계약 테스트는 별도 opt-in 테스트입니다. 일반 `flutter test` 또는 worker 단위 테스트 통과를 실제 서버 통합 검증으로 해석하지 않습니다. 최신 실행 범위·성공/실패 수는 [최종 검증 보고서](docs/validation/portfolio-mvp-1.0-20261112.md)에 구분합니다.

## 기술과 구조

- Flutter/Dart, Material 3, file_selector, image, shared_preferences
- idb_shim의 웹 IndexedDB; 네이티브용 파일 저장소는 별도 인터페이스 구현
- supabase_flutter, Auth/JWT, Postgres/RLS, 비공개 Storage, Deno/TypeScript Edge Functions, SHA-256, Magick WASM
- `lib/models`, `screens`, `widgets`, `services`, `services/storage`로 책임 분리. 복잡한 상태관리 의존성 없이 저장소·서비스 주입
- `test`: 모델·저장소·입력 UX·인증·사진·계정 전환·에러 회귀
- `supabase/drafts`, `functions`, `tests`: 설계 SQL·사진 검증/작업 함수·보안 테스트
- `tool`, `scripts`: 별도 합성 프로브와 opt-in 로컬 검증. 실제 데이터 초기화 명령으로 사용하지 않음

## 아직 구현하지 않은 범위

AI 코디 추천/이미지 자동 분석, 날씨 API, 코디 기록, 로컬·서버 옷장 통합 및 사진 이전, WebP 자동 변환, 자동 사진 정리·사용자 quota, 실제 클라우드 배포는 미구현입니다. 해당 메뉴는 준비 중으로 표시합니다.

Android/iOS 실기기, Safari, 배포 환경의 보안·성능은 별도 검증이 필요합니다. 현재 iOS 플랫폼 디렉터리는 없습니다. 미저장 경고는 앱의 지원 이동 경로와 브라우저 기본 이탈 경고를 사용하며 브라우저 강제 종료/크래시까지 데이터 보존을 보장하지 않습니다.

개발자의 요구·UX·데이터 보호 기준과 실제 Edge 확인을 바탕으로 Codex의 구현·테스트·진단·문서 작성 지원을 활용했습니다. 구체적 기여 범위와 검증 근거는 포트폴리오 문서에 구분했습니다.
