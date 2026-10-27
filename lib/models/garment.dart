import 'dart:math';

import 'garment_options.dart' show standardColorHex;

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
  veryThin(1, '매우 얇음', '예: 얇은 시스루·쉬폰'),
  thin(2, '얇음', '예: 가벼운 여름 티셔츠'),
  medium(3, '보통', '예: 기본 셔츠·맨투맨'),
  thick(4, '두꺼움', '예: 도톰한 니트·데님'),
  veryThick(5, '매우 두꺼움', '예: 두툼한 코트·패딩');

  const GarmentThickness(this.level, this.label, this.example);
  final int level;
  final String label, example;

  static GarmentThickness? fromStorage(Map<String, Object?> json) {
    final level = json['thicknessLevel'];
    if (level != null) {
      return values.firstWhere(
        (v) => v.level == level,
        orElse: () => throw const FormatException('Invalid thickness level'),
      );
    }
    final legacy = json['thickness'];
    if (legacy == null) return null;
    return values.firstWhere(
      (v) => v.name == legacy || v.label == legacy || v.level == legacy,
      orElse: () => throw const FormatException('Unknown thickness'),
    );
  }
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
    List<String>? materials,
    this.fit = '',
    this.notes = '',
    this.imageMimeType = 'image/jpeg',
    required this.imageWidth,
    required this.imageHeight,
  }) : materials = List.unmodifiable(
         materials ?? (material.isEmpty ? <String>[] : [material]),
       ),
       additionalColors = List.unmodifiable(additionalColors),
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
  final List<String> materials;
  int? get thicknessLevel => thickness?.level;
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
    'version': 2,
    'id': id,
    'name': name,
    'category': category.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'subtype': subtype,
    'primaryColor': primaryColor,
    'primaryColorHex': standardColorHex(primaryColor),
    'additionalColors': additionalColors,
    'additionalColorDetails': additionalColors
        .map((name) => {'name': name, 'hex': standardColorHex(name)})
        .toList(),
    'seasons': seasons.map((v) => v.name).toList(),
    'thickness': thickness?.name,
    'thicknessLevel': thicknessLevel,
    'styleTags': styleTags,
    'material': material,
    'materials': materials,
    'fit': fit,
    'notes': notes,
    'imageMimeType': imageMimeType,
    'imageWidth': imageWidth,
    'imageHeight': imageHeight,
  };

  factory Garment.fromJson(Map<String, Object?> json) {
    final version = json['version'] ?? 1;
    if (version != 1 && version != 2) {
      throw const FormatException('Unsupported garment version');
    }
    return Garment(
      id: json['id'] as String,
      name: json['name'] as String,
      category: GarmentCategory.values.byName(json['category'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      subtype: json['subtype'] as String? ?? '',
      primaryColor: json['primaryColor'] as String? ?? '',
      additionalColors: (json['additionalColors'] as List? ?? [])
          .cast<String>(),
      seasons: (json['seasons'] as List? ?? [])
          .map((v) => Season.values.byName(v as String))
          .toList(),
      thickness: GarmentThickness.fromStorage(json),
      styleTags: (json['styleTags'] as List? ?? []).cast<String>(),
      material: json['material'] as String? ?? '',
      materials: (json['materials'] as List?)?.cast<String>(),
      fit: json['fit'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      imageMimeType: json['imageMimeType'] as String? ?? 'image/jpeg',
      imageWidth: json['imageWidth'] as int,
      imageHeight: json['imageHeight'] as int,
    );
  }
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
