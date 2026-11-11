// Standalone synthetic-only browser probe. No Auth, IndexedDB or HTTP APIs.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:my_closet/models/garment.dart';
import 'package:my_closet/screens/garment_editor_screen.dart';
import 'package:my_closet/services/garment_photo_service.dart';
import 'package:my_closet/services/revisioned_wardrobe_repository.dart';

class _MemoryProbe implements MetadataOnlyWardrobeRepository {
  final rows = <String, Garment>{};
  @override
  Future<List<Garment>> list() async => rows.values.toList();
  @override
  Future<void> save(Garment g, {Uint8List? imageBytes}) async => rows[g.id] = g;
  @override
  Future<void> delete(String id) async {
    rows.remove(id);
  }

  @override
  Future<Uint8List> readImage(String id) async =>
      throw StateError('No probe photos');
  @override
  Future<void> close() async {}
}

class _NoPhoto implements GarmentPhotoService {
  @override
  Future<ProcessedPhoto?> pick() async => null;
}

void main() {
  final repository = _MemoryProbe();
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => FilledButton(
              onPressed: () => Navigator.push<Garment>(
                context,
                MaterialPageRoute(
                  settings: const RouteSettings(name: '/probe-editor'),
                  builder: (_) => GarmentEditorScreen(
                    repository: repository,
                    photoService: _NoPhoto(),
                  ),
                ),
              ),
              child: const Text('합성 편집 열기'),
            ),
          ),
        ),
      ),
    ),
  );
}
