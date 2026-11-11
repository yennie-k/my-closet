# Flutter 로컬 인증 연동 — 2026-10-29

기본 앱의 IndexedDB 옷장·설정·온보딩은 그대로 유지하면서 **명시적 개발 설정에서만** Supabase 인증과 서버 의류의 읽기 전용 테스트 화면을 추가했다. 클라우드 연결, SQL/정책 변경, 배포, 로컬 옷 업로드는 하지 않았다.

## 구현과 데이터 경계

- 공식 `supabase_flutter` **2.18.3**을 고정하고 Flutter 3.47.8 / Dart 3.13.7에서 analyze/test/web build로 호환성을 확인했다.
- `MY_CLOSET_SUPABASE_ENABLED`의 기본값은 false다. 이 경우 SDK를 초기화하지 않고 기존 화면만 표시한다.
- 개발 연결은 API **`http://127.0.0.1:54321`**, 웹 origin **`http://localhost:8081` 또는 `http://127.0.0.1:8081`**만 허용한다. URL 불일치, 8080 실행, secret/legacy JWT 형식의 키는 초기화 전에 차단하고 로컬 앱은 계속 사용할 수 있다.
- 클라이언트에는 publishable key만 들어간다. 이는 브라우저 번들에서 볼 수 있는 공개 키다. 실제 키·사용자 토큰·비밀번호를 소스/보고서/로그에 넣지 않았다.
- 회원가입·이메일/비밀번호 로그인·현재 기기 로그아웃은 SDK Auth API를 사용한다. 서버가 발급한 사용자 JWT는 SDK가 관리하며, 수동 JWT 디코딩으로 인증하지 않는다. 실제 테스트 토큰의 알고리즘은 ES256이었다.
- 저장된 세션은 SDK가 복원하고 필요 시 refresh token으로 갱신한다. 앱의 초기 복원에서는 Auth `getUser()`로 사용자 상태를 확인한다. Auth stream에는 `onError`를 두어 갱신 실패를 처리하고 서버 조회 화면의 개인 데이터를 비운다.
- 세션 저장 키는 `my_closet.local_supabase.auth.v1`이다. 기존 설정 키 `my_closet.preferences.v1`과 IndexedDB `my_closet_wardrobe_v1`은 그대로다.
- `AuthController`는 로컬 설정·의류 저장소를 참조하지 않는다. `ServerWardrobeReader`는 조회 메서드만 제공하며, 쓰기 가능한 `WardrobeRepository`를 구현하지 않는다. 기존 `createWardrobeRepository()` 연결을 유지했다.
- 개발 모드의 마이페이지에 로그인 상태·로그인/회원가입·로그아웃·서버 조회 버튼이 나타난다. 테스트 경로는 **`/#/dev/server-wardrobe`**다. 미로그인 상태에서는 서버 조회를 실행하지 않는다. 로그인 시 본인 메타데이터 최대 100건만 조회한다. 사진 다운로드 및 서버 의류 변경 기능은 없다.
- 로그아웃/계정 변경 시 화면 목록을 즉시 비우고 generation/request 번호로 이전 요청의 늦은 응답을 버린다. 로그아웃 HTTP 실패 시에도 SDK 메모리 세션 및 해당 저장 키를 제거하며, 서버 종료 확인 실패를 알린다.
- 기존 3종 Material 테마를 그대로 상속한다. 인증 입력과 계정 카드에는 모바일 줄바꿈, 최소 터치 영역, 비밀번호 숨김, 입력 검증, 한국어 오류 안내를 적용했다.

## 실행

프로젝트 루트 PowerShell에서 실행한다. **기본 실행**에는 개발 설정을 전달하지 않는다.

```powershell
flutter run -d chrome --web-port=8080
```

**로컬 인증 실행**은 다음과 같다. 이번 검증에서 `config/supabase.local.json`을 로컬 CLI의 publishable key만 사용해 생성했고 이 파일은 Git에서 제외했다. 다른 기기에서는 `config/supabase.local.example.json`을 별도 `supabase.local.json`으로 복사한 뒤 **로컬** publishable key를 입력한다. 기존 설정 파일을 덮어쓰지 않는다. service_role/secret key는 입력하지 않는다.

```powershell
flutter pub get
flutter run -d chrome --web-hostname=localhost --web-port=8081 --dart-define-from-file=config/supabase.local.json
```

8081은 8080과 다른 브라우저 origin이므로 기존 옷이 보이지 않는 것이 정상이다. 처음에는 8081에서 온보딩을 완료하고 마이페이지를 연다. 테스트 계정을 직접 가입하거나 별도 합성 fixture 계정으로 로그인한다. 로그인해도 로컬 옷을 업로드하거나 서버 설정으로 덮어쓰지 않는다. `localhost`와 `127.0.0.1`도 서로 다른 origin이므로 테스트 중 주소를 바꾸지 않는다.

