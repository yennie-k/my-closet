# SQL 보완 리뷰 — 2026-10-27

상태: **초안 수정·오프라인 구문 검사만 수행. 서버 SQL/보안 테스트 미실행.**

이번 문서와 수정된 SQL이 초판 설계안의 사진 상태·서버 권한·업로드/정리 절차를 대체합니다. 기존 모델 22키, 서버 UUID/local_id 분리, 사용자별 RLS, 비공개 경로, 로컬 원본 보존은 유지합니다. Flutter/IndexedDB는 변경하지 않습니다.

## 1. 사진 신뢰 상태 분리

| 항목 | 기록 주체 | 의미 |
| --- | --- | --- |
| `upload_state=reserved` | 서버 예약 endpoint | 소유권·한도 검사 후 **하나의** 경로와 예상 크기·만료 시각을 배정 |
| `upload_state=client_confirmed` | 사용자 JWT, 조건부 PATCH | 클라이언트가 업로드 응답을 확인했다고 주장. 실제 객체·해시 검증 완료가 아님 |
| `upload_state=checking` | 서버 검증 worker | 예약을 revision CAS로 점유하고 실제 객체를 검사 중 |
| `upload_state=failed` + `upload_error_code` | 서버 worker | 누락/해시·크기·MIME 불일치/손상/만료 등. 기존 정상 사진은 유지 |
| `photo_state=pending` | 기본값 / 서버 | 아직 검증된 활성 사진이 없음 |
| `photo_state=ready`, `photo_verified_at` | **서버만** | 그 시각에 서버가 실제 객체를 내려받아 검증한 사실을 신뢰 주체가 기록한 것 |

authenticated에는 photo_state/photo_path/photo_sha256/photo_size_bytes/photo_verified_at/사진 MIME·크기의 UPDATE 권한을 주지 않습니다. 예약 컬럼과 정리 컬럼도 서버 전용입니다. 최초 INSERT에서 모델의 image MIME·픽셀 수는 임시 입력값일 뿐이며, 그 행은 pending으로만 생성됩니다. INSERT로 ready를 주장하는 것도 허용되지 않습니다.

클라이언트는 자기 행의 `reserved → client_confirmed` 전이만 할 수 있습니다. lease가 만료됐거나 예약이 없으면 트리거가 거부합니다. 사진 관련 보호 필드의 직접 변경은 컬럼 GRANT와 트리거가 이중 차단합니다.

서버의 최초 활성화/사진 교체에도 트리거를 적용했습니다. 기존 checking 슬롯과 정확히 같은 경로·예상 크기를 소비하고 새 검증 시각을 기록해야 하며, 기존 활성 사진을 교체할 때는 해당 경로를 최소 24시간 유예의 retired 슬롯으로 넘겨야 합니다. 이 상태 제약도 실제 S3 바이트를 검사하는 알고리즘을 대체하지는 않습니다.

### 서버가 ready로 전환하기 전 수행할 일

1. Edge Function 입구에서 실제 사용자 JWT를 검증하고, 요청된 서버 의류 ID의 user_id가 그 사용자와 일치하는지 확인합니다. body.user_id는 신뢰하지 않습니다.
2. DB에 기록된 upload_path/크기/lease와 예상 revision을 읽습니다. 요청 body의 임의 경로를 다운로드하지 않습니다. checking 전이는 id+user_id+revision+upload_path 조건으로 CAS합니다.
3. Storage API로 **그 객체의 원시 바이트**를 다운로드합니다. 일반 metadata HEAD나 ETag만으로 성공 판정하지 않습니다.
4. SHA-256을 계산하여 예약 경로의 파일명 해시와 비교합니다. 실제 byte 길이를 upload_size_bytes 및 2MiB 한도와 비교합니다. 실제 디코더로 형식·손상·픽셀 수를 확인하고 예상 MIME/로컬 이미지 정보와의 차이를 검사합니다.
5. 객체 버전/갱신 여부도 전후 확인합니다. 원본이 바뀌었거나 불일치면 실패로 남기고 ready로 바꾸지 않습니다.
6. 같은 upload_path와 checking 상태, 사용자 ID, 예상 revision으로 조건부 UPDATE합니다. 측정된 실제 값만 photo_sha256/photo_size_bytes/image_*에 쓰고 photo_verified_at과 ready를 함께 기록합니다. 후보 슬롯은 함께 비우고, 기존 활성 사진이 있으면 retired 슬롯으로 넘깁니다.

