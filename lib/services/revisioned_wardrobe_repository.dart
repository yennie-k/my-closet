import '../models/garment.dart';
import 'wardrobe_repository.dart';

/// Allows metadata-only creation (photos are optional). A repository may also
/// implement ServerPhotoRepository for upload/verified-photo capabilities.
/// Photo policy belongs to the storage capability, not a navigation flag.
/// IndexedDB/file repositories do not implement this capability.
abstract interface class MetadataOnlyWardrobeRepository
    implements WardrobeRepository {}

/// Optional capability: the exact object read by the editor is the CAS baseline.
/// Local repositories and their persistence formats do not need to change.
abstract interface class RevisionedWardrobeRepository
    implements WardrobeRepository {
  Future<Garment> refresh(Garment original);
  Future<Garment> saveWithOriginal(Garment garment, {Garment? original});
  Future<void> deleteWithOriginal(Garment original);
}
