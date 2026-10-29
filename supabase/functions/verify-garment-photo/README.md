# 사진 검증 worker

로컬에서 실행·검증한 Supabase Edge Function이다. Flutter·원본 SQL·기존 데이터는 수정하지 않는다. 클라우드 배포 명령은 이 작업에 포함하지 않는다.

## 요청과 인증

```http
POST /functions/v1/verify-garment-photo
Authorization: Bearer <사용자 세션 JWT>
apikey: <프로젝트 publishable/anon 키>
Content-Type: application/json

{"garment_id":"<서버 UUID>","upload_path":"<DB 예약 경로>"}
```

`upload_path`는 재시도 식별자·일치 검사 용도다. 버킷/크기/해시/사용자 ID/ready 등 추가 입력은 거부한다. 실제 경로는 소유자 RLS 조회로 읽은 DB의 `upload_path`와 정확히 같아야 한다. 기대 해시는 **DB 예약 경로 파일명**에 저장된 SHA-256이며, 기존 활성 사진의 `photo_sha256`와 혼동하지 않는다. 검증 후 `photo_sha256`에는 직접 계산한 값이 저장된다.

CLI 2.122.0 / Edge Runtime 1.77.8에서 게이트웨이 `verify_jwt` 기본값 true를 유지한 채 ES256 사용자 토큰으로 검증했다. `--no-verify-jwt`는 사용하지 않는다. 함수도 매 요청 Auth `/auth/v1/user`로 토큰과 사용자를 확인한 뒤, 익명/서비스 역할을 거부하고 사용자 JWT로 RLS 조회한다. [인증 공식 문서](https://supabase.com/docs/guides/functions/auth)

관리자 키는 Edge Runtime의 서버 환경변수에서만 읽는다. 필요한 사진 컬럼의 조건부 PATCH와 고정 버킷 파일 읽기에만 사용한다. 사용자 소유권을 확인하기 전에 관리자 파일 읽기/수정을 하지 않는다. SQL의 기존 최소 GRANT와 ready 클라이언트 쓰기 차단을 유지한다.

## 검증과 상태 전이

1. 인증, 소유권, 예약 경로/크기/만료/클라이언트 확인 상태를 검사한다.
2. `revision + id + user_id + upload_path + upload_state + 유효기간` 조건으로 checking을 획득한다. 반환 revision이 이 검증 시도의 fencing token이다.
3. 실제 파일을 최대 2 MiB까지만 읽고 길이를 DB 기대 크기와 비교한다. 매직 바이트·확장자, SHA-256, 컨테이너 구조를 검사한다.
4. 고정 버전 `npm:@imagemagick/magick-wasm@0.0.45`로 실제 픽셀을 디코딩한다. 제한은 한 변 4096px, 총 400만 화소다. PNG CRC/IEND, JPEG EOI, WebP RIFF 길이를 검사하고 애니메이션 PNG/WebP는 거부한다. 디코더 경고도 거부한다. [Supabase WASM 이미지 처리 예시](https://supabase.com/docs/guides/functions/examples/image-manipulation), [라이브러리 및 라이선스](https://github.com/dlemstra/magick-wasm)
5. 파일을 다시 읽어 존재·바이트 해시·ETag·Last-Modified를 비교한다. 예약 만료를 다시 검사한다.
6. 획득했던 revision과 경로/상태가 유지되는 경우에만 ready로 전환한다. 크기·해시·MIME·해상도·검증 시각을 서버 계산 결과로 저장하고 후보 슬롯을 비운다. 기존 활성 사진이 있으면 25시간 retired 유예에 둔다.

두 서비스 사이에 원자적 트랜잭션은 없다. 일반 클라이언트의 후보 파일 삭제·덮어쓰기는 기존 Storage RLS로 막지만, 관리자 권한의 마지막 읽기 이후 변경까지 영구 보장하지는 않는다. 향후 모든 관리자 쓰기/GC는 같은 예약·lease 규칙을 따라야 한다. `ready`는 `verified_at` 시점의 attestation이며 무기한 존재 보장이 아니다.

## 충돌과 재시도

- 같은 경로가 이미 검증됐다면 기존 attestation과 `already_verified=true`를 반환하며 revision을 증가시키지 않는다. 다시 디코딩한 결과로 해석하지 않는다.
- `checking`의 `server_updated_at`으로 60초 lease를 판단한다. 만료 후 새 revision으로만 takeover한다. 죽은 프로세스가 되살아나도 이전 revision으로는 커밋할 수 없다.
- 네트워크 등 일시 장애는 본인이 획득한 revision에서만 client_confirmed로 돌린다. DB 장애로 해제가 안 되면 lease가 남고, 이후 호출이 복구한다. 일반 의류 편집이 revision을 바꿔도 안전하게 충돌 처리되며 lease 만료까지 기다릴 수 있다.
- 실패해도 기존 활성 사진·로컬 파일을 삭제하지 않는다. 예약/정리 endpoint는 별도 구현 대상이다.

| error | HTTP | retryable | 처리 |
| --- | --- | --- | --- |
| unauthorized | 401 | false | 다시 인증 |
| not_found_or_not_owned | 404 | false | 타 사용자/없는 의류 구분 노출 없음 |
| reservation_mismatch / client_confirmation_required | 409 | false | 현재 예약과 업로드 확인 흐름 점검 |
| expired | 409 | false | 새 예약 필요 |
| verification_in_progress / revision_conflict | 409 | true | backoff 후 재조회·재시도 |
| not_found | 404 | true | 만료 전 실제 객체 수신 또는 재예약 확인 필요 |
| size_mismatch / hash_mismatch / mime_mismatch / invalid_image | 422 | false | 같은 입력 반복 금지; 새 파일/예약 필요 |
| object_changed | 409 | true | 관리자 파일 변경 원인 확인 후 재검증 |
| storage_unavailable / database_unavailable / verification_unavailable | 503 | true | 일시 장애 backoff; lease 복구 가능 |
| database_permission_denied / database_constraint / server_configuration | 503 | false | 서버 권한/설정 수리 필요 |

## 로컬 실행

실제 소스는 이 폴더에 있고 검증한 로컬 복사본은 `C:\Projects\my_closet_supabase_local\supabase\functions\verify-garment-photo`다. 서버 환경변수는 로컬 CLI가 주입하며 소스에 키를 작성하지 않는다.

프로젝트 루트에서 `node supabase/local/worker-serve.mjs`를 실행한다. 이 진입점은 로컬 named pipe·포트·원격 연결 표식을 확인한 뒤 로컬 CLI의 `functions serve verify-garment-photo`만 호출한다. 이미 실행 중이면 두 번째 프로세스를 시작하지 않는다. `worker-sync.mjs`는 이번 작업에서 생성한 함수 파일만 해시 확인 후 동기화하며 이전 코드 사본을 보관한다.

테스트 도구의 WASM 의존성은 Flutter와 별개로 Git에서 무시하는 build에 준비했다.

```powershell
npm.cmd install --prefix build/photo-worker-tools --no-save --ignore-scripts @imagemagick/magick-wasm@0.0.45
node --experimental-strip-types --test supabase/tests/photo_worker.test.ts
```

로컬 통합 테스트 runner는 고정 run ID의 사본·fixture를 보존하므로 그대로 재실행해 덮어쓰지 않는다. 새 run ID와 기존 데이터 보존 범위를 검토한 후 재실행한다. `worker-setup.mjs`의 실패 폴더(worker-1)는 보존했고 최종 실행 폴더는 worker-2다. 초기화로 재실행하지 않는다.

[실행 보고서](../../../docs/supabase/photo-worker-report-20261029.md)와 [기계 판독 결과](../../../docs/supabase/photo-worker-results-20261029.json)를 참고한다. 클라우드 적용 전에는 의존성 lock/번들, 실제 부하·장애 복구, 예약/GC worker, quota, 브라우저 CORS 및 Flutter 연동을 별도로 검증해야 한다.
