# My Closet

기존 Flutter 프로젝트에 온보딩과 디지털 옷장 MVP를 구현했습니다. 한국어 UI, Material 3 테마, PC/모바일 반응형 레이아웃을 지원합니다.

## 실행

검증 환경: Windows / Flutter 3.47.8 / Dart 3.13.7 / Chrome.

```powershell
flutter pub get
flutter run -d chrome --web-port 8080
```

브라우저 저장소는 origin(프로토콜·호스트·포트)별로 분리됩니다. 개발 중 등록한 옷을 계속 보려면 같은 주소와 포트를 사용해 주세요.

```powershell
flutter build web
```

빌드 결과는 `build/web`에 생성됩니다.

## 유지한 1차 기능

- 환영 → 앱 디자인 → 패션 취향 복수 선택 → 체감온도 → 확인·저장의 온보딩
- 미니멀(아이보리·베이지), 러블리(핑크·파스텔), 모던(블랙·화이트) 전역 테마
- 마이페이지 설정 수정·저장·취소, 재실행 시 온보딩 생략
- 5개 메뉴: 홈 / 내 옷장 / 코디 추천 / 코디 기록 / 마이페이지
- 너비 900px 미만 하단 메뉴, 900px 이상 사이드 메뉴
- 기존 `my_closet.preferences.v1` 설정 키와 JSON 형식을 변경하지 않았습니다.

## 2차 디지털 옷장

- 등록된 사진 카드 그리드와 전체 개수, 검색 결과 개수
- 대분류 → 소분류의 2단계 필터와 이름 검색(앞뒤 공백 무시, 영문 대소문자 무시), 세 조건 동시 적용
- 처음 등록을 안내하는 빈 화면, 검색 결과가 없는 화면, 로딩·실패·재시도 화면
- 의류 등록, 상세 보기, 정보·사진 수정, 확인 창을 거치는 삭제
- 필수: 이름, 카테고리, 사진
- 선택: 세부 종류, 대표·추가 색상, 계절 복수 선택, 두께, 스타일 태그 복수 선택, 소재, 핏, 메모
- 고유 ID, UTC 등록일·수정일, 이미지 MIME·해상도 저장
- 사진 선택 취소 시 기존 사진 유지, 변경 및 삭제 지원. 사진은 필수이므로 삭제 후에는 새 사진을 선택해야 저장할 수 있습니다.
- 저장 실패 시 폼과 기존 저장 데이터 유지, 삭제 실패 시 목록 데이터 유지
- 모바일 홈의 스타일 프로필 카드를 콘텐츠 전체 너비로 확장하고 세 항목을 세로로 배치. PC의 가로 배치는 유지

### 사진 처리

`file_selector`로 파일을 선택합니다. 확장자와 실제 디코더를 모두 검사하며 JPG/JPEG, PNG, WebP만 받습니다.

- 원본 최대 15MiB, 최대 2,400만 화소, 한 변 최대 12,000px
- 디코딩 전 헤더에서 해상도를 확인하여 과도한 이미지 메모리 사용 제한
- 첫 프레임만 사용하고 EXIF 방향을 적용
- 긴 변 최대 1,600px로 비율 유지 축소
- 투명 배경을 흰색으로 합성하고 JPEG 품질 85로 변환, 필요 시 품질 65로 재압축
- 저장할 사진 최대 2MiB, 출력물에는 원본 EXIF 위치 정보 등을 복사하지 않음
- `compute`로 네이티브에서는 별도 isolate 처리. 웹에서는 메인 스레드에서 처리되므로 큰 사진 처리 시 잠시 반응이 느려질 수 있음
- 이미지 읽기·디코딩 실패 시 대체 UI 표시 및 사진 재선택 안내

AI 이미지 분석은 구현하지 않았습니다. `GarmentPhotoService`와 `normalizeGarmentPhoto`를 저장소와 분리하여 향후 분석 서비스에 정규화된 바이트를 전달할 수 있습니다.

## 데이터 저장

