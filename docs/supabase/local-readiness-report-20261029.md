# Windows 로컬 Supabase 실행 준비 점검 — 2026-10-29

현재 환경에서는 Docker 및 WSL이 준비되지 않아 Supabase 통합 테스트를 실행하지 못했다. SQL 실행 실패가 아니라 **런타임 미준비로 인한 미실행**이다. 클라우드 `my-closet`에 연결하지 않았고 SQL, Auth 사용자 생성, Storage API 요청도 보내지 않았다.

## 1. 실제 확인한 환경

| 항목 | 결과 |
| --- | --- |
| 프로젝트 | `C:\Projects\my_closet` |
| Windows | Windows 11 Home, 64-bit, 10.0.26200 |
| CPU | Intel Core i7-12700K, 12코어 / 20논리 프로세서 |
| 가상화 | 펌웨어 가상화 및 SLAT `True` |
| 메모리 | 총 약 31.75 GiB, 조회 당시 여유 약 13.11 GiB |
| C: 디스크 | 여유 약 162.35 GiB |
| Node.js / npm | `v22.16.0` / `10.9.2`, 사용 가능 |
| Docker | PATH, 시스템/사용자 표준 설치 경로에서 실행 파일 미발견; 관련 프로세스/서비스도 미발견 |
| Supabase CLI | PATH에서 미발견 |
| psql | PATH에서 미발견; 추후 로컬 DB 컨테이너의 psql 사용 가능 |
| WSL | `wsl.exe --status` 종료 코드 50, 미설치 안내 출력 |
| 로컬 Supabase 설정 | `supabase/config.toml`, 로컬 migration 디렉터리 및 연결용 `.temp` 없음 |

처음 sandbox에서 시스템 CIM 조회가 거부되어 승인된 읽기 전용 조회로 다시 확인했다. 시스템 도구 설치, WSL 기능 활성화, 재부팅, Docker 기동, npm 패키지 설치는 하지 않았다. 비표준 경로의 휴대용 설치까지 전수 검색한 결과는 아니다.

