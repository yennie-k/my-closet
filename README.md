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
- 8개 카테고리 필터와 이름 검색(앞뒤 공백 무시, 영문 대소문자 무시), 두 조건 동시 적용
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

이 스크립트는 전용 Chrome 프로필과 별도 테스트 DB를 사용합니다. 앱과 동일한 `IndexedDbWardrobeRepository`를 실행해 정보와 사진을 저장하고 **실제 Page.reload** 후 새로운 JavaScript 컨텍스트에서 다시 읽어 값과 바이트를 비교한 뒤 수정·삭제를 확인합니다. 테스트 프로필은 무시되는 `build/storage_probe` 아래에 남습니다.

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
