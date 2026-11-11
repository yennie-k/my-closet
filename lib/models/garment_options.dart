import 'garment.dart';

const subtypeSuggestions = <GarmentCategory, List<String>>{
  GarmentCategory.tops: [
    '반팔 티셔츠',
    '긴팔 티셔츠',
    '셔츠',
    '블라우스',
    '니트',
    '맨투맨',
    '후드티',
    '가디건',
    '민소매',
    '폴로셔츠',
  ],
  GarmentCategory.bottoms: [
    '청바지',
    '슬랙스',
    '반바지',
    '미니스커트',
    '미디스커트',
    '롱스커트',
    '레깅스',
    '조거팬츠',
    '와이드 팬츠',
  ],
  GarmentCategory.outerwear: [
    '코트',
    '트렌치코트',
    '패딩',
    '경량 패딩',
    '재킷',
    '블레이저',
    '바람막이',
    '플리스',
    '점퍼',
  ],
  GarmentCategory.dresses: [
    '미니 원피스',
    '미디 원피스',
    '롱 원피스',
    '니트 원피스',
    '점프수트',
    '투피스 세트',
  ],
  GarmentCategory.shoes: ['운동화', '로퍼', '부츠', '앵클부츠', '플랫슈즈', '힐', '샌들', '슬리퍼'],
  GarmentCategory.bags: ['숄더백', '크로스백', '토트백', '백팩', '미니백', '에코백', '클러치'],
  GarmentCategory.accessories: [
    '목걸이',
    '귀걸이',
    '반지',
    '팔찌',
    '벨트',
    '모자',
    '스카프',
    '머플러',
  ],
  GarmentCategory.other: [],
};

class StandardGarmentColor {
  const StandardGarmentColor(this.name, this.hex);
  final String name, hex;
}

const garmentColors = [
  StandardGarmentColor('블랙', '#202020'),
  StandardGarmentColor('화이트', '#FFFFFF'),
  StandardGarmentColor('아이보리', '#F4EEDC'),
  StandardGarmentColor('베이지', '#D6BE98'),
  StandardGarmentColor('브라운', '#795548'),
  StandardGarmentColor('그레이', '#858585'),
  StandardGarmentColor('네이비', '#263650'),
  StandardGarmentColor('블루', '#3E78BB'),
  StandardGarmentColor('핑크', '#EAA5BE'),
  StandardGarmentColor('레드', '#C83F43'),
  StandardGarmentColor('버건디', '#752F45'),
  StandardGarmentColor('그린', '#4B805D'),
  StandardGarmentColor('옐로', '#F0D16B'),
  StandardGarmentColor('퍼플', '#8E6CB0'),
  StandardGarmentColor('오렌지', '#E89148'),
  StandardGarmentColor('카키', '#77794A'),
  StandardGarmentColor('카멜', '#BF8A55'),
  StandardGarmentColor('민트', '#A6D9C5'),
];

String? standardColorHex(String name) {
  for (final color in garmentColors) {
    if (color.name == name.trim()) return color.hex;
  }
  return null;
}

bool sameColorName(String a, String b) =>
    a.trim().toLowerCase() == b.trim().toLowerCase();

class MaterialOption {
  const MaterialOption(this.name, this.description, this.pattern);
  final String name, description;
  final int pattern;
}

