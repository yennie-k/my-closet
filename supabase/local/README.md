# Windows 로컬 통합 테스트 재개 절차

2026-10-29 현재 Docker/WSL 및 Supabase CLI가 준비되지 않아 **아래 명령은 실행하지 않았다**. 현재 폴더는 안내 문서만 포함하며 CLI 프로젝트 설정이 아니다. [실제 점검 결과](../../docs/supabase/local-readiness-report-20261029.md)를 먼저 확인한다.

## 1. 시스템 준비 — 사용자가 설치 여부 결정

1. [Microsoft WSL 설치 안내](https://learn.microsoft.com/en-us/windows/wsl/install)에 따라 관리자 PowerShell에서 `wsl --install`을 수행하고 필요한 재부팅을 완료한다. 이 명령은 시스템 기능과 기본 Linux 배포판을 설치하므로 자동 실행하지 않는다.
2. [Docker Desktop Windows 설치 안내](https://docs.docker.com/desktop/setup/install/windows-install/)의 Windows x86_64 설치 파일을 사용한다. Windows Home에서는 Linux 컨테이너를 사용하고 WSL 2 backend를 준비한다.
3. Docker Desktop을 직접 실행하고 다음을 확인한다.

```powershell
wsl --version
docker version
docker info --format '{{.OSType}}'
docker context show
```

Client와 Server가 모두 표시되고 OSType은 `linux`여야 한다. Docker context가 원격 서버를 가리키거나 `DOCKER_HOST` / `DOCKER_CONTEXT` 환경변수가 원격 주소를 지정하면 중단한다. 로컬 Docker Desktop engine만 사용한다. WSL/메모리 설정을 일괄 변경하거나 기존 Docker 자원을 삭제하지 않는다.

## 2. 기존 폴더와 격리한 새 CLI 작업 디렉터리

프로젝트의 기존 `supabase/drafts`와 `tests`를 덮어쓰지 않도록 Git에서 이미 무시하는 `build` 안에 **새 폴더**를 사용한다. 다음은 시스템 준비 후의 수동 실행 예시다. 기존 경로가 있으면 자동 삭제하지 않고 중단한다.

```powershell
Set-Location -LiteralPath C:\Projects\my_closet
$localTestRoot = 'C:\Projects\my_closet\build\supabase-local-20261029'
if (Test-Path -LiteralPath $localTestRoot) { throw '이미 존재하는 경로입니다. 새 실행 폴더를 선택하세요.' }
New-Item -ItemType Directory -Path $localTestRoot
Set-Location -LiteralPath $localTestRoot
npm.cmd init -y
npm.cmd install --save-dev --save-exact supabase
npx.cmd --no-install supabase --version
npx.cmd --no-install supabase init
```

CLI 다운로드는 이 새 작업 폴더의 Node 개발 의존성으로만 설치한다. Flutter 루트의 의존성 파일이나 전역 npm 패키지를 변경하지 않는다. 생성된 package-lock과 실제 CLI 버전을 남겨 다음 실행도 같은 버전을 사용한다. npm 방식 CLI는 Node 20 이상이 필요하며 현재 설치된 Node 22는 이 조건을 만족한다. [공식 CLI 설치 안내](https://supabase.com/docs/guides/local-development/cli/getting-started)

이후에도 이 새 작업 폴더에서 실행한다. 생성된 `supabase/config.toml`의 `project_id`를 `my-closet-local-security-20261029`처럼 로컬 테스트임이 분명한 값으로 설정한다. 포트 사용 여부를 확인하고 충돌이 있으면 이 로컬 설정에서만 변경한다. 기존 루트 `supabase`에 설정·migration을 만들지 않는다.

`SUPABASE_WORKDIR`, `SUPABASE_ACCESS_TOKEN` 또는 원격 연결용 설정이 상속된 쉘은 사용하지 않는다. 새 로컬 폴더에 `supabase/.temp/project-ref`가 있으면 중단한다. **login, link, db push, --linked, 원격 --db-url, 클라우드 키 입력은 사용하지 않는다.** Docker 이미지/CLI 다운로드 외 테스트 API 목적지는 loopback으로 제한한다.

로컬 API가 외부 네트워크에 노출되지 않도록 공식 안내의 loopback Docker network를 사용한다. 이름이 이미 존재하면 삭제·재생성하지 말고 설정을 검토한다.

```powershell
docker network create -o 'com.docker.network.bridge.host_binding_ipv4=127.0.0.1' my-closet-local-security-20261029
npx.cmd --no-install supabase start --network-id my-closet-local-security-20261029
```

네트워크 및 컨테이너 생성은 Docker 준비 후 수행하는 로컬 작업이다. 실제 게시 포트가 `127.0.0.1`에 바인딩됐는지 `docker ps`와 `docker inspect`로 확인한다. 모든 서비스가 정상 상태여야 하며, 실패를 `--ignore-health-check`로 숨기지 않는다. [공식 로컬 네트워크 안내](https://supabase.com/docs/guides/local-development)

## 3. SQL 적용과 버킷 준비

로컬 DB 컨테이너의 psql을 사용하면 Windows에 별도로 PostgreSQL을 설치할 필요가 없다. 실행 전 `docker inspect`로 이 실행의 project ID와 로컬 컨테이너인지 확인한다. SQL 실행 계정과 API 사용자 JWT의 권한은 구분한다.

1. 로컬 `auth`/`storage` 관리형 스키마 및 역할이 준비됐는지 확인한다. DB 및 Storage 이미지 버전과 helper 정의도 기록한다.
2. 기존 `C:\Projects\my_closet\supabase\drafts\01_database.draft.sql`을 읽어 로컬 psql에 `-X -v ON_ERROR_STOP=1`로 적용한다. 기존 앱 객체가 이미 있다면 중단하고 원인을 확인한다.
3. 로컬 Studio 또는 로컬 Storage API로 `garment-photos` 비공개 버킷을 생성한다. `public=false`, `file_size_limit=2097152`, `allowed_mime_types=[image/jpeg,image/png,image/webp]`를 확인한다. SQL로 Storage 객체나 버킷을 직접 생성하지 않는다.
4. `02_storage_policies.draft.sql`을 적용한다. 버킷 생성이 선행되어야 한다. helper/ACL preflight가 실패하면 정확한 메시지와 버전을 기록하고 중단한다.

초안은 이미 BEGIN/COMMIT을 포함한다. 두 파일을 하나의 `psql --single-transaction`으로 감싸거나 실패한 신규 스키마를 자동 DROP하지 않는다. 이번 로컬 리허설에서는 원본을 직접 읽어 적용하며, 클라우드 migrations로 복사하지 않는다.

## 4. DB 및 RLS 테스트

로컬 Studio의 Auth 기능이나 loopback Auth API에서 일회용 A/B 계정을 생성한다. 이메일은 예를 들어 `a-<run-id>@example.test`, `b-<run-id>@example.test`로 하고 가짜 메타데이터만 사용한다. 실제 사용자나 사진, IndexedDB export는 사용하지 않는다.

동일한 psql 연결에서 session GUC `my_closet_test.allow_fixtures=yes`, `my_closet_test.user_a=<A UUID>`, `my_closet_test.user_b=<B UUID>`를 설정하고 기존 `tests/01_security_contract.draft.sql`을 `ON_ERROR_STOP=1`로 실행한다. 파일은 새 계정을 요구하며 앱 fixture를 ROLLBACK한다. 사용자 생성은 SQL이 아닌 Auth 기능으로 수행한다.

계속해서 opt-in GUC가 설정된 연결에서 `tests/02_storage_contract.draft.sql`을 실행한다. 이 파일은 함수·operation 비교 및 정책 카탈로그만 검사하며 HTTP 테스트를 대신하지 않는다. 두 테스트 모두 일반 psql assertion 스크립트로 실행한다.

추가로 의류와 설정 각각에 대해 두 DB 연결에서 같은 revision을 읽은 뒤 UPDATE를 경쟁시킨다. 첫 UPDATE 성공 및 COMMIT 후 대기하던 두 번째 UPDATE가 0행인지 확인한다. 0행이면 사용자 권한으로 재조회하여 충돌·삭제·접근 불가를 구분하고 SQLSTATE 42501 및 HTTP 권한 오류와 별도로 기록한다. 기존 SQL의 순차 stale revision 검사를 실제 동시 세션 검사로 보고하지 않는다.

## 5. Storage HTTP 검증과 worker 경계

기존 `tests/storage_api_security.draft.mjs`는 재사용할 assertion을 포함하지만 staging 전용 opt-in, publishable 키 형식, 실제 검증된 activePath를 요구한다. **현재는 이 파일을 그대로 실행하지 않는다.** 다음 로컬 준비가 필요하다.

- 별도 local-only 진입점에서 `127.0.0.1`과 선택한 포트만 허용한다. redirect는 거절한다. 로컬 CLI가 반환하는 anon/publishable 키와 A/B user JWT만 HTTP 테스트에 사용한다.
- 테스트용 1×1 PNG 같은 합성 이미지를 직접 만들고 해시와 크기를 계산한다. 실제 옷 사진을 사용하지 않는다.
- 로컬 DB의 명시적 `SET ROLE service_role` 및 revision CAS로 해당 경로 예약 fixture를 준비한다. 실제 서버 예약 endpoint가 구현됐다고 주장하지 않는다. 일반 postgres 역할만으로 보호된 사진 상태를 수정하려 하지 않는다.
- 활성 사진 fixture가 없어도 업로드, 인증 다운로드, 교차 사용자 차단, 기존 의류 없는 경로 차단, 다른 경로 차단, 만료 예약, 업로드 재시도 및 client_confirmed 이후 재업로드 거절을 먼저 검증할 수 있다.
- 단건/다건 고아 삭제, 예약 사진 삭제 방지, retired 유예 및 다른 버킷 회귀 검증에는 별도 합성 fixture가 필요하다. 삭제 API가 0개 삭제 성공을 반환할 수 있으므로 응답 코드뿐 아니라 실제 바이트 유지/제거를 확인한다.
- 활성 사진 삭제 보호를 검사하려고 서버 역할로 ready fixture를 만드는 경우 결과는 **Storage 정책 시뮬레이션**으로만 기록한다. 실제 파일 다운로드·디코딩·해시 검증 worker의 성공을 뜻하지 않는다.

worker가 구현되기 전 `client_confirmed → ready`의 실제 검증, 잘못된 해시/크기/이미지 처리, 검증 중 파일 변경, durable 고아 정리 및 quota는 미검증으로 남긴다. 관리자 키를 Flutter나 테스트 소스에 넣지 않는다. 로컬 자격 증명 및 JWT는 Git에서 무시되는 작업 폴더나 프로세스 메모리에만 두고 보고서에 출력하지 않는다.

## 6. 결과와 종료

CLI/이미지/DB 버전, 실행별 SQL 성공 또는 정확한 SQLSTATE, HTTP 상태와 assertion 결과, 미실행 항목을 새 보고서에 기록한다. 민감한 응답과 키는 기록하지 않는다. 실패 시 원본 초안과 기존 앱 데이터를 변경하지 말고 수정 제안과 재현 정보를 남긴다.

이 실행의 작업 폴더에서 `npx.cmd --no-install supabase stop`으로 종료한다. `--all`, `--no-backup`, `db reset` 또는 전역 Docker prune을 사용하지 않는다. 기존 Flutter·Git·IndexedDB는 이 과정의 대상이 아니다. 클라우드 적용은 별도 검토와 승인 이후의 작업이다.
