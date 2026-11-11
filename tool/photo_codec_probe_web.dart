import 'dart:convert';
import 'dart:js_interop';

import 'photo_codec_probe_core.dart';

@JS('photoProbeInput')
external JSString get input;
@JS('photoProbeOutput')
external set output(JSString value);
void main() {
  final cases = jsonDecode(input.toDart) as List;
  output = jsonEncode([
    for (final c in cases) probePhoto(Map<String, dynamic>.from(c as Map)),
  ]).toJS;
}
