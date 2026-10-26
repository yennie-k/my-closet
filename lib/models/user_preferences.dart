enum AppDesign {
  minimal('미니멀', '아이보리 · 베이지'),
  lovely('러블리', '핑크 · 파스텔'),
  modern('모던', '블랙 · 화이트');

  const AppDesign(this.label, this.description);
  final String label;
  final String description;
}

enum TemperaturePreference {
  cold('추위를 많이 탐', '선선한 날에도 따뜻하게 입는 편이에요.'),
  normal('보통', '날씨에 맞춰 가볍게 조절하는 편이에요.'),
  hot('더위를 많이 탐', '가볍고 시원한 옷을 선호해요.');

  const TemperaturePreference(this.label, this.description);
  final String label;
  final String description;
}

const fashionStyles = ['미니멀', '캐주얼', '스트릿', '페미닌', '시크', '스포티', '빈티지'];

class UserPreferences {
  const UserPreferences({
    this.design = AppDesign.minimal,
    this.styles = const [],
    this.temperature = TemperaturePreference.normal,
    this.onboardingComplete = false,
  });
  final AppDesign design;
  final List<String> styles;
  final TemperaturePreference temperature;
  final bool onboardingComplete;

  UserPreferences copyWith({
    AppDesign? design,
    List<String>? styles,
    TemperaturePreference? temperature,
    bool? onboardingComplete,
  }) => UserPreferences(
    design: design ?? this.design,
    styles: styles == null ? this.styles : List.unmodifiable(styles),
    temperature: temperature ?? this.temperature,
    onboardingComplete: onboardingComplete ?? this.onboardingComplete,
  );

  Map<String, dynamic> toJson() => {
    'version': 1,
    'design': design.name,
    'styles': styles,
    'temperature': temperature.name,
    'onboardingComplete': onboardingComplete,
  };

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    final raw = json['styles'];
    final styles = raw is List
        ? fashionStyles.where(raw.contains).toList()
        : <String>[];
    return UserPreferences(
      design: AppDesign.values.firstWhere(
        (v) => v.name == json['design'],
        orElse: () => AppDesign.minimal,
      ),
      styles: List.unmodifiable(styles),
      temperature: TemperaturePreference.values.firstWhere(
        (v) => v.name == json['temperature'],
        orElse: () => TemperaturePreference.normal,
      ),
      onboardingComplete:
          json['onboardingComplete'] == true && styles.isNotEmpty,
    );
  }
}
