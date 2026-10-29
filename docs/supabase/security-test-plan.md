# Supabase 보안·이전 검증 계획 — 미실행

이 문서는 테스트 **계획**입니다. Supabase DB/SQL/Auth/Storage에 접속하거나 실행한 결과가 아닙니다. 검토 대상은 [설계안](design-draft.md)과 `supabase/drafts`의 SQL 2개입니다.

**최신 보완:** [SQL 리뷰](sql-review-20261027.md)와 `supabase/tests`의 SQL/HTTP 테스트를 함께 사용합니다. 업로드 예약은 이제 서버 전용 단일 슬롯이며, client_confirmed와 ready를 구분합니다. service_role은 사진 컬럼만 접근하고 설정/일반 의류 관리 권한은 없습니다.

## 1. 승인 후 테스트 환경

- 운영 데이터가 없는 staging/local Supabase에서 먼저 적용합니다. 운영 프로젝트 ref와 혼동하지 않도록 실행 대상과 리전을 기록합니다.
- 이메일 확인이 완료된 사용자 A/B, 로그아웃 요청, 가능하면 Supabase anonymous Auth 사용자 C를 준비합니다. 사용자별 JWT를 구분하고 토큰/키를 로그에 남기지 않습니다.
- HTTP/SDK 테스트는 publishable key와 해당 사용자 access token을 사용합니다. SQL Editor의 postgres나 service_role로 성공한 결과를 RLS 검증으로 간주하지 않습니다.
- 원본 테스트 의류 3벌: 상의/니트, 하의/사용자 정의 종류, 아우터/빈 subtype. 각 사진을 서로 다른 실제 JPEG/PNG/WebP로 만들고 JSON·원시 바이트 SHA-256·ID·날짜를 사전 기록합니다.
- v1 원본과 v2 원본, 빈 소재 목록, 혼방 문자열, 표준/사용자 정의 색상, 5단계 두께, 레거시 핏을 추가 fixture로 준비합니다.
- 모든 데이터와 버킷은 테스트 전용입니다. 기존 사용자 IndexedDB를 지우거나 덮어쓰는 setup/teardown을 작성하지 않습니다.

## 2. 적용 전 정적·환경 검사

1. 모델 저장 키 22개와 설정 키 5개가 설계/DTO에 빠짐없이 매핑되는지 비교합니다.
2. `public`이 Exposed schemas에 있는지, 자동 테이블 노출 OFF·자동 RLS ON이 실제 설정과 일치하는지 확인합니다. Auth 스키마를 노출하지 않습니다.
3. 동일한 테이블/트리거/policy/버킷이 이미 있으면 실행을 멈추고 차이를 검토합니다. 충돌을 피하려고 DROP/IF NOT EXISTS로 덮지 않습니다.
4. migration 소유자가 FK/트리거/RLS/정책 생성 권한을 갖는지 확인합니다. SQL 01은 새 테이블과 권한을 한 트랜잭션으로 생성합니다.
5. 버킷은 Dashboard/Storage API에서 private, 2MiB, JPEG/PNG/WebP로 만들고 확인합니다. Storage 객체를 SQL DML로 만들거나 삭제하지 않습니다.
6. SQL 02의 helper 함수 존재, 관리 Storage RLS/GRANT, operation label 지원을 확인합니다. 사전 조건이 다르면 staging에서도 먼저 설계를 수정합니다.
7. 초안은 승인 전에는 `supabase/migrations`로 복사하지 않습니다. 현재 단계에서 실행할 명령은 없습니다.

## 3. 테이블 GRANT/RLS 검증

두 테이블 각각에 대해 아래를 HTTP/SDK로 반복합니다. UPDATE/DELETE가 0행을 반환할 수 있으므로 HTTP 상태만 보지 않고 실제 A/B의 데이터와 영향 행 수를 확인합니다.