**검증 worker 자체는 아직 구현·실행하지 않았습니다.** SQL은 Storage 바이트를 읽지 못하며, 이 흐름을 수행한 service_role의 진술을 신뢰합니다. 서비스 키가 탈취되거나 worker가 거짓 값을 쓰면 SQL만으로 막을 수 없습니다. ready는 검증 시점의 스냅샷이며 파일이 영원히 존재한다는 보장은 아닙니다. AI 처리 등 중요한 사용 전에는 서버가 다시 확인해야 합니다.

사진 교체 중에도 기존 ready 활성 사진은 유지합니다. 후보 상태가 실패해도 기존 활성 경로를 지우거나 ready를 내려버리지 않습니다. 신규 사진이 검증된 후에만 활성 경로를 교체합니다. 모든 과정에서 로컬 원본은 유지합니다.

## 2. revision만으로는 잠금이 아님: 두 모델 모두 CAS 필수

트리거의 revision 증가는 변경 감지용입니다. 클라이언트/서버 요청이 `WHERE revision = 읽었던 값`을 포함하지 않으면 일반 UPDATE는 여전히 마지막 쓰기로 덮어씁니다. 이번에는 Dart 코드를 바꾸지 않고 아래 계약을 이후 어댑터 구현의 필수 조건으로 둡니다.

```dart
// 설명용 예시. 실제 코드/패키지 연동은 아직 하지 않음.
final rows = await client.from('garments')
    .update(editableMetadataPatch) // id/user_id/local_id/사진 보호 필드/revision 제외
    .eq('id', envelope.serverId)
    .eq('user_id', authenticatedUserId)
    .eq('revision', envelope.revision)
    .select('id, revision, server_updated_at');

final settingsRows = await client.from('user_preferences')
    .update(editablePreferencesPatch) // user_id/서버 날짜/revision 제외
    .eq('user_id', authenticatedUserId)
    .eq('revision', settingsRevision)
    .select('user_id, revision, updated_at');
```

- 성공 1행: 반환된 revision으로 envelope를 갱신합니다. 사진 예약/검증도 같은 revision을 바꾸므로 이후 편집 전 최신 값을 가져옵니다.
- 성공 응답이나 0행: 자동 덮어쓰거나 최신 revision으로 무조건 재전송하지 않습니다. 자기 행을 **RLS가 적용된 사용자 클라이언트**로 재조회합니다.
  - 보이는 행의 revision이 달라짐: 동시 수정 충돌. 로컬 draft를 보존하고 “다른 곳에서 수정되었어요”와 최신값 비교/다시 편집/취소를 제공합니다.
  - 행이 보이는데 revision이 같음: UPDATE 정책/다른 조건/권한 설정 등으로 적용되지 않은 상태입니다. 단순 버전 충돌로 단정하지 않습니다.
  - 행이 보이지 않음: 삭제 또는 권한/세션으로 비가시 상태. 둘을 클라이언트가 확정할 수 없으므로 “찾을 수 없거나 접근할 수 없어요”로 안내합니다. 타 사용자 행 존재를 추측하지 않습니다.
- SQLSTATE `42501`: 실제 컬럼/테이블 권한 거부와 RLS WITH CHECK 오류 계열입니다. 0행 CAS와 분리하여 처리하고 입력은 보존합니다. 에러 코드만으로 내부 GRANT/RLS 중 어느 원인인지 확정하지 않습니다.
- HTTP 401/만료 JWT: 재인증 분기. 23514는 검증/상태 전이, 23505는 유일 키 중복 분기로 분리합니다. UPDATE `USING`으로 걸러진 경우는 권한 문제여도 0행일 수 있음을 유지합니다.
- 두 요청이 같은 revision을 보낸 실제 동시성 테스트도 필요합니다. 순차 stale-CAS SQL 테스트만으로 모든 경합을 검증했다고 주장하지 않습니다.
- 사진 예약/확인/검증, 삭제 요청에도 동일한 조건을 적용합니다. 무조건 upsert 또는 revision 조건 없는 재시도는 금지합니다. 서버 검증기는 CAS 실패 후 원래의 객체 검사 결과를 다른 새 후보에 적용하지 않습니다.

