# 서버 개발 옷장 사진 연동 — 2026-11-02

## 범위와 데이터 보호

명시적으로 활성화한 **로컬 서버 개발 옷장**에만 사진 선택·업로드·검증·조회·교체·삭제 예약을 추가했다. 기본 `내 옷장`은 계속 기존 IndexedDB를 사용한다. 실사용 Chrome `localhost:8080` 프로필은 열지 않았으며 옷 3벌이나 사진을 읽거나 이전하지 않았다. 서버 테스트는 기존 합성 A/B 계정과 이번 실행에서 새로 만든 합성 의류·이미지만 사용했다. 테스트 데이터는 자동 초기화/일괄 정리하지 않았다.

기존 SQL 초안, DB/RLS/Storage 정책, `verify-garment-photo` 4개 소스, Garment v2 및 IndexedDB 저장 구현은 변경하지 않았다. 서버 최초 스냅샷의 기존 의류·설정·Storage 객체 메타데이터·버킷을 행 해시로 비교한다. 이는 실제 기존 이미지 바이트를 다운로드해 대조한 테스트는 아니다.

클라우드 접속·배포·SQL 적용·Git commit/push는 하지 않았다. Flutter에는 publishable key와 사용자 세션만 사용한다. 관리자 키는 기존 로컬 Edge Runtime의 서버 환경변수로만 읽는다.

## 사진 처리 흐름

1. 기존 선택/압축 서비스를 재사용한다. JPG·PNG·WebP 입력(최대 15MB, 기존 24MP 입력 방어)을 최대 1,600px JPEG로 정규화한다. 투명 배경은 흰색이 되며 원본 포맷/메타데이터 보존 기능은 아니다. 출력 크기·실제 헤더를 다시 검사해 **2MiB, 4,000,000화소, 각 변 4,096px 이하**를 보장한다. 원본 PNG/WebP 바이트의 서버 검증도 별도 HTTP/SDK 테스트로 확인했다.
2. 먼저 기존 revision 기반 저장소로 의류 메타데이터를 저장한다. 사진 없는 `pending` 등록을 계속 지원한다. 메타데이터와 사진은 하나의 트랜잭션이 아니므로 사진 실패 시 이미 저장된 정보를 명시적으로 안내한다. 같은 편집 화면의 재시도는 동일 local_id/서버 UUID를 사용한다.
3. 새 `garment-photo-operations` Edge Function이 Auth 서버 `/auth/v1/user`로 사용자 JWT를 검증하고 사용자 RLS 조회로 의류 소유권을 확인한다. 서버는 기존 최소 photo-column GRANT로만 revision CAS를 수행해 10분 예약을 만든다. 경로는 `사용자 UUID/서버 의류 UUID/실제 바이트 SHA256.확장자`이다. 클라이언트가 임의 경로나 ready를 지정할 수 없다.
4. Flutter가 사용자 JWT로 비공개 버킷에 `upsert:false` 업로드한다. 덮어쓰기나 무제한 자동 업로드 재시도는 하지 않는다. 업로드 성공 응답이 유실된 경우 같은 경로의 실제 바이트 길이/해시를 확인해 재시도한다.
5. 클라이언트는 정확한 revision/예약 경로에 대해 `upload_state=client_confirmed`만 설정한다. 이는 업로드 완료 주장이지 서버 검증 완료가 아니다.
6. 새 함수의 `verify`가 동일 사용자 JWT로 **기존** `verify-garment-photo`를 호출한다. 기존 worker가 Storage 존재·경로·예약 만료·크기·형식·실제 디코딩·픽셀·SHA-256을 검사하고 CAS로 ready를 승인한다. 기존 worker 소스/CORS는 그대로 두고 새 함수가 브라우저 호출 경계를 제공한다.
7. Flutter는 재조회한 `ready`와 `photo_verified_at`가 있는 사진만 카드/상세 화면에 표시한다. 공개 URL/서명 URL을 생성하지 않고 JWT 인증 다운로드를 사용한다. 다운로드의 길이/SHA-256도 서버 기록과 비교한다.

## 사진 교체와 정리의 계약

