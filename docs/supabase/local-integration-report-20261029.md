# Supabase 로컬 통합 테스트 결과 — 2026-10-29

원본 DB/Storage SQL 초안 두 개를 **로컬에 적용했고**, 기존 SQL 계약 테스트와 실제 JWT/Storage HTTP 검증을 통과했다. 개별 검사 기준 RLS **29 통과 / 0 실패**, Storage **33 통과 / 0 실패**다. 서버 검증 worker는 구현하거나 검증하지 않았다. 클라우드 `my-closet`에는 접속하지 않았다.

[기계 판독 결과 및 전체 검사 목록](local-integration-results-20261029.json)에 실제 helper 정의, 컨테이너 버전, 각 검사 결과와 오류 응답을 기록했다. 한 개의 이름 붙은 검사는 여러 assertion을 포함할 수 있다. SQL 계약 suite의 내부 assertion을 개별 검사 숫자에 중복 합산하지 않았다.

## 1. 대상 확인과 보존

| 항목 | 실제 확인 결과 |
| --- | --- |
| Flutter 프로젝트 | `<PROJECT_ROOT>` |
| Supabase 테스트 프로젝트 | `<LOCAL_SUPABASE_DIR>` |
| CLI | 2.122.0, 설치된 실행 파일 직접 사용; 다운로드/업데이트 없음 |
| API / DB | `http://127.0.0.1:54321` / `127.0.0.1:54322` |
| DB 컨테이너 | `supabase_db_my_closet_supabase_local`, 호스트 54322 → 컨테이너 5432 |
| PostgreSQL | 17.11, 이미지 `supabase/postgres:17.11.0.006` |
| Storage | `supabase/storage-api:v1.84.19` |
| Auth / PostgREST | `gotrue:v2.197.0` / `postgrest:v16.5` |
| Docker context | `desktop-linux`, 로컬 Windows named pipe |
| 원격 연결 | 두 프로젝트에 `.temp/project-ref` 없음; 원격 접속용 환경변수 없음 |
| 실행 전 데이터 | Auth 0명, 버킷 0개, 파일 0개, 앱 테이블 및 private schema 없음 |
| 보호 파일 | Flutter 코드·테스트·의존성·원본 SQL/테스트·기존 안내·로컬 config 등 50개 해시 동일 |

API URL은 코드에서 numeric loopback으로 고정했고 다른 origin과 HTTP redirect를 거절했다. DB 작업은 위 포트에 연결된 동일 Docker 컨테이너의 psql로 실행했다. `login`, `link`, `db push`, 원격 `--db-url`, reset, Docker prune을 실행하지 않았다. 브라우저·Flutter·IndexedDB 및 실제 의류 사진은 사용하지 않았다.

현재 컨테이너의 호스트 포트는 `0.0.0.0` 및 `::`에 게시되어 있다. 외부에서 실제 접근 가능한지는 방화벽 검증을 하지 않았다. 이번 요청은 loopback으로만 보냈고 네트워크 설정은 변경하지 않았다. 로그 수집용 vector 컨테이너는 재시작 중이었지만 이번 DB/Auth/Storage 요청은 정상 완료됐다.

## 2. 백업과 실제 적용 순서

빈 대상임을 확인한 뒤 `pg_dump --format=custom`으로 전체 DB 논리 백업을 생성했다. `pg_restore --list`로 백업 목차를 읽는 데 성공했다. **실제 restore는 실행하지 않았으므로 복원 성공을 검증한 것은 아니다.** 실행 전 Storage 객체가 0개였으므로 기존 파일 바이너리 백업 대상은 없었다.

- 백업: `<PROJECT_ROOT>\build\supabase-local\20261029-run1\before.dump`
- SHA-256: `763d96424e683cd36b59324b2f0206b2703a816f13dadc92f2dd85cbfca7704e`
- 원상복구 주의 및 대상: 같은 폴더의 `RESTORE-REQUIRES-APPROVAL.txt`; 아래 복구 절차도 참고.

