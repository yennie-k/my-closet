# My Closet Supabase 3차 개발 설계 초안

상태: **검토용 / SQL 미실행 / Flutter 코드·기존 데이터 미변경**. 작성일: 2026-10-27 (Asia/Seoul).

**보완 리뷰 반영:** 사진의 클라이언트 완료 신호/서버 검증 분리, service_role 최소 컬럼 권한, 예약 슬롯·정리 및 CAS 처리의 최신 명세는 [SQL 보완 리뷰](sql-review-20261027.md)를 함께 읽어야 합니다. 아래도 해당 흐름으로 수정했습니다. 기존 초기 CREATE 초안이 이미 적용된 경우에는 별도 ALTER migration 검토가 필요합니다.

사용자가 전달한 프로젝트 조건은 `my-closet`, Seoul 리전, Data API 활성화, 새 테이블 자동 노출 비활성화, 자동 RLS 활성화입니다. 실제 프로젝트 설정이나 기존 원격 테이블·정책은 조회하지 않았습니다. 이 문서는 코드 분석에 따른 제안이며 배포 완료 보고가 아닙니다.

## 결과물과 적용 경계

- [DB SQL 초안](../../supabase/drafts/01_database.draft.sql): 테이블·제약·인덱스·트리거·테이블 RLS·GRANT
- [Storage 정책 SQL 초안](../../supabase/drafts/02_storage_policies.draft.sql): 버킷 사전 조건 확인·객체 RLS
- [보안/이전 테스트 계획](security-test-plan.md): 이후 승인된 staging에서 수행할 테스트

두 SQL은 `supabase/migrations`가 아닌 **`supabase/drafts`**에 두었습니다. CLI 자동 적용 대상으로 승격하거나 실행하는 작업은 이번 범위가 아닙니다. Supabase 연결·SQL 실행·버킷 생성·Auth 설정 변경·패키지 설치를 하지 않았습니다. 기존 README나 Dart 파일도 수정하지 않습니다.

## 1. 실제 모델 분석

읽은 코드: `lib/models/garment.dart`, `lib/models/user_preferences.dart`, `lib/services/preferences_service.dart`, `lib/services/wardrobe_repository.dart`, `lib/services/storage/indexeddb_wardrobe_repository.dart`, `lib/services/garment_photo_service.dart`, 등록 화면과 앱 진입점.

### 의류 모델: 저장 키 22개 전부 매핑

| 현재 JSON 키 | 서버 컬럼 / 타입 | 보존 및 변환 규칙 |
| --- | --- | --- |
| `version` | `model_version smallint` | 서버는 2. 원본 버전은 별도 `source_model_version`에 1 또는 2 |
| `id` | `local_id text` | 로컬 ID 그대로. 서버 PK `id uuid`와 구분 |
| `name` | `name text` | 필수 문자열 |
| `category` | `category text` | enum **이름** tops/bottoms/outerwear/dresses/shoes/bags/accessories/other. 한국어 화면 라벨로 저장하지 않음 |
| `createdAt` | `created_at timestamptz` | 기존 등록 시각 보존, 업로드 시각으로 교체하지 않음 |
| `updatedAt` | `updated_at timestamptz` | 기존 수정 시각 보존, 업로드/전송 재시도로 갱신하지 않음 |
| `subtype` | `subtype text` | 추천 종류 외 사용자 입력·빈 문자열 허용 |
| `primaryColor` | `primary_color text` | 표준/사용자 정의 문자열 그대로 |
| `primaryColorHex` | `primary_color_hex text nullable` | `#RRGGBB` 또는 null. 사용자 색상에 임의 HEX를 추정하지 않음 |
| `additionalColors` | `additional_colors text[]` | 복수 색상·순서·사용자 정의 값 유지 |
| `additionalColorDetails` | `additional_color_details jsonb` | `{name,hex}` 배열 보존. SQL은 배열 형태만 검사하고 어댑터는 각 항목과 색상명 대응을 검증 |
| `seasons` | `seasons text[]` | spring/summer/autumn/winter 복수 선택 |
| `thickness` | `thickness text nullable` | veryThin/thin/medium/thick/veryThick enum 이름 유지 |
| `thicknessLevel` | `thickness_level smallint nullable` | 1~5. 이름과 수치 쌍이 일치하도록 CHECK. 보온성 컬럼으로 취급하지 않음 |
| `styleTags` | `style_tags text[]` | 문자열 목록. 미래 사용자 정의 태그도 잘리지 않도록 DB 추천 enum으로 제한하지 않음 |
| `material` | `material text` | 원본 단일 문자열 유지. 혼방 문자열을 임의 분할하지 않음 |
| `materials` | `materials text[]` | 현재 소재 목록의 기준. 빈 목록도 의미가 있음 |
| `fit` | `fit text` | 현재 추천 밖 기존 핏·사용자 입력·빈 값 유지 |
| `notes` | `notes text` | 줄바꿈 포함 보존 |
| `imageMimeType` | `image_mime_type text` | JPEG/PNG/WebP. 기존 사진은 재인코딩 없이 해당 MIME으로 업로드 |
| `imageWidth` | `image_width integer` | 양의 정수, 원본 저장 이미지의 픽셀 너비 |
| `imageHeight` | `image_height integer` | 양의 정수, 원본 저장 이미지의 픽셀 높이 |

