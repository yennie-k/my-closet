# camera JPEG 줄무늬 원인 확인과 제한된 호환 처리 — 2026-11-09

이 문서는 11월 5일의 ‘원인 미확정’ 조사 결과를 갱신한다. 사용자가 지정한 **camera JPEG 한 파일을 읽기 전용으로** 분석했다. 원본이나 변환 이미지를 파일로 복사/저장하지 않았고 서버에 업로드하지 않았다. 실제 사진을 회귀 fixture로 사용하지 않았다.

## 확인된 손상 지점

**현재 image 4.12.0의 JPEG 디코딩에서 restart 경계 동기화가 깨져 원시 픽셀부터 손상된다. PNG 인코딩·EXIF·리사이즈·최종 JPEG 인코딩이 최초 원인은 아니다.**

기존 진단 앱의 경로는 다음과 같다.

| 패널 | 디코더/처리/인코더 |
| --- | --- |
| A | 원본 바이트 → Flutter `Image.memory`의 엔진 이미지 코덱 → 화면 |
| B decoded | `image.JpegDecoder.startDecode/decodeFrame(0)` → 참고용 최대 600px `copyResize` → `image.encodePng` → Flutter 코덱으로 PNG 표시 |
| B oriented/resized/composited | 위 Dart 픽셀에서 각각 방향 보정/앱 리사이즈/흰 배경 합성 → 참고 축소·PNG → Flutter 표시 |
| 기존 C | 이미 손상된 Dart 픽셀 → `image.encodeJpg` → Flutter 표시 |

B에는 참고 축소와 PNG가 추가되므로 B 화면만으로 원인을 확정하지 않았다. 이번에는 축소 없이 디코딩 직후 전체 RGBA를 추출하고 다음을 비교했다.

1. 같은 원본 바이트를 Flutter `ui.instantiateImageCodec`과 Dart `JpegDecoder`로 각각 디코딩한다.
2. 모든 RGB 채널의 차이와 행별 평균 오차를 비교한다. 투명도·축소·PNG를 거치지 않는다.
3. Dart 픽셀을 **원래 해상도 PNG**로 인코딩한 후, Dart PNG와 Flutter PNG 코덱으로 각각 다시 디코딩한다.
4. 두 PNG 왕복 결과가 원래 Dart RGBA와 바이트 단위로 같은지 확인한다.
5. B0 `RawImage` 패널은 Dart RGBA를 `ui.decodeImageFromPixels`로 표시하며 PNG 인코딩·참고 축소를 전혀 거치지 않는다.

## 실제 JPEG 헤더

- 88,308바이트, SOF0 baseline sequential, 8-bit precision, 2048×1536.
- Y 2×1, Cb/Cr 1×1: 4:2:2. 한 MCU는 16×8픽셀이다.
- DRI 512 MCU, RST marker 47개, RST0~RST7 순환.
- 원본 EXIF 방향 1, ICC 없음, Adobe transform marker 없음, EOI 존재.
- Individual user-file fingerprints are retained only in private local diagnostics.

원본 EXIF 값은 이번에 JPEG 메타데이터에서 따로 읽었다. 이전 도구는 디코딩 후 EXIF를 표시했는데 이 라이브러리는 디코딩 중 방향을 적용하고 태그를 지울 수 있어 그 값만으로 원본 방향을 판단하면 안 된다.

## restart 경계에서 발생한 일과 근거

이 파일에는 entropy 구간 뒤 RST marker 앞에 `0x55` 여분 바이트가 있다. 일정한 경계 정렬을 위한 패딩으로 보이며, 목적 자체는 추론이다. 여분 바이트의 실제 존재와 디코더 동작은 직접 확인했다.