### 사용자 설정

기존 `shared_preferences` / `SharedPreferencesAsync` 저장을 그대로 유지합니다. **사진이나 의류 목록은 여기에 저장하지 않습니다.**

### 웹

`idb_shim`의 실제 브라우저 IndexedDB 구현을 사용합니다. 메모리 저장소로 조용히 대체하지 않습니다.

- DB: `my_closet_wardrobe_v1`, 버전 1
- `garments`: ID를 키로 하는 JSON 호환 의류 메타데이터
- `photos`: 동일 ID를 키로 하는 `Uint8List` 이미지 바이너리
- 사진·정보 저장 및 삭제는 두 object store를 묶은 단일 read/write 트랜잭션으로 수행
- 요청 성공뿐 아니라 트랜잭션 커밋 완료까지 기다린 후 UI에 저장 성공 반영
- 정보만 수정할 때는 기존 이미지 바이트 유지
- 목록에서는 메타데이터만 읽고, 사진은 보이는 카드에서 로드. 리스트는 SliverGrid로 구성
- Blob URL이나 Base64 문자열을 영속 저장하지 않음

브라우저의 저장 차단·용량 초과·손상된 정보에 대한 오류를 안내합니다. 저장 차단 시 임시 메모리 저장을 성공처럼 표시하지 않습니다. 손상된 정보는 임의로 삭제하지 않습니다.

### Android/iOS 및 네이티브

조건부 import로 `dart:io` 기반 `FileWardrobeRepository`를 선택합니다. `path_provider`의 앱 지원 디렉터리 아래 `wardrobe_v1/`에 옷 한 벌당 파일을 저장합니다.

- 파일: `<id>.closet`
- 구조: 4바이트 헤더 길이 + UTF-8 JSON 메타데이터 + 원시 이미지 바이트
- 임시 파일에 flush한 뒤 대상 파일명으로 교체하므로 기록 중인 파일을 바로 목록에 노출하지 않음
- 사진과 정보는 한 파일에 함께 존재하며 삭제 시 함께 삭제
- 입력 ID를 검증하며 `.tmp` 파일은 목록에서 제외

파일 저장 구현은 Windows의 실제 임시 디렉터리로 읽기·재열기·덮어쓰기·삭제를 검증했습니다. Android/iOS 빌드, 파일 선택기 권한 및 실기기 동작은 이번 환경에서 검증하지 않았습니다. 현재 프로젝트에는 iOS 플랫폼 디렉터리가 없으므로 iOS 확장 시 별도 플랫폼 설정이 필요합니다.

### 향후 Supabase 전환

`WardrobeRepository`는 `list`, `readImage`, `save`, `delete`, `close`를 정의합니다. UI는 이 인터페이스만 사용하며 앱에서 구현체를 주입합니다. Supabase 구현체에서 메타데이터를 Database, 사진을 Storage로 연결할 수 있습니다. 원격 Storage 업로드와 DB 변경의 실패 보상·동기화 정책은 해당 단계에서 구현해야 합니다.

## 의존성 호환성

현재 SDK의 `flutter pub add` 의존성 해석, 분석 및 웹 빌드로 호환성을 확인했습니다.