`Garment.newId()`는 16바이트 난수를 32자리 hex 문자열로 만듭니다. UUID 캐스팅으로 대체하면 기존 코드의 ID와 일치하지 않으므로 **서버 UUID를 별도로 둡니다.** 웹의 기존 키는 일반 문자열일 수 있어 `local_id`를 32자리 정규식으로 제한하지 않습니다.

현재 `toJson()`은 HEX를 표준 색상 이름에서 다시 계산합니다. `fromJson()`은 HEX 스냅샷 키를 별도 속성으로 보유하지 않습니다. 따라서 이전기는 **원본 IndexedDB 메타데이터도 읽기 전용으로 함께 확보**해야 합니다. 모델로 읽었다가 `toJson()`만 호출하는 이전은 원래 HEX 스냅샷을 바꿀 수 있습니다. 서버 어댑터는 원본 값이 있으면 그 값을 전송하고, 없는 v1 필드만 현재 규칙으로 보완합니다.

v1 호환 규칙은 기존 Dart와 동일하게 적용합니다. `materials` 키가 없으면 `material` 문자열 전체를 한 항목으로 읽고, `materials: []`가 있으면 빈 목록을 유지합니다. thin/medium/thick은 2/3/4로 보완합니다. 알 수 없는 버전·부정확한 자료형은 조용히 기본값으로 바꾸지 말고 해당 행을 이전 보류합니다. 모든 원본과 사진은 로컬에 남습니다.

### 사용자 설정 모델

| 현재 JSON 키 | `user_preferences` 컬럼 | 값 |
| --- | --- | --- |
| `version` | `model_version` | 1 |
| `design` | `design` | minimal / lovely / modern |
| `styles` | `styles text[]` | 현재 UI: 미니멀·캐주얼·스트릿·페미닌·시크·스포티·빈티지 |
| `temperature` | `temperature` | cold / normal / hot |
| `onboardingComplete` | `onboarding_complete` | boolean. true라면 styles가 하나 이상 |

이 설정에는 현재 날짜 필드가 없습니다. 서버 생성/수정 시각과 revision은 새 동기화 메타데이터입니다. 기존 저장 키 `my_closet.preferences.v1`은 보존합니다. 원본의 알 수 없는 취향을 현재 `fromJson()`이 걸러낼 수 있으므로, 이전 전에 원본 스냅샷과 정규화 결과 차이를 검토합니다.

### 현재 로컬 저장/사진 처리