현재 로컬 Auth 설정은 `enable_confirmations=false`여서 가입 직후 로그인된다. 확인이 필요한 응답에는 Mailpit `http://127.0.0.1:54324` 안내를 표시한다. 이메일 확인 발송/링크 복귀 흐름은 이번에 켜거나 종단 간 검증하지 않았다. 자동 URI 인증 수신은 비활성화했다. 확인 메일을 사용하는 환경을 추가할 때 redirect allowlist와 확인 링크/PKCE 흐름을 별도로 구현·검증해야 한다.

## 실제 검증 결과

[기계 판독 결과](flutter-auth-results-20261029.json)에 검사 이름과 보존 비교를 기록했다.

| 검사 | 결과 | 범위 |
| --- | --- | --- |
| `flutter analyze` | 통과, 이슈 0 | 전체 Flutter 프로젝트 |
| `flutter test` | **61 통과 / 0 실패** | 기존 50 + 신규 11; 세 테마의 360/1280px 입력·오류 검증, 세션/늦은 조회 응답 처리 등 |
| 기본 `flutter build web --no-web-resources-cdn` | 통과 | 개발 flag 없는 기본 앱 |
| 개발 설정 web build | 통과 | `build/web_auth`, 별도 origin에서 실행 |
| 실제 로컬 Auth/REST API | **15 통과 / 0 실패** | 신규 A/B 가입, 약한 비밀번호 거절, 정상/오류 로그인, ES256, Auth 사용자 확인, 본인 조회, 교차 사용자 차단, anon 차단, 로그아웃/refresh 거절 |
| 실제 production Flutter + Chrome | **14 통과 / 0 실패** | UI 가입/로그인/오류/로그아웃, 실제 페이지 새로고침, 세션 복원·refresh, 서버 조회, 모바일 화면, 합성 IndexedDB·설정 보존 |
| 기존 브라우저 저장소 회귀 | 통과 | 별도 probe DB/프로필에서 v1 원본 읽기 비변경, 두 번 실제 새로고침, v2 정보·바이너리 사진 보존, 합성 fixture CRUD |

의도한 부정 검사에서는 잘못된 비밀번호가 400, 약한 비밀번호가 400/422, anon 의류 조회가 401/SQLSTATE 42501을 반환했다. 타 사용자 의류 ID 직접 조회는 **user_id 조건을 넣지 않아도** RLS로 200/빈 배열을 반환했다. UI에서 타 사용자 행이 안 보이는 검사와 별도로 서버 RLS를 검사했다.

Chrome 하네스는 `localhost:8081`과 **새 임시 프로필**만 사용했다. UI에서 신규 C 계정을 가입시킨 뒤 서버 의류가 없음을 확인하여 로컬 의류 자동 업로드가 없음을 검사했다. 합성 로컬 의류·사진 바이트·설정은 전체 흐름 전후 동일했다. 8080이나 기존 Chrome 프로필은 열지 않았다. 실제 사용자의 기존 옷장을 열어 전후 비교한 것은 아니다.

토큰 갱신 검사는 격리된 페이지의 JavaScript 시계만 2시간 앞당겨 SDK 만료 분기를 실행했고, **실제 local refresh HTTP 200** 수신 시 즉시 복구했다. JWT·서버·Windows 시스템 시간을 바꾸지 않았다. 1시간 자연 만료를 기다린 테스트는 아니다. SDK가 `expires_at` 캐시 대신 JWT의 exp에서 만료를 계산하므로, 초기의 캐시 시각 변경 시도는 refresh 요청을 발생시키지 않았다.

초기 일반 `flutter test` 실행은 한글 Windows 사용자 TEMP 경로에서 엔진 isolate 시작 오류로 실패했다. 기존 `scripts/test.ps1`로 TEMP를 프로젝트 build 아래에 지정해 전체 61건 통과를 확인했다. 초기 Chrome 하네스의 문서 로딩/문자열 이스케이프/탭 식별 오류를 수정했고, 재로딩 완료 이벤트까지 기다리는 방식으로 보완한 후 최종 14건을 재실행했다. 초기 오류는 통과로 집계하지 않았다.

## 기존 서버 데이터 보존 확인

작업 시작 시 기존 행 전체의 JSON digest와 ID를 기록하고 마지막에 다시 비교했다.

| 대상 | 작업 전 | 작업 후 | 기존 행 변경 |
| --- | ---: | ---: | --- |
| garments | 42 | 44 | 없음; 새 A/B 합성 fixture 2건만 추가 |
| user_preferences | 2 | 2 | 없음 |
| storage.objects | 35 | 35 | 없음 |
| storage.buckets | 3 | 3 | 없음 |
| auth.users | 8 | 12 | 없음; 새 합성 계정 4개만 추가 |

Storage 쓰기/삭제 요청을 실행하지 않았다. 기존 사진 파일 바이트를 다시 다운로드해서 해시 비교한 검사는 아니다. 앱 모델·로컬 저장소·의류 등록/수정/상세·테마·SQL 초안·기존 SQL 테스트·Edge Function 파일도 Git diff로 변경이 없음을 확인했다. 테스트 계정/fixture는 자동 삭제하지 않고 검토용으로 남겨 두었다.

