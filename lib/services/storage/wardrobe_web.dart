import 'package:idb_shim/idb_browser.dart';

import '../wardrobe_repository.dart';
import 'indexeddb_wardrobe_repository.dart';

// Never fall back to memory: the user must be told if persistence is unavailable.
WardrobeRepository createRepository() =>
    IndexedDbWardrobeRepository.lazy(() => idbFactoryNative);
