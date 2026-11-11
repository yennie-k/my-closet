// Standalone local diagnostic app: no repositories, authentication or uploads.

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:my_closet/services/garment_photo_service.dart';
import 'package:my_closet/services/wardrobe_repository.dart';

import 'photo_pixel_diagnostics.dart';
import 'photo_pixel_report_bridge.dart';

void main() => runApp(const MaterialApp(home: PhotoDiagnosticScreen()));

class DiagnosticResult {
  DiagnosticResult(this.metadata, this.stages, this.output, this.raw);
  final String metadata;
  final Map<String, Uint8List> stages;
  final ProcessedPhoto output;
  final DecodedPixels? raw;
}

DiagnosticResult inspectPhoto((String, Uint8List) input) {
  final previews = <String, Uint8List>{};
  var metadata = '';
  DecodedPixels? raw;
  final output = normalizeGarmentPhoto(
    input,
    observe: (stage, image) {
      if (stage == PhotoProcessingStage.decoded) {
        if (image.width * image.height <= 4000000) raw = dartPixels(image);
        metadata =
            '읽은 바이트: ${input.$2.length}\n'
            '형식: ${img.findDecoderForData(input.$2)?.format.name}\n'
            '해상도: ${image.width} × ${image.height}\n'
            '채널: ${image.numChannels} / 채널 형식: ${image.format.name}\n'
            '소스 JPEG EXIF 방향: ${img.decodeJpgExif(input.$2)?.imageIfd.orientation ?? 'JPEG가 아니거나 태그 없음'}\n'
            '디코딩 후 EXIF 방향: ${image.exif.imageIfd.orientation ?? 1}\n'
            'ICC 프로필: ${image.iccProfile != null ? '있음' : '없음'}';
      }
      // Small diagnostic thumbnails only; never write a file or keep decoded
      // full-size stage copies. Extra diagnostic resize is explicitly labelled.
      final thumb = image.width > 600 || image.height > 600
          ? img.copyResize(
              image,
              width: image.width >= image.height ? 600 : null,
              height: image.height > image.width ? 600 : null,
            )
          : image;
      previews[stage.name] = img.encodePng(thumb);
    },
  );
  return DiagnosticResult(metadata, previews, output, raw);
}

class PhotoDiagnosticScreen extends StatefulWidget {
  const PhotoDiagnosticScreen({super.key});
  @override
  State<PhotoDiagnosticScreen> createState() => _PhotoDiagnosticScreenState();
}

class _PhotoDiagnosticScreenState extends State<PhotoDiagnosticScreen> {
  Uint8List? _original;
  DiagnosticResult? _result;
  String? _error;
  bool _busy = false;
  Map<String, Object?>? _pixelReport;
  void _evict() {
    for (final bytes in [
      ?_original,
      ...?_result?.stages.values,
      if (_result != null) _result!.output.bytes,
    ]) {
      MemoryImage(bytes).evict();
    }
  }