## 3. service_role 권한 보완

공개 브라우저 역할에 ready 권한을 주는 대신 신뢰 서버의 최소 **애플리케이션 테이블** 권한을 정의했습니다.

| 역할 | 허용 |
| --- | --- |
| authenticated | 본인 설정/의류 메타데이터 CRUD, 유효한 예약에 대한 완료 신호. 사진 상태/사실/예약 직접 수정 불가 |
| service_role | garments의 id/user_id/revision 및 사진·예약·정리 관련 컬럼 SELECT/UPDATE만 |
| service_role의 금지 | preferences 접근, garments INSERT/DELETE, name/notes 등 일반 정보 SELECT/UPDATE, revision 직접 수정 |
| anon/PUBLIC | 개인 테이블 권한 없음 |

service_role은 RLS를 우회하므로 이 권한은 특정 사용자로 자동 제한되지 않습니다. 서버 함수는 요청자의 JWT 및 소유자를 직접 검증하고 명시적 user_id 조건을 써야 합니다. service_role 클라이언트에서 select('*')는 사용하지 않고 필요한 컬럼만 조회합니다. 관리자에게 모든 CRUD를 주는 방식은 채택하지 않았습니다.

중요한 한계: Supabase의 관리형 service key는 이미 Storage 전반에서 강한 권한을 가집니다. 앱 테이블의 컬럼 GRANT를 줄였다고 키 자체가 garment-photos 한 버킷으로 한정되는 것은 아닙니다. 이번 SQL은 그 관리형 Storage GRANT를 변경하거나 넓히지 않습니다. 키는 서버 비밀 저장소에만 두고, 함수별 분리·감사·rate limit을 적용해야 합니다. 이후 더 좁은 권한이 필요하면 전용 DB 역할/감사 가능한 제한 RPC·프록시를 별도로 설계합니다. 이것도 현재 구현됐다고 주장하지 않습니다. [Edge Functions 인증·RLS/관리 클라이언트 구분](https://supabase.com/docs/guides/functions/auth)

일반 관리·사용자 지원 작업은 이 사진 worker 권한으로 하지 않습니다. 필요할 때 별도 최소 권한과 감사 기록을 검토합니다.

## 4. Storage 함수·operation 확인

공식 문서와 upstream SQL/라우트 소스를 읽어 다음 **정의 존재와 작업명**을 확인했습니다. 사용자 프로젝트의 배포 버전은 조회하지 않았으므로 실제 지원은 미검증입니다.

- `storage.operation()`은 transaction-local `storage.operation` 설정을 읽음: [공식 migration 0024](https://github.com/supabase/storage/blob/master/migrations/tenant/0024-operation-function.sql)
- `allow_only_operation(text)`, `allow_any_operation(text[])`는 `storage.` 접두사를 정규화하고 누락된 operation은 허용하지 않음: [공식 migration 0058](https://github.com/supabase/storage/blob/master/migrations/tenant/0058-operation-ergonomics.sql), [helper 문서](https://supabase.com/docs/guides/storage/schema/helper-functions)
- 일반 업로드 `storage.object.upload`, 인증 다운로드 `storage.object.get_authenticated`, 목록 `storage.object.list`/`list_v2`, 단건 삭제 `storage.object.delete`, 다건 삭제 `storage.object.delete_many`: [공식 작업명](https://github.com/supabase/storage/blob/master/src/http/routes/operations.ts)
- 단건/다건은 실제 별도 경로에 연결됨: [deleteObject](https://github.com/supabase/storage/blob/master/src/http/routes/object/deleteObject.ts), [deleteObjects](https://github.com/supabase/storage/blob/master/src/http/routes/object/deleteObjects.ts)

초안 02는 함수 존재와 관리형 RLS/권한을 먼저 확인합니다. SELECT allowlist에는 삭제/업로드 내부 조회도 포함하며 signed URL/덮어쓰기/이동은 계속 금지합니다. 대상 버전에서 operation 설정이 다르면 허용을 넓혀 우회하지 않고 실패 원인과 deployed 소스를 비교한 뒤 재검토합니다.

### 경로·누적 제한

업로드는 **본인 폴더 + 본인 의류 행 + 서버가 배정한 정확한 upload_path + reserved + 미만료 + 정리 대기 없음**을 모두 만족해야 합니다. 단지 의류 폴더가 존재한다는 이유로 임의 해시 파일을 계속 올릴 수 없습니다.

한 행은 active+candidate 또는 active+retired 슬롯만 가집니다. retired를 정리하기 전 다음 후보를 만들지 못하며, 기존 후보 경로를 다른 후보로 바로 치환할 수도 없습니다. 후보는 15분 이내 lease로 제한합니다. 이 제약은 **DB가 참조하는 슬롯 수**를 제한하는 것이지 물리 파일 총수를 완벽히 세는 한도는 아닙니다.

직접 사용자 DELETE는 active/candidate 및 유예 중 retired 경로를 보호합니다. 행 없는 본인 고아 객체는 조회·삭제할 수 있습니다. 다른 사용자 prefix는 계속 거부합니다. 다른 버킷은 각 restrictive guard의 `bucket_id <> 'garment-photos'` 분기를 통과하며 기존 정책을 따릅니다. managed schema GRANT·소유권·기존 정책을 DROP/변경하지 않습니다.

### 고아·재시도·정리 프로토콜

1. 예약 endpoint는 호출자/소유권/CAS, 기존 후보·retired 유무를 확인하고 계정별 용량·예약 빈도·의류 수 한도를 검사합니다. 유효한 같은 예약의 재시도는 같은 경로로 응답합니다. 이 endpoint와 계정 quota는 아직 미구현입니다.
2. 업로드 timeout/409는 같은 경로를 인증 다운로드하여 실제 해시·크기를 비교합니다. 일치하면 덮어쓰지 않고 다음 단계로 갑니다. checking 단계에는 재업로드를 허용하지 않습니다.
3. 신규 사진 검증 성공 후 active를 교체하면서 old active를 retired로 기록하고 24시간 등 정리 유예를 둡니다. 후보 슬롯은 함께 해제합니다.
4. 정리 worker는 active/candidate 재참조 여부, lease/진행 중 작업, 유예 시각을 **직전 재조회**하고 Storage API로 삭제합니다. 이미 없음도 재시도 가능한 결과로 처리하고 API 재확인 후 CAS로 retired/failed 후보 슬롯을 비웁니다. storage.objects를 SQL DELETE하지 않습니다.
5. 만료된 후보는 바로 슬롯만 비우지 않습니다. 지연 업로드·검증 job이 끝났는지 확인하고 grace period와 작업 잠금/heartbeat를 적용한 후 객체를 정리합니다. 늦게 도착한 파일은 주기적 prefix 목록/행 참조 대조로 찾아 다시 정리합니다.
6. 의류 삭제는 사용자 범위의 **DELETE CAS가 성공한 후** 캡처한 경로들을 durable cleanup manifest로 정리합니다. CAS 실패 시 사진을 지우지 않습니다. 행 삭제로 사진이 자동 삭제되지는 않습니다. 직접 API로 행만 삭제한 경우도 주기적 고아 정리가 필요합니다. service_role에는 앱 행 DELETE를 추가하지 않았습니다.
7. 정리 job에는 project_ref/user_id/garment_id/검증된 경로·세대·시각을 저장하고 실패 횟수·backoff·최종 오류를 감사합니다. 활성 경로가 바뀌면 오래된 job을 재평가합니다. 이 durable queue/worker도 아직 미구현입니다.

행을 지우고 새로 만드는 남용, 실패 worker, 만료 직전 시작된 늦은 업로드 때문에 물리 고아는 여전히 생길 수 있습니다. 프로젝트/계정 quota·rate limit·주기적 GC 없이는 물리 용량 상한을 보장할 수 없습니다. DB와 Storage는 분산 트랜잭션이 아니고, Storage 검사/삭제와 DB CAS 사이의 TOCTOU도 완전히 제거되지 않습니다. worker/GC 직렬화와 실경합 테스트가 배포 전 필수입니다. 어떤 정리도 IndexedDB 로컬 원본을 자동 삭제하지 않습니다.

## 5. 준비한 테스트와 현재 검증 범위

- `supabase/tests/01_security_contract.draft.sql`: staging opt-in + 실제로 존재하는 신선한 A/B Auth 사용자 필요. RLS, 컬럼 권한, 두 테이블 CAS/0행, 클라이언트 ready/예약 변조 거부, 서비스 최소 권한, 완료 신호와 ready 구분. 마지막 ROLLBACK.
- `supabase/tests/02_storage_contract.draft.sql`: 함수와 operation 정규화, 버킷·정책 카탈로그를 검사. Storage 파일을 만들거나 삭제하지 않음.
- `supabase/tests/storage_api_security.draft.mjs`: 명시적 staging opt-in, 고정 host, run marker, publishable key+A/B JWT, 준비된 예약/활성/고아 fixture가 있어야 실행 가능. 업로드·인증 다운로드·목록·단건·다건 삭제를 실제 HTTP로 확인하도록 준비. 서비스 키는 입력으로 받지 않음.
- SQL의 service ready 테스트는 **신뢰 경계 시뮬레이션**입니다. 실제 객체가 없어도 서비스가 상태를 기록할 수 있음을 숨기지 않으며, 실제 byte 검증 알고리즘이 동작했다는 증거가 아닙니다.

SQL 구문 검사는 pglast/libpg_query로 오프라인 파싱합니다. outer SQL과 PL/pgSQL 함수/DO 본문을 검사하지만 테이블·함수 존재, RLS 동작, role 속성, GRANT/PostgREST 호환, 실제 Storage operation 및 파일 무결성은 해석/검증하지 않습니다. 실제 실행 결과는 하나도 없습니다.

정적 결과는 [sql-review-static-report.json](sql-review-static-report.json)에 파일 해시와 함께 기록했습니다. 파서는 pglast 8.7 / 내장 PostgreSQL 18.6 parser이며 프로젝트의 실제 Postgres 버전을 확인한 것은 아닙니다. SQL 4개에서 outer statement 총 89개와 PL/pgSQL 본문 12개를 파싱했습니다. 별도 AST 검사에서 authenticated의 사진 보호 필드 쓰기 금지, service_role의 사진 컬럼만 GRANT, 테이블 UPDATE의 USING/WITH CHECK, Storage 관리 GRANT/스키마 변경 없음도 확인했습니다. HTTP 스크립트는 `node --check` 구문 검사만 수행했습니다.

## 6. 적용 전 release gate

1. 새 모델 필드/상태·서버 권한 변경 재검토. 이미 이전 SQL을 적용한 환경이 있다면 새 CREATE 초안을 재실행하지 말고 별도 ALTER migration을 설계.
2. staging에서 실제 Postgres 버전으로 두 migration과 SQL 테스트 수행. 실제 A/B/로그아웃 JWT로 동일 API 결과도 확인.
3. 예약·확인·다운로드 검증·ready CAS·정리 worker 구현과 해시/크기/MIME/손상·권한·동시성 테스트.
4. HTTP 테스트로 단건/다건 삭제를 별도로 확인하고, 다른 버킷의 기존 허용/거부 결과 및 ACL/정책 목록이 바뀌지 않았는지 비교.
5. 슬롯 해제/삭제/늦은 업로드 경합, 재시작·계정 변경, 계정 quota·비밀키 누출 방지 검증.
6. 사용자 설정·의류 모두 CAS 구현 및 충돌 UI 검증. 그 전까지 실제 앱 연동/운영 SQL 적용 보류.
