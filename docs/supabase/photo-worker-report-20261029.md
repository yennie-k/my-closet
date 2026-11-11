# 사진 검증 worker 구현 및 로컬 검증 — 2026-10-29

`verify-garment-photo` Supabase Edge Function을 구현하고 실제 로컬 Auth·DB·Storage와 연결해 검증했다. 이제 정상 합성 JPG·PNG·WebP는 **실제 파일 읽기, 형식/크기/해시 비교, 픽셀 디코딩**을 거친 경우에만 client_confirmed → checking → ready로 전환된다. 기존 회귀 검사도 유지됐다. 클라우드 연결·SQL 실행·배포는 하지 않았다.

[전체 결과 JSON](photo-worker-results-20261029.json), [함수 사용법·에러 계약](../../supabase/functions/verify-garment-photo/README.md), [이전 로컬 보고서](local-integration-report-20261029.md)를 함께 참고한다.

## 검증 결과

| 검사 | 통과 | 실패 | 실제 검증 범위 |
| --- | ---: | ---: | --- |
| 최종 단위 테스트 | 24 | 0 | 실제 디코더 + 결정적인 충돌/오류 I/O 주입 |
| 최종 Edge HTTP 통합 | 22 | 0 | 실제 함수·JWT·DB·Storage |
| 실제 파일/DB 경쟁 및 lease 복구 | 5 | 0 | 아래의 실행 계층 구분 참고 |
| 실제 worker 사진 교체·실패 보존 | 2 | 0 | 실제 Edge HTTP 및 기존 활성 파일 보존 |
| 기존 DB/Storage SQL 계약 suite | 2 | 0 | 기존 SQL 원본 실행; DB fixture ROLLBACK |
| 기존 RLS 회귀 | 29 | 0 | 새 A/B fixture에 기존 assertion 재사용 |
| 기존 Storage 회귀 | 33 | 0 | 실제 HTTP·정책 상태·승인된 신규 fixture 삭제 |

각 숫자는 이름 붙은 검사 또는 suite 기준이며 내부 assertion을 중복 합산하지 않았다. Edge HTTP 검사는 최종 오류 분류 보완 뒤 새 fixture로 다시 실행했다. 초기 22개 단위 검사에서는 예상하지 않은 실패 13개가 있었고 이를 수정했다. 이 초기 실패를 성공이나 의도한 부정 테스트로 처리하지 않았다.

## 환경과 인증 확인

- 로컬 프로젝트: `<LOCAL_SUPABASE_DIR>`
- API / DB: `http://127.0.0.1:54321` / `127.0.0.1:54322`
- CLI: 2.122.0, Edge Runtime: 1.77.8, 런타임 표시 Deno 호환성: 2.1.4
- PostgreSQL: 17.11, Storage: v1.84.19 — 기존 스택 유지
- Docker context: 로컬 Windows named pipe의 `desktop-linux`
- 원격 연결 표식 및 원격 접속용 환경변수 없음. 함수 실행·HTTP runner 모두 로컬 대상 가드 적용.

