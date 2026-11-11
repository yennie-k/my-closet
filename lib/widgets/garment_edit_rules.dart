import '../models/garment.dart';
import '../models/garment_options.dart';

/// Temporary editor decisions only. Never migrates or mutates a saved garment.
class GarmentClassificationChange {
  const GarmentClassificationChange({
    required this.subtype,
    required this.fit,
    this.clearSubtype = false,
    this.clearFit = false,
  });

  final String subtype, fit;
  final bool clearSubtype, clearFit;
  bool get needsReset => clearSubtype || clearFit;

  static GarmentClassificationChange category({
    required GarmentCategory target,
    required String subtype,
    required String fit,
  }) {
    // Free text has no reliable category ownership. Ask before clearing it in
    // an existing editor; the caller preserves the stored original throughout.
    final clearSubtype =
        subtype.trim().isNotEmpty &&
        !(subtypeSuggestions[target] ?? []).contains(subtype.trim());
    final nextSubtype = clearSubtype ? '' : subtype;
    final clearFit = needsFitReview(target, nextSubtype, fit);
    return GarmentClassificationChange(
      subtype: nextSubtype,
      fit: clearFit ? '' : fit,
      clearSubtype: clearSubtype,
      clearFit: clearFit,
    );
  }

  static GarmentClassificationChange subtypeChange({
    required GarmentCategory? category,
    required String subtype,
    required String fit,
  }) {
    final clearFit = needsFitReview(category, subtype, fit);
    return GarmentClassificationChange(
      subtype: subtype,
      fit: clearFit ? '' : fit,
      clearFit: clearFit,
    );
  }
}