`<LOCAL_SUPABASE_DIR>\rehearsals\20261029-run1`에 원본과 바이트가 동일한 `01_database.local.sql`, `02_storage_policies.local.sql` 및 해시 manifest를 생성했다. 의존성을 확인한 뒤 직접 psql 리허설로 적용했으며 CLI migration history에 성공 기록을 임의로 삽입하지 않았다. 자동 실행되는 migrations 디렉터리에도 추가하지 않았다. 버킷 생성은 두 SQL 사이의 별도 API 단계다.

| 단계 | 실제 결과 |
| --- | --- |
| `01_database.draft.sql` | 적용 성공 |
| Storage API로 비공개 `garment-photos` 생성 | 성공; 2 MiB / JPEG·PNG·WebP 제한 |
| `02_storage_policies.draft.sql` | 적용 성공 |
| `01_security_contract.draft.sql` | 원본 그대로 실행 성공; 앱 fixture ROLLBACK |
| `02_storage_contract.draft.sql` | 원본 그대로 실행 성공; 카탈로그/helper 검증 후 ROLLBACK |

원본 SQL 수정이나 권한 확대는 필요하지 않았다. 처음 sandbox에서 Docker named pipe 접근이 거부되어 승인된 로컬 실행 권한으로 재실행했다. SQL 적용·정책 검사에서 재현된 오류는 없다.

## 3. DB / RLS 결과 — 개별 29 통과, 0 실패

로컬 Auth Admin API로 일회용 `example.test` A/B 계정을 만들고, 비밀번호 로그인으로 발급된 실제 user JWT를 사용했다. 비밀번호·JWT·service key는 보고서나 소스에 넣지 않았다. JWT는 Git에서 무시되는 `build`의 private 실행 파일에만 보관한다. SQL 계약 테스트의 JWT GUC 시뮬레이션과 실제 서명 JWT 요청은 구분했다.

검증한 동작은 다음과 같다.

- A/B 각각 의류·설정 등록 및 조회, A의 정상 수정·삭제, B 데이터 보존.
- 상대 사용자 SELECT는 빈 목록, UPDATE/DELETE는 0행이며 원래 데이터 유지.
- 다른 `user_id`로 INSERT는 RLS `42501`, `user_id` UPDATE는 컬럼 ACL `42501`로 차단.
- 미로그인 anon 접근 차단 및 두 테이블의 anon CRUD/컬럼 GRANT 부재.
- 익명 Auth claim 접근 차단은 SQL 시뮬레이션으로 확인. 실제 익명 로그인은 설정상 비활성화돼 실행하지 않았다.
- 실제 JWT의 `sub`를 서명 없이 바꾸면 HTTP 401로 거절.
- 사용자 설정과 의류 모두 revision 조건부 첫 UPDATE 성공, stale revision UPDATE는 0행. 보호 컬럼 쓰기 권한 오류 `42501`과 구분.
- **두 실제 DB 연결**로 같은 revision을 경쟁시킴. 두 번째 세션의 row-lock 대기를 관찰한 뒤 첫 세션을 COMMIT했고, 두 번째 UPDATE가 0행으로 끝나며 revision은 한 번만 증가함을 각각 확인.
- service_role의 사진 컬럼 SELECT/예약 변경 허용, 설정 SELECT·일반 의류 notes SELECT·name UPDATE 차단. 일반 INSERT/DELETE 권한 부재 확인.
- 소재 문자열·복수 소재·사용자 정의 종류·추가 색상 HEX·두께 4 값의 실제 API 왕복 확인. 기존 IndexedDB 데이터를 이전한 검사는 아니다.

기존 SQL 계약 suite도 별도로 통과했다. 원본 suite의 service_role ready 전이는 물리 파일이 없는 신뢰 경계 시뮬레이션이다.

## 4. Storage 결과 — HTTP 및 정책 상태 검사 33 통과, 0 실패

