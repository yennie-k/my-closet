import 'package:flutter_test/flutter_test.dart';
import 'package:my_closet/models/user_preferences.dart';

void main() {
  test('Preferences survive serialization with all selections', () {
    const preferences = UserPreferences(
      design: AppDesign.lovely,
      styles: ['캐주얼', '빈티지'],
      temperature: TemperaturePreference.cold,
      onboardingComplete: true,
    );
    final restored = UserPreferences.fromJson(preferences.toJson());
    expect(restored.design, AppDesign.lovely);
    expect(restored.styles, ['캐주얼', '빈티지']);
    expect(restored.temperature, TemperaturePreference.cold);
    expect(restored.onboardingComplete, isTrue);
  });
  test('Invalid stored selections recover with safe defaults', () {
    final restored = UserPreferences.fromJson({
      'design': 'unknown',
      'styles': [42, 'unknown'],
      'temperature': null,
      'onboardingComplete': true,
    });
    expect(restored.design, AppDesign.minimal);
    expect(restored.temperature, TemperaturePreference.normal);
    expect(restored.styles, isEmpty);
    expect(restored.onboardingComplete, isFalse);
  });
}
