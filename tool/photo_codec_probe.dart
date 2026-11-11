import 'dart:convert';
import 'dart:io';

import 'photo_codec_probe_core.dart';

void main() {
  final folder = Directory('build/photo-codec-20261105');
  final cases = jsonDecode(
    File('${folder.path}/manifest.json').readAsStringSync(),
  ) as List;
  final result = [
    for (final c in cases) probePhoto(Map<String, dynamic>.from(c as Map)),
  ];
  File('${folder.path}/vm-results.json').writeAsStringSync(jsonEncode(result));
  stdout.writeln('VM codec probe completed: ${result.length} synthetic cases');
}