설치된 패키지의 `jpeg_scan.dart`는 한 restart interval을 디코딩한 뒤 입력 포인터가 곧바로 `FF D0~D7`를 가리키는 경우만 소비한다. 그 사이에 다른 바이트가 있으면 marker를 찾아 재동기화하지 않고 다음 interval의 MCU 루프를 시작한다. 이 파일에서는 여분 바이트를 새 MCU의 entropy로 처리한 뒤 marker에서 수천 번의 short read가 발생하고, 행 위치가 밀려 줄무늬가 된다.

원본을 변경하지 않고 **라이브러리 코드만 build 폴더에 복사**해 계측했다. pub cache와 앱이 사용하는 패키지는 수정하지 않았다.

- 첫 interval: 입력 624→1909, MCU 0→512. 실제 RST0는 1918에 있어 여분 9바이트가 남는다.
- 다음 반복은 1909→1918만 읽고 MCU 512→1024를 진행하며 short read 4095회를 기록했다.
- 한 행에 2048/16 = 128 MCU이므로 512 MCU는 4 MCU행 = **32픽셀 행**이다. 관측된 32행 단위 주기와 일치한다.
- 실험 복사본에서 ‘예상한 restart 경계에서 다음 marker를 찾아 재동기화’만 보완하자 short read가 사라지고 Flutter 원본과의 평균 채널 오차가 **63.8975→0.2157**로 감소했다.
- 스트리밍 최적화를 끈 같은 라이브러리 경로도 원래는 동일하게 깨졌다. 따라서 스트리밍 밴드 버퍼만의 문제가 아니다.

이는 이 JPEG의 여분 바이트 처리와 라이브러리의 복구 동작 사이의 호환성 문제다. 정상적인 restart marker 기능 자체가 잘못됐다는 뜻은 아니다. 원본을 다시 저장하거나 JPEG 바이트에서 특정 값을 임의로 지우는 방식은 사용하지 않았다.

