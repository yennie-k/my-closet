# Supabase SQL 초안 — 실행하지 않음

이 디렉터리는 검토용이며 Supabase CLI의 `migrations` 디렉터리가 아닙니다.

1. [설계안](../../docs/supabase/design-draft.md)을 검토합니다.
2. `01_database.draft.sql`: 새 개인 테이블 2개와 제약·인덱스·트리거·RLS·최소 GRANT.
3. 승인 후 private `garment-photos` 버킷을 Dashboard/Storage API에서 설계한 제한으로 준비하는 단계가 필요합니다. 현재 생성하지 않았습니다.
4. `02_storage_policies.draft.sql`: 버킷·관리 권한·operation helper 사전 조건을 확인하고 객체 정책을 정의합니다.
5. [테스트 계획](../../docs/supabase/security-test-plan.md)에 따라 이후 승인된 staging에서 검증합니다.

보완 내용은 [SQL 리뷰](../../docs/supabase/sql-review-20261027.md)를 확인하세요. 오프라인 SQL/PLpgSQL 구문 검사는 별도 보고서에 기록하며 실제 적용/DB 테스트는 하지 않았습니다. `supabase/tests`에 승인된 staging용 SQL 및 HTTP 테스트 초안을 준비했습니다. 기존 원격 테이블·정책에 맞춰 diff를 검토하기 전 실행하지 마세요. 동일 객체가 있으면 자동 삭제·병합하지 않고 실패하도록 작성했습니다. 버킷이나 파일을 SQL DML로 생성·삭제하는 코드는 없습니다.
