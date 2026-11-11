# 로컬 Supabase 디지털 옷장 CRUD 1단계 — 2026-11-02

기본 IndexedDB 옷장을 유지하면서 **별도 개발 플래그·경로에서만** 서버 의류 메타데이터 CRUD를 추가했다. 실제 클라우드 연결·배포, SQL/GRANT/RLS/Storage 정책/사진 worker 변경, IndexedDB 초기화, 기존 옷 자동 이전, Git commit/push는 하지 않았다.

## 시작 전 확인

- Git에는 앞선 인증 작업의 미커밋 변경과 새 파일이 남아 있었다. 이를 초기화하거나 되돌리지 않고 작업을 이어 갔다.
- `Garment` v2, `WardrobeRepository`, IndexedDB 구현, 등록·수정·상세 화면, 필터, Auth 서비스, SQL 초안과 로컬 Auth/worker 보고서를 읽었다.
- 기존 로컬 가드로 `<LOCAL_SUPABASE_DIR>`, Docker `desktop-linux`, CLI 2.122.0, API `127.0.0.1:54321`, DB `127.0.0.1:54322`, 원격 project-ref 없음 상태를 확인했다. `login`, `link`, `db push`, reset 명령을 사용하지 않았다.
- 작업 전 서버에는 의류 44건, 사용자 설정 2건, Storage 객체 35건/버킷 3개, Auth 사용자 13명이 있었다. 전 행의 ID/JSON digest를 ignored build 폴더에 기록해 보존 비교 기준으로 삼았다.

## 사진 없이 등록할 수 있는 이유와 제약

기존 SQL은 `photo_state=pending`, `upload_state=none`, 실제 사진 경로/해시/크기/검증 시각이 null인 신규 행을 허용한다. 실제 Storage 객체는 요구하지 않는다. 따라서 보안 정책을 완화하거나 합성 사진을 업로드할 필요가 없다.

다만 `Garment` 모델과 SQL의 `image_width`, `image_height`는 양수 필수이고 MIME도 필수다. **신규 메타데이터 전용 행은 JPEG/1×1을 스키마용 자리 값으로 사용**한다. 이는 실제 이미지의 형식·크기·검증 결과가 아니며 사진 상태는 계속 pending이다. UI에는 사진 대신 ‘사진 연결 전’ 안내를 표시하고 파일 선택·업로드·다운로드를 실행하지 않는다. 기존 사진이 있는 행의 MIME/해상도/사진 상태/예약은 변경하지 않는다.

사진·후보 예약·retired 경로가 연결된 의류는 이번 앱에서 삭제를 거절한다. 현재 SQL DELETE 자체는 Storage 정리 작업을 수행하지 않으므로, 행만 지워 고아 파일을 만드는 일을 피하기 위한 앱 제약이다. 정상 메타데이터 전용 의류의 삭제는 지원한다. 삭제 SQL 요청에도 사진 상태·null 경로·revision 조건을 함께 넣어 검사 후 사진 상태가 바뀌는 경쟁을 막는다. 기존 정책을 강화/완화한 것은 아니다.

## 저장소와 식별자 설계

- `WardrobeRepository`의 기존 인터페이스와 로컬 구현은 변경하지 않았다.
- `SupabaseWardrobeRepository`는 그 인터페이스를 구현하며, 선택적 `RevisionedWardrobeRepository` 기능으로 `refresh(original)`, `saveWithOriginal(value, original:)`, `deleteWithOriginal(original)`을 제공한다.
- 서버 UUID와 사용자/revision/사진 상태는 별도 `ServerGarmentRecord` 봉투로 관리한다. **도메인 `Garment.id`는 `local_id`**, `ServerGarmentRecord.serverId`는 서버 UUID다. 신규 UUID는 DB가 생성한다.
- 서버에서 반환한 원본 `Garment` 객체와 봉투를 Expando로 연결한다. 목록을 다시 불러오더라도 이미 열린 편집 화면의 원본 revision을 새 값으로 바꾸지 않는다. 전역 ‘마지막 revision’ 캐시를 수정 조건으로 쓰지 않는다.
- 저장 성공 시 서버가 반환한 새 객체/revision을 상세 화면으로 전달한다. 서버 ID·revision을 IndexedDB나 기존 의류 JSON에 추가하지 않는다.
- 모든 정상 조회에 user_id 조건을 넣으며, 최종 데이터 격리는 사용자 JWT와 기존 RLS가 담당한다. 의류 전체 목록은 200건 단위로 읽어 서버 기본 반환 상한에 따른 조용한 잘림을 피한다. 여러 페이지를 읽는 동안의 동시 추가/삭제에 대한 일관된 snapshot까지 제공하는 것은 아니다.
- `close()`는 해당 화면 저장소를 무효화하며 앱 공용 Auth 클라이언트를 종료하지 않는다.