[libjpeg-turbo의 marker 처리 코드](https://github.com/libjpeg-turbo/libjpeg-turbo/blob/main/src/jdmarker.c)에서도 다음 marker를 탐색하고 불필요한 바이트를 건너뛰는 복구 경로를 확인했다. 다만 현재 Flutter 엔진의 정확한 내부 libjpeg 버전까지 특정한 것은 아니다. 결론의 직접 근거는 같은 원본에 대한 픽셀 비교와 위 통제 실험이다.

## 실제 원본 수치 비교

오차는 RGB 채널 값 0~255에 대한 전체 픽셀 평균 절대 오차다. JPEG의 정상 반올림·색차 업샘플링·재압축은 작은 차이를 만들 수 있으므로 서로 다른 코덱의 완전 일치를 정상 조건으로 삼지 않는다.

| 비교 | Windows Flutter test | Edge Flutter web |
| --- | ---: | ---: |
| Flutter 원본 vs 기존 Dart 디코딩 직후 | 63.8975 | 63.9063 |
| Dart 픽셀 vs Dart PNG 왕복 | 0, RGBA 완전 동일 | 0, RGBA 완전 동일 |
| Dart 픽셀 vs Flutter PNG 왕복 | 0, RGBA 완전 동일 | 0, RGBA 완전 동일 |
| 재동기화 실험 복사본 vs Flutter 원본 | 0.2157 | 이 실험은 VM에서만 수행 |
| 수정 후 최종 JPEG vs 정상 원본을 같은 방식으로 축소한 기준 | 0.4231 | 0.4401 |

수정 후 실제 출력은 양쪽 모두 1600×1200(1.92MP)이다. VM 126,565바이트 / Edge 127,428바이트로 2MiB 제한을 충족했다. 코덱의 작은 플랫폼별 차이로 JPEG 바이트가 달라질 수 있다. 업로드 해시는 최종 실제 바이트를 기준으로 계산하므로 기존 서버 계약에는 영향을 주지 않는다.

## 선택한 최소 수정

앱의 전체 디코더나 패키지 버전을 교체하지 않았다. 일반 사용자 사진은 기존 `FileGarmentPhotoService`를 통해 공통 비동기 진입점 `prepareGarmentPhoto`를 사용한다.

1. 기존 확장자·바이트·해상도 검증을 먼저 적용한다. native 메모리 할당 전에도 15MiB/24MP/한 변 12,000px 상한을 지킨다.
2. 첫 scan 앞에서 nonzero DRI를 선언한 JPEG만, A에서 이미 정상 동작을 확인한 **Flutter 기본 코덱**으로 디코딩한다.
3. 이미 방향이 적용된 RGBA에서 EXIF 없는 Image를 만들고, 기존 긴 변 1600 리사이즈·흰 배경 합성·JPEG 85/65 압축을 재사용한다. 방향을 두 번 적용하지 않는다.
4. 나머지 JPEG·PNG·WebP는 기존 Dart 경로를 유지한다. 일반 3개 형식은 변경 전 정규화 결과와 **바이트 동일** 회귀를 확인한다.
5. native Codec/Image는 RGBA 복사 후 즉시 해제한다. 실패 시 기존 사진을 대체하지 않고 사용자 오류를 반환한다. Dart의 손상 경로로 자동 재시도하지 않는다.
6. 출력 2MiB/4MP 및 Flutter 미리보기 디코딩 검증도 유지한다.

패키지 내부의 재동기화 실험 코드는 원인 확인용이며 앱에 포함하지 않았다. 운영 경로는 Flutter 공개 API만 사용한다. 일반 옷장과 서버 개발 옷장 모두 같은 선택 서비스를 쓰므로 같은 보완이 적용된다. 이미 저장된 사진을 다시 변환하지 않는다.

저수준 동기 함수 `normalizeGarmentPhoto`는 기존 Dart 비교/일반 형식 처리용으로 남아 있다. 새 사용자 파일 처리는 반드시 `prepareGarmentPhoto`를 거쳐야 한다. 진단 앱의 B/B0는 의도적으로 **기존 Dart 경로**를 보여주고, C는 **수정된 실제 앱 경로**를 보여준다.

## 수정·추가 파일

| 구분 | 파일 |
| --- | --- |
| 앱 수정 | `lib/services/garment_photo_service.dart`, `garment_photo_processor.dart` |
| 진단 앱 | `tool/photo_diagnostic_app.dart` — B0 raw 패널, 소스 EXIF, 기존/앱 경로 구분 |
| 픽셀 비교 | `tool/photo_pixel_diagnostics.dart`, `jpeg_pixel_diagnostic_test.dart`, `jpeg_restart_diagnostic_test.dart` |
| 숫자 전용 web bridge | `tool/photo_pixel_report_{bridge,stub,web}.dart` |
| 합성 회귀 | `test/photo_pixel_diagnostics_test.dart`, `jpeg_restart_compatibility_test.dart`, `test/fixtures/synthetic_restart_422.jpg`, fixture README |
| 도구 | `scripts/jpeg_restart_fixtures.mjs`, `jpeg_readonly_edge_diagnostic.mjs`, `browser_test_driver.mjs`의 전용 InPrivate/IPv4 진단 옵션 |
| 문서 | 이 문서, `jpeg-restart-results-20261109.json`, README |

기존 미커밋 변경 사항은 보존했다. Git 전체 변경 목록이 이번 작업 범위만을 뜻하지 않는다.

## 회귀 및 데이터 보호

- 실제 원본: VM과 Edge 모두 읽기 전용, 숫자·헤더·해시만 기록. 원본 해시/수정 시각 동일. 변환 이미지 파일과 화면 캡처는 저장하지 않았다.
- 자동 회귀: 직접 생성한 RGB 패턴으로 작은 4:2:2/DRI JPEG를 만들고, **합성 fixture에만** 메모리에서 0x55 여분 바이트를 추가했다. 기존 Dart 경로의 손상과 호환 경로의 복구를 재현한다. 실제 사진을 fixture로 복사하지 않았다.
- 정상 JPG/PNG/WebP의 기존 결과 동일, restart JPEG EXIF 2/3/5/6/8 단일 적용, 입력 형식/해상도 방어, PNG 전체 해상도 무손실 왕복을 검사한다. 기존 저장/수정 실패 보호 및 IndexedDB·서버 옷장 위젯 회귀도 전체 테스트에 포함한다.
- SQL·RLS·Storage 정책·Edge Functions·모델·IndexedDB 구현은 수정하지 않았다. 이번 작업은 DB/Storage API나 SQL을 호출하지 않았다. 기존 의류·사진·설정에 쓰기 요청을 보내지 않았다.
- 실제 사진 Edge 진단에서 Supabase cloud/local URL을 차단했다. 진단 앱에는 인증/업로드/저장소 연결이 없다. 전용 프로필을 사용하고 기본 8080 실사용 브라우저에는 접근하지 않았다.
- 실제 사진의 물리적 클라우드 업로드/ready 테스트는 **수행하지 않았다**. 서버 정책/worker 회귀를 이번에 다시 실행했다고 주장하지 않는다.
- 초기 Edge 자동화는 localhost/InPrivate 빈 페이지와 큰 SelectableText 보고서 수집에서 실패했다. IPv4와 숫자 전용 메모리 bridge로 보완 후 실제 파일 비교에 성공했다. 실패 시에도 사진 캡처/덤프는 수행하지 않았다.

최종 검증은 순차 실행했다.

| 검증 | 결과 |
| --- | --- |
| `flutter analyze` | No issues found |
| `scripts/test.ps1 --concurrency=1` → `flutter test` | **109 통과 / 0 실패** (기존 101 + 새 8) |
| 실제 원본 VM/Edge 읽기 전용 픽셀 비교 | 모두 성공, 원본 해시 동일 |
| restart 간격 합성 fixture 6종 및 0x55 패딩 재현 | 통과 |
| 기본 `flutter build web` | 성공 |
| 개발 설정 웹 빌드 `build/web_photos` | 성공 |
| 독립 진단 앱 웹 빌드 | 성공 |

개별 파일 진단 JSON(개인 로컬 보관, 커밋 제외)을 함께 기록했다. 실제 파일의 결과는 시각 사진을 캡처한 것이 아니라 전체 픽셀 비교 수치로 검증했다.

## 사용자의 Edge 확인 방법

앱을 완전히 재시작한다. 기존 브라우저 저장소나 사진은 지우지 않는다.

```powershell
# 파일 저장/서버 연결이 없는 진단 앱
flutter run -d edge --web-hostname=localhost --web-port=8082 --target=tool/photo_diagnostic_app.dart

# 실제 앱 개발 모드 (진단 확인 후 다른 터미널에서 순차 실행)
flutter run -d edge --web-hostname=localhost --web-port=8081 --dart-define-from-file=config/supabase.crud.local.json
```

1. 진단 앱에서 camera JPEG를 선택한다. A는 정상, B0/B는 기존 문제를 보여줄 수 있으며 **C. 앱에서 사용하는 최종 JPEG가 정상**이면 된다. B가 남아 있는 것은 비교용으로 기존 디코더를 유지했기 때문이다.
2. `앱 디코딩 경로: Flutter 호환 경로 (restart JPEG)`를 확인한다.
3. `JPEG 원시 픽셀·PNG 전후 비교 (저장 없음)`에서 기존 Dart 오차는 약 63.9, PNG 왕복은 0, `production_processing`의 최종 오차는 약 0.44인지 확인한다. 작은 플랫폼/빌드 차이는 가능하다.
4. 실제 앱의 선택 미리보기도 확인할 수 있다. 문제 사진을 서버에 업로드할 필요는 없다. 확인 후 선택을 취소한다.

물리적 Android/iOS·다른 브라우저/GPU 설정은 미검증이다. 확인 범위는 Windows Flutter test와 Edge web이다. 임의로 손상된 모든 JPEG를 복구하거나 시각적 정확성을 자동 판정하는 기능으로 확장하지 않았다.
