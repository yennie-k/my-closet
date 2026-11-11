# 서버 사진 없는 등록 검증 수정 — 2026-11-02

## 확인한 원인과 확인 범위

사용자가 받은 `의류 이름, 카테고리, 사진과 입력한 값을 확인해 주세요.`는 DB/Storage 오류가 아니라 `GarmentEditorScreen._save()`의 **로컬 모드 공통 검증 문구**였다. 기존 코드는 다음 두 상황을 한 조건/문구로 합쳤다.

1. 이름·카테고리·추가 색상 등 Form 검증 실패
2. 사진 필수 모드에서 사진 없음

사진 필수 여부는 저장소의 기능이 아니라 생성자 `metadataOnly` 플래그로 판단했고 기본값은 false였다. 따라서 서버 저장소를 넘겨도 어느 호출 지점에서 플래그를 생략하면 로컬 사진 필수 검증으로 돌아갔다. **이름과 카테고리를 정상 입력한 상태에서 플래그만 생략한 재현 테스트가 수정 전 동일한 문구로 실패**했다. 수정 후 같은 테스트가 통과했다.

한편 점검 당시 소스의 정상 서버 경로는 플래그를 true로 전달하고 있었고, 실제 실행 중인 8081 Flutter 프로세스/HTTP 서버는 없었다. 사용자가 당시 어떤 경로·빌드·입력값을 사용했는지까지 확정한 것은 아니다. 특히 로그인 후 기본 ‘내 옷장’을 열면 의도적으로 IndexedDB 옷장이므로 사진이 필요하다. 이 경로를 서버 옷장으로 오인한 경우까지 사진 검증을 우회시키지 않았다.

## 최소 수정

- `MetadataOnlyWardrobeRepository` 기능 표식을 추가하고 Supabase 구현체가 이를 선언하도록 했다.
- 목록·등록·상세 화면은 저장소에서 사진 정책을 판단한다. 중복된 화면 플래그와 전달 코드를 제거했으므로 등록/수정 호출에서 플래그가 빠져 정책이 달라질 수 없다.
- 로컬 IndexedDB/파일 저장소는 이 표식을 구현하지 않아 기존 사진 필수 정책을 유지한다. 로컬 폼에는 `이 기기 옷장 · 사진 필수` 안내도 표시한다.
- `FormState.validateGranularly()`로 실제 검증 메시지를 모아 표시한다. 예를 들어 이름 누락, 카테고리 누락, 대표 색상과 같은 추가 색상 입력, 로컬 사진 누락을 구분한다. 이름과 카테고리가 정상인데 색상 입력만 잘못된 경우 사진이나 이름 오류라고 표시하지 않는다.
- INSERT/UPDATE/DELETE payload와 기존 저장 모델은 변경하지 않았다. 사진 없는 신규 행은 기존 SQL 기본값 `photo_state=pending`, `upload_state=none`, 사진 경로/해시/크기/검증 시각 null을 사용한다. 새 사진 메타데이터 자리 값에 관한 기존 1×1 계약도 그대로다.

수정 파일:

- `lib/services/revisioned_wardrobe_repository.dart`
- `lib/services/supabase_wardrobe_repository.dart` — 기능 표식 선언만 변경
- `lib/screens/wardrobe_screen.dart`
- `lib/screens/garment_editor_screen.dart`
- `lib/screens/garment_detail_screen.dart`
- `lib/screens/server_wardrobe_screen.dart` — 불필요해진 플래그 전달 제거
- `test/server_wardrobe_test.dart` — 기존 테스트 조정 및 회귀 4건 추가

SQL·RLS·Storage 정책·사진 worker·인증 구현·모델 직렬화·IndexedDB 구현·기기 설정은 수정하지 않았다. 기존 미커밋 변경은 보존했으며 commit/push를 하지 않았다.

## 최종 검증

| 검사 | 통과 | 실패 |
| --- | ---: | ---: |
| 전체 `flutter test` (`scripts/test.ps1`) | 75 | 0 |
| 실제 Supabase 저장소 CRUD/RLS 회귀 | 19 | 0 |
| 실제 인증 API 회귀 | 7 | 0 |
| production Flutter + Chrome CRUD | 19 | 0 |
| 기존 IndexedDB 브라우저 회귀 | 성공 | 0 |
| `flutter analyze` | 성공 | 0 이슈 |
| 기본 웹 빌드 / CRUD 개발 웹 빌드 | 모두 성공 | 0 |

새 위젯 회귀 4건은 플래그 없는 서버 저장소의 사진 없는 등록→상세→수정→삭제, 이름/카테고리별 구체적 오류, 추가 색상 오류 구분, 로컬 사진 필수 및 사진 선택 후 정상 저장을 확인한다. 수정 전 재현 1건의 실패는 의도한 실패로 별도 기록했으며 최종 통과 개수에 합치지 않았다.

실제 저장소 회귀에서는 사진 없는 pending 계약과 전체 v2 필드, CAS/동시 수정, 중복/응답 유실, 타 사용자·anon CRUD 차단을 확인했다. 인증 API는 새 합성 A 계정의 로그인·잘못된 비밀번호·ES256·Auth 사용자 확인·로그아웃·refresh 거절·약한 비밀번호 거절을 확인했다. Chrome은 새 임시 프로필의 localhost:8081에서 사진 없는 CRUD·로그인/계정 전환·새로고침·충돌·네트워크 복구를 확인했다.

[검사별 결과 및 보존 비교 JSON](photo-policy-fix-results-20261102.json)에 근거를 남겼다. 실제 모바일 기기와 기존 worker/Storage 전체 suite를 이번에 재실행한 것은 아니다.

## 데이터 보존

이번 점검 시작의 기존 의류 60건, 사용자 설정 2건, Storage 객체 35건/버킷 3개, Auth 사용자 15명은 행 digest가 모두 동일했다. 새 합성 사용자 2명과 검사 후 남은 합성 의류 4건만 추가되었다. 기존 DB를 초기화하거나 기존 행을 수정/삭제하지 않았다.

실제 Chrome 8080 프로필/옷/사진을 열지 않았다. 브라우저 보존 검사는 격리된 8081의 합성 데이터로 했으며, 기존 Storage 파일 바이트를 내려받아 비교한 것은 아니다. Storage 쓰기/삭제와 실제 사용자 사진 사용은 하지 않았다.

## 재실행

기존 개발 실행을 종료한 뒤 다음 명령으로 새 코드를 실행하고 8081을 새로고침한다. 브라우저 저장 데이터 삭제나 `flutter clean`은 필요하지 않다.

```powershell
flutter run -d chrome --web-hostname=localhost --web-port=8081 --dart-define-from-file=config/supabase.crud.local.json
```

로그인 후 **마이페이지 → 서버 개발 옷장 열기**로 이동한다. 이 화면에서는 사진 선택 없이 이름·카테고리로 등록할 수 있다. 기본 ‘내 옷장’ 메뉴는 계속 로컬 옷장이므로 사진이 필수다. 사진·예약이 이미 연결된 서버 의류의 삭제 제한은 기존 단계와 동일하게 유지한다.