## v2 필드 매핑

| Flutter | Supabase | 처리 |
| --- | --- | --- |
| id | local_id | 사용자별 유일 키, 서버 UUID와 분리 |
| version=2 | model_version=2 | 기존 모델 버전 유지 |
| name / category / subtype | name / category / subtype | enum 저장 이름 및 자유 입력 보존 |
| createdAt / updatedAt | created_at / updated_at | 최초 등록일 불변, 수정일은 도메인 값 |
| primaryColor / primaryColorHex | primary_color / primary_color_hex | 표준 HEX 연결; 이름 불변 시 기존 custom HEX 유지 |
| additionalColors / additionalColorDetails | additional_colors / additional_color_details | 복수 선택; 색상 이름 목록이 같으면 기존 JSON 원문 보존 |
| seasons | seasons | 복수 계절 enum 저장 이름 |
| thickness / thicknessLevel | thickness / thickness_level | nullable 및 1~5 일관성 유지 |
| styleTags | style_tags | 사용자 정의 문자열 포함 |
| material / materials | material / materials | 기존 단일 문자열과 복수 배열을 별도로 유지; 빈 배열도 그대로 |
| fit / notes | fit / notes | 자유 입력 및 줄바꿈 보존 |
| imageMimeType / imageWidth / imageHeight | image_mime_type / image_width / image_height | 조회·신규 행 자리 값만; 수정 payload에서 제외 |

`source_model_version`, `import_fingerprint`, 서버 생성/수정 시각, 사진 워크플로 필드는 봉투에 남겨 두고 일반 정보 수정 payload에 포함하지 않는다. `user_id`, 서버 ID, local_id, 등록일, revision 역시 UPDATE payload에 넣지 않는다. 기존 revision/server_updated_at 트리거를 사용하며, Flutter 모델의 updated_at을 서버 시각으로 대체하지 않는다.

## 충돌·재시도·오류

UPDATE는 `id=읽었던 서버 UUID AND user_id=현재 소유자 AND revision=읽었던 revision`에만 적용한다. DELETE도 동일한 CAS 조건을 사용한다. 반영된 행이 0개면 **같은 사용자 JWT**로 서버 ID를 재조회한다.

| 재조회 결과 | 안내 |
| --- | --- |
| 행이 보이고 revision이 바뀜 | 충돌, 덮어쓰기 없음; 입력 보관 후 닫기/새로고침 안내 |
| 행이 안 보임 | 삭제 또는 접근 불가 가능성; 둘을 확정적으로 구분하지 않음 |
| 같은 revision인데 반영 안 됨 | 권한 또는 사진 상태 제한 안내 |
| 재조회 자체가 네트워크/권한 오류 | 해당 오류를 구분하여 표시 |

RLS로 숨겨진 행과 실제 삭제 행을 완전히 구별하려고 관리자 키나 권한 우회 조회를 사용하지 않는다. 서버 SQLSTATE 42501은 권한, JWT 오류는 인증, 연결 실패/timeout은 네트워크, 저장 제약 오류는 입력 검증으로 구분한다. 알 수 없는 오류는 별도 일반 서버 오류로 표시하고 원본 예외·JWT·비밀번호를 화면/로그에 출력하지 않는다.

신규 폼은 열릴 때 생성한 local_id와 createdAt을 유지하고 같은 폼의 재시도에 재사용한다. 버튼은 저장 중 입력을 차단하며 저장 메서드도 재진입을 막는다. DB의 `(user_id, local_id)` 유일 제약이 병렬 등록을 한 행으로 제한한다. 중복 키 응답에서는 기존 행을 읽어 같은 입력이면 성공을 복구하고, 다른 입력이면 충돌로 거절한다. **merge upsert는 사용하지 않는다.** 네트워크 단절로 저장 결과가 불명확해도 같은 폼에서 재시도할 수 있다.

초안 ID는 메모리에만 있으므로 폼을 폐기하거나 새로고침하면 새 요청 ID가 생긴다. 여러 새 폼에서 의미상 같은 옷을 등록하는 것까지 중복 판별하지 않는다. UPDATE/DELETE 응답 유실의 재시도는 최초 revision을 유지하므로 이미 반영되었다면 충돌/삭제·접근 불가 안내가 나올 수 있다. timeout은 이미 서버에서 commit된 요청을 취소한다는 뜻이 아니다.

