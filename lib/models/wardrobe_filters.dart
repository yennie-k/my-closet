import 'garment.dart';
import 'garment_options.dart' show subtypeSuggestions;

// null = all, empty string = no subtype. Keep these separate from user text
// such as literal names "전체" or "미분류". This never changes stored values.
String subtypeFilterValue(Garment garment) => garment.subtype.trim();

List<String> wardrobeSubtypes(
  List<Garment> garments, {
  GarmentCategory? category,
}) {
  final values = <String, String>{};
  var unclassified = false;
  if (category != null) {
    for (final value in subtypeSuggestions[category] ?? <String>[]) {
      values.putIfAbsent(value.toLowerCase(), () => value);
    }
  }
  for (final garment in garments) {
    if (category != null && garment.category != category) continue;
    final value = subtypeFilterValue(garment);
    if (value.isEmpty) {
      unclassified = true;
    } else {
      values.putIfAbsent(value.toLowerCase(), () => value);
    }
  }
  return [...values.values, if (unclassified) ''];
}

String subtypeFilterLabel(String value) => switch (value) {
  '' => '미분류',
  '전체' || '미분류' => '$value (직접 입력)',
  _ => value,
};

List<Garment> filterWardrobeBySubtype(
  List<Garment> garments,
  String query,
  String? subtype, {
  GarmentCategory? category,
}) {
  final name = query.trim().toLowerCase();
  return garments
      .where(
        (garment) =>
            (category == null || garment.category == category) &&
            (subtype == null ||
                subtypeFilterValue(garment).toLowerCase() ==
                    subtype.toLowerCase()) &&
            garment.name.toLowerCase().contains(name),
      )
      .toList();
}
