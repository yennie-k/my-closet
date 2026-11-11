# 특정 JPEG 줄무늬 미리보기 조사 — 2026-11-05

## 결론과 확인 범위

**camera JPEG의 정확한 원인은 아직 확정하지 못했다. 줄무늬 수정 완료로 보고하지 않는다.** 원본 파일은 제공받거나 열지 않았고, 경로를 검색하거나 테스트 fixture로 복사하지 않았다. 아래 결과는 사용자가 알려준 속성, 현재 코드, 직접 생성한 합성 이미지로 확인한 범위다.

사용자가 확인한 정보: JPEG, 88,308바이트, 2048×1536(3,145,728화소), Windows 표기 24비트, 96DPI. 입력 제한 15MiB/24MP 안에 있으므로 크기 초과는 원인에서 제외할 수 있다. 현재 처리기는 긴 변을 1600으로 줄이므로 일반 방향이면 **1600×1200 / 1.92MP**가 된다. EXIF가 90도 회전 방향이면 **1200×1600**이다. 96DPI 값은 리사이즈 계산에 사용하지 않는다.

24비트는 JPEG의 SOF 방식, 성분 샘플링, ICC 프로필, Adobe 변환, EXIF 방향을 설명하지 않는다. 작은 파일 크기도 특정 인코딩 방식이나 손상을 증명하지 않는다. Windows 사진 앱의 정상 표시는 그 앱의 디코더에서 정상이라는 근거이며, 다른 디코더의 동작까지 보장하지는 않는다.

## 실제 코드 경로

1. `FileGarmentPhotoService.pick()`이 `file_selector`로 파일을 선택한다. `XFile.length()` 확인 후 `readAsBytes()`로 바이너리를 읽는다. 텍스트 변환이나 Base64 왕복은 없다.
2. 공통 `normalizeGarmentPhoto()`가 확장자에 대응하는 JPG/PNG/WebP 디코더로 실제 헤더를 읽고 크기/해상도를 제한한다. 확장자만 바꾼 다른 형식은 해당 디코더에서 거부된다.
3. `image` 4.12.0이 첫 프레임을 디코딩한다. `bakeOrientation` → 긴 변 1600 리사이즈 → 8비트 RGB 흰 캔버스에 투명도 합성 → JPEG 품질 85(필요 시 65) 인코딩 순서다.
4. 편집 화면은 **원본 대신 이 JPEG 바이트**를 `Image.memory`로 보여준다. 사진 선택/처리에 실패하면 `_photo`와 기존 의류를 교체하지 않는다. 저장소 호출은 저장 버튼을 누른 이후다.
5. 서버 옷장은 이후 별도의 예약/업로드/검증 경로를 사용한다. 문제 사진은 업로드 전에 깨졌으므로 이번 증상 조사 우선순위는 로컬 디코딩·변환·Flutter web 렌더링이다. 이미 다른 사진이 ready로 승인됐다는 사실만으로 문제 사진의 전처리도 정상이라고 볼 수 없다.

**일반 IndexedDB 옷장과 서버 개발 옷장이 같은 선택/변환 서비스를 사용한다.** 따라서 전처리 결함이 확인되면 양쪽에 영향을 줄 수 있다. 두 저장소나 서버 worker의 문제라고 단정할 근거는 없다.

## 확인한 것과 미확정인 것