| 추가 패키지 | 사용 버전 | 용도 / 공식 문서 |
| --- | --- | --- |
| file_selector | 1.1.0 | [기기 파일 선택](https://pub.dev/packages/file_selector), Dart 3.9+ / Flutter 3.35+ |
| image | 4.12.0 | [이미지 디코딩·방향·축소·JPEG 인코딩](https://pub.dev/packages/image), Dart 3.0+ |
| idb_shim | 2.11.1 | [IndexedDB 바이너리·트랜잭션](https://pub.dev/packages/idb_shim), Dart 3.12+ |
| path_provider | 2.1.6 | [네이티브 앱 지원 디렉터리](https://pub.dev/packages/path_provider), Dart 3.11+ / Flutter 3.41+ |

별도 상태관리 패키지는 추가하지 않았습니다.

## 2차 변경 파일

| 파일 | 변경 내용 |
| --- | --- |
| `lib/app.dart` | 옷장 저장소·사진 서비스 주입 및 소유 저장소 정리 |
| `lib/models/garment.dart` | 의류·카테고리·계절·두께 모델, ID 및 검색·필터 |
| `lib/screens/app_shell.dart` | 내 옷장 실제 화면 연결, 옷장 자체 스크롤 사용 |
| `lib/screens/home_screen.dart` | 옷장 준비 중 문구 교체, 모바일 프로필 카드 너비 개선 |
| `lib/screens/wardrobe_screen.dart` | 반응형 목록·카운트·검색·필터·빈 상태·오류 |
| `lib/screens/garment_editor_screen.dart` | 필수/선택 필드 및 사진 등록·수정 폼 |
| `lib/screens/garment_detail_screen.dart` | 상세 정보·수정·삭제 확인 |
| `lib/widgets/garment_photo.dart` | 비동기 이미지 로딩·사진 오류 UI |
| `lib/services/garment_photo_service.dart` | 파일 선택과 이미지 검증·정규화 |
| `lib/services/wardrobe_repository.dart` | 저장 인터페이스·오류 메시지 |
| `lib/services/storage/wardrobe_factory.dart` | 플랫폼별 저장소 선택 |
| `lib/services/storage/wardrobe_web.dart` | 실제 IndexedDB 팩토리 |
| `lib/services/storage/indexeddb_wardrobe_repository.dart` | 웹 트랜잭션 CRUD |
| `lib/services/storage/wardrobe_io.dart` | 네이티브 파일 저장 구현 |
| `lib/services/storage/wardrobe_stub.dart` | 미지원 플랫폼 처리 |
| `test/garment_test.dart` | 모델 직렬화·검색·필터 |
| `test/photo_service_test.dart` | JPG/PNG/WebP, 크기 축소, 잘못된 사진 검증 |
| `test/wardrobe_repository_test.dart` | 트랜잭션 계약·롤백·파일 영속 저장 |
| `test/wardrobe_widget_test.dart` | 등록·수정·삭제·실패 처리·모바일/PC·홈 카드 |
| `test/support/wardrobe_fakes.dart` | 테스트 저장소·사진 선택 대역 |
| `test/widget_test.dart` | 기존 온보딩·설정 회귀 테스트에 옷장 연결 반영 |
| `tool/browser_storage_probe.dart` | 실제 IndexedDB 저장소를 사용하는 브라우저 새로고침 검증 |
| `scripts/browser_storage_test.ps1`, `.cjs` | 프로브 컴파일·독립 Chrome 실행·새로고침·결과 확인 |
| `pubspec.yaml`, `pubspec.lock`, `README.md` | 의존성 및 구현/검증 문서 |

## 검증 방법

```powershell
flutter analyze
flutter test
flutter build web
```

이 Windows 환경에서는 사용자 기본 임시 경로에서 Flutter 테스트 엔진이 `Could not prepare isolate`로 시작되지 않는 현상이 있어 1차 개발에서 만든 도우미를 사용했습니다. 프로세스 내 TEMP/TMP만 프로젝트의 `build/test_temp`로 바꾸고, 실행 후 복원합니다.

```powershell
.\scripts\test.ps1
```

실제 브라우저 저장소 및 페이지 새로고침 검증(Chrome과 Node.js 필요):

```powershell
.\scripts\browser_storage_test.ps1
```

이 스크립트는 전용 Chrome 프로필과 별도 테스트 DB를 사용합니다. 앱과 동일한 `IndexedDbWardrobeRepository`를 실행합니다. 현재 프로브는 구버전 메타데이터와 사진을 저장하고, **실제 Page.reload 두 번**을 거쳐 구버전 읽기·새 형식 수정·사진 보존·삭제를 확인합니다. 테스트 프로필은 무시되는 `build/storage_probe` 아래에 남습니다.

Flutter의 Chrome 테스트 러너는 이 환경에서 CanvasKit 404 및 중첩 테스트 경로 오류로 시작되지 않아, 위 독립 프로브로 저장소를 검증했습니다.

### 2026-10-26 검증 결과

- `flutter analyze`: No issues found
- `scripts/test.ps1` → `flutter test`: **20개 통과** (기존 6개 포함)
- `flutter build web`: 성공
- Chrome 실제 IndexedDB 프로브: **WRITE_OK → 실제 페이지 새로고침 → READ_AFTER_RELOAD_OK; UPDATE_OK; DELETE_OK**
- 360px/1440px 위젯 테스트: 사진 등록 대역, 모든 정보 저장, 필수값 검증, 사진 취소·변경·삭제, 저장 실패 후 재시도, 수정, 삭제 취소·실패·성공
- 기존 온보딩·테마·로컬 설정 서비스 경계 테스트 유지

### 검증하지 않은 범위 및 제약

- 실제 OS 파일 선택 창의 클릭·권한 흐름, Android/iOS/Safari 실기기. 사진 선택 UI 테스트는 대역을 사용하고 실제 이미지 처리 함수는 별도로 검증했습니다.
- 새로고침 검증은 실제 저장소를 쓰는 독립 프로브입니다. 배포된 앱 전체에서 파일 선택부터 새로고침까지 이어지는 UI E2E 검증은 아닙니다.
- 실제 디스크/브라우저 용량을 가득 채우는 테스트. 실패 UI와 용량 오류 메시지는 대역으로 검증했습니다.
- 브라우저 데이터 삭제, 시크릿 모드 종료, 저장소 정리 정책에 따른 데이터 제거는 막을 수 없습니다. 자동 백업·내보내기·기기 간 동기화는 없습니다.
- 여러 탭의 동시 편집 충돌 해결 및 실시간 동기화는 없습니다. 브라우저를 새로고침하면 저장된 데이터를 다시 읽습니다.
- 날씨 API, AI 코디 추천, 코디 기록, 로그인, Supabase는 이번 범위에 포함하지 않았습니다.

## 디지털 옷장 입력 UX 개선 (2026-10-27)

### 입력 화면

- 세부 종류: 요청된 카테고리별 추천을 칩으로 제공하고 직접 입력도 지원합니다. 카테고리 변경 시 추천만 바뀌며 기존 텍스트는 유지합니다. 기타 카테고리는 직접 입력을 사용합니다.
- 색상: 대표/추가 색상에 동일한 15색 원형 팔레트를 사용합니다. 대표는 단일, 추가는 복수 선택이며 체크·테두리·색상명·선택됨 텍스트로 상태를 표시합니다. 추가 색상에서 대표 색상은 선택할 수 없고, 직접 입력 중복도 검사합니다. 대표 색상 변경 시 같은 추가 색상은 제외합니다.
- 사용자 정의 색상: 이름 직접 입력과 추가/해제를 지원합니다. 표준 색상만 HEX를 연결하며 사용자 정의 이름은 그대로 유지하고 HEX는 null로 둡니다. 임의로 유사 색상을 추정하지 않습니다.
- 소재: 18종의 설명·직접 그린 질감 패턴·복수 선택을 제공합니다. 혼방 비율 등은 한 항목의 사용자 정의 문자열로 추가할 수 있습니다. 기존 소재 문자열도 선택된 항목으로 표시합니다.
- 핏: 카테고리별 우선순위와 상의/하의/원피스 실루엣을 제공합니다. 그림 카드를 눌러 단일 선택하거나 직접 입력할 수 있습니다. 카테고리 변경 시 기존 핏 값은 유지합니다.
- 두께: 1~5단계 명칭과 예시를 표시합니다. 보온성과는 별개임을 화면에 설명하고 보온성 값으로 변환하지 않습니다.
- 선택지는 접을 수 있는 섹션으로 구성합니다. 선택 내용은 섹션 요약에도 표시하며, 색상·소재의 직접 입력은 추가 버튼 또는 최종 저장 시 반영합니다.
- 모든 그림은 Flutter CustomPainter로 직접 작성했습니다. 외부 사진·SVG·원단 이미지 다운로드 없이 동작하며, 실제 원단/착용 사진이 아닌 참고 일러스트임을 명시합니다. 같은 패턴을 사용하는 소재도 있으므로 설명 텍스트를 우선 참고해야 합니다.
- 모바일 터치 영역과 글자 확대를 고려했습니다. 기본 테마 3종 및 360px/1440px 화면 테스트를 유지합니다.

### 모델 버전 2와 비파괴적 호환 처리

**IndexedDB 이름·DB 버전·object store·기존 키는 그대로 유지합니다. 앱 시작 시 일괄 마이그레이션이나 데이터 덮어쓰기를 수행하지 않습니다.**

| 필드 | 버전 2 처리 |
| --- | --- |
| `version` | 의류 메타데이터 버전 2. DB의 구조 버전 1과는 별개 |
| `material` | 기존 문자열을 보존하는 호환 필드 |
| `materials` | 소재 선택 목록. v1 문자열이 있으면 구분자를 임의 해석하지 않고 문자열 전체를 한 항목으로 읽음 |
| `thickness` | 기존 enum 이름도 함께 저장 |
| `thicknessLevel` | 1~5 정수 또는 null. 구버전 thin/medium/thick은 2/3/4로 해석 |
| `primaryColor`, `additionalColors` | 기존 문자열/목록 구조 유지 |
| `primaryColorHex`, `additionalColorDetails` | 표준 이름에 대응하는 HEX. 사용자 정의 이름의 HEX는 null |

`materials`가 존재하면 빈 목록을 포함해 이 목록이 현재 소재 값입니다. `material`은 원본 문자열 보존용이므로 새 기능과 Supabase 연동에서는 `materials`를 사용합니다. 두께 수치는 `Garment.thicknessLevel` 또는 `GarmentThickness.level`로 접근합니다.

읽을 때만 v1을 메모리에서 해석하고, 실제 변경 내용을 저장할 때 해당 의류의 메타데이터를 v2로 저장합니다. 변경 없는 수정 화면에서 저장하면 쓰기 자체를 생략하여 수정일도 유지합니다. 실제 내용을 바꾸면 같은 ID·등록일로 저장하고 수정일만 갱신합니다. 사진을 바꾸지 않으면 기존 바이너리에 쓰지 않습니다. 이미지 MIME·해상도·메모·기존 사용자 정의 값도 이어받습니다.

알 수 없는 버전이나 잘못된 필드는 읽기 오류로 처리하며 원본 레코드를 덮어쓰지 않습니다. 저장 실패 시 기존 IndexedDB 트랜잭션 롤백을 사용합니다. 네이티브 파일 저장도 같은 모델 해석을 사용합니다. 새 형식은 구버전 앱으로 되돌려 사용하는 것까지 보장하지는 않습니다.

### 이번 변경 파일

- `lib/models/garment.dart`: v1/v2 호환, 소재 목록·표준 색상 HEX·두께 수치
- `lib/models/garment_options.dart`: 카테고리별 세부 종류, 15색, 소재 설명, 핏 우선순위
- `lib/widgets/garment_input_fields.dart`: 섹션·추천 입력·팔레트·사용자 정의 목록·소재·핏·두께 공통 입력기
- `lib/widgets/garment_illustrations.dart`: 직접 제작한 질감 패턴과 실루엣 Painter
- `lib/screens/garment_editor_screen.dart`: 등록/수정 입력기 연결, 기존 값 유지, 변경 없는 저장 생략
- `lib/screens/garment_detail_screen.dart`: 복수 소재 표시
- `test/garment_compatibility_test.dart`: 구버전 모델·색상·두께 매핑, 읽기/실패 시 원본 보존
- `test/garment_input_ux_test.dart`: 카테고리·팔레트·직접 입력·소재·핏·글자 확대·테마·변경 없는 저장
- `test/wardrobe_widget_test.dart`: 기존 등록/수정/삭제 흐름을 새 입력 UI로 검증
- `tool/browser_storage_probe.dart`, `scripts/browser_storage_test.cjs`: 구버전 원본과 새 버전 저장 후 두 번 새로고침 검증
- `README.md`: 모델 호환 정책과 최신 검증 결과

### 최신 검증 결과

- `flutter analyze`: No issues found
- `scripts/test.ps1` → `flutter test`: **33개 통과** (온보딩·테마·옷장 기존 기능 포함)
- `flutter build web`: 성공
- 실제 Chrome 프로브: `WRITE_OK` → `READ_AFTER_RELOAD_OK; UPDATE_WRITTEN` → `UPDATED_AFTER_RELOAD_OK; LEGACY_PRESERVED; DELETE_OK`
- 프로브는 읽은 뒤에도 원본 v1 레코드가 그대로인지 확인하고, v2 수정 후 사진 바이트·ID·등록일·수정일·기존 혼방 소재 보존을 확인합니다. 프로브에서 날짜를 바꾸지 않는 수정은 저장소 자체가 날짜를 임의 변경하지 않음을 확인하기 위한 것입니다. UI에서 실제 정보를 바꾸면 수정일을 갱신합니다.

테스트용 DB와 브라우저 프로필만 사용했습니다. 기존 사용자의 실제 저장소에 일괄 변환을 실행하지 않았습니다. 실제 모바일/Safari·스크린리더·OS 파일 선택 창을 이용한 전체 UI E2E는 검증하지 않았으며, 위 Chrome 검증은 실제 저장소를 사용하는 독립 프로브입니다.

## 소규모 옷장 UX 개선 (2026-10-27)

### 변경 내용

- 옷장 필터를 `전체 + 등록된 세부 종류`로 변경했습니다. 사용자 정의 종류도 포함하고, 앞뒤 공백 및 영문 대소문자가 같은 종류는 한 번만 표시합니다. 표시 순서는 목록에서 처음 나타난 순서이며, 값이 없는 옷은 `미분류`로 묶습니다. 저장된 문자열은 바꾸지 않습니다.
- 실제로 `전체` 또는 `미분류`라는 종류명을 직접 입력한 경우에는 `(직접 입력)`을 붙여 시스템 필터와 구분합니다.
- 종류 목록은 이름 검색 결과가 아닌 등록된 전체 의류에서 생성합니다. 선택한 종류와 이름 검색은 동시에 적용됩니다.
- 등록·수정·삭제 후 목록을 다시 읽어 필터도 갱신합니다. 선택 중인 종류가 사라지면 `전체`로 돌아갑니다. 새 옷 등록 후에는 기존 동작대로 전체 목록을 보여줍니다.
- 모바일은 필터를 가로로 스크롤하고, PC에서는 여러 줄로 배치합니다.
- 카키 `#77794A`, 카멜 `#BF8A55`, 민트 `#A6D9C5`를 공통 팔레트에 추가했습니다. 대표/추가 색상 모두 18색을 사용하며 직접 입력과 중복 방지는 유지합니다. 기존에 직접 입력했던 동일 이름도 읽기나 필터 사용만으로 덮어쓰지 않습니다.
- 상의·아우터는 슬림/레귤러/오버/루즈 핏만 추천합니다. 바지는 와이드/스트레이트/테이퍼드/스키니를 우선 추천하고, 설명도 바지에 맞췄습니다.
- 하의의 세부 종류에 `스커트` 또는 `치마`가 있으면 A라인/H라인과 스커트 그림을 사용합니다. 원피스는 원피스 설명을, 세트·점프수트는 별도의 설명과 참고 아이콘을 사용합니다.
- 신발·가방·액세서리·기타에는 추천 그림을 생략하고 선택 사항인 직접 입력만 제공합니다. 기존 핏 값은 추천 목록과 달라도 그대로 표시·저장합니다.

### 소재 그림 확인

소재 그림은 `lib/widgets/garment_illustrations.dart`의 `FabricPatternPainter extends CustomPainter`로 직접 그립니다. 선·곡선·도형으로 질감의 특징을 간략히 표현하며 외부 이미지·SVG·네트워크 이미지 다운로드를 사용하지 않습니다. 이번 작업에서는 그림 디자인을 변경하지 않았습니다.

소재 선택 화면에는 기존의 “직접 그린 참고 일러스트이며 실제 원단 사진이 아니에요” 안내를 유지했습니다. 그림은 원단의 실제 촉감을 재현하지 않으며 설명 텍스트와 함께 참고해야 합니다.

### 데이터 보존

의류 직렬화 모델·DB 이름·DB 버전·IndexedDB object store·이미지 저장 구현은 변경하지 않았습니다. 데이터 초기화나 추가 마이그레이션은 없습니다. 필터는 기존 `subtype` 문자열을 화면에서 읽어 생성할 뿐입니다. 실제 사용자의 저장소를 테스트용으로 사용하지 않았습니다.

### 이번 변경 파일

| 파일 | 역할 |
| --- | --- |
| `lib/models/wardrobe_filters.dart` | 세부 종류 추출·중복 제거·미분류·이름 검색 결합 |
| `lib/screens/wardrobe_screen.dart` | 동적 필터, 모바일 가로 스크롤, 수정/삭제 후 필터 갱신 |
| `lib/models/garment_options.dart` | 새 3색, 카테고리/종류별 핏·설명 |
| `lib/widgets/garment_input_fields.dart` | 종류에 맞는 핏 그림·설명 및 선택 입력 안내 |
| `lib/screens/garment_editor_screen.dart` | 핏 선택기에 현재 세부 종류 전달 |
| `test/wardrobe_small_ux_test.dart` | 동적 필터·검색·수정·삭제·가로 스크롤·팔레트·핏 테스트 |
| `test/wardrobe_widget_test.dart` | 기존 옷장 테스트를 세부 종류 필터로 갱신, 추가 후 필터 검증 |
| `test/garment_compatibility_test.dart` | 표준 색상 18종으로 기대값 갱신 |
| `test/support/wardrobe_fakes.dart` | 테스트 의류의 세부 종류 지정 지원 |
| `README.md` | 최신 사용·검증 내역 |

### 최종 검증

- `flutter analyze`: No issues found
- `scripts/test.ps1` → `flutter test`: **41개 통과**
- `flutter build web`: 성공
- 실제 Chrome의 독립 저장소 프로브: 구버전 읽기 비파괴, 수정 후 두 번 새로고침, 기존 사진 바이너리·정보 보존 통과
- 360px/1440px 화면에서 필터·검색 및 수정/삭제 후 필터 갱신을 검증했습니다. 새 3색은 대표/추가 색상 선택 및 HEX 저장을 확인했습니다.

제약: 임의의 사용자 정의 하의 종류가 스커트인지 의미 분석하지는 않습니다. `스커트`/`치마`라는 단어가 없으면 바지 기준 추천을 표시하며 직접 핏 입력은 계속 가능합니다. 실제 모바일/Safari·OS 파일 선택 창·스크린리더와 배포 앱 전체 UI E2E는 이번에도 별도 미검증입니다.

## 옷장 필터 구조 수정: 대분류 → 소분류 (2026-10-27)

이 항목이 현재 옷장 필터의 동작이며, 앞선 소규모 UX 개선 내역의 단일 단계 필터를 대체합니다.

- 상단에 전체 / 상의 / 하의 / 아우터 / 원피스·세트 / 신발 / 가방 / 액세서리 / 기타를 항상 표시합니다. 옷이 없는 대분류도 선택할 수 있습니다.
- 대분류 전체는 옷장 전체를 대상으로 하며 소분류를 숨깁니다. 대분류 선택 시 아래에 작은 칩으로 해당 대분류의 소분류를 표시합니다.
- 기본 소분류는 등록 화면과 동일한 `subtypeSuggestions`를 재사용합니다. 등록된 옷이 없어도 추천 소분류는 표시합니다.
- 선택한 대분류에 속한 사용자 정의 종류를 기본 목록 뒤에 추가합니다. 앞뒤 공백·영문 대소문자를 기준으로 중복을 제거하며 저장된 원본 텍스트는 수정하지 않습니다.
- 해당 대분류에 세부 종류가 비어 있는 옷이 있으면 미분류를 추가합니다. 실제 종류명으로 입력한 전체/미분류는 `(직접 입력)`을 붙여 시스템 필터와 구분합니다.
- 소분류 전체는 현재 대분류 안의 모든 옷을 의미합니다. 대분류를 선택하면 소분류를 전체로 초기화하고 이름 검색어는 유지합니다.
- 대분류·소분류·이름 검색을 동시에 적용하고 0벌도 검색 결과 개수에 표시합니다. 선택한 대분류/소분류의 결과가 없으면 “아직 등록된 옷이 없어요”를 표시합니다.
- 추가·수정·삭제 후 다시 읽어 결과와 사용자 정의 소분류를 갱신합니다. 삭제된 사용자 정의 소분류의 선택은 현재 대분류의 전체로 돌아갑니다. 추천 소분류는 보유 옷이 0벌이 되어도 계속 남습니다.
- 모바일에서는 대분류·소분류가 각각 가로 스크롤됩니다. PC에서는 각각 여러 줄로 표시하며, 강조된 대분류와 작은 소분류 칩을 구분합니다. 사진 그리드와 테마 3종은 유지합니다.

### 이번에 변경한 파일

| 파일 | 변경 |
| --- | --- |
| `lib/models/wardrobe_filters.dart` | 대분류에 속한 기본·사용자 정의·미분류 목록과 세 조건 결합 |
| `lib/screens/wardrobe_screen.dart` | 2단계 필터 표시·선택 초기화·빈 상태·결과 개수 |
| `test/hierarchical_wardrobe_filter_test.dart` | 빈 대분류·공유 추천·조건 결합·선택 초기화·세 벌/사진 보존·반응형·테마 검증 |
| `test/wardrobe_small_ux_test.dart` | 이전 단일 단계 필터 테스트를 계층형 동작으로 갱신 |
| `test/wardrobe_widget_test.dart` | 기존 등록·검색·수정·삭제 회귀 테스트의 필터 선택 경로 갱신 |
| `README.md` | 현재 필터 동작 및 검증 결과 |

등록·수정 화면, `garment_options.dart`, 색상 팔레트, 소재 그림, 핏 설명, 두께, 의류 직렬화 모델 및 저장소 구현 파일은 이번 작업에서 변경하지 않았습니다. DB 초기화·마이그레이션은 없으며 실제 사용자 저장소를 테스트에 사용하지 않았습니다.

### 검증 결과

- `flutter analyze`: No issues found
- `scripts/test.ps1` → `flutter test`: **50개 통과**
- `flutter build web`: 성공
- 별도 IndexedDB 메모리 어댑터 테스트: 의류 세 벌의 메타데이터·사진 바이트가 필터 조건 순회 및 저장소 재열기 후 동일한지 확인
- 실제 Chrome 독립 프로브: 기존 형식 읽기와 수정·두 번 새로고침 후 사진·정보 보존 통과
- 360px/1440px 반응형 필터와 테마 3종 확인

실제 사용자가 보유한 세 벌을 직접 열어 비교한 것은 아닙니다. 세 벌 보존 테스트는 격리된 테스트 데이터로 실행했으며, 실제 사용자 DB에는 읽기·쓰기·삭제를 수행하지 않았습니다. Chrome 검증도 전용 프로필과 테스트 DB를 사용하는 저장소 프로브이며 배포 앱 전체 UI E2E는 아닙니다. 실제 모바일/Safari·스크린리더 검증은 별도입니다.
