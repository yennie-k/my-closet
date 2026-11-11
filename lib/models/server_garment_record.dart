import 'garment.dart';

/// Server identity/concurrency/photo envelope, never serialized into IndexedDB.
class ServerGarmentRecord {
  ServerGarmentRecord(Map<String, dynamic> row)
    : raw = Map.unmodifiable(row),
      serverId = row['id'] as String,
      userId = row['user_id'] as String,
      revision = (row['revision'] as num).toInt(),
      garment = Garment.fromJson({
        'version': row['model_version'],
        'id': row['local_id'],
        'name': row['name'],
        'category': row['category'],
        'createdAt': row['created_at'],
        'updatedAt': row['updated_at'],
        'subtype': row['subtype'],
        'primaryColor': row['primary_color'],
        'additionalColors': row['additional_colors'],
        'seasons': row['seasons'],
        'thickness': row['thickness'],
        'thicknessLevel': row['thickness_level'],
        'styleTags': row['style_tags'],
        'material': row['material'],
        'materials': row['materials'],
        'fit': row['fit'],
        'notes': row['notes'],
        'imageMimeType': row['image_mime_type'],
        'imageWidth': row['image_width'],
        'imageHeight': row['image_height'],
      });

  final Map<String, dynamic> raw;
  final String serverId, userId;
  final int revision;
  final Garment garment; // garment.id == local_id, never the server UUID.

  bool get hasPhotoWorkflow =>
      raw['photo_state'] != 'pending' ||
      raw['photo_path'] != null ||
      raw['upload_state'] != 'none' ||
      raw['upload_path'] != null ||
      raw['retired_photo_path'] != null;

  static Map<String, dynamic> metadata(
    Garment value, {
    ServerGarmentRecord? original,
  }) {
    final json = value.toJson();
    // Preserve server/custom HEX values when names have not changed. The v2
    // domain model derives standard HEX values and has no custom HEX editor.
    final details = original?.raw['additional_color_details'];
    final oldNames = original?.garment.additionalColors;
    final sameNames =
        oldNames != null &&
        oldNames.length == value.additionalColors.length &&
        value.additionalColors.asMap().entries.every(
          (e) => oldNames[e.key] == e.value,
        );
    final oldDetails = <String, dynamic>{
      if (details is List)
        for (final item in details)
          if (item is Map && item['name'] is String)
            item['name'] as String: Map<String, dynamic>.from(item),
    };
    return {
      'model_version': 2,
      'name': value.name,
      'category': value.category.name,
      'updated_at': value.updatedAt.toUtc().toIso8601String(),
      'subtype': value.subtype,
      'primary_color': value.primaryColor,
      'primary_color_hex':
          original != null &&
              original.garment.primaryColor == value.primaryColor
          ? original.raw['primary_color_hex']
          : json['primaryColorHex'],
      'additional_colors': value.additionalColors,
      'additional_color_details': sameNames
          ? details
          : [
              for (final item in (json['additionalColorDetails'] as List))
                oldDetails[(item as Map)['name']] ?? item,
            ],
      'seasons': value.seasons.map((v) => v.name).toList(),
      'thickness': value.thickness?.name,
      'thickness_level': value.thicknessLevel,
      'style_tags': value.styleTags,
      'material': value.material,
      'materials': value.materials,
      'fit': value.fit,
      'notes': value.notes,
    };
  }

  static Map<String, dynamic> insert(Garment value, String userId) => {
    ...metadata(value),
    'user_id': userId,
    'local_id': value.id,
    'source_model_version': 2,
    'created_at': value.createdAt.toUtc().toIso8601String(),
    'image_mime_type': value.imageMimeType,
    'image_width': value.imageWidth,
    'image_height': value.imageHeight,
    // Photo workflow uses secure DB defaults; no client attestation fields.
  };
}
