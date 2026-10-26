import 'dart:math';

enum GarmentCategory {
  tops('상의'),
  bottoms('하의'),
  outerwear('아우터'),
  dresses('원피스/세트'),
  shoes('신발'),
  bags('가방'),
  accessories('액세서리'),
  other('기타');

  const GarmentCategory(this.label);
  final String label;
}

enum Season {
  spring('봄'),
  summer('여름'),
  autumn('가을'),
  winter('겨울');

  const Season(this.label);
  final String label;
}

enum GarmentThickness {
  thin('얇음'),
  medium('보통'),
  thick('두꺼움');

  const GarmentThickness(this.label);
  final String label;
}

class Garment {
  Garment({
    required this.id,
    required this.name,
    required this.category,
    required this.createdAt,
    required this.updatedAt,
    this.subtype = '',
    this.primaryColor = '',
    List<String> additionalColors = const [],
    List<Season> seasons = const [],
    this.thickness,
    List<String> styleTags = const [],
    this.material = '',
    this.fit = '',
    this.notes = '',
    this.imageMimeType = 'image/jpeg',
    required this.imageWidth,
    required this.imageHeight,
  }) : additionalColors = List.unmodifiable(additionalColors),
       seasons = List.unmodifiable(seasons),
       styleTags = List.unmodifiable(styleTags);

  final String id,
      name,
      subtype,
      primaryColor,
      material,
      fit,
      notes,
      imageMimeType;
  final GarmentCategory category;
  final List<String> additionalColors, styleTags;
  final List<Season> seasons;
  final GarmentThickness? thickness;
  final DateTime createdAt, updatedAt;
  final int imageWidth, imageHeight;

  static String newId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id,
    'name': name,
    'category': category.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'subtype': subtype,
    'primaryColor': primaryColor,
    'additionalColors': additionalColors,
    'seasons': seasons.map((v) => v.name).toList(),
    'thickness': thickness?.name,
    'styleTags': styleTags,
    'material': material,
    'fit': fit,
    'notes': notes,
    'imageMimeType': imageMimeType,
    'imageWidth': imageWidth,
    'imageHeight': imageHeight,
  };

  factory Garment.fromJson(Map<String, Object?> json) => Garment(
    id: json['id'] as String,
    name: json['name'] as String,
    category: GarmentCategory.values.byName(json['category'] as String),
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    subtype: json['subtype'] as String? ?? '',
    primaryColor: json['primaryColor'] as String? ?? '',
    additionalColors: (json['additionalColors'] as List? ?? []).cast<String>(),
    seasons: (json['seasons'] as List? ?? [])
        .map((v) => Season.values.byName(v as String))
        .toList(),
    thickness: json['thickness'] == null
        ? null
        : GarmentThickness.values.byName(json['thickness'] as String),
    styleTags: (json['styleTags'] as List? ?? []).cast<String>(),
    material: json['material'] as String? ?? '',
    fit: json['fit'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
    imageMimeType: json['imageMimeType'] as String? ?? 'image/jpeg',
    imageWidth: json['imageWidth'] as int,
    imageHeight: json['imageHeight'] as int,
  );
}

List<Garment> filterGarments(
  List<Garment> items,
  String query,
  GarmentCategory? category,
) {
  final normalized = query.trim().toLowerCase();
  return items
      .where(
        (item) =>
            (category == null || item.category == category) &&
            item.name.toLowerCase().contains(normalized),
      )
      .toList();
}