| ID | 시도 | 기대 결과 |
| --- | --- | --- |
| D01 | publishable key만 사용해 SELECT/INSERT/UPDATE/DELETE | 권한 거부, 데이터 노출/변경 없음 |
| D02 | 만료·변조된 JWT | 인증 거부, anonymous fallback으로 개인 데이터 접근 불가 |
| D03 | A가 자기 행 SELECT/INSERT | 성공. 기본 user_id=auth.uid()와 명시적 A user_id 모두 확인 |
| D04 | A가 B 행 SELECT 및 user_id 필터 조작 | B 행이 반환되지 않음 |
| D05 | A가 user_id=B로 INSERT | WITH CHECK가 거부 |
| D06 | A가 자기 행의 수정 가능 필드만 UPDATE | 성공, revision 1 증가. garments.updated_at은 입력값 보존 |
| D07 | A가 B 행 UPDATE/DELETE | 0행 또는 거부, B 데이터 불변 |
| D08 | A가 자기 행 user_id를 B로 PATCH | 컬럼 권한 거부. USING/WITH CHECK도 소유권 이동을 허용하지 않음 |
| D09 | 서버 id/local_id/created_at/import_fingerprint/source_model_version 변경 | 허용되지 않은 컬럼 UPDATE 거부 |
| D10 | revision/server_created_at/server_updated_at 또는 prefs 서버 날짜를 INSERT/PATCH | 컬럼 권한 거부 |
| D11 | A의 자기 행 DELETE | 성공. 다른 사용자 행 불변. 사진은 별도 Storage API 정리 대상 |
| D12 | Auth anonymous C의 CRUD | 거부. role=authenticated만으로 허용되지 않음 |
| D13 | user_metadata에 user_id/role 등 권한처럼 보이는 값 설정 | 소유권/권한에 영향 없음 |
| D14 | settings.styles=[]와 onboarding_complete=true | CHECK 거부. 완료 전 false/빈 목록은 허용 |
| D15 | 잘못된 category/season/thickness 쌍, level=0/6 | CHECK 거부, 기존 행 불변 |
| D16 | 사용자 정의 subtype/색상/태그/혼방/핏 저장 | 손실 없이 성공. HEX=null과 materials=[]도 확인 |
| D17 | 올바른 이름·값의 v2 전체 DTO INSERT | 누락 컬럼 없이 성공; 서버에서 v2 JSON 재구성 후 비교 |
| D18 | 예상 revision이 같은 두 기기에서 동시 PATCH | 한쪽만 변경 성공, 다른 쪽은 0행 충돌. 무조건 재전송 금지 |
| D19 | 100개 이상 가짜 계정/row 요청, 긴 값 | 행 분리 유지. 비용/남용 방지는 RLS 외 rate limit·quota 단계로 별도 검토 |
| D20 | private 트리거 함수 RPC·직접 호출, TRUNCATE/REFERENCES/TRIGGER 권한 | 앱 역할에서 불가. trigger를 거친 정상 UPDATE만 성공 |

DB 관리자가 `pg_policies`, `pg_class.relrowsecurity/relforcerowsecurity`, `information_schema.column_privileges`, `has_column_privilege` 등으로 실제 ACL을 확인합니다. 컬럼 INSERT/UPDATE를 사용하므로 table-level has_table_privilege만으로 모든 접근 가능 여부를 판정하지 않습니다.

추가 확인: anon/PUBLIC에 개인 테이블 권한이 없는지, authenticated에 사진 검증/예약 및 table-wide INSERT/UPDATE/TRUNCATE 권한이 없는지, 함수에 PUBLIC EXECUTE가 없는지 확인합니다. service_role은 사진 worker용 컬럼 SELECT/UPDATE만 있어야 하며 preferences·일반 정보·INSERT/DELETE는 거부되어야 합니다.

## 4. Storage RLS/operation 검증

대상 경로는 `<A UUID>/<A의 서버 의류 UUID>/<sha256>.확장자`이며 테스트 파일의 실제 내용·MIME을 일치시킵니다.