// Patterns are schematic illustrations drawn in Flutter, not fabric photos.
const materialOptions = [
  MaterialOption('면', '부드러운 촉감의 기본 직물', 0),
  MaterialOption('데님', '사선 조직이 보이는 탄탄한 원단', 1),
  MaterialOption('폴리에스터', '매끈한 합성섬유 · 가공에 따라 달라요', 2),
  MaterialOption('나일론', '가볍고 매끈한 합성섬유', 2),
  MaterialOption('울', '잔털이 느껴지는 양모 섬유', 3),
  MaterialOption('캐시미어', '가늘고 부드러운 모섬유', 3),
  MaterialOption('린넨', '굵기가 불규칙한 자연스러운 조직', 0),
  MaterialOption('실크', '매끄럽고 은은한 광택', 2),
  MaterialOption('레이온', '부드럽게 흐르는 재생섬유', 2),
  MaterialOption('아크릴', '울과 비슷한 가벼운 합성섬유', 3),
  MaterialOption('가죽', '표면 결이 있는 탄탄한 소재', 4),
  MaterialOption('인조가죽', '가죽을 닮게 가공한 소재', 4),
  MaterialOption('스웨이드', '짧고 고운 털이 있는 표면', 3),
  MaterialOption('니트', '고리 모양으로 짠 편물 조직', 5),
  MaterialOption('플리스', '복슬한 털이 올라온 표면', 3),
  MaterialOption('쉬폰', '얇고 비침이 있는 가벼운 직물', 0),
  MaterialOption('코듀로이', '세로 골이 도드라지는 조직', 6),
  MaterialOption('퍼', '길거나 풍성한 털 질감', 7),
];

class FitOption {
  const FitOption(this.name, this.description);
  final String name, description;
}

// Presentation context only: stored category, subtype and fit values stay intact.
enum FitContext {
  tops,
  pants,
  shorts,
  leggings,
  skirt,
  coat,
  puffer,
  jacket,
  outerwear,
  dress,
  jumpsuit,
  set,
  optional,
}

FitContext fitContextFor(GarmentCategory? category, String subtype) {
  final kind = subtype.trim();
  if (category == GarmentCategory.tops) return FitContext.tops;
  if (category == GarmentCategory.outerwear) {
    if (kind.contains('코트')) return FitContext.coat;
    if (kind.contains('패딩')) return FitContext.puffer;
    if (['재킷', '자켓', '블레이저', '바람막이', '플리스', '점퍼'].any(kind.contains)) {
      return FitContext.jacket;
    }
    return FitContext.outerwear;
  }
  if (category == GarmentCategory.bottoms) {
    if (kind.contains('스커트') || kind.contains('치마')) return FitContext.skirt;
    if (kind.contains('반바지')) return FitContext.shorts;
    if (kind.contains('레깅스')) return FitContext.leggings;
    return FitContext.pants;
  }
  if (category == GarmentCategory.dresses) {
    if (kind.contains('점프수트')) return FitContext.jumpsuit;
    if (kind.contains('세트')) return FitContext.set;
    return FitContext.dress;
  }
  return FitContext.optional;
}

String fitContextLabel(GarmentCategory? category, String subtype) =>
    switch (fitContextFor(category, subtype)) {
      FitContext.tops => '상의',
      FitContext.pants => subtype.trim() == '조거팬츠' ? '조거팬츠' : '바지',
      FitContext.shorts => '반바지',
      FitContext.leggings => '레깅스',
      FitContext.skirt => '스커트',
      FitContext.coat => subtype.contains('트렌치') ? '트렌치코트' : '코트',
      FitContext.puffer => subtype.contains('경량') ? '경량 패딩' : '패딩',
      FitContext.jacket =>
        ['재킷', '블레이저', '바람막이', '플리스', '점퍼'].contains(subtype.trim())
            ? subtype.trim()
            : '재킷',
      FitContext.outerwear => '아우터',
      FitContext.dress => '원피스',
      FitContext.jumpsuit => '점프수트',
      FitContext.set => '세트',
      FitContext.optional => category?.label ?? '선택한 분류',
    };

