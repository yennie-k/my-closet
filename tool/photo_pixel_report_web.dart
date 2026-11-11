// Diagnostic app only: numerical report in page memory, no image/pixel bytes.
import 'dart:convert';
import 'dart:js_interop';

@JS('myClosetPixelReportJson')
external set _report(JSString? value);
void publishPixelReport(Map<String, Object?>? report) {
  _report = report == null ? null : jsonEncode(report).toJS;
}