| ID | 시도 | 기대 결과 |
| --- | --- | --- |
| S01 | 버킷 public 상태·크기·MIME 설정 확인 | private, 2,097,152 byte, JPEG/PNG/WebP만 |
| S02 | A가 서버 배정 upload_path에 reserved/미만료 상태로 uploadBinary(upsert:false) | INSERT 성공. 본인 의류 폴더 안이라도 배정되지 않은 경로는 거부 |
| S03 | B의 사용자 폴더, B 서버 의류 ID, 존재하지 않는 의류 ID로 업로드 | 거부 |
| S04 | 사용자 접두사 생략/다른 폴더 깊이/../이상한 확장자/비정상 해시 경로 | 거부 |
| S05 | A가 본인 파일 download/list/info | 사용자 JWT에서만 성공. 배포된 operation helper의 실제 label도 확인 |
| S06 | B의 파일 download/list/info, 상위 prefix로 전체 목록 요청 | A 폴더 밖 내용 노출 없음 |
| S07 | 로그아웃·publishable key만·만료 JWT·anonymous C의 파일 조회 | 접근 불가. 403/404 등 구체 상태보다 파일/내용 미노출을 확인 |
| S08 | public URL로 같은 파일 조회 | 다운로드 불가 |
| S09 | signed download URL·다중 sign·signed upload URL 발급 | operation guard로 거부. helper가 없으면 SQL 사전 조건에서 중단 |
| S10 | 동일 파일 Storage upsert:true, UPDATE, move | 거부. 새 해시 경로 업로드로 교체하는 정상 절차는 성공 |
| S11 | A의 미참조 고아 DELETE, B 파일 DELETE | 본인 고아만 삭제. 활성/후보/유예 중 retired는 보호하며 단건/다건을 각각 테스트 |
| S12 | A metadata 행이 삭제된 뒤 남은 A 파일 조회/삭제 | 본인 고아 정리는 가능, 다른 사용자 접근은 계속 거부 |
| S13 | 2MiB 초과, 잘못된 MIME, 빈 파일, 내용과 MIME 불일치 | 버킷 크기/MIME 제한 확인. 콘텐츠 진위는 별도 어댑터 디코딩/해시 검사로 보완 |
| S14 | 테스트용 광범위 permissive 정책을 추가한 staging | restrictive guard가 여전히 이 버킷의 교차 사용자·signed URL·UPDATE를 차단 |
| S15 | 다른 테스트 버킷의 기존 정상 정책 | 이 버킷 전용 restrictive guard 때문에 막히지 않음 |
| S16 | 여러 기기가 같은 경로 upload, 한쪽 timeout/409 | 덮어쓰기 없이 다운로드 SHA-256 비교로 재개 |

Storage operation helper가 배포 버전과 맞지 않으면 allowlist를 무작정 제거하지 않습니다. 실제 정상 요청의 operation을 확인하고 SQL 초안을 수정·재검토합니다. 현재 allowlist는 일반 업로드/다운로드/목록/metadata/삭제용이며 S3/TUS/변환/공유 URL은 범위 밖입니다.

관리자/서비스 키를 가진 서버는 이 앱 역할의 RLS를 우회할 수 있습니다. 키를 브라우저에서 완전히 제외하는 빌드 검사와 저장소 secret scan도 별도로 수행합니다.

## 5. IndexedDB 이전·재시도 검증