| 항목 | 근거 / 상태 |
| --- | --- |
| 원본 바이트 읽기 | 바이너리 읽기이며 코드상 문자 인코딩 변환 없음. 원본 파일 바이트 자체는 미확인 |
| JPG 특성 | baseline 4:4:4/4:2:0/4:2:2, progressive, grayscale, CMYK 합성 fixture 통과. 실제 파일의 세부 인코딩은 모름 |
| 동일 해상도 | 2048×1536의 4:2:0/4:2:2/1×2/4:1:1/progressive 합성 JPEG 통과 |
| PNG/WebP | RGB·16비트·인터레이스·팔레트 PNG, lossy/lossless WebP 합성 비교 통과 |
| EXIF 방향 | 2~8 변환 및 코너 색·크기 회귀 통과. 실제 파일 방향은 모름 |
| 투명도/비트 범위 | 8/16비트 투명 PNG와 투명 WebP의 흰 배경 합성 회귀 통과. JPEG 원본 자체는 보통의 알파 투명도 포맷이 아님 |
| 리사이즈/압축 | 동일 크기 합성 JPEG에서 1600×1200 생성, 2MiB/4MP 제한 통과. 실제 이미지 내용에 대한 손상은 미확인 |
| Flutter 렌더링 | 격리된 Edge의 실제 Flutter 진단 화면 4개 합성 파일 정상, 2048×1536 화면도 확인 |
| 브라우저 캐시 | 새 전용 프로필과 새 파일 바이트를 사용했다. 캐시 문제를 재현하지 못했으며 실사용 프로필 캐시는 지우지 않음 |
| GPU 경로 | 자동 Edge는 headless/disable-gpu 환경. 사용자의 실제 GPU 가속 경로는 미검증 |
| 특정 이미지 | 원본 미접근. 줄무늬가 처음 발생하는 단계 미확정 |

합성 비교는 ImageMagick WASM(독립 코덱) 기준 픽셀과 Dart VM/web 디코딩·최종 JPEG 및 Edge 네이티브 JPEG 디코딩의 **16개 표본 위치**를 비교했다. 기준 오차는 채널 평균 절대 오차 8 미만이며 실제 최대 평균 오차는 약 2.1이었다. 이는 모든 픽셀/모든 카메라 JPEG를 검증한 것이 아니다. 특정 내용/마커 조합에서 발생하는 결함이나 촘촘한 줄무늬를 전부 배제할 수 없다.

## 이번 변경: 원인 추측에 따른 코덱 교체 대신 최소 방어와 진단

- `lib/services/garment_photo_processor.dart` 추가: 기존 ProcessedPhoto와 순수 변환 함수를 선택기에서 분리했다. 기존 서비스가 재수출하므로 기존 호출부는 유지한다. 이미지 라이브러리 버전·JPEG 품질·리사이즈 방식·저장 형식은 바꾸지 않았다.
- 단계 관찰 callback은 별도 진단 앱에서만 사용한다. 일반 앱에서는 호출하지 않는다.
- `lib/services/garment_photo_service.dart`: 처리 완료 후 **실제 Flutter 코덱으로 첫 프레임 디코딩과 출력 크기를 검사한 뒤** 선택 결과를 반환한다. 빈/과대 결과·디코딩 실패·치수 불일치는 사용자 오류로 돌려주고 새 선택을 적용하지 않는다. 사용한 Codec/Image는 finally에서 해제한다.
- **이 방어는 유효한 JPEG 안에 잘못된 픽셀이 이미 인코딩된 줄무늬를 자동 판별하지 못한다.** 원본과 다르게 보이는 사진을 안전하다고 승인하는 기능이 아니다. 기존 서버 검증도 파일 무결성/디코딩을 확인하며 사람의 시각적 정확성을 판정하지 않는다.
- 기존 화면·모델·IndexedDB·서버 CRUD·SQL·RLS·Storage 정책·Edge Function은 이번에 수정하지 않았다. 새 패키지 의존성도 없다.

## 추가·수정 파일