List<FitOption> fitsForCategory(
  GarmentCategory? category, {
  String subtype = '',
}) {
  final context = fitContextFor(category, subtype);
  final kind = fitContextLabel(category, subtype);
  if (context == FitContext.tops && subtype.contains('민소매')) {
    return const [
      FitOption('슬림핏', '가슴과 허리의 몸선을 따라 여유가 적은 민소매'),
      FitOption('레귤러핏', '몸판에 적당한 여유를 둔 기본 민소매'),
      FitOption('오버핏', '몸판을 크게 잡은 넉넉한 민소매'),
      FitOption('루즈핏', '몸판이 몸에 붙지 않고 여유 있게 떨어지는 민소매'),
    ];
  }
  if ([
    FitContext.coat,
    FitContext.puffer,
    FitContext.jacket,
    FitContext.outerwear,
  ].contains(context)) {
    final puffer = context == FitContext.puffer;
    return [
      FitOption('레귤러핏', '$kind 안에 옷을 겹쳐 입을 수 있도록 어깨와 품에 적당한 여유를 둬요.'),
      FitOption('오버핏', '$kind의 어깨선과 품을 크게 잡은 넉넉한 실루엣이에요.'),
      FitOption('루즈핏', '$kind의 품과 소매가 몸에 붙지 않고 여유 있게 떨어져요.'),
      if (!puffer) FitOption('슬림핏', '$kind의 가슴과 허리선을 따라 품이 좁아지는 실루엣이에요.'),
      if (context == FitContext.coat) ...[
        const FitOption('A라인', '코트의 몸판이 아래로 갈수록 넓어지는 실루엣이에요.'),
        const FitOption('H라인', '코트의 몸판이 허리 굴곡 없이 곧게 떨어지는 실루엣이에요.'),
      ],
    ];
  }
  if (context == FitContext.pants && subtype.trim() == '조거팬츠') {
    return const [
      FitOption('테이퍼드핏', '허벅지는 여유 있고 밑단으로 갈수록 통이 좁아지는 조거팬츠'),
      FitOption('레귤러핏', '엉덩이와 허벅지에 적당한 여유를 둔 조거팬츠'),
      FitOption('루즈핏', '엉덩이와 다리에 넉넉한 여유를 둔 조거팬츠'),
    ];
  }
  return switch (context) {
    FitContext.tops => const [
      FitOption('슬림핏', '가슴과 허리의 몸선을 따라 여유가 적은 상의'),
      FitOption('레귤러핏', '어깨와 품에 적당한 여유를 둔 기본 상의'),
      FitOption('오버핏', '어깨선과 품을 크게 잡은 넉넉한 상의'),
      FitOption('루즈핏', '품과 소매가 편안하게 떨어지는 여유 있는 상의'),
    ],
    FitContext.pants => const [
      FitOption('와이드핏', '허벅지부터 밑단까지 통이 넓은 바지'),
      FitOption('스트레이트핏', '다리 옆선이 곧게 떨어지는 일자 바지'),
      FitOption('테이퍼드핏', '허벅지는 여유 있고 밑단으로 갈수록 좁아지는 바지'),
      FitOption('스키니핏', '허벅지부터 발목까지 다리선에 밀착되는 바지'),
      FitOption('슬림핏', '다리선을 따라 가늘게 떨어지는 바지'),
      FitOption('레귤러핏', '엉덩이와 허벅지에 적당한 여유를 둔 기본 바지'),
      FitOption('루즈핏', '엉덩이와 다리에 넉넉한 여유를 둔 바지'),
    ],
    FitContext.shorts => const [
      FitOption('레귤러핏', '엉덩이와 허벅지에 적당한 여유를 둔 반바지'),
      FitOption('와이드핏', '허벅지부터 밑단까지 통이 넓은 반바지'),
      FitOption('슬림핏', '엉덩이와 허벅지의 몸선을 따라 통이 좁은 반바지'),
      FitOption('루즈핏', '엉덩이와 허벅지에 넉넉한 여유를 둔 반바지'),
    ],
    FitContext.leggings => const [FitOption('스키니핏', '엉덩이부터 다리선을 따라 밀착되는 레깅스')],
    FitContext.skirt => const [
      FitOption('A라인', '허리에서 밑단으로 갈수록 퍼지는 스커트'),
      FitOption('H라인', '엉덩이 아래로 곧게 떨어지는 스커트'),
    ],
    FitContext.dress => const [
      FitOption('A라인', '상체보다 치마 밑단이 넓게 퍼지는 원피스'),
      FitOption('H라인', '상체부터 치마 밑단까지 곧게 떨어지는 원피스'),
      FitOption('슬림핏', '가슴과 허리의 몸선을 따라 떨어지는 원피스'),
      FitOption('레귤러핏', '몸에 적당한 여유를 두고 떨어지는 원피스'),
      FitOption('루즈핏', '전체적으로 넉넉한 여유를 둔 원피스'),
    ],
    FitContext.jumpsuit => const [
      FitOption('레귤러핏', '상체와 바지 부분에 적당한 여유를 둔 점프수트'),
      FitOption('슬림핏', '상체와 다리의 몸선을 따라 여유가 적은 점프수트'),
      FitOption('루즈핏', '상체와 바지 부분에 넉넉한 여유를 둔 점프수트'),
    ],
    FitContext.set => const [
      FitOption('레귤러핏', '구성된 옷들이 전반적으로 적당한 여유를 가진 세트'),
      FitOption('슬림핏', '구성된 옷들이 전반적으로 몸선을 따르는 세트'),
      FitOption('루즈핏', '구성된 옷들이 전반적으로 넉넉한 여유를 가진 세트'),
    ],
    FitContext.optional => const [],
    // Handled above so descriptions can use the actual outerwear subtype.
    FitContext.coat ||
    FitContext.puffer ||
    FitContext.jacket ||
    FitContext.outerwear => const [],
  };
}