- 새 후보 검증 실패 시 기존 활성 경로·해시·사진을 유지한다. 성공 시 기존 worker가 이전 사진을 `retired_photo_path`에 보관하고 **25시간** 보호한다.
- 기존 SQL에는 후보 1개/retired 1개 슬롯만 있으므로 retired 사진 정리 전 다음 교체를 거부한다. UI가 정리 가능 시각과 실패 이유를 표시한다.
- `사진 삭제 예약`은 활성 사진을 화면에서 분리해 pending으로 전환하고 이전 사진을 25시간 보관한다. 사용자 JWT로 활성 사진을 직접 물리 삭제하는 우회는 없다.
- `보호 기간 지난 사진 정리`는 기존 Storage RLS를 그대로 적용하는 **사용자 JWT**로 물리 삭제하고, 인증 GET으로 실제 부재를 확인한 후 CAS로 retired 슬롯을 비운다. 서비스 역할로 Storage 삭제하지 않는다.
- 실패/취소 후보는 기존 활성 사진을 건드리지 않고 기존 retired 슬롯에 정리 경로를 먼저 기록한다. 삭제나 CAS가 실패하면 경로를 남겨 새로고침 후 재시도할 수 있다. 아직 검증하지 않은 후보에는 활성 사진의 25시간 보호를 새로 부여하지 않는다.
- 활성·예약·retired 경로가 남아 있는 의류 삭제는 기존 저장소 보호를 유지한다. 사진 삭제 예약 → 보호 기간 경과 → 정리 → 의류 삭제 순서다. 사진 없는 의류는 기존 CRUD대로 삭제할 수 있다.
- 자동 정리 worker/스케줄러는 구현하지 않았다. 기존 정책을 완화하거나 슬롯을 강제로 초기화하지 않는다.

## 세션 및 캐시

사진 바이트 캐시는 저장소 인스턴스별 최대 12개이며 디스크/IndexedDB에는 서버 사진을 저장하지 않는다. 인증 다운로드는 no-store/no-cache 요청과 업로드 cacheControl=0을 사용한다. 각 비동기 작업 전후 사용자·세션을 확인한다. 로그아웃·계정 변경 시 기존 중첩 Navigator와 저장소를 폐기하고 해당 서버 `MemoryImage` 캐시 키와 편집 미리보기만 제거한다. 전체 Flutter ImageCache나 기존 로컬 사진 캐시를 일괄 삭제하지 않는다. 늦게 도착한 다운로드가 다음 계정 화면에 표시되지 않는 위젯 테스트도 포함했다.

## 이번 작업 파일

| 구분 | 추가/수정 파일 |
| --- | --- |
| 서버 기능 추가 | `supabase/functions/garment-photo-operations/{core,adapter,index}.ts` |
| Flutter 저장소 추가 | `lib/services/server_photo_repository.dart`, `supabase_photo_wardrobe_repository.dart` |
| Flutter 연결/정책 | `lib/main.dart`, `services/revisioned_wardrobe_repository.dart` 설명, `services/supabase_wardrobe_repository.dart` 삭제 안내, `services/garment_photo_service.dart` 결과 MIME 필드 |
| UI | `screens/garment_editor_screen.dart`, `garment_detail_screen.dart`, `wardrobe_screen.dart`, `server_wardrobe_screen.dart`, `widgets/garment_photo.dart`, 새 `widgets/server_photo_actions.dart` |
| 패키지 | `pubspec.yaml`, `pubspec.lock`: 기존 전이 의존성 crypto 3.0.8을 직접 명시 |
| 테스트 | 새 `test/server_photo_test.dart`, `tool/server_photo_contract_test.dart`, `supabase/tests/photo_operations.test.ts`, `scripts/photo_browser_test.mjs` |
| 테스트 도구 | `scripts/browser_test_driver.mjs` 파일 선택 지원, `scripts/wardrobe_browser_test.mjs` 사진 선택 사항/새 빌드 경로 지원 |
| 로컬 실행 | 새 `supabase/local/photo-flow-{sync,serve,http-test,report}.mjs` |
| 문서 | 이 문서, `photo-upload-results-20261102.json`, `README.md` 최신 안내 |

이전 인증/CRUD 단계의 미커밋 변경 사항은 유지했다. Git 전체 상태가 이번 사진 작업의 파일만을 뜻하지 않는다.

## 검증 결과