| 파일 | 역할 |
| --- | --- |
| `lib/services/garment_photo_processor.dart` | 공통 순수 처리기 분리, 선택적 단계 관찰 |
| `lib/services/garment_photo_service.dart` | 재수출·선택기 유지, Flutter 첫 프레임 검증 |
| `tool/photo_diagnostic_app.dart` | 저장소/인증/업로드 없는 독립 진단 화면 |
| `tool/photo_codec_probe{,_core,_web}.dart` | 동일 처리기의 VM/web 픽셀 비교 |
| `scripts/photo_codec_fixtures.mjs` | 직접 만든 합성 패턴 28종 생성 |
| `scripts/photo_codec_browser_test.mjs` | 격리된 Edge 코덱 비교 |
| `scripts/photo_diagnostic_browser_test.mjs` | 8082 Flutter 진단 UI 회귀 |
| `scripts/browser_test_driver.mjs` | 기본 8081 유지, 진단용 8082 선택 지원 |
| `test/photo_pipeline_regression_test.dart` | 신규 19개 처리/렌더링/기존 사진 보호 테스트 |
| `tool/photo_pipeline_server_test.dart` | 새 합성 의류 3건의 실제 로컬 서버 승인 회귀 |
| `supabase/local/photo-preview-regression.mjs` | 로컬 연결 guard, 기존 행/소스 보존 비교. SQL 적용·초기화 없음 |
| 이 문서 및 `photo-preview-server-results-20261105.json` | 결과와 데이터 보호 근거 |

이전 단계의 미커밋 변경 사항은 유지했다. 전체 `git status`의 파일이 모두 이번 변경은 아니다.

## 테스트 결과

- `flutter test --concurrency=1` (`scripts/test.ps1`): **101 통과 / 0 실패**. 기존 82개와 새 19개를 포함한다. 처리 실패 시 기존 로컬 사진/정보 보존, 기존 서버 교체 실패 보호·세션 캐시 보호도 포함한다.
- 합성 VM/web/독립 코덱 비교: **28개 모두 통과**. VM에서도 디코드 오류 없음, Edge 비교 28/0.
- 실제 Edge Flutter 미리보기: **4 통과 / 0 실패**. 동일 해상도 JPEG, PNG, WebP, EXIF 회전 JPEG의 선택·단계별 표시를 확인했다.
- 실제 로컬 Supabase: **3 통과 / 0 실패**. 합성 JPG/PNG/WebP를 공통 전처리·Flutter 디코딩 후 업로드하고 기존 worker의 ready 승인, 인증 다운로드, 서버 재조회를 확인했다. 새 합성 의류만 추가했으며 기존 데이터를 수정/삭제하지 않았다.
- `flutter analyze`: **No issues found**. 기본 `flutter build web`, 개발 설정 `flutter build web --dart-define-from-file=config/supabase.crud.local.json --output=build/web_photos`: **모두 성공**. 독립 진단 앱의 웹 빌드도 성공했다.
- 독립 IndexedDB 브라우저 프로브: **통과**. 합성 데이터의 기존 형식 비파괴 읽기/사진 CRUD/두 번 새로고침을 확인했다. 실사용 8080 프로필은 테스트 대상이 아니다.

실제 DB/Storage의 기존 행·버킷은 전후 행 해시로 비교한다. 원본 이미지 바이트를 다운로드하거나 실사용 IndexedDB 세 벌을 열어 비교한 것은 아니다. 아이보리 셔츠·고양이 사진을 포함한 기존 데이터에 수정/삭제 요청을 보내지 않았다. 클라우드 접속/배포, SQL 적용, DB 초기화, Git commit/push는 하지 않았다.

전후 비교 결과: 기존 의류 85건, 사용자 설정 2건, Storage 객체 메타데이터 58건, 버킷 3건의 원래 행은 모두 동일했다. 새 합성 의류/사진만 각각 3건 추가됐다. SQL 초안·기존/신규 사진 함수·IndexedDB 구현·모델 등 보호 파일 11개도 동일하다. [보존 및 실제 서버 회귀 결과](photo-preview-server-results-20261105.json), [전체 요약 결과](photo-preview-investigation-results-20261105.json)를 참고한다.

## 사용자가 Edge에서 camera JPEG를 확인하는 방법