bool needsFitReview(GarmentCategory? category, String subtype, String fit) =>
    fit.trim().isNotEmpty &&
    !fitsForCategory(
      category,
      subtype: subtype,
    ).any((option) => option.name == fit.trim());

bool subtypeBelongsToOtherCategory(GarmentCategory? category, String subtype) {
  final value = subtype.trim();
  if (value.isEmpty ||
      category == null ||
      (subtypeSuggestions[category] ?? []).contains(value)) {
    return false;
  }
  return subtypeSuggestions.entries.any(
    (entry) => entry.key != category && entry.value.contains(value),
  );
}

String thicknessExample(GarmentThickness thickness, GarmentCategory? category) {
  final clothingExamples = switch (category) {
    GarmentCategory.tops => const [
      '예: 매우 얇은 시스루 상의',
      '예: 가벼운 여름 티셔츠',
      '예: 기본 셔츠·맨투맨',
      '예: 도톰한 니트',
      '예: 매우 두툼한 니트·맨투맨',
    ],
    GarmentCategory.bottoms => const [
      '예: 매우 얇은 쉬폰 스커트',
      '예: 얇은 여름 바지·스커트',
      '예: 보통 두께의 면바지',
      '예: 도톰한 데님·코듀로이 바지',
      '예: 매우 두꺼운 원단의 바지·스커트',
    ],
    GarmentCategory.dresses => const [
      '예: 매우 얇은 쉬폰 원피스',
      '예: 가벼운 여름 원피스·세트',
      '예: 보통 두께의 원피스·세트',
      '예: 도톰한 니트 원피스',
      '예: 두툼한 울·니트 원피스·세트',
    ],
    _ => null,
  };
  if (clothingExamples != null) return clothingExamples[thickness.level - 1];
  if (category == GarmentCategory.outerwear) {
    return switch (thickness) {
      GarmentThickness.veryThin => '예: 매우 얇은 홑겹 바람막이',
      GarmentThickness.thin => '예: 가벼운 홑겹 재킷',
      GarmentThickness.medium => '예: 보통 두께의 재킷',
      GarmentThickness.thick => '예: 도톰한 울 코트',
      GarmentThickness.veryThick => '예: 부피감 있는 두툼한 패딩',
    };
  }
  if ([
    GarmentCategory.shoes,
    GarmentCategory.bags,
    GarmentCategory.accessories,
    GarmentCategory.other,
  ].contains(category)) {
    return const [
      '매우 얇고 가벼운 원단·재질',
      '얇은 원단·재질',
      '중간 정도 두께의 원단·재질',
      '도톰한 원단·재질',
      '매우 두툼한 원단·재질',
    ][thickness.level - 1];
  }
  return thickness.example;
}