| 검증 | 결과 |
| --- | --- |
| `flutter analyze` | 통과, No issues found |
| `scripts/test.ps1` → `flutter test` | 82 통과 / 0 실패 — 기존 75 + 사진 7 |
| `flutter build web` 기본 모드 | 성공 |
| 사진 개발 설정 웹 빌드 | 성공, `build/web_photos` |
| 새 Edge operations 단위 계약 | 15 통과 / 0 실패 |
| 기존 worker 단위 계약 회귀 | 24 통과 / 0 실패 |
| 실제 HTTP 사진 업로드/원본 worker/Storage | 16 통과 / 0 실패 |
| 정리 완료 후 의류 삭제 / 비로그인 사진 다운로드 차단 보충 검증 | 1 / 2 통과, 모두 0 실패 |
| 실제 Dart 사진 저장소 ↔ 로컬 Supabase | 9 통과 / 0 실패 |
| 실제 Dart 메타데이터 CRUD/RLS 회귀 | 19 통과 / 0 실패 |
| 실제 Edge 사진 UI | 16 통과 / 0 실패 |
| 실제 Edge 기존 CRUD UI | 19 통과 / 0 실패 |
| 기존 IndexedDB 프로브 | 독립 Chrome 프로필/합성 데이터로 기존 형식 비파괴 읽기·사진 CRUD·두 번 새로고침 통과 |

HTTP/SDK는 JPG·PNG·WebP의 실제 ready 승인, 다른 사용자/비인증 차단, 직접 ready 설정 거부, 해시/비이미지/크기/픽셀 초과 거부, 이전 사진 보호, 중복 요청·동시 요청, 유실 응답 재시도 및 정리를 검사했다. Edge UI는 실제 파일 선택 이벤트·미리보기·업로드·교체·실패 보존·새로고침·A/B 전환·재로그인·사진 삭제 예약·의류 삭제 보호를 검사했다. 360px 모바일 뷰포트의 가로 오버플로와 PC 화면을 확인했고 기존 3개 테마/입력 UX는 Flutter 회귀에 포함된다.

권한/검증 실패가 예상되는 항목은 **거부를 확인한 통과 테스트**다. 초기 테스트의 OPTIONS 응답 예상(204였으나 로컬 gateway가 200 반환)과 Edge 접근성 카드 선택/화면 밖 fixture 검색 오류는 수정 후 통과했다. 일반 사진 카드의 버튼 의미도 보완했다. 최종 정적 분석에서 발견한 braces 스타일 경고는 수정했다.

기존 역사적 29개 RLS/33개 Storage 전체 runner는 이번 단계에서 재실행하지 않았다. 해당 도구는 새 계정/제어 버킷 정책 생성 등을 요구한다. 이번에는 정책을 변경하지 않고 현재 Dart CRUD/RLS 19개와 사진 HTTP/Storage 16개, 원본 worker 계약 24개로 회귀를 검증했다. 이전 실행 결과를 이번 실행인 것처럼 합산하지 않았다.

## 로컬 실행 및 Edge 수동 확인

Supabase/Docker가 실행 중이고 기존 원본 worker가 로컬 폴더에 준비된 상태에서 프로젝트 루트에서 실행한다. sync 도구는 로컬 API/DB·비연결 상태와 원본 worker 일치를 확인하고 **새 함수만** 복사한다. 기존 함수를 변경하거나 SQL을 적용하지 않는다.

```powershell
Set-Location <PROJECT_ROOT>
node supabase/local/photo-flow-sync.mjs
node supabase/local/photo-flow-serve.mjs
```

위 터미널을 유지하고 다른 터미널에서 Flutter를 완전히 재시작한다. 기존 main의 저장소 생성 변경은 hot reload만으로 반영되지 않을 수 있다. Edge 실행 시 Flutter 디바이스 이름은 `edge`이다.

이번 검증의 로컬 함수 serve 프로세스는 실행 상태로 남겼다. 이미 로컬 함수가 동작 중이면 serve를 중복 실행하지 않는다.

```powershell
flutter run -d edge --web-hostname=localhost --web-port=8081 --dart-define-from-file=config/supabase.crud.local.json
```

설정 파일은 기존 로컬 API `http://127.0.0.1:54321`, publishable key, `MY_CLOSET_SUPABASE_ENABLED=true` 및 `MY_CLOSET_SERVER_WARDROBE_ENABLED=true`를 사용한다. 기기별 파일은 Git 제외 상태로 유지한다. service_role/secret key를 넣지 않는다. `localhost:8080` 실사용 창의 저장소를 지우거나 프로필을 테스트에 재사용하지 않는다. 더 강한 분리는 새 Edge 프로필을 사용한다.