기존 옷장 창은 그대로 두고 프로젝트 루트의 다른 터미널에서 **별도 진단 앱**을 실행한다. 8082가 이미 사용 중이면 해당 프로세스를 종료하지 말고 다른 빈 포트를 사용한다. 이 앱에는 저장소/로그인/업로드 코드가 없고 기존 사용자 설정도 로드하지 않는다.

```powershell
flutter run -d edge --web-hostname=localhost --web-port=8082 --target=tool/photo_diagnostic_app.dart
```

1. `진단할 사진 선택`에서 원본 파일을 선택한다. 이 동작은 브라우저에서 읽기만 하며 파일 수정·이동·삭제나 프로젝트 fixture 복사를 하지 않는다.
2. `A. 원본 → Flutter 코덱`, B의 decoded/oriented/resized/composited, `C. 최종 JPEG`를 비교한다. B는 메모리 절약용 최대 600px PNG 썸네일이므로 추가 리사이즈의 영향도 고려해야 한다.
3. **처음 줄무늬가 나타난 패널**, 화면에 표시된 형식/치수/채널 형식/EXIF 방향/ICC 유무, Edge 버전과 그래픽 가속 사용 여부를 알려주면 다음 조사를 좁힐 수 있다. 원본이나 사진 자체를 보내지 않고도 이 정보부터 공유할 수 있다.
4. A만 또는 A부터 이상하면 Flutter/브라우저 원본 코덱 경로를, A 정상·decoded부터 이상하면 Dart 디코딩 및 진단 썸네일 경로를 확인한다. oriented/resized/composited에서 처음 달라지면 해당 변환을, PNG 정상·최종 JPEG만 이상하면 인코딩과 JPEG 렌더링을 추가 확인한다. 이 분류도 곧바로 결함 원인 확정을 뜻하지 않는다.
5. 모든 패널이 정상인데 서버 편집 화면만 깨지면 기존 앱이 구버전 빌드인지, 편집 미리보기/메모리 캐시/renderer 차이가 있는지 확인한다. 사이트 데이터 삭제나 IndexedDB 초기화는 하지 않는다. 진단 창을 닫으면 표시용 메모리 사용을 해제할 수 있다.
6. 줄무늬가 보이는 결과는 옷장에 저장하지 않는다. 진단 앱에는 저장 버튼이 없다. 실제 서버 앱을 다시 확인할 때는 완전히 재시작한 개발 빌드를 사용한다.

추가로 필요한 JPEG 헤더 항목은 SOF baseline/progressive, 성분 수·H/V 샘플링, Adobe transform, EXIF orientation, ICC 프로필이다. 현재 Windows 속성만으로는 알 수 없다. 위 단계 비교만으로 구분되지 않으면 사용자가 허용하는 원본 읽기 전용 진단 또는 정확한 인코딩 조건으로 만든 추가 합성 재현물이 필요하다. 원본 파일 수정/이동/삭제는 필요하지 않다.

## 도구 재실행

브라우저와 대형 테스트는 동시에 실행하지 않는다. 합성 파일·프로필·임시 자격 증명은 Git 제외 `build` 안에만 둔다.

```powershell
node scripts/photo_codec_fixtures.mjs
dart run tool/photo_codec_probe.dart
dart compile js tool/photo_codec_probe_web.dart -o build/photo-codec-20261105/probe.js
node scripts/photo_codec_browser_test.mjs
flutter build web --target=tool/photo_diagnostic_app.dart --output=build/photo_diagnostic_web
node scripts/photo_diagnostic_browser_test.mjs
.\scripts\test.ps1 --concurrency=1
```

`image`는 자체 Dart 코덱이며 플랫폼 코덱을 사용하지 않는다는 [패키지 성능 문서](https://github.com/brendan-duncan/image/blob/main/doc/performance.md)도 확인했다. 이 차이는 조사할 경계이며 특정 파일의 결함 원인이라는 증거는 아니다. 기존 4.12.0 코드를 검사하고 실행했으며 추측으로 버전을 교체하지 않았다.