## UI와 로컬 데이터 분리

- **내 옷장 메뉴는 개발 모드에서도 계속 이 기기의 IndexedDB**를 사용한다. 인증했다고 로컬 저장소를 서버 저장소로 갈아 끼우지 않는다.
- `MY_CLOSET_SERVER_WARDROBE_ENABLED=true`를 기존 로컬 인증 설정과 함께 켜야 마이페이지의 **‘서버 개발 옷장 열기’** 버튼과 `/#/dev/server-wardrobe-crud` 경로가 생성된다. 기본값은 false다.
- 기존 읽기 전용 경로 `/#/dev/server-wardrobe`와 ‘서버 의류 조회 테스트’ 버튼은 별도로 유지했다. CRUD를 켜지 않은 기존 Auth 설정도 그대로 작동한다.
- CRUD 화면은 API 주소·개발용 서버·사진 업로드 없음·자동 이전 없음 배너로 구분한다. PC에는 옷장 복귀 메뉴를 제공하고 모바일은 반응형 화면/가로 스크롤 필터를 사용한다.
- 기존 목록·등록·상세 화면에 기본값 false인 `metadataOnly` 옵션을 추가하여 대분류→소분류, 이름 검색, 컬러 팔레트/사용자 입력, 소재/핏/두께 UI, 테마 3종을 재사용했다.
- 서버 상세 진입 때 다시 조회하며, 명시적 ‘서버 새로고침’과 오류 후 재시도를 제공한다. 등록·수정·삭제 후 목록/필터를 다시 읽는다.
- 서버 작업 공간의 **전체 중첩 Navigator**를 사용자 ID/auth generation으로 묶었다. 로그아웃·계정 변경·인증 오류가 생기면 목록뿐 아니라 열려 있는 상세·수정 폼/초안도 폐기한다. 저장소 역시 요청 전후 세션을 확인하고 이전 요청의 늦은 응답을 버린다.

기존 Chrome 8080 프로필은 열지 않았다. 실제 옷 3벌을 읽거나 이전/수정/삭제하는 명령을 실행하지 않았다. 테스트는 새 프로필의 8081과 합성 메타데이터/바이트로만 수행했다.

## 실행과 수동 확인

프로젝트 루트 PowerShell에서 기본 실행은 그대로다.

```powershell
flutter run -d chrome --web-port=8080
```

CRUD 개발 설정 `config/supabase.crud.local.json`은 이번 로컬 CLI의 publishable key만으로 생성했고 Git에서 제외했다. 기존 `config/supabase.local.json`은 변경하지 않았다. 다른 기기에서는 새 example 파일을 참고해 별도 설정 파일을 만들며 기존 파일을 덮어쓰지 않는다.

```powershell
flutter run -d chrome --web-hostname=localhost --web-port=8081 --dart-define-from-file=config/supabase.crud.local.json
```

API는 정확히 `http://127.0.0.1:54321`, 웹 origin은 localhost 또는 127.0.0.1의 8081만 허용한다. 클라우드 URL, 8080에서의 개발 연결, secret/service key 형식은 초기화 전에 거절한다. 두 개발 플래그가 함께 필요하다. 키는 브라우저에 공개되는 publishable key이므로 비밀키를 넣어서는 안 된다.

1. 8081 최초 사용이면 별도 온보딩을 마친다. 8080과 다른 origin이므로 실제 로컬 옷이 보이지 않는 것이 정상이다.
2. 마이페이지에서 로컬 계정 로그인 → ‘서버 개발 옷장 열기’를 누른다. 직접 테스트용 계정을 만들거나 검토용 합성 계정을 사용한다.
3. 옷 추가 → 이름/카테고리/원하는 선택 정보를 입력 → 저장한다. 사진은 선택하지 않는다.
4. 대분류/소분류/검색, 상세 수정, 새로고침, 삭제 취소/확인을 확인한다.
5. 두 탭에서 같은 의류를 수정하면 나중 저장에 충돌 안내가 나타난다. 자동 덮어쓰기는 하지 않는다.
6. 서버 화면 우측 로그아웃을 누르면 열려 있던 편집 화면도 사라진다. 다른 계정으로 로그인하면 그 계정 데이터만 표시한다.

현재 로컬 Auth는 이메일 확인 off다. Mailpit/확인 링크 흐름과 네이티브 플랫폼의 인증·로컬 API 주소는 앞선 인증 문서의 제약을 그대로 따른다.

## 최종 검증

