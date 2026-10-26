import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../models/garment.dart';
import '../wardrobe_repository.dart';

WardrobeRepository createRepository() => FileWardrobeRepository(
  () async =>
      Directory('${(await getApplicationSupportDirectory()).path}/wardrobe_v1'),
);

// Each .closet file contains a 4-byte header length, UTF-8 metadata, then raw
// image bytes. Replacement is prepared in a temporary file before rename.
class FileWardrobeRepository implements WardrobeRepository {
  FileWardrobeRepository(this.directoryProvider);
  final Future<Directory> Function() directoryProvider;
  Future<Directory> _directory() async =>
      (await directoryProvider()).create(recursive: true);
  Future<File> _file(String id) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const WardrobeException('옷 ID가 올바르지 않아요.');
    }
    return File('${(await _directory()).path}/$id.closet');
  }

  Future<(Garment, int)> _header(File file) async {
    final handle = await file.open();
    try {
      final size = await handle.read(4);
      if (size.length != 4) throw const FormatException();
      final length = ByteData.sublistView(size).getUint32(0);
      if (length == 0 || length > 65536) throw const FormatException();
      final data = await handle.read(length);
      return (
        Garment.fromJson(
          Map<String, Object?>.from(jsonDecode(utf8.decode(data)) as Map),
        ),
        length + 4,
      );
    } finally {
      await handle.close();
    }
  }

  @override
  Future<List<Garment>> list() async {
    final items = <Garment>[];
    await for (final file in (await _directory()).list()) {
      if (file is File && file.path.endsWith('.closet')) {
        try {
          items.add((await _header(file)).$1);
        } catch (_) {
          throw const WardrobeException(
            '저장된 옷 정보가 손상되어 읽지 못했어요. 원본 파일은 보관하고 있어요.',
          );
        }
      }
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  @override
  Future<Uint8List> readImage(String id) async {
    final file = await _file(id);
    final offset = (await _header(file)).$2;
    final data = await file.readAsBytes();
    if (data.length <= offset) {
      throw const WardrobeException('사진이 손상됐어요. 사진을 다시 선택해 주세요.');
    }
    return Uint8List.sublistView(data, offset);
  }

  @override
  Future<void> save(Garment garment, {Uint8List? imageBytes}) async {
    final image = imageBytes ?? await readImage(garment.id);
    if (image.isEmpty) throw const WardrobeException('사진이 필요해요.');
    final header = utf8.encode(jsonEncode(garment.toJson()));
    final length = ByteData(4)..setUint32(0, header.length);
    final output = BytesBuilder()
      ..add(length.buffer.asUint8List())
      ..add(header)
      ..add(image);
    final target = await _file(garment.id);
    final temp = File('${target.path}.${Garment.newId()}.tmp');
    try {
      await temp.writeAsBytes(output.takeBytes(), flush: true);
      await temp.rename(target.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  @override
  Future<void> delete(String id) async {
    final file = await _file(id);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> close() async {}
}