공식 CLI 문서는 npm 사용 시 Node 20 이상과 컨테이너 런타임을 요구하며, 전체 서비스에는 최소 7GB RAM을 권장한다. 현재 하드웨어는 준비 여력이 있어 보이지만 Docker/WSL 설치 및 실제 컨테이너 기동 검증은 필요하다. Docker 이미지 다운로드량, 런타임 메모리 사용량, 포트 충돌은 미측정이다. Windows에서 컨테이너 없는 native Supabase 실행을 우회 대안으로 사용하지 않았다. [CLI 설치](https://supabase.com/docs/guides/local-development/cli/getting-started), [start 요구사항](https://supabase.com/docs/reference/cli/supabase-start), [Docker Windows 요구사항](https://docs.docker.com/desktop/setup/install/windows-install/)

## 2. SQL 의존성 및 실행 순서 검토

기존 초안과 테스트 원본을 덮어쓰거나 실제 migrations로 승격하지 않았다.

1. 새 로컬 Supabase를 초기화·기동하여 관리형 `auth`, `storage`, 역할과 API를 준비한다.
2. `drafts/01_database.draft.sql` 적용: Auth FK, 개인 테이블, 트리거, RLS 및 GRANT. `auth.users`, `auth.uid()`, `auth.jwt()`, 관리형 역할 및 `gen_random_uuid()`가 선행되어야 한다.
3. **로컬** Storage API 또는 로컬 Studio에서 `garment-photos`를 private으로 생성한다. 제한은 2,097,152 bytes, MIME은 JPEG/PNG/WebP의 세 종류다. Storage 테이블 직접 DML은 사용하지 않는다.
4. helper 함수, 버킷 제한, Storage RLS/관리형 ACL을 확인한 후 `drafts/02_storage_policies.draft.sql` 적용한다.
5. 로컬 Auth에서 가짜 A/B 사용자를 생성하고, 새 계정으로 DB 보안 SQL을 실행한다. 앱 fixture는 테스트 마지막에 ROLLBACK된다. Auth 계정 자체는 테스트 SQL이 생성·삭제하지 않는다.
6. Storage 계약 SQL을 실행한 후 별도의 HTTP fixture와 사용자 JWT로 API 테스트를 수행한다.

두 초안은 각각 BEGIN/COMMIT을 포함하며 신규 스키마에 한 번 적용하는 구조다. 01 성공 후 02 실패 시 01은 남는다. 동일 파일을 무조건 재실행하거나 기존 객체를 DROP하여 해결하면 안 된다. 02의 버킷은 외부 API 준비 단계이므로, 두 파일만 자동 migration 디렉터리에 넣어도 전 과정이 완성되는 것은 아니다.

`supabase/tests/*.sql`은 예외 발생과 ROLLBACK으로 판정하는 psql 스크립트다. pgTAP의 TAP 출력 테스트로 간주하거나 `supabase test db` 성공을 가정하지 않는다. psql `ON_ERROR_STOP=1` 및 실제 assertion 결과가 필요하다.

## 3. 실제 수행한 검증

| 검증 | 결과 | 한계 |
| --- | --- | --- |
| 기존 SQL 4개 오프라인 파싱 | 통과: SQL 문 89개, PL/pgSQL 블록 12개 | PostgreSQL 서버에 실행하지 않음 |
| AST 기반 GRANT/RLS 정적 검사 | 통과 | 실제 역할 상속, 트리거 실행 권한, 카탈로그 해석 미검증 |
| HTTP 스크립트 `node --check` | 통과 | JavaScript 구문만 검사; HTTP 요청 없음 |
| DB 초안 적용 | 미실행 | Docker/로컬 PostgreSQL 없음 |
| A/B 생성·DB RLS·권한 변조 | 미실행 | 로컬 Auth/DB 없음 |
| revision CAS·충돌 처리 | 미실행 | 기존 SQL은 순차 stale revision 검사; 동시 세션 검사는 별도 필요 |
| service_role 최소 권한 | 정적 검사만 통과 | 실제 역할/Storage 권한 미검증 |
| 버킷·업로드·조회·삭제·목록 | 미실행 | Storage 서버 및 fixture 없음 |
| 예약 만료·재시도·활성 사진 보호 | 미실행 | 시간 경계와 API 동작 검증 필요 |
| 실제 사진 검증 worker | 미구현·미검증 | client_confirmed → checking → ready의 실제 검증 완료를 주장하지 않음 |

파서는 기존에 `build/sql_review_tools`에 설치된 pglast 8.7 / PostgreSQL 파서 18.6을 재사용했다. 새 서버 버전이나 클라우드 버전을 확인한 것이 아니다. 기존 검사기의 보고서 쓰기를 메모리에서 가로채 **기존 보고서를 보존**하고 [이번 정적 검사 결과](local-readiness-static-20261029.json)를 새 파일로 남겼다.

## 4. 확인한 테스트 준비 문제와 남은 보안 위험

- **로컬 HTTP 실행 가드:** 기존 스크립트는 `disposable-staging` 및 `MY_CLOSET_ALLOW_REMOTE_TESTS=yes`를 요구한다. 이번 로컬 작업에서 이 가드를 우회하거나 staging으로 위장해 실행하지 않았다. 후속 로컬 runner는 numeric loopback URL·예상 포트·로컬 Docker context만 허용하고 HTTP redirect를 따라가지 않아야 한다. 기존 코드를 수정하지 않는 별도 로컬 진입점이 적합하다.
- **API 키 호환성:** 기존 HTTP 스크립트는 `sb_publishable_` 접두사만 허용한다. 설치할 CLI가 로컬 legacy anon JWT만 제공하면 API 요청 전 assertion에서 중단될 수 있다. 로컬 CLI의 실제 키 형식을 확인한 후 로컬 전용 runner에서 anon 역할만 허용해야 한다. service/secret key를 사용자 HTTP 테스트에 대신 넣으면 안 된다.
- **worker 의존 fixture:** 기존 HTTP 스크립트는 실제로 검증된 `activePath`를 필수로 요구한다. worker가 없으므로 전체 스크립트는 아직 준비 불가다. 업로드·접근 차단·예약 검사는 별도 테스트로 실행하고, 활성 경로 삭제 정책을 서버 역할로 만든 모의 상태로 검증한다면 반드시 ‘정책 fixture 시뮬레이션’으로 표시해야 한다. 실제 서버 검증 성공으로 보고하지 않는다.
- **실제 동시성:** 기존 SQL의 stale revision 테스트는 두 UPDATE를 순서대로 실행한다. 두 DB 연결의 동일 revision 경쟁, 한 세션 대기 후 0행 결과, 의류와 사용자 설정 각각의 최신값 재조회·충돌 안내는 추가 검증해야 한다. Flutter 충돌 UI는 이번 범위에서 변경하지 않았다.
- **시간·재시도·정리:** 만료 예약 업로드 거절, client_confirmed 이후 재업로드 거절, 중복 업로드에서 기존 바이트 보존, 응답 유실 후 재조회, retired 유예 전/후 삭제, 삭제와 검증의 경쟁 및 고아 정리를 검증해야 한다. 기존 HTTP 스크립트만으로 이 항목들이 모두 커버되지는 않는다.
- **권한 영향:** service_role의 앱 테이블 제한과 별개로 관리형 Storage의 서버 권한은 넓을 수 있다. 다른 버킷용 control fixture, API 권한 오류와 0행 결과, 익명 Auth, 미로그인 요청도 실행 검증이 필요하다. 실제로 재현된 신규 RLS 취약점은 없으며, 이는 보안 통과를 뜻하지 않는다.

`storage.allow_only_operation(text)` / `allow_any_operation(text[])`는 현재 [공식 helper 문서](https://supabase.com/docs/guides/storage/schema/helper-functions)에 있다. 하지만 설치될 Storage 이미지의 지원 여부 및 실제 operation 라벨은 아직 모른다. 02 초안은 helper 미지원 시 `Storage operation helpers unavailable: review deployment; do not weaken policies` 예외로 중단하도록 설계되어 있다. **이번 실행에서 발생한 오류가 아니라 코드에 정의된 예상 오류**다. 구버전에서 이 오류가 발생하면 CLI/Storage 버전과 helper 정의·라우트 operation을 기록하고 호환 버전 또는 검토된 정책을 선택해야 한다. 가드를 제거하거나 모든 작업을 허용하는 수정은 하지 않는다.

## 5. 변경 파일과 보존 범위

추가한 파일만 있다.

- `docs/supabase/local-readiness-report-20261029.md`: 이 보고서.
- `docs/supabase/local-readiness-static-20261029.json`: 이번 오프라인 정적 검사 결과.
- `supabase/local/README.md`: 설치 및 로컬 전용 실행 재개 절차.

기존 SQL, 테스트 스크립트, 설계 문서, Flutter 코드와 의존성 파일은 수정하지 않았다. 기존 Git 기록에도 쓰기 작업을 하지 않았다. 브라우저나 Flutter 앱을 실행하지 않아 IndexedDB 및 실제 옷 사진에 접근하지 않았다.

## 6. 클라우드 적용 전 남은 작업

1. 사용자 주도로 WSL/Docker Desktop을 설치·기동하고 CLI를 격리된 로컬 작업 폴더에 준비한다. [설치·재개 절차](../../supabase/local/README.md) 참고.
2. 새 로컬 스택의 버전·함수·ACL을 기록하고 위 순서로 초안을 적용한다.
3. A/B DB 보안 테스트, 두 연결의 동시 CAS, 실제 HTTP 및 다른 버킷 회귀 테스트를 실행한다.
4. 서버 예약/검증/정리 worker, 크기·해시·MIME·이미지 디코딩 불일치, 재시도·quota·고아 정리를 구현·검증한다.
5. 테스트 결과를 검토하고 클라우드 버전과의 차이를 확인한 뒤 별도 승인을 받아 적용 계획을 세운다. 이 보고서는 클라우드 적용 승인이나 migration 승격을 의미하지 않는다.
