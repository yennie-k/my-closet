# 검토용 보안 테스트 — 아직 실행하지 않음

이 디렉터리의 SQL/HTTP 스크립트는 실제 서버에 실행하지 않았습니다. [보완 리뷰](../../docs/supabase/sql-review-20261027.md)의 미검증 항목과 release gate를 먼저 확인하세요.

## 테스트 구분

1. `01_security_contract.draft.sql`: 별도 승인된 staging에 두 migration을 적용하고 신선한 A/B Auth 사용자를 준비한 뒤 DB RLS/ACL/CAS/상태 전이를 테스트합니다. opt-in GUC가 없으면 즉시 실패하며 모든 fixture는 ROLLBACK합니다. Auth 테이블과 Storage 객체를 직접 변경하지 않습니다.
2. `02_storage_contract.draft.sql`: 실제 배포 helper의 signature·operation 정규화와 정책 카탈로그만 확인합니다. 이 결과는 HTTP upload/remove가 동작한다는 증거가 아닙니다.
3. `storage_api_security.draft.mjs`: 실제 HTTP 업로드·JWT 다운로드·목록·단건/다건 삭제 및 교차 사용자 거부를 확인하도록 준비했습니다. 활성/후보 사진은 직접 삭제가 막히고 미참조 고아만 삭제됩니다. 현재 verifier/reservation endpoint가 미구현이므로 필요한 fixture를 자동 준비할 수 없습니다.

SQL의 service ready 전환은 서버 권한 경계 **시뮬레이션**입니다. 해당 테스트에는 실제 이미지 객체가 없으며 실제 파일 검증 성공으로 보고하면 안 됩니다. 해시/크기 불일치·손상·누락에 대한 worker 테스트는 실제 객체를 내려받는 별도 통합 테스트가 필요합니다.

## HTTP 스크립트 입력 명세

실행에는 Node.js 22+, publishable key, 테스트 A/B user JWT가 필요합니다. service/secret key를 받지 않습니다. 다음 환경 이름이 모두 필요합니다. 값을 저장소나 로그에 기록하지 마세요.

```text
MY_CLOSET_ALLOW_REMOTE_TESTS=yes
MY_CLOSET_TARGET_KIND=disposable-staging
MY_CLOSET_EXPECTED_STAGING_HOST=<승인된 staging host>
MY_CLOSET_TEST_RUN_ID=<이 실행만의 marker>
SUPABASE_URL=<승인된 staging URL>
SUPABASE_PUBLISHABLE_KEY=<publishable key>
TEST_USER_A_JWT=<일회성 테스트 계정 A JWT>
TEST_USER_B_JWT=<일회성 테스트 계정 B JWT>
```

JSON fixture 파일은 별도 비공개 임시 경로에 준비하여 첫 CLI 인자로 전달하는 형식입니다. 아래는 필드 명세이며 바로 실행 가능한 fixture가 아닙니다.

```json
{
  "approvedTestRun": "<같은 marker>",
  "uploadFile": "<로컬 테스트 이미지 파일 경로>",
  "extension": "jpg",
  "uploadPath": "<A UUID>/<서버 의류 UUID>/<실제 이미지 SHA-256>.jpg",
  "activePath": "<서버가 실제 검증한 A의 활성 사진 경로>",
  "deleteSinglePath": "<A의 미참조 고아 fixture 1>",
  "deleteManyPaths": ["<A의 미참조 고아 fixture 2>", "<A의 미참조 고아 fixture 3>"]
}
```

uploadPath는 다른 모든 fixture와 다르고 서버가 배정한 유효한 reserved 슬롯이어야 합니다. activePath는 실제 verifier 통합 테스트에서 검증된 객체여야 하며 SQL 시뮬레이션으로 대신하지 않습니다. 삭제 fixture는 모두 A 소유, 서로 다른 경로, 실제 존재하는 이미지, active/candidate/유예 중 retired에 참조되지 않는 객체여야 합니다. 테스트는 고아 3개를 소비하며 새 업로드는 이후 verifier/GC 테스트용으로 남깁니다.

필수 endpoint 검증은 일반 upload, 인증 GET, list, 단건 DELETE `.../object/<bucket>/<path>`, 다건 DELETE `.../object/<bucket>`의 prefixes body를 각각 사용합니다. 공식 작업명과 현재 API 라우트 정의를 비교했지만 실제 프로젝트 버전은 미확인입니다. 기존 다른 버킷은 별도 읽기 전용 control fixture로 적용 전/후 허용·거부 결과와 ACL/정책 목록을 비교해야 합니다.

## 오프라인 구문 검사

`supabase/tools/check_draft_sql.py`는 DB 연결 없이 pglast의 PostgreSQL 파서로 SQL과 PL/pgSQL 본문을 검사하고 grants AST를 확인합니다. 필요한 pglast는 프로젝트의 무시되는 `build/sql_review_tools`에만 설치했습니다. Flutter 의존성에는 추가하지 않았습니다.

보고서: [sql-review-static-report.json](../../docs/supabase/sql-review-static-report.json). 이 보고서는 실행/카탈로그/권한/Storage 검증 완료를 뜻하지 않습니다. 현재 실제 DB 테스트 결과는 없습니다.