1. 마이페이지 → 로그인 → **서버 개발 옷장**으로 이동한다. 기본 ‘내 옷장’과 서버 배너가 구분되는지 확인한다.
2. 합성 계정으로 새 의류에 합성 JPG/PNG/WebP를 선택하고 미리보기 → 저장을 진행한다. 예약/전송/서버 검증 단계 후 카드가 표시되는지 확인한다.
3. 상세 화면의 ‘서버에서 검증된 사진이에요’를 확인하고 브라우저 새로고침/로그아웃·재로그인을 수행한다.
4. 다른 합성 이미지로 한 번 교체한다. 다시 교체하면 이전 사진 보호 안내가 나오며 현재 사진이 유지되는 것이 정상이다.
5. 업로드 실패 시 의류 정보는 이미 저장될 수 있다. 같은 화면에서 재시도하거나 상세의 남은 업로드 취소/검증 재시도를 사용한다. 취소만으로 활성 사진을 지우지 않는다.
6. 다른 계정으로 전환하면 이전 계정 카드·편집 화면·사진이 남지 않아야 한다.
7. 사진 삭제는 예약으로 처리된다. 정리 가능 시각이 지난 뒤 정리하고 의류를 삭제한다. 테스트를 위해 기존 행이나 시간을 직접 수정하지 않는다.

자동 테스트는 각 실행의 새 build 폴더를 사용한다. 키·JWT·합성 비밀번호가 포함된 `private-context.json`을 출력/공유/커밋하지 않는다. 동일 HTTP 실행 폴더의 Edge 테스트는 마지막에 새 합성 사진의 삭제를 예약하므로 재실행할 때는 새 HTTP fixture 실행을 준비한다.

```powershell
node --experimental-strip-types --test supabase/tests/photo_operations.test.ts supabase/tests/photo_worker.test.ts
.\scripts\test.ps1
flutter analyze
flutter build web
flutter build web --dart-define-from-file=config/supabase.crud.local.json --output=build/web_photos

# 아래 명령이 출력하는 새 폴더 경로만 사용한다.
node supabase/local/photo-flow-http-test.mjs build/supabase-wardrobe-crud/crud-1793596184467/private-fixtures.json
.\scripts\test.ps1 tool/server_photo_contract_test.dart --dart-define=MY_CLOSET_PHOTO_FIXTURES=<PROJECT_ROOT>/build/supabase-photo-flow/<새 폴더>/private-context.json
$env:CHROME_EXECUTABLE=Join-Path ${env:ProgramFiles(x86)} 'Microsoft/Edge/Application/msedge.exe'
node scripts/photo_browser_test.mjs build/supabase-photo-flow/<새 폴더>
```

## 남은 제약과 클라우드 적용 전 작업

- 25시간을 실제로 기다리지 않았다. 만료 후 정리 HTTP 테스트는 **이번에 만든 합성 행 하나만** service_role로 만료 시각을 조정한 정책 시계 시뮬레이션이다. 실제 사용자 JWT Storage 삭제와 CAS는 실행했다.
- 물리 모바일 기기·Safari·스크린리더, 오랜 시간 대기한 자연 토큰 만료, 대량 업로드/부하/장애 테스트는 미검증이다.
- 자동 고아 정리/보존 기간 작업, 사용자별 용량·빈도 제한과 운영 관측은 추가 구현이 필요하다. 최대 파일 제한만으로 계정별 저장 남용을 제한하지 않는다.
- 로컬 gateway는 OPTIONS를 광범위한 CORS 헤더로 응답했다. 실제 POST는 localhost:8081 origin 검사와 Auth 소유권 검증을 통과해야 한다. CORS를 권한 통제로 취급하지 않는다.
- 서버 검증과 DB 변경 사이의 관리자가 직접 파일을 조작하는 상황은 일반 사용자 RLS 보호와 별개의 신뢰 경계다. Cloud에서는 최소 서비스 키 권한/보관, 함수 인증 설정, URL·origin 허용 목록, worker 리소스/업로드 제한을 다시 검토해야 한다.
- 비공개 다운로드와 캐시 만료는 [Supabase 인증 다운로드 문서](https://supabase.com/docs/guides/storage/serving/downloads) 및 [로그아웃 후 브라우저 캐시 주의사항](https://supabase.com/kb/troubleshooting/storage-private-bucket-files-still-accessible-after-remove-access-or-logout)을 참고했다. JWT는 [공식 함수 인증 문서](https://supabase.com/docs/guides/functions/auth)의 서버 검증 경계를 따른다. 이번 구현은 설치된 CLI/원본 worker 인증을 유지했으며 새 SDK로 교체하지 않았다.
- 서버 사진의 기본 IndexedDB 옷장 통합, 실제 옷 이전, 클라우드 배포는 이번 범위가 아니다.