| ID | 시나리오 | 확인 사항 |
| --- | --- | --- |
| M01 | 3벌 최초 이전 | 서버 3행, 사진 3개, 원본 로컬 3행·3사진 유지 |
| M02 | 같은 이전을 두 번 시작 | UNIQUE(user_id,local_id)에 의해 중복 행 없음, 동일 해시 객체 덮어쓰기 없음 |
| M03 | INSERT 응답 유실 후 재시작 | 같은 local_id로 조회해 같은 server_id 예약 재사용 |
| M04 | 업로드 성공 후 클라이언트 확인/서버 ready 전 종료 | 예약/journal에서 재개. 클라이언트 신호만으로 ready 불가. 서버 실제 byte 검사 후 완료 |
| M05 | ready PATCH 성공 응답 유실 | 재조회로 완료 판단, 다른 새 행/파일 생성하지 않음 |
| M06 | A 이전 중 B로 로그인 | 작업 정지 및 계정 불일치 경고. A 원본을 B에 자동 전송하지 않음 |
| M07 | source v1와 v2, legacy 소재 문자열/빈 목록 | 재구성 JSON의 의미·문자열·배열 순서 보존 |
| M08 | 같은 local_id인데 다른 내용, 서버는 이미 편집됨 | 자동 upsert/덮어쓰기 없음. 사용자에게 충돌 보류 표시 |
| M09 | 같은 옷 이름이지만 다른 local_id | 별도 의류로 이전, 이름만으로 합치지 않음 |
| M10 | 네트워크 불안정·탭 2개 동시 이전 | 한 사용자/로컬 ID당 서버 행 하나, 제한된 재시도·진행 로그 |
| M11 | 잘못된 JSON/지원 밖 버전/손상 사진/2MiB 초과 legacy | 해당 행만 보류, 원본 메타데이터와 이미지 바이트 불변 |
| M12 | 이전 중 로컬 편집 | 잠금 또는 fingerprint 변경 감지. 이전 완료 표시가 최신 편집을 덮지 않음 |
| M13 | 서버 metadata는 ready지만 사진 누락/해시 불일치 | 성공으로 표시하지 않음. 로컬 원본으로 복구 선택 가능 |
| M14 | 새로고침/브라우저 종료 후 재개 | journal의 계정/프로젝트/해시 검증 후 이어서 수행 |
| M15 | 성공 후 로그아웃/앱 재실행 | 로컬 원본 그대로, 원격 캐시는 계정 간 공유되지 않음 |
| M16 | 서버 사진 교체 중 revision 충돌 | 기존 ready 사진·메타데이터 유지. 새 고아 객체만 별도 정리 대상 |
| M17 | 원격 DELETE/계정 삭제 | 로컬 사본에 삭제를 전파하지 않음. Storage 물리 삭제는 API로 별도 확인 |

원본의 **22개 키 전부**와 사용자 설정 **5개 키**를 비교합니다. 원본 raw JSON 스냅샷·v2 canonical 변환 결과를 따로 보유하고, 날짜는 서버 수신 시각이 아니라 원래 시각인지 확인합니다. 사진은 내려받은 원시 바이트 해시로 비교합니다. ETag/파일명/MIME 표기만 일치하는 것을 성공으로 간주하지 않습니다.

## 6. Flutter 통합 이후의 회귀 범위

- 기존 온보딩, theme 3종, 계층형 대/소분류+검색, 사진 추가/변경/삭제, 직접 입력, 소재 목록, 두께 1~5.
- 로컬 모드·로그아웃·오프라인 유지. 공개 키만 있는 상태에서 기존 개인 클라우드 데이터가 표시되지 않음.
- 사용자 변경 직후 이전 계정 카드/이미지/비동기 응답이 남지 않음.
- 불변 필드를 포함하지 않는 PATCH, 예상 revision 조건, ready 행만 보이는 목록.
- PC/모바일 웹, Chrome/Safari, 이후 Android/iOS 딥링크·세션 복원.
- 통합 구현 후 `flutter analyze`, `flutter test`, `flutter build web`. 현재 설계 작업에는 앱 변경이 없으므로 실행 결과를 새로 주장하지 않습니다.

## 7. 적용 승인과 되돌리기

1. 설계·SQL 초안 검토 → staging 실행에 대한 별도 승인 → schema/ACL/RLS/Storage 테스트 → Flutter 어댑터 구현 및 재검증 → 운영 적용에 대한 별도 승인 순서입니다.
2. SQL은 아직 실행하지 않았습니다. 첫 SQL과 두 번째 SQL은 별도 트랜잭션이므로 두 번째가 실패해도 첫 번째 변경은 이미 존재할 수 있습니다. 두 단계 모두 검증될 때까지 앱의 원격 연결을 활성화하지 않습니다.
3. 첫 적용 중 SQL 오류는 해당 트랜잭션을 rollback합니다. 이미 적용되어 데이터가 들어간 테이블/버킷은 자동 DROP으로 되돌리지 않습니다. 백업과 원인 검토 후 수정 migration을 별도 설계합니다.
4. 로컬 원본은 모든 단계에 남겨 둡니다. 전체 로컬 데이터 삭제는 이전의 일부로 제공하지 않습니다.

검증 기록에는 실행 대상 ref(민감값은 마스킹), 버전, SQL 파일 해시, JWT 역할/사용자 구분, 기대/실제 응답, 영향 행 수, 원본/서버 해시, 원본 보존 결과를 남깁니다. 아직 이 계획의 실행 기록은 없습니다.
