import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'photo_pixel_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('sequential synthetic restart-marker decoder comparison', () async {
    final folder = Directory('build/jpeg-restart-20261109');
    final manifest = jsonDecode(
      File('${folder.path}/manifest.json').readAsStringSync(),
    ) as List;
    final results = <Map<String, Object?>>[];
    for (final item in manifest) {
      final report = await compareJpegPixels(
        File('${folder.path}/${item['file']}').readAsBytesSync(),
      );
      for (final key in [
        'dart_raw_vs_png_dart_roundtrip',
        'dart_raw_vs_png_flutter_roundtrip',
      ]) {
        expect(
          (report[key] as Map)['rgba_exact'],
          isTrue,
          reason: '${item['file']} $key',
        );
      }
      final brief = <String, Object?>{
        'case': item['file'],
        'jpeg': report['jpeg'],
      };
      for (final key in [
        'flutter_vs_dart_decoded',
        'flutter_vs_dart_nonstreaming',
        'dart_streaming_vs_nonstreaming',
      ]) {
        final metric = Map<String, Object?>.from(report[key] as Map)
          ..remove('row_rgb_mae');
        brief[key] = metric;
      }
      results.add(brief);
      stdout.writeln('SYNTHETIC_DIAGNOSTIC ${jsonEncode(brief)}');
    }
    File('${folder.path}/results.json').writeAsStringSync(jsonEncode(results));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