직접 작성한 코드로 1×1 PNG를 생성했다. 교체 fixture는 정상 PNG의 tEXt chunk를 추가해 별도 해시를 만들었다. 외부 이미지나 실제 옷 사진은 사용하지 않았다.

기존 `storage_api_security.draft.mjs`는 staging 가드 및 실제 worker가 검증한 activePath를 요구하므로 그대로 실행하지 않았다. 원본의 업로드·다운로드·목록·단건/다건 삭제 assertion을 별도 로컬 전용 runner로 옮겨 재사용·확장했다. 원본 파일은 유지했으며 모의 active fixture를 실제 검증 fixture로 위장하지 않았다.

- private 버킷 설정과 정확한 MIME/크기 제한 확인.
- 빈 예약 경로에 B가 먼저 업로드하는 요청 차단; 객체가 생성되지 않았음을 DB SELECT로 확인한 뒤 A의 업로드 성공.
- A의 실제 JWT 인증 다운로드 및 업로드 바이트 SHA-256 일치 확인.
- B 다운로드, 미로그인/공개 다운로드, 타 사용자 경로 업로드 차단.
- 의류 없는 경로, 본인 의류의 미예약 해시 경로 업로드 차단.
- 중복 POST 재시도 거절 후 기존 바이트 유지; upsert 및 PUT 덮어쓰기 차단.
- signed URL 발급 차단, 본인 목록 조회 성공, 타 사용자 목록 빈 결과.
- 1초 예약을 실제 만료시킨 후 업로드 차단. 만료 예약의 client_confirmed 변경은 `23514`로 거절.
- 정상 client_confirmed 변경 후 `photo_state=pending` 유지 및 재업로드 차단.
- client_confirmed 후보·모의 active 사진·유예 중 retired 사진에 대한 단건 삭제 거절 및 바이트 보존.
- 타 사용자 단건/다건 삭제가 본인 객체를 삭제하지 못함을 확인.
- 의류 행 삭제 후에도 소유자의 고아 파일 단건 삭제 성공, 다건 고아 삭제 성공.
- 교체 후 retired 유예 보호 및 정리 전 신규 후보 할당 차단. 유예 종료는 서버 역할로 시각 fixture를 변경한 뒤 삭제 성공 확인. **실제 24시간 경과를 기다린 검사는 아니다.**
- 별도 private control 버킷과 그 버킷에만 적용되는 시험 정책으로 업로드·다운로드·삭제가 가능함을 확인하여 garment 전용 restrictive guard가 다른 버킷을 막지 않음을 검증.

삭제는 승인된 manifest의 합성 PNG 5개·의류 1행·설정 1행만 대상으로 했다. Auth 계정 및 버킷은 삭제하지 않았다. Storage 객체는 모두 HTTP API로 생성·삭제했으며 `storage.objects`/`buckets` 직접 DML은 하지 않았다.

중요한 실제 응답 차이도 확인했다.

| 요청 | 실제 응답 및 확인 |
| --- | --- |
| 중복 업로드 | HTTP 400, 본문 `statusCode=409`, `Duplicate`, `KeyAlreadyExists`; 바이트 유지 |
| upsert | HTTP 400, 본문 `statusCode=403`, `AccessDenied`, RLS 위반; 바이트 유지 |
| 보호된 사진 또는 타 사용자 단건 삭제 | HTTP 400, 본문 `statusCode=403`, `AccessDenied`; 바이트 유지 |
| 타 사용자 다건 삭제 | **HTTP 200 / `[]`**, 원래 두 파일은 유지 |
| 소유자 고아 단건·다건 삭제 | HTTP 200, 실제 Storage 메타데이터에서 객체 제거 확인 |

따라서 Flutter 연동 시 HTTP 상태 하나만으로 권한 거절·실제 삭제·중복 업로드를 판정하면 안 된다. 응답 본문 코드와 반환 행/객체 목록, 소유자 재조회가 필요하다. 타 사용자 다건 삭제의 HTTP 200을 보안 실패나 삭제 성공으로 오판하지 않았다.