## 재현 명령

`flutter-auth-prepare.mjs`는 로컬 Docker context·원격 link 없음·로컬 API/DB 포트 가드를 통과한 경우에만 새 합성 A/B와 서버 의류를 만든다. 기존 행·스키마·Storage는 변경하지 않는다. 출력된 `folder`를 뒤 명령에 사용한다. 비밀번호/JWT는 ignored build 하위에만 보관하며 출력하거나 커밋하지 않는다.

```powershell
node supabase/local/flutter-auth-prepare.mjs
flutter build web --output build/web_auth --no-web-resources-cdn --dart-define-from-file=config/supabase.local.json
# 위 prepare가 출력한 이번 실행 폴더를 사용한다.
node scripts/auth_browser_test.mjs build/supabase-flutter-auth/auth-<run-id>
.\scripts\test.ps1
.\scripts\browser_storage_test.ps1
flutter analyze
flutter build web --no-web-resources-cdn
```

브라우저 하네스는 8081이 이미 사용 중이면 종료하며 다른 서버/프로필을 종료하지 않는다. 테스트 프로필과 결과는 ignored build 아래 보존한다. 보고서 생성 스크립트 `flutter-auth-report.mjs`는 기존 행 보존을 다시 확인하고 결과 JSON을 신규 생성한다. 기존 보고서가 있으면 덮어쓰지 않고 중단한다. 고정 날짜의 테스트 집계는 이번 실행 결과이므로 다른 실행의 Flutter 검사 결과를 대신하지 않는다.

## 변경 파일

- `pubspec.yaml`, `pubspec.lock`: 공식 SDK와 잠금 버전.
- `.gitignore`, `config/supabase.local.example.json`: 기기별 공개 클라이언트 설정 분리.
- `lib/config/supabase_config.dart`: 개발 활성화/로컬 URL·키·origin 검증.
- `lib/main.dart`: 조건부 SDK 초기화와 세션 복원 시작.
- `lib/app.dart`, `lib/screens/app_shell.dart`, `lib/screens/profile_screen.dart`: 선택적 인증 주입·마이페이지·개발 경로.
- `lib/services/auth_service.dart`: Auth 포트/SDK 어댑터·안전한 오류 메시지.
- `lib/services/auth_controller.dart`: 세션·비동기 상태 관리.
- `lib/services/server_wardrobe_reader.dart`: 별도 서버 메타데이터 모델·읽기 전용 조회.
- `lib/screens/auth_screen.dart`: 한국어 로그인·가입 폼.
- `lib/screens/server_wardrobe_test_screen.dart`: 인증 필요 개발 조회 화면·늦은 응답 폐기.
- `lib/widgets/auth_account_card.dart`: 마이페이지 계정 카드.
- `test/auth_test.dart`: 신규 단위/위젯 11건.
- `scripts/auth_browser_test.mjs`: 실제 production Flutter/Chrome 검사.
- `supabase/local/flutter-auth-prepare.mjs`, `flutter-auth-report.mjs`: 합성 fixture/API 검사·보존 비교.
- 이 문서, 결과 JSON, 루트 README의 실행 안내 링크.
- Git 제외 파일: `config/supabase.local.json`, `build/supabase-flutter-auth/*`, `build/web_auth/*`.

## 남은 작업과 보안 경계

- 기존 RLS 29/Storage 33 및 worker suite는 이번 Flutter 변경에서 재실행하지 않았다. 해당 SQL/worker는 수정하지 않았고 이번 Auth/조회 경계는 별도 실제 API 검사로 확인했다.
- Android/iOS/네이티브 Windows 인증 실행은 미검증이다. 네이티브/실기기의 로컬 API 주소와 딥링크는 다음 플랫폼 작업에서 명시적으로 구성해야 한다.
- 로그아웃은 이 브라우저의 세션/refresh 권한을 종료한다. 이미 발급된 access JWT는 만료 전까지 유효할 수 있다. 즉시 전체 access token 취소나 모든 기기 로그아웃을 구현한 것은 아니다.
- 서버 사진 표시, 서버 의류 CRUD, 사용자 설정 동기화, 수동 이전 UI와 원자성·충돌 처리, OAuth/비밀번호 재설정은 아직 없다.
- 실제 클라우드 설정·연결·배포는 별도 단계다. 이 개발 빌드의 로컬 제한을 무심코 완화하지 말고 redirect/CORS/키/환경 분리와 RLS를 다시 검토해야 한다.

SDK 동작의 근거: [공식 Flutter SDK](https://pub.dev/packages/supabase_flutter), [초기화](https://supabase.com/docs/reference/dart/initializing), [회원가입](https://supabase.com/docs/reference/dart/auth-signup), [Auth 상태 stream과 onError](https://supabase.com/docs/reference/dart/auth-onauthstatechange). 세션 복원·로그아웃·만료 판정은 설치된 2.18.3 / gotrue 2.27.3 소스도 확인했다.