`functions serve verify-garment-photo`를 기본 게이트웨이 JWT 검증을 유지한 채 실행했다. **`--no-verify-jwt`는 사용하지 않았다.** 실제 사용자 토큰의 알고리즘은 ES256이었고 정상 요청이 처리됐다. 변조 서명은 게이트웨이가 거절했다. 현재 문서는 사용자 함수에서 기본 검증을 유지하도록 안내하며, 이번 설치 버전에서도 실제 동작을 확인했다. [공식 함수 인증 문서](https://supabase.com/docs/guides/functions/auth)

함수도 매 요청 Auth의 `/auth/v1/user`로 검증한 사용자만 허용한다. 그 후 sub/role/aud/exp 및 비익명 사용자 여부를 검사한다. 단순 JWT 디코딩이나 클라이언트 user_id를 인증 근거로 사용하지 않는다. service_role 토큰을 사용자 신원으로 사용하는 요청도 거절했다.

## 구현 방식

입력은 `garment_id`, `upload_path` 두 필드뿐이다. path는 기대 예약과의 일치 및 재시도 식별자이며 URL·버킷·해시를 클라이언트가 임의 지정하는 통로가 아니다. `garment-photos` 버킷만 고정 사용한다.

1. 사용자 JWT의 RLS 문맥으로 의류를 조회하고 소유권을 확인한다. 없는 의류와 타 사용자 의류는 같은 404 오류다.
2. DB 예약 경로, 예상 크기, 만료, client_confirmed를 확인한다. **예상 SHA는 DB의 upload_path 파일명에 저장된 값**이다. 기존 활성 사진의 photo_sha256는 새 후보의 기대 해시로 사용하지 않는다.
3. id/user_id/revision/경로/상태/유효기간 조건부 UPDATE로 checking을 획득한다. 반환 revision이 이 시도의 fencing token이다.
4. 서버 권한으로 실제 객체를 최대 2 MiB까지만 읽어 DB 예상 길이와 비교하고 SHA-256을 계산한다. 실제 매직 바이트와 확장자를 비교한다.
5. PNG CRC/IEND, JPEG EOI, WebP RIFF 길이를 검사하고 `magick-wasm@0.0.45`로 실제 픽셀을 디코딩한다. 경고·손상·애니메이션 PNG/WebP는 거절한다. WASM·고정 버전의 실제 해시는 JSON 보고서에 남겼다. [Supabase의 WASM 처리 예시](https://supabase.com/docs/guides/functions/examples/image-manipulation), [라이브러리](https://github.com/dlemstra/magick-wasm)
6. 파일을 다시 읽어 길이·해시·ETag·Last-Modified와 존재 여부를 재확인한다. 예약 만료도 다시 검사한다.
7. 처음 획득한 revision·경로·상태가 유지되는 경우에만 ready를 저장한다. 실제 크기/해시/MIME/해상도/검증 시각을 기록하고 후보 슬롯을 비운다. 교체라면 이전 활성 사진을 25시간 retired 유예에 둔다.

관리자 권한은 서버 환경변수로만 공급하며 소유권 확인 이후의 사진 읽기·사진 컬럼 CAS에만 사용한다. **SQL·GRANT·RLS를 수정하거나 권한을 넓히지 않았다.** 기존 service_role 최소 컬럼 권한으로 동작했다. 함수는 파일을 삭제하지 않는다.

## 요구한 부정 테스트와 실제 응답

아래 요청은 거절되는 것이 의도한 결과다. 해당 오류와 후보 비활성화/기존 데이터 보존을 assertion으로 확인했으므로 테스트 결과는 통과다.

| 입력/상황 | 실제 기대 응답 | 상태 확인 |
| --- | --- | --- |
| 정상 JPG / PNG / WebP | 200 ready | 실제 해시·길이·4×3 해상도·검증 시각 저장 |
| 크기 불일치 | 422 size_mismatch | 후보 ready 안 됨, failed |
| SHA-256 불일치 | 422 hash_mismatch | 후보 ready 안 됨, failed |
| JPG 확장자에 PNG 내용 | 422 mime_mismatch | 후보 ready 안 됨, failed |
| 실제 객체 없음 | 404 not_found, retryable=true | pending 유지; 서버 fixture로 객체 도착 후 재검증 성공 |
| 손상 PNG, 해시 자체는 일치 | 422 invalid_image | CRC/구조 검사에서 차단 |
| 타 사용자 의류 | 404 not_found_or_not_owned | 다른 사용자 사진 읽기/변경 없음 |
| 미로그인·JWT 변조·서비스 토큰 | 401 계열 | 사용자 인증 단계 차단 |
| 만료된 예약 | 409 expired | pending 유지 |
| client_confirmed 생략 | 409 client_confirmation_required | reserved 유지 |
| DB와 다른 예약 경로 | 409 reservation_mismatch | 기존 후보 유지 |
| 클라이언트 ready 직접 PATCH | 403 / SQLSTATE 42501 | 기존 최소 GRANT 유지 |
| 완료된 같은 요청 재전송 | 200 already_verified=true | revision 증가 없음 |
| 동일 사진 8개 동시 Edge 요청 | 200 또는 409 in_progress/conflict | checking 획득+ready 커밋의 revision 증가가 총 2회뿐 |

완료된 중복 요청은 **기존 verified_at의 attestation을 반환**하며 파일을 새로 검증했다는 의미가 아니다. API 응답에 already_verified를 명시한다.

## 동시성·장애 검증의 실행 계층

실제 Edge HTTP에서 병렬 요청, 새 checking lease의 충돌, **실제 60초 이상 경과한 lease의 재획득**을 검증했다. 단위 테스트는 중단된 이전 worker가 뒤늦게 완료되더라도 takeover 이후 커밋하지 못함을 결정적으로 검증했다.

파일 변경·삭제·예약 변경·메타데이터 변경 네 경우에는 프로덕션의 core/adapter/동일 WASM 디코더를 Node에서 실행하고 **실제 로컬 DB·Storage HTTP**를 연결했다. 디코딩 직후의 테스트 경계에만 변경을 주입해 경쟁을 재현했다. Edge endpoint에 디버그 경로나 대기 hook은 추가하지 않았다. 이 네 검사는 실제 backend 통합이지만 HTTP로 호출한 Edge isolate 내부의 결정적 중단을 재현한 검사는 아니다.

- 실제 객체 교체: 두 번째 읽기에서 object_changed, 후보 ready 안 됨.
- 실제 객체 삭제: not_found, 후보 ready 안 됨. 삭제 파일은 이 검사에서 새로 만든 합성 파일 1개뿐.
- 예약 교체: 기존 slot 해제와 새 예약 후 이전 worker는 revision_conflict; 새 reserved 상태 보존.
- 일반 메타데이터 동시 편집: revision_conflict; 편집값 보존.
- 실제 worker 정상 교체: 새 MIME·해시 저장 및 이전 검증 사진의 파일/유예 유지.
- 실제 worker 교체 실패: 이전 활성 사진의 ready/path/hash/size/verified_at/MIME 모두 유지, 실패한 후보는 활성화되지 않음.

일시 장애는 획득한 revision에서만 client_confirmed로 해제한다. 해제도 DB 장애로 실패하면 checking lease를 남기고 만료 후 재호출로 복구한다. 같은 terminal 실패의 재호출은 재다운로드·revision 증가 없이 같은 오류를 반환한다. 서버 권한/제약 설정 오류는 retryable=false로 구분했다. **자율적인 durable job 재실행 큐를 구현한 것은 아니다.**

## 회귀 검사와 기존 데이터 보존

기존 29/33개 assertion을 원본 파일 수정 없이 새 실행용 사본에서 재사용했다. run ID·작업 경로·control 버킷/정책명·import 경로를 분리했고, 빈 DB를 가정하던 두 개의 fixture count만 **새 A/B 사용자 범위**로 바꿨다. 실제 RLS·권한·HTTP assertion을 완화하지 않았다. 원본 SQL 계약 두 개도 그대로 실행했다. 변경 내역과 원본 해시는 JSON의 source_adaptations에 있다.

이전 실행의 의류 **6행**, 설정 **1행**, 사진 **2개**가 모두 동일함을 확인했다. 의류와 설정은 모든 저장 필드의 snapshot을 비교했고 사진은 실제 다운로드한 바이너리 SHA-256을 비교했다. Flutter 코드·기존 테스트·SQL·의존성·로컬 config 등 기존 보호 파일 **50개**의 해시도 동일했다. IndexedDB나 실제 사용자 사진에는 접근하지 않았다.

작업 전 현재 DB의 `before-worker.dump`, 기존 합성 사진 두 개의 바이너리 및 backup manifest를 `build/supabase-local/20261029-worker-2`에 보관했다. `pg_restore --list`는 통과했지만 실제 restore는 하지 않았다. 새 private JWT 실행 파일과 백업은 Git에서 무시되는 build에만 있고 소스/보고서에 키를 기록하거나 커밋하지 않았다.

## 발견·수정한 문제

1. **새 setup 스크립트 오류:** 여러 줄 JSON을 기존 단일 행 helper로 읽어 파싱이 실패했다. DB/사진 변경 전에 중단됐고, 전체 JSON 파싱으로 수정했다. worker-1 실패 폴더를 삭제하지 않고 worker-2에서 진행했다.
2. **디코더 호출 오류:** 0.0.45의 getPixels는 callback 방식이다. 호출을 수정했다.
3. **디코더 목록 제한 오류:** listLength=1은 내부 임시 이미지 때문에 정상 정적 이미지도 거절했다. 4로 변경하고 별도의 정적 컨테이너 검사와 화소/메모리 제한을 유지했다. 초기 단위 13개 실패 원인을 수정한 뒤 최종 24개가 통과했다.
4. **재시도 분류:** 권한/제약 설정 오류를 일반 DB 장애와 구분해 retryable=false로 처리했다. 디코더 초기화 Promise가 일시 실패하면 캐시를 해제해 다음 호출에서 재시도할 수 있게 했다.
5. **도구 환경:** sandbox의 npm DNS 및 CLI telemetry 파일 접근 제한으로 최초 호출이 실패했다. 승인된 도구 접근으로 재실행했다. 시스템 패키지 설치·Flutter 의존성 변경은 하지 않았다.

원본 SQL/Storage helper·GRANT·RLS의 신규 오류나 취약점은 이번 테스트에서 재현되지 않았다. 관리자 키를 보유한 임의 코드의 악용까지 방어됐다고 주장하지 않는다.

## 추가한 파일

- `supabase/functions/verify-garment-photo/index.ts`: Edge 진입점, 인증·입력·응답.
- `adapter.ts`: Auth/RLS 조회·최소 컬럼 CAS·제한된 Storage 읽기.
- `core.ts`: 검증·상태·lease·멱등성·실패 처리.
- `image.ts`: 제한된 실제 WASM 디코딩.
- `deno.json`, `README.md`: 함수 설정·사용 계약.
- `supabase/tests/photo_worker.test.ts`: 24개 단위 검사.
- `supabase/local/worker-setup.mjs`, `worker-sync.mjs`, `worker-serve.mjs`: 백업·해시 기반 로컬 동기화·서빙.
- `worker-http-test.mjs`, `worker-race-test.mjs`, `worker-replacement-test.mjs`, `worker-regression.mjs`, `worker-report.mjs`: 실행·회귀·결과 수집.
- `docs/supabase/photo-worker-report-20261029.md`, `photo-worker-results-20261029.json`: 보고서.

로컬 Supabase 폴더에는 새 함수의 실행 소스 5개만 추가·갱신했다. 수정 전 worker 코드도 build 안에 보관했다. 기존 로컬 config 및 SQL 원본은 수정하지 않았다. 실제 클라우드 migration 또는 function 배포 파일로 승격하지 않았다.

## 실행 방법과 종료 상태

로컬 서빙 프로세스는 실행 상태로 두었다. 이미 실행 중이면 중복 시작하지 않는다. 재기동할 때는 프로젝트 루트에서 `node supabase/local/worker-serve.mjs`를 사용한다. 이 스크립트는 검증된 로컬 프로젝트에서만 CLI의 functions serve를 호출한다. 단위 테스트 명령은 다음과 같다.

```powershell
node --experimental-strip-types --test supabase/tests/photo_worker.test.ts
```

초기화하지 않고 새 run ID를 준비해야 통합 runner를 재실행할 수 있다. 현재 fixture는 모두 합성이며 최종 DB에는 Auth **8명**, 의류 **42행**, 설정 **2행**, Storage 객체 **35개**, 버킷 **3개**가 있다. 이전 데이터와 이번 실행 자료를 추가 정리하지 않았다. 정리는 명시적 run별 manifest와 소유권을 확인한 별도 작업으로 수행해야 한다.

## 클라우드 적용 전 남은 작업

- 검증은 마지막 파일 읽기와 DB CAS의 **시점 attestation**이다. Storage와 PostgreSQL 사이에는 원자적 트랜잭션이 없어, 관리자 권한으로 마지막 읽기 이후 파일을 변경·삭제하는 경우까지 막지는 못한다. 일반 클라이언트는 테스트한 RLS로 차단된다. 미래 관리자 upload/GC는 lease·참조 검사에 참여해야 한다.
- 예약 발급 endpoint, durable job/watchdog, 자동 고아/retired 정리, 계정 quota·rate limit은 미구현이다.
- 한 변 4096px·400만 화소·2 MiB·정적 JPG/PNG/WebP만 지원한다. 이번 합성 이미지는 작으며 대형 이미지 성능·메모리·고부하 벤치마크는 하지 않았다. 기존 로컬 원본을 자동 변환/삭제하지 않는다.
- 실제 Edge 프로세스를 강제 종료하거나 서버 전체가 재시작되는 장애, 장기 네트워크 응답 유실·정리 경쟁은 미검증이다. 결정적인 시뮬레이션과 실제 시간 lease 복구가 durable 큐 검증을 대신하지 않는다.
- 의존성 lock/번들 무결성 고정, 클라우드 버전·자동 노출 비활성 설정·환경변수와 별도 staging 검증이 필요하다. 현재 함수는 npm 버전을 고정했으며 배포 lock 작업은 남아 있다.
- Flutter 호출·브라우저 CORS·충돌 UI·IndexedDB 이전·백업 실제 복원은 이번 범위에 포함하지 않았다. Flutter analyze/test/build도 앱 변경이 없어 실행하지 않았다.

이 결과는 로컬 서버 검증 완료의 증거이며 클라우드 배포 승인을 의미하지 않는다. 클라우드 적용은 후속 검토·승인 후 별도 수행해야 한다.
