import 'package:flutter/material.dart';

import 'app.dart';
import 'services/preferences_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyClosetApp(store: LocalPreferencesStore()));
}
