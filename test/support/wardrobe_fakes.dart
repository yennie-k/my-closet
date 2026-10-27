import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:my_closet/models/garment.dart';
import 'package:my_closet/services/garment_photo_service.dart';
import 'package:my_closet/services/wardrobe_repository.dart';

Uint8List testPhoto() => img.encodeJpg(img.Image(width: 8, height: 8));

Garment testGarment({
  String? id,
  String name = '아이보리 셔츠',
  GarmentCategory category = GarmentCategory.tops,
  String subtype = '',
}) => Garment(
  id: id ?? Garment.newId(),
  name: name,
  category: category,
  subtype: subtype,
  createdAt: DateTime.utc(2026, 10, 26),
  updatedAt: DateTime.utc(2026, 10, 26),
  imageWidth: 8,
  imageHeight: 8,
);

class MemoryWardrobe implements WardrobeRepository {
  final items = <String, Garment>{};
  final photos = <String, Uint8List>{};
  bool failSave = false, failDelete = false, failList = false;
  @override
  Future<List<Garment>> list() async {
    if (failList) throw const WardrobeException('목록을 불러오지 못했어요.');
    return items.values.toList();
  }

  @override
  Future<Uint8List> readImage(String id) async {
    final photo = photos[id];
    if (photo == null) throw const WardrobeException('사진 없음');
    return photo;
  }

  @override
  Future<void> save(Garment garment, {Uint8List? imageBytes}) async {
    if (failSave) throw const WardrobeException('저장 공간이 부족해요. 다시 시도해 주세요.');
    items[garment.id] = garment;
    if (imageBytes != null) photos[garment.id] = imageBytes;
  }

  @override
  Future<void> delete(String id) async {
    if (failDelete) throw const WardrobeException('삭제하지 못했어요. 다시 시도해 주세요.');
    items.remove(id);
    photos.remove(id);
  }

  @override
  Future<void> close() async {}
}

class FakePhotoService implements GarmentPhotoService {
  bool fail = false, cancel = false;
  @override
  Future<ProcessedPhoto?> pick() async {
    if (fail) throw const WardrobeException('손상된 사진이에요.');
    return cancel ? null : ProcessedPhoto(testPhoto(), 8, 8);
  }
}