[전체 검사 이름과 보존 비교 JSON](wardrobe-crud-results-20261102.json)을 함께 제공한다.

| 검사 | 통과 | 실패 | 실제 범위 |
| --- | ---: | ---: | --- |
| `flutter analyze` | 성공 | 0 이슈 | 전체 프로젝트 |
| `flutter test` (`scripts/test.ps1`) | 71 | 0 | 기존 61 + 신규 10; 세 테마/360·1280px 폼, 초안 ID 재사용, 열린 폼 로그아웃 제거, 이전 계정의 늦은 응답 폐기 |
| 실제 로컬 Dart 저장소 통합 | 19 | 0 | 실제 Auth/REST/RLS/DB; 합성 A/B |
| 실제 production Flutter Chrome CRUD | 19 | 0 | 8081 새 프로필, 등록/조회/수정/삭제·필터·새로고침·충돌·네트워크 복구·로그아웃/계정 전환·모바일 |
| 기존 IndexedDB 브라우저 회귀 | 성공 | 0 | 합성 probe DB의 v1 읽기 비변경, v2 사진/정보, 두 번 실제 reload, CRUD |
| 기본 웹 build | 성공 | 0 | CRUD/auth flag 없는 기본 앱 |
| CRUD 개발 웹 build | 성공 | 0 | 별도 설정으로 `build/web_crud` 생성 |

실제 저장소 검사는 A의 v2 전 필드 roundtrip, 수정/삭제, B의 A 행 SELECT/PATCH/DELETE 차단, anon CRUD 4종 차단, user_id 변조/사진 사실 필드 변경 차단, stale revision·진짜 병렬 UPDATE, 중복 INSERT 동시 요청·재시도, **실제 INSERT commit 후 응답 유실 주입** 복구를 포함했다. 연결 차단/권한 오류/지연 응답은 실제 SDK HTTP 계층에 주입한 검사와 실제 서버 요청을 구분했다. 사용하지 않은 새 로컬 fixture 행만 테스트 삭제 대상으로 삼았다.

브라우저에서는 새 합성 의류를 UI로 만들고 해당 행에만 다른 탭 변경을 흉내 낸 사용자 JWT PATCH를 실행했다. Chrome에서 REST 요청을 차단/복구해 오류 UI와 재조회도 확인했다. UI에서 최종 삭제한 행은 실제 API에서도 사라졌음을 확인했다. 보존용 합성 IndexedDB 메타데이터/바이트/테마는 전체 흐름 전후 같았다. 기존 8080의 실제 데이터와 실제 Storage 파일 바이트를 열어 비교한 것은 아니다.

초기 통합 검사 1건은 주입용 403 응답의 `request` 메타데이터가 빠져 SDK의 오류 parsing이 실패했다. 주입 응답을 보완한 뒤 19건을 재실행해 통과했다. Chrome 하네스에서도 메뉴/칩의 접근성 역할, 입력 포커스/힌트 소실, 같은 URL 새로고침 대기 문제를 수정하고 전체 19건을 다시 실행했다. 초기 실패를 통과로 세지 않았다.

## 재현용 명령

```powershell
# 새 합성 A/B 생성 + 작업 전 보존 기준 기록; 기존 DB reset 없음
node supabase/local/wardrobe-crud-prepare.mjs

# prepare가 출력한 새 실행 폴더를 사용한다. 아래 run-id는 예시 자리 표시다.
.\scripts\test.ps1 tool/server_wardrobe_contract_test.dart --dart-define=MY_CLOSET_CRUD_FIXTURES=build/supabase-wardrobe-crud/crud-<run-id>/private-fixtures.json
flutter build web --output build/web_crud --no-web-resources-cdn --dart-define-from-file=config/supabase.crud.local.json
node scripts/wardrobe_browser_test.mjs build/supabase-wardrobe-crud/crud-<run-id>

.\scripts\test.ps1
.\scripts\browser_storage_test.ps1
flutter analyze
flutter build web --no-web-resources-cdn
```

재현 스크립트는 기존 8081 서버가 사용 중이면 종료하며 임의로 다른 서버를 죽이지 않는다. 검사 종료 시 자신이 만든 headless Chrome과 테스트용 HTTP 서버만 종료한다. 비밀번호/토큰은 ignored build의 private fixture 또는 프로세스 메모리에만 있으며 소스·콘솔·결과 보고서에 포함하지 않는다. 테스트 프로필/합성 행은 자동 일괄 정리하지 않는다. 이전 실패 실행의 fixture도 검토용으로 남아 있을 수 있다.