  @override
  void dispose() {
    _evict();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'JPG / PNG / WebP',
            extensions: ['jpg', 'jpeg', 'png', 'webp'],
          ),
        ],
      );
      if (file == null) return;
      if (await file.length() > maxInputPhotoBytes) {
        throw const WardrobeException('15MB 이하 파일을 선택해 주세요.');
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      _evict();
      setState(() {
        _original = bytes;
        _result = null;
        _pixelReport = null;
      });
      publishPixelReport(null);
      final baseline = await compute(inspectPhoto, (file.name, bytes));
      final processed = await prepareGarmentPhoto((file.name, bytes));
      final result = DiagnosticResult(
        '${baseline.metadata}\n앱 디코딩 경로: ${hasJpegRestartInterval(bytes) ? 'Flutter 호환 경로 (restart JPEG)' : '기존 Dart 경로'}',
        baseline.stages,
        processed,
        baseline.raw,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is WardrobeException ? e.message : '진단을 완료하지 못했어요.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _comparePixels() async {
    if (_busy || _original == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final report = await compareJpegPixels(_original!);
      final prepared = await comparePreparedJpeg(_original!);
      final preparedMetric =
          prepared['reference_resized_vs_production_jpeg'] as Map;
      preparedMetric.remove('row_rgb_mae');
      report['production_processing'] = prepared;
      // No pixel arrays or image files exported. Keep just metadata and error
      // statistics; full comparisons above have already examined every pixel.
      for (final value in report.values.whereType<Map>()) {
        if (value['row_rgb_mae'] is List<double>) {
          final rows = value.remove('row_rgb_mae') as List<double>;
          value['row_mae_min'] = rows.reduce((a, b) => a < b ? a : b);
          value['row_mae_max'] = rows.reduce((a, b) => a > b ? a : b);
          value['first_32_row_mae'] = rows.take(32).toList();
        }
      }
      if (mounted) {
        setState(() => _pixelReport = report);
        publishPixelReport(report);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '픽셀 비교를 완료하지 못했어요. JPEG 400만 화소 이하인지 확인해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _preview(String label, Uint8List bytes) => SizedBox(
    width: 320,
    child: Column(
      children: [
        Text(label),
        SizedBox(
          height: 240,
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            semanticLabel: label,
            errorBuilder: (_, _, _) => const Text('이 단계의 Flutter 디코딩 실패'),
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('사진 단계별 진단 · 저장하지 않음')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '선택한 파일은 이 화면 메모리에서만 사용해요. 옷장·DB·Storage에 저장하거나 업로드하지 않아요.\n'
            '단계 PNG는 최대 600px 참고 미리보기이며 최종 JPEG는 앱과 동일한 처리 결과예요.',
          ),
          FilledButton(
            onPressed: _busy ? null : _pick,
            child: const Text('진단할 사진 선택'),
          ),
          if (_busy) const Text('한 장을 순차 처리하고 있어요…'),
          if (_error != null) Text(_error!),
          if (_original != null && _result == null)
            _preview('A. 원본 → Flutter 코덱', _original!),
          if (_result != null) ...[
            SelectableText(_result!.metadata),
            Text(
              '최종: ${_result!.output.width} × ${_result!.output.height} / ${_result!.output.bytes.length} bytes',
            ),
            if (_result!.raw != null)
              _RawPixelPreview(
                key: ObjectKey(_result!.raw),
                pixels: _result!.raw!,
              ),
            OutlinedButton(
              onPressed: _busy ? null : _comparePixels,
              child: const Text('JPEG 원시 픽셀·PNG 전후 비교 (저장 없음)'),
            ),
            if (_pixelReport != null)
              SelectableText(
                const JsonEncoder.withIndent('  ').convert(_pixelReport),
              ),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _preview('A. 원본 → Flutter 코덱', _original!),
                for (final stage in _result!.stages.entries)
                  _preview('B. ${stage.key} → PNG 참고 미리보기', stage.value),
                _preview('C. 앱에서 사용하는 최종 JPEG', _result!.output.bytes),
              ],
            ),
            const Text(
              '원본부터 깨짐: Flutter/브라우저 원본 디코딩 경로 확인\n'
              'B0부터 깨짐: PNG·축소 이전의 Dart 디코딩 픽셀 확인\n'
              'decoded부터 깨짐: Dart 디코딩 경로 확인\n'
              'oriented/resized/composited에서 처음 깨짐: 해당 변환 단계 확인\n'
              '최종 JPEG만 깨짐: JPEG 인코딩/Flutter 디코딩 경로 확인\n'
              '색상 프로필 차이와 참고 썸네일의 추가 리사이즈를 함께 고려해야 해요.',
            ),
          ],
        ],
      ),
    ),
  );
}

class _RawPixelPreview extends StatefulWidget {
  const _RawPixelPreview({super.key, required this.pixels});
  final DecodedPixels pixels;
  @override
  State<_RawPixelPreview> createState() => _RawPixelPreviewState();
}

class _RawPixelPreviewState extends State<_RawPixelPreview> {
  ui.Image? _image;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pixels = widget.pixels;
    final completer = Completer<ui.Image>();
    try {
      ui.decodeImageFromPixels(
        pixels.rgba,
        pixels.width,
        pixels.height,
        ui.PixelFormat.rgba8888,
        completer.complete,
        rowBytes: pixels.width * 4,
      );
      final image = await completer.future;
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
    } catch (_) {
      if (mounted) setState(() => _error = '원시 픽셀 표시 실패');
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('B0. Dart 디코딩 직후 RGBA → RawImage (PNG·축소 없음)'),
      SizedBox(
        width: 640,
        height: 320,
        child: _error != null
            ? Text(_error!)
            : _image == null
            ? const Text('원시 픽셀 표시 중…')
            : RawImage(image: _image, fit: BoxFit.contain),
      ),
    ],
  );
}
