import '../wardrobe_repository.dart';
import 'wardrobe_stub.dart'
    if (dart.library.io) 'wardrobe_io.dart'
    if (dart.library.js_interop) 'wardrobe_web.dart'
    as platform;

WardrobeRepository createWardrobeRepository() => platform.createRepository();