## 보존 확인과 변경 파일

최종 결과 JSON의 before/after 수치는 **기존 행 전체의 digest 동일성**과 별도로 기록했다. 기존 서버 의류 44건, 설정 2건, Storage 객체 35건/버킷 3개, 기존 Auth 사용자 13명은 변경되지 않았다. 새 합성 사용자 2명과 검사 후 남은 합성 의류만 늘었다. 파일 해시 비교에서도 `garment.dart`, 기존 저장소 인터페이스/IndexedDB/설정 서비스, DB/Storage SQL 초안 및 worker 진입 파일이 동일했다. 다른 worker/정책 파일도 수정하지 않았다.

| 추가 파일 | 역할 |
| --- | --- |
| `lib/models/server_garment_record.dart` | 서버 봉투/전체 필드 매핑 |
| `lib/services/revisioned_wardrobe_repository.dart` | 선택적 원본 revision 저장소 기능 |
| `lib/services/supabase_wardrobe_repository.dart` | JWT/RLS CRUD·CAS·멱등 등록·오류 분류 |
| `lib/screens/server_wardrobe_screen.dart` | 개발 전용 인증 경계·중첩 navigation |
| `config/supabase.crud.local.example.json` | 별도 CRUD 설정 예시 |
| `test/server_wardrobe_test.dart` | 단위/위젯 10건 |
| `tool/server_wardrobe_contract_test.dart` | opt-in 실제 저장소 통합 19건 |
| `scripts/browser_test_driver.mjs`, `scripts/wardrobe_browser_test.mjs` | 격리 Chrome production UI 검사 |
| `supabase/local/wardrobe-crud-prepare.mjs`, `wardrobe-crud-report.mjs` | 합성 계정/기준 기록·읽기 전용 보존 비교 |
| 이 문서와 결과 JSON | 실행/제약/검증 근거 |

수정 파일은 `lib/main.dart`, `app.dart`, `config/supabase_config.dart`, `screens/app_shell.dart`, `profile_screen.dart`, `widgets/auth_account_card.dart`의 선택적 개발 연결, `wardrobe_screen.dart`, `garment_editor_screen.dart`, `garment_detail_screen.dart`, `widgets/garment_photo.dart`의 재사용 옵션/새로고침/원본 전달, `.gitignore`, README, pubspec/lock이다. http 1.6.0은 이미 SDK가 사용하던 버전을 직접 의존성으로 선언했으며 새 상태관리 패키지는 넣지 않았다.

## 남은 위험과 사진 연동 전 작업

- 실제 클라우드, Android/iOS/네이티브 Windows, 자연 만료까지 장시간 기다리는 인증 시험은 미검증이다. 기존 SQL/Storage 29·33 및 worker suite를 이번 Flutter 변경에서 재실행했다고 주장하지 않는다.
- 실제 옷 3벌 수동 이전, 서버 사진 다운로드/업로드/교체, 설정 동기화는 없다. 기본 로컬 화면에 서버 결과를 섞지 않는다.
- 타임아웃·응답 유실에는 서버 commit 가능성이 있다. 저장 초안과 원본 revision을 보존하고, 충돌 시 사용자가 확인해야 한다. 브라우저 reload 뒤 신규 초안의 영구 멱등 키 보존은 다음 설계 대상이다.
- 사진 연동 전에는 예약 발급 API·현재 세션/소유권 검증·만료/크기/해시/버킷·경로 확인·client_confirmed→기존 검증 worker 호출·검증 완료 후 재조회·교체/retired 정리를 연결해야 한다. 클라이언트는 ready 또는 실제 검증 결과를 직접 설정하면 안 된다.
- 사진 있는 의류의 삭제에는 DB 행과 Storage의 비원자적 처리, 재시도, 삭제 대기/tombstone, 고아 파일 정리와 실패 복구를 먼저 설계해야 한다. 그 전까지 해당 삭제를 앱에서 막는다.
- JWT 로그아웃은 현재 클라이언트 세션을 지우지만 이미 전송된 쓰기를 취소하지 않으며, 발급된 access JWT의 즉시 전역 폐기 기능을 의미하지 않는다.

API 사용 근거: [공식 Dart 필터](https://supabase.com/docs/reference/dart/using-filters), [upsert의 병합 동작](https://supabase.com/docs/reference/dart/upsert), [PostgreSQL INSERT/유일 충돌](https://www.postgresql.org/docs/current/sql-insert.html). 병합 덮어쓰기를 피하려고 INSERT와 유일 충돌 복구, 명시적 revision 조건을 사용했다.