`storage.operation()`, `storage.allow_only_operation(text)`, `storage.allow_any_operation(text[])`는 이 로컬 버전에 모두 존재했고 실제 SQL 호출도 통과했다. 업로드·JWT GET·list·단건 delete·다건 delete는 HTTP로 확인했다. 미지원 helper/작업명 오류는 재현되지 않았다. prefix 비교 규칙은 [공식 helper 문서](https://supabase.com/docs/guides/storage/schema/helper-functions), 작업명 정의는 [공식 Storage 소스](https://github.com/supabase/storage/blob/master/src/http/routes/operations.ts)와 대조했다. 로컬에서 가져온 실제 함수 정의는 JSON 보고서에 포함했다.

## 5. worker 경계와 미검증 범위

**실제 서버 worker의 client_confirmed → ready 검증을 수행하지 않았다.** active 및 retired 삭제 정책을 시험하기 위해 로컬 서버 역할로 checking/ready 상태를 구성했다. 다운로드 SHA-256 비교는 테스트 프로세스가 수행한 바이트 일치 검사이며, 운영 서버 검증 worker의 구현을 대신하지 않는다.

다음은 미검증이다.

- 실제 예약/검증/정리 endpoint의 사용자 검증, revision CAS, 재시도 및 durable job 처리.
- 잘못된 SHA·크기·MIME·손상 이미지의 worker 디코딩 처리, 검증 중 객체 변경.
- 네트워크 응답 유실·프로세스 중단·장기 고아 정리·quota·계정 rate limit·고부하 경쟁.
- 실제 24시간 경과, 정리와 재업로드의 TOCTOU 경쟁. 이번 시간 fixture 검사는 완전한 시간/장애 검증이 아니다.
- HTTP list_v2 및 metadata GET/HEAD, TUS, S3, 이미지 변환. list_v2의 helper 문자열 비교는 SQL에서만 통과했다.
- 실제 백업 복원, Flutter 충돌 안내 UI, IndexedDB 이전, 클라우드 버전 및 설정 일치.

현재 로컬 config의 `auto_expose_new_tables`는 미설정(기본값 적용)이며, 사용자가 설명한 클라우드의 자동 노출 비활성화 환경과 동일하게 구성한 것은 아니다. 최종 앱 테이블의 명시적 GRANT/REVOKE 및 RLS는 실제로 검증했지만, 이를 클라우드 환경 전체의 통합 테스트 성공으로 확대 해석하지 않는다. service_role의 관리형 Storage 권한은 앱 테이블의 최소 권한과 별도로 넓을 수 있어 미래 worker에서 호출자 소유권 검증이 필요하다.

## 6. 생성 파일과 실행 기록

기존 Flutter·SQL 설계·테스트 파일은 수정하지 않았다. 새 파일은 다음과 같다.

- `supabase/local/integration.mjs`: 대상·환경·연결 가드와 로컬 SQL/HTTP 공통 함수.
- `supabase/local/prepare.mjs`: 빈 대상 확인, 백업, 로컬 리허설 사본, 순차 적용 및 Storage 계약 검사.
- `supabase/local/exercise.mjs`: 원본 DB 계약, A/B JWT, RLS, 두 연결 CAS, Storage 및 합성 fixture.
- `supabase/local/additional.mjs`: JWT 변조, 최소 anon ACL, retired/다른 버킷 fixture 및 삭제 manifest.
- `supabase/local/delete-tests.mjs`: 승인된 합성 manifest로만 실행하는 삭제 검증.
- `supabase/local/report.mjs`: 키/JWT를 제외한 검증 보고서 생성.
- `docs/supabase/local-integration-results-20261029.json`: 전체 결과와 helper 정의.
- `docs/supabase/local-integration-report-20261029.md`: 이 보고서.

외부 로컬 테스트 프로젝트에는 앞서 설명한 리허설 SQL 두 개와 manifest만 추가했다. 기존 config/package/Git 파일은 수정하지 않았다. 비밀 실행 자료와 백업은 Git에서 무시되는 `build/supabase-local/20261029-run1`에만 있다. Git 커밋이나 push를 수행하지 않았다.

실행 순서는 아래와 같았다. 각 스크립트는 고정된 실행 ID와 결과 파일의 기존 존재 여부를 검사하므로 **같은 명령을 그대로 다시 실행해 기존 결과를 덮어쓰지 않는다.** 재실행은 새 실행 ID와 새 로컬 상태를 검토한 후 준비해야 한다. 기존 local DB를 reset하여 재실행하지 않는다.

```text
node supabase/local/integration.mjs inspect
node supabase/local/prepare.mjs
node supabase/local/exercise.mjs
node supabase/local/additional.mjs
node supabase/local/delete-tests.mjs --approved-synthetic-manifest
node supabase/local/report.mjs
```

새 Node 파일은 `node --check`로 구문도 확인했다. Flutter 기능 변경이 없어 flutter analyze/test/build는 이번 작업에서 실행하지 않았다.

## 7. 종료 상태와 복구 방법

기존 실행 중이던 로컬 스택은 계속 실행 상태로 두었다. 최종 로컬 상태는 가짜 Auth 2명, 의류 6행, 설정 1행, 사진 2개, 버킷 2개다. 사진 두 개는 업로드 확인 후보와 모의 active 사진이며, 운영용 검증 데이터가 아니다. control 버킷과 그 시험 정책도 남아 있다.

원상복구 작업은 실행하지 않았다. 아래 변경은 추가 삭제를 수반하므로 **대상 manifest를 검토하고 별도 승인을 받은 다음** 수행해야 한다.

1. 후속 테스트 writer를 중단하고 현재 fixture manifest를 별도로 보관한다. 백업 SHA와 TOC를 다시 확인한다.
2. 이번 run의 A/B 사용자 metadata와 소유권을 다시 검사한다. 제거하려면 로컬 Auth Admin API로 이 두 시험 계정만 삭제한다. FK로 남은 시험 앱 행도 삭제되므로 이 영향을 승인 범위에 포함한다.
3. 기록된 남은 합성 사진 두 개를 로컬 Storage API로 제거하고, 비어 있음을 확인한 뒤 이번에 만든 두 버킷만 Storage API로 삭제한다. SQL로 Storage 메타데이터를 지우지 않는다.
4. `mc_photos_*` 9개 정책과 `mc_local_control_20261029_run1` 시험 정책, 이번에 만든 두 앱 테이블 및 private 트리거 함수/schema를 명시적으로 검토하여 제거한다. 다른 관리형 객체나 다른 run의 객체는 제거하지 않는다. public schema ACL은 백업과 비교해 이번 명시적 USAGE 변경분까지 확인한다.
5. 완전 복원 증명이 필요하면 같은 이미지의 **새 격리된 로컬 복구 스택**에 백업을 복원하여 관리형 스키마·owner·ACL까지 비교한다. 현재 실행 스택에 `pg_restore --clean`, db reset, volume 삭제를 자동 적용하지 않는다.

이 절차는 복원 성공 결과가 아니라 영향 범위가 정의된 복구 계획이다.

## 8. 클라우드 적용 전 남은 작업

1. 서버 예약/사진 검증/고아 정리 worker와 호출자 인증·소유권 검증을 구현한다.
2. hash/size/MIME/decode 불일치, 장애 재시도, durable cleanup, quota와 경쟁 조건을 추가 검증한다.
3. 응답 본문 코드·0행 CAS 결과를 구분하는 Flutter 연동 및 충돌 UI를 구현·검증한다.
4. 클라우드 Storage/Postgres 버전과 설정에 맞는 별도 staging 적용 검토, 자동 노출 비활성 환경 검증 및 백업 복원 리허설을 수행한다.
5. 그 결과를 검토하고 별도 승인 후에만 클라우드 migration 적용을 계획한다. 이번 작업에서 클라우드 SQL은 실행하지 않았다.