- IndexedDB `my_closet_wardrobe_v1`, DB 구조 버전 1: `garments` 메타데이터와 `photos` Uint8List가 같은 의류 ID를 키로 사용됩니다.
- 로컬 `save/delete`는 메타데이터와 사진을 하나의 트랜잭션으로 처리합니다. 원격 DB와 Storage 사이에는 이와 같은 단일 트랜잭션이 없으므로 원격 어댑터에 별도 복구 절차가 필요합니다.
- 신규 사진 선택은 JPG/PNG/WebP를 받아 현재 최대 1,600px JPEG, 최대 2MiB로 변환합니다. 선택 원본 15MiB 제한과 **저장/업로드 결과 2MiB 제한**은 구분해야 합니다.
- 기존 바이너리는 재압축하지 않습니다. 2MiB를 넘거나 손상된 과거 사진이 있다면 자동 변환·삭제하지 않고 그 행만 보류해 사용자에게 안내합니다.

## 2. 인증 설계

초기 제안은 이메일/비밀번호 + 이메일 확인 + 비밀번호 재설정입니다. OAuth는 다음 확장으로 두고, 웹 링크 처리는 PKCE와 승인된 redirect URL 목록을 사용합니다. localhost의 고정 개발 포트와 실제 HTTPS 배포 주소를 구분합니다. Auth URL/메일 설정은 승인 후 Dashboard에서 별도 검증합니다. [Auth PKCE 공식 문서](https://supabase.com/docs/guides/auth/sessions/pkce-flow)

- 신원은 Supabase Auth의 서명된 JWT와 `auth.uid()`로 판단합니다. 클라이언트가 보낸 user_id나 user_metadata를 신뢰하지 않습니다.
- `user_preferences.user_id`, `garments.user_id` 모두 `auth.users(id)`의 PK를 참조합니다. `auth` 스키마를 Data API에 노출하거나 앱에 직접 권한을 주지 않습니다. [사용자 테이블 참조 지침](https://supabase.com/docs/guides/auth/managing-user-data)
- 로그아웃 상태는 기존 로컬 모드로 계속 이용할 수 있으나 원격 개인 데이터에는 접근하지 않습니다. Supabase의 anonymous sign-in 기능은 MVP에서 비활성화하고, 정책에도 `is_anonymous=true` JWT를 거부하는 조건을 둡니다.
- 로그인 성공만으로 로컬 데이터를 올리지 않습니다. 계정 식별자를 보여준 뒤 사용자가 이전 대상을 확인하고 명시적으로 시작합니다.
- 로그인 시 서버 설정이 있으면 먼저 읽습니다. 로컬 설정으로 무조건 upsert하지 않습니다. 서로 다르면 선택한 설정만 적용하며 로컬 원본은 남깁니다.
- 사용자 생성 트리거로 설정을 만들지 않습니다. 첫 인증 세션에서 설정 행을 INSERT하고, 중복이면 SELECT합니다. 계정 생성 자체를 앱 설정 트리거 실패와 결합하지 않습니다.
- 브라우저에는 URL과 **publishable key**만 전달합니다. 빌드 환경변수도 웹 번들에 노출된다고 가정합니다. service_role, secret key, DB 비밀번호는 앱/웹/.env 공개 파일에 넣지 않습니다. 현재 단계에서는 어떤 키도 요구하거나 기록하지 않습니다. [API 키 공식 문서](https://supabase.com/docs/guides/getting-started/api-keys)
- 로그아웃/계정 변경 시 원격 목록, 이미지 메모리 캐시, 진행 중 요청을 비우거나 취소합니다. 계정별 이전 journal은 `(project_ref, user_id, local_id)`로 분리합니다. A 계정 로컬 사본을 B에 자동 업로드하지 않습니다. 공유 기기의 **로컬 사본 자체는 자동 삭제되지 않으므로** 로컬 데이터와 계정 데이터가 다름을 UI에 명확히 표시합니다.

## 3. 테이블 구조와 추가 서버 필드

### `public.user_preferences`

사용자당 1행. PK/FK는 user_id. 다섯 모델 필드 외 `created_at`, `updated_at`, `revision`을 서버가 관리합니다. 수정은 예상 revision을 조건으로 보내고 0행 갱신이면 최신 설정을 다시 읽어 충돌을 해결합니다.

### `public.garments`

위 22개 모델 키 매핑 외 아래 필드를 둡니다.

| 컬럼 | 용도 |
| --- | --- |
| `id uuid` | 서버 행 PK. 기본값 gen_random_uuid() |
| `user_id uuid` | 소유자 FK. 기본값 auth.uid(), RLS로 재검증 |
| `local_id text` | 현재 Flutter Garment.id를 보존. UNIQUE(user_id, local_id) |
| `source_model_version smallint` | 최초 가져온 원본 버전 1 또는 2. 가져온 뒤 수정 금지 |
| `photo_state text` | pending / ready. 원격 기본 목록은 ready만 조회 |
| `photo_path text nullable` | 버킷 내부 경로, URL 아님. pending 예약 단계는 null 가능 |
| `photo_sha256 text nullable` | 저장 이미지 바이트의 SHA-256 lowercase hex |
| `photo_size_bytes bigint nullable` | 1~2,097,152 byte |
| `photo_verified_at timestamptz nullable` | 서비스 검증 주체가 실제 파일을 검사한 시각. 클라이언트 수정 불가 |
| `upload_state text` | none/reserved/client_confirmed/checking/failed. 클라이언트는 reserved→client_confirmed만 허용 |
| `upload_path`, `upload_size_bytes`, `upload_expires_at`, `upload_error_code` | 서버가 배정하는 단일 후보 슬롯·예상 크기·만료·오류. 실제 파일 검증 값과 구분 |
| `retired_photo_path`, `retired_cleanup_after` | 교체된 활성 사진을 API로 정리하기 위한 서버 전용 슬롯 |
| `import_fingerprint text nullable` | 최초 이전 스냅샷 식별 해시, 가져온 뒤 변경 금지 |
| `server_created_at`, `server_updated_at` | 서버 수신/수정 시각. 로컬 날짜와 분리 |
| `revision bigint` | 서버 관리 증가 값, 동시 수정 낙관적 잠금 |

명시적 `garments_user_id_idx`와 `(user_id,category,subtype)` 인덱스가 있습니다. UNIQUE(user_id,local_id)도 재시도 조회를 지원합니다. 검색/계층형 필터는 현재의 category/subtype/name을 그대로 사용합니다. 사진 URL, 바이너리, Base64를 garments에 넣지 않습니다.

SQL은 등록 추천을 사용자 정의 문자열의 제약으로 만들지 않습니다. 원본 길이/순서를 임의 절단하거나 추가 색상·소재를 자동 정렬/중복 제거하지 않습니다. 날짜는 시각을 보존하며 원본 ISO 문자열 자체는 로컬 스냅샷에 남깁니다.

## 4. RLS와 GRANT

자동 RLS는 정책을 대신 만들지 않으며, 자동 노출이 꺼진 프로젝트는 RLS와 별도로 명시적 권한이 필요합니다. 이 설계는 public 스키마가 Exposed schemas에 있는 것을 전제로 하므로 실제 설정을 먼저 확인해야 합니다. [공식 GRANT/RLS 설명](https://supabase.com/docs/guides/api/securing-your-api), [자동 테이블 노출 변경 안내](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically)

| 작업 | 두 테이블의 정책 |
| --- | --- |
| SELECT | authenticated, uid 존재, user_id=uid, 익명 Auth 아님 |
| INSERT | 위 소유권 조건을 WITH CHECK로 검사 |
| UPDATE | 기존 행은 USING으로, 변경 후 행은 WITH CHECK로 같은 조건 검사 |
| DELETE | USING으로 본인 행만 허용 |

SQL은 두 테이블의 자동 권한을 PUBLIC/anon/authenticated/service_role에서 먼저 회수하고 필요한 것만 다시 부여합니다. authenticated에 스키마 USAGE, 테이블 SELECT/DELETE, 허용 컬럼의 INSERT/UPDATE만 줍니다. anon에는 개인 테이블 권한을 주지 않습니다. UUID이므로 sequence 권한도 필요 없습니다.

UPDATE에서 user_id, 서버 id, local_id, 등록일, 원본 provenance와 사진 보호 필드를 제외합니다. 클라이언트는 사진 검증 상태를 변경하지 않습니다. revision/서버 시각은 입력·수정 권한 없이 private 스키마의 SECURITY INVOKER 트리거가 관리합니다. 해당 함수는 RPC로 노출하거나 앱 역할에 EXECUTE를 부여하지 않습니다. `GRANT ALL`, 전체 public 테이블/함수에 대한 일괄 GRANT, auth 스키마 GRANT는 없습니다. [컬럼 권한 공식 설명](https://supabase.com/docs/guides/database/postgres/column-level-security)

**PATCH는 변경 가능한 필드만** 보내고 두 테이블 모두 예상 revision을 WHERE에 포함해야 합니다. 0행이면 자기 행 재조회로 충돌/비가시/미적용을 분기하며 자동 덮어쓰지 않습니다. 모델 전체 JSON upsert는 변경 불가 필드 때문에 실패할 수 있습니다. service_role에는 사진 worker용 SELECT/UPDATE 컬럼만 추가하고 설정 접근·의류 INSERT/DELETE·일반 정보 편집은 주지 않습니다. 서비스 키 자체의 Storage 권한은 여전히 강하므로 서버 전용 보관이 필수입니다. 상세 오류/동시성 처리는 보완 리뷰를 따릅니다.

## 5. 비공개 `garment-photos` 버킷

승인 후 Dashboard 또는 신뢰할 수 있는 Storage 관리 API로 다음 설정을 만듭니다. 앱이 버킷을 만들거나 공개로 전환할 권한을 갖지 않게 합니다.

```json
{
  "id": "garment-photos",
  "name": "garment-photos",
  "public": false,
  "file_size_limit": 2097152,
  "allowed_mime_types": ["image/jpeg", "image/png", "image/webp"]
}
```

위 JSON은 설정 명세이며 SDK마다 fileSizeLimit/allowedMimeTypes 등 인자 이름이 다를 수 있습니다. 현재 아무 버킷도 생성하지 않았습니다. SQL 02는 이 설정이 이미 준비되어 있는지 확인하고 다르면 중단하는 초안입니다.

경로는 `<auth user UUID>/<garments.id UUID>/<photo_sha256>.jpg|png|webp`. 로컬 의류 ID와 파일명 사용자 입력은 경로에 삽입하지 않습니다. `photo_path` CHECK는 행 소유자·서버 ID·해시·MIME과 경로의 일치를 검사합니다.

- SELECT: 본인 사용자 폴더의 정상 경로만 조회/다운로드/목록 허용.
- INSERT: 본인 의류의 서버 전용 upload_path와 정확히 일치하고 reserved/미만료/retired 정리 완료인 경우에만 일반 업로드 허용.
- UPDATE: **의도적으로 거부**. Storage upsert=false, 새 사진은 새 해시 경로 업로드 후 메타데이터 교체. 이동·덮어쓰기도 사용하지 않음.
- DELETE: 본인 폴더만. 활성/진행 중 후보/유예 중 retired 참조는 직접 삭제를 막고, 본인 고아는 행 존재 없이 정리할 수 있음.
- restrictive guard로 기존의 광범위 permissive 정책이 나중에 추가되어도 이 버킷의 사용자 경로·금지 작업 조건을 우회하지 못하게 함. 다른 버킷에는 guard를 통과시켜 기존 정책을 따르게 함.

MVP는 인증된 `download`로 바이트를 받아 표시합니다. 공개 URL·signed download/upload URL은 사용하지 않고, operation-aware SELECT guard로 서명 URL 발급 작업도 제외했습니다. SDK의 일반 업로드·목록·메타데이터·삭제 내부 조회를 허용 목록에 포함했습니다. 실제 프로젝트에 해당 helper와 operation 지원이 있는지 staging에서 반드시 확인하며, 없으면 SQL이 중단되도록 했습니다. TUS/S3/복사/이미지 변환은 이번 allowlist 범위 밖입니다. [Storage helper](https://supabase.com/docs/guides/storage/schema/helper-functions), [공식 operation 목록](https://github.com/supabase/storage/blob/master/src/http/routes/operations.ts)

비공개 버킷도 signed URL을 발급하면 URL 보유자가 만료까지 접근할 수 있습니다. 따라서 이 설계에서는 사용자 JWT 방식만 채택합니다. [비공개 버킷 접근 방식](https://supabase.com/docs/guides/storage/buckets/fundamentals)

Supabase 관리 Storage 테이블의 객체 메타데이터를 SQL로 INSERT/DELETE하지 않습니다. 관리 스키마 구조·소유권·전체 GRANT도 바꾸지 않고 정책만 추가합니다. 파일 업로드/삭제/버킷 관리에는 Storage API를 사용합니다. [Storage 스키마 지침](https://supabase.com/docs/guides/storage/schema/design), [버킷 생성 방법](https://supabase.com/docs/guides/storage/buckets/creating-buckets)

DB와 Storage는 원자적이지 않습니다. 클라이언트의 완료 신호는 upload_state=client_confirmed이고 ready가 아닙니다. ready/실제 해시·크기/검증 시각은 서버 전용입니다. worker가 실제 바이트 다운로드·디코딩·해시·크기 비교를 한 후에만 기록해야 하며, 현재 worker는 미구현입니다. SQL 자체는 파일을 검증하지 못하므로 서비스 주체의 진술을 신뢰합니다. 이후 AI 처리 전에도 재검증해야 합니다.

## 6. IndexedDB 이전 프로토콜

### 원칙과 준비

**성공 전·성공 후·재시도·계정 변경 모두 로컬 메타데이터/사진을 자동 삭제하지 않습니다.** 원격 삭제를 원본 로컬 삭제로 연결하지도 않습니다. 로컬 초기화와 클라우드 이전은 별개 사용자 작업입니다.

1. 로그인된 프로젝트/사용자를 고정하고 이전할 의류와 계정 이메일을 보여줍니다. 사용자가 확인하기 전 업로드하지 않습니다.
2. 원본 DB를 읽기 전용으로 열어 garments와 photos의 일관된 스냅샷을 확보합니다. 기존 DB 구조를 바꾸지 않고 별도 export/별도 journal 저장소를 사용합니다.
3. 모델 22개 키, 이미지 디코딩·크기/MIME·SHA-256, ID 연결, 날짜, v1→v2 보완 결과를 검증합니다. 원본 사진을 변환하지 않습니다. 원본 손상/제약 초과 행은 보류하고 원인을 표시합니다.
4. fingerprint는 키 정렬 등 명세가 고정된 canonical JSON의 v2 메타데이터(보존한 로컬 날짜·ID·HEX 포함)와 사진 SHA-256을 함께 해싱합니다. journal에 fingerprint 알고리즘 버전도 저장합니다. 전송 시각·server ID·revision은 입력에서 제외합니다.
5. journal 키는 `(project_ref,user_id,local_id)`이며 server_id, fingerprint, 사진 해시, 상태, 마지막 오류를 담습니다. 사진 Base64를 shared_preferences에 추가하지 않습니다. 이 journal은 기존 garments/photos를 대체하지 않습니다.

### 행별 상태 전이

`로컬 사전 검사 → 행 생성(pending) → 서버 후보 슬롯 배정 → 사진 업로드 → 클라이언트 완료 신호 → 서버 실제 바이트 검사 → 서버 ready CAS → 재조회 확인 → 완료(로컬 유지)`

1. 서버에서 `(user_id,local_id)`를 조회합니다. 없으면 서버 ID 기본 생성으로 pending 행 INSERT. 원본 날짜와 모델 필드, import_fingerprint를 포함하되 사진 검증/예약 컬럼은 클라이언트가 보내지 않습니다. 이후 인증된 서버 예약 endpoint가 예상 사진 해시·크기와 소유권·한도를 확인하고 후보 슬롯을 배정합니다.
2. 네트워크 시간 초과·동시 탭으로 INSERT 결과가 불명확하면 무조건 새 UUID 행을 만들지 말고 같은 유일 키로 다시 조회합니다. UNIQUE(user_id,local_id)가 원자적으로 중복 행을 막습니다. 409 충돌은 기존 행을 읽는 분기로 처리합니다.
3. 기존 행의 fingerprint와 현재 스냅샷이 같고 ready면 이미 완료된 것으로 보고 메타데이터를 덮어쓰지 않습니다. pending이면 실제 필드/사진 상태와 revision도 비교한 뒤 이어 갑니다. fingerprint가 다르거나 서버가 이미 다른 내용으로 수정되어 있으면 자동 upsert하지 않고 충돌로 보류합니다.
4. 이름이 같은 옷은 중복의 근거가 아닙니다. 다른 기기의 동일 local_id인데 내용이 다르면 사용자 검토 후 업로드용 복제 ID를 별도 journal에서 발급하는 선택지를 제공합니다. 원본 IndexedDB ID는 바꾸지 않습니다. 다른 사용자끼리 같은 local_id는 각자의 별도 행으로 허용합니다.
5. 서버가 배정한 정확한 경로에 `upsert:false`로 uploadBinary합니다. 이미 같은 경로가 있으면 자동 덮어쓰지 말고 본인 JWT로 내려받아 SHA-256·크기·MIME을 비교합니다. 이는 클라이언트 검사일 뿐 서버 검증 완료가 아닙니다. 다르면 보류하고, 같으면 upload_state=client_confirmed를 예상 revision 조건으로 PATCH합니다.
6. 별도 서버 worker가 실제 객체를 내려받아 검사한 뒤 id/user_id/revision/upload_path 조건으로 실제 사진 정보와 photo_state=ready를 기록합니다. 클라이언트에는 이 권한이 없습니다. `updated_at`은 원본 그대로이며 server_updated_at/revision만 서버에서 증가합니다. 응답 유실 시 재조회하고 다른 후보에 검사 결과를 재사용하지 않습니다. worker 구현·검증 전에는 이 단계가 가능하다고 주장하지 않습니다.
7. 완료는 서버 필드와 이미지 검증 결과를 모두 재확인한 뒤 표시합니다. 로컬 원본은 유지합니다. 성공 개수뿐 아니라 보류·실패·이미 완료 건수를 구분해 보여줍니다.

### 편집·실패·동시성

- MVP 이전 중에는 해당 옷의 편집을 잠시 막거나, 스냅샷 fingerprint가 달라지면 구 업로드 완료를 현재 편집의 완료로 표시하지 않습니다. 실시간 양방향 오프라인 동기화는 별도 단계입니다.
- 사진 교체는 기존 active 유지 → 서버 단일 후보 배정/업로드/검사 → 서버 CAS로 active 교체와 retired 등록 → API 정리 순서입니다. retired를 정리하기 전 새 후보를 받지 못합니다. CAS 실패 시 새 후보를 자동 적용하지 않습니다.
- 업로드 실패/DB 반영 실패는 pending 또는 고아 원격 객체를 남길 수 있습니다. journal로 재개하며 자동으로 기존 사진을 제거하지 않습니다. 새로 생긴 불필요한 원격 고아만 별도 확인된 정리 절차로 제거합니다.
- 삭제는 사용자 범위의 metadata DELETE CAS가 성공한 후 캡처한 경로를 durable 정리 manifest로 처리합니다. CAS 실패 전에 사진을 지우지 않습니다. DB 삭제는 Storage 파일을 지우지 않으며 원격 정리 중 상태를 재시도 가능하게 유지합니다. 실제 정리에는 Storage API만 사용하고 worker/queue는 아직 미구현입니다.
- 인증 만료 시 작업을 멈추고 재인증합니다. 재개 전 user_id/project_ref가 이전 journal과 같은지 다시 확인합니다.
- 같은 버킷 소유 객체가 있는 Auth 사용자 삭제는 별도 서버 작업으로 설계합니다. Storage API 정리 후 Auth 삭제를 진행하고, 로컬 원본은 지우지 않습니다. DB FK cascade가 물리 Storage 파일을 삭제한다고 가정하지 않습니다.

## 7. 이후 Flutter 연동 시 바꿀 파일 (이번에는 변경하지 않음)

| 기존/신규 파일 | 이후 역할 |
| --- | --- |
| `pubspec.yaml`, `pubspec.lock` | 승인 후 호환 버전의 supabase_flutter 및 필요한 해시 의존성 추가 |
| `lib/main.dart` | URL/publishable key 초기화, 시작 실패 처리 |
| `lib/app.dart` | 인증 상태·계정별 원격 저장소 주입, 기존 로컬 모드 보존 |
| `lib/services/preferences_service.dart` | 인터페이스 유지. 별도 원격 구현체와 충돌 조정 사용 |
| 신규 `lib/services/auth_service.dart`, 인증 화면 | 가입/로그인/확인/재설정/로그아웃 |
| 신규 `lib/services/supabase_preferences_store.dart` | 컬럼 매핑·revision CAS·첫 INSERT와 중복 처리 |
| 신규 `lib/services/storage/supabase_wardrobe_repository.dart` | 기존 WardrobeRepository 구현, ready 조회·JWT 사진 다운로드·부분 PATCH |
| 신규 `lib/services/garment_remote_mapper.dart` | camelCase↔snake_case, Garment.id↔local_id, 별도 서버 envelope |
| 신규 이전 서비스·journal 저장소·검토 화면 | 원본 스냅샷, 해시·예약·재개·중복/충돌 처리·로컬 보존 |
| `lib/services/storage/wardrobe_factory.dart` | 로그인/오프라인 모드에 맞는 구현 선택 |
| `lib/screens/profile_screen.dart` | 계정 및 수동 이전 진입점 |
| `lib/screens/wardrobe_screen.dart` | 원격 로딩/오류·미완료 이전 진행 안내, 필터 UX 유지 |
| `lib/widgets/garment_photo.dart` | 계정 변경/로그아웃 시 원격 사진 캐시 분리 |
| `lib/screens/garment_editor_screen.dart`, 상세 화면 | 원격 부분 실패·revision 충돌·재시도에 맞는 완료 표시 |
| `lib/models/garment.dart` | 22키 v2 직렬화 유지 권장. server UUID/revision 등은 별도 envelope로 보유 |
| IndexedDB 구현 | 기존 save/delete를 이전 과정에서 호출하지 않음. 원본 메타데이터를 손실 없이 읽는 읽기 전용 snapshot 인터페이스 별도 검토 |
| `web/index.html`, 인증 URL 설정 | 배포 origin/CSP/redirect 검증. 기존 Flutter 화면·테마는 유지 |
| 신규 테스트들 | mapper, Auth 상태 변경, RLS/API, 이전 재시도/손상/3벌 보존 |

## 8. 검토가 필요한 결정

1. 이메일/비밀번호 + 확인 메일을 첫 인증 방식으로 채택할지
2. 별도 서버 UUID + 사용자별 local_id 유일 키를 채택할지
3. pending 예약과 ready 공개, 해시 경로/덮어쓰기 금지 방식을 채택할지
4. 사용자 JWT 다운로드만 허용하고 signed URL/TUS/S3는 초기 범위에서 제외할지
5. 2MiB 업로드 상한을 기존 저장 결과 기준으로 유지하고 초과 원본은 보류할지
6. 익명 Auth를 비활성화하고 로그인 상태의 수동 이전만 허용할지

검토 이후 별도 승인된 staging에서 권한·Storage operation 호환성을 실행 검증해야 합니다. 보완 리뷰에서는 오프라인 PostgreSQL/PLpgSQL 파서 구문 검사를 수행하며 별도 보고서에 기록합니다. DB 실행·Auth·RLS·Storage E2E는 계속 미검증입니다. 기존 앱 코드를 바꾸지 않았으므로 Flutter 빌드 결과를 새로 생성하지도 않았습니다.
