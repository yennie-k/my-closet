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

enum FitContext { tops, pants, skirt, dress, set, optional }

FitContext fitContextFor(GarmentCategory? category, String subtype) {
  if (category == GarmentCategory.tops ||
      category == GarmentCategory.outerwear) {
    return FitContext.tops;
  }
  if (category == GarmentCategory.bottoms) {
    return subtype.contains('스커트') || subtype.contains('치마')
        ? FitContext.skirt
        : FitContext.pants;
  }
  if (category == GarmentCategory.dresses) {
    return subtype.contains('세트') || subtype.contains('점프수트')
        ? FitContext.set
        : FitContext.dress;
  }
  return FitContext.optional;
}

List<FitOption> fitsForCategory(
  GarmentCategory? category, {
  String subtype = '',
}) => switch (fitContextFor(category, subtype)) {
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
  FitContext.set => const [
    FitOption('레귤러핏', '전체적으로 적당한 여유를 둔 세트·점프수트'),
    FitOption('슬림핏', '몸선을 따라 여유가 적은 세트·점프수트'),
    FitOption('루즈핏', '전체적으로 넉넉한 여유를 둔 세트·점프수트'),
  ],
  FitContext.optional => const [],
};
