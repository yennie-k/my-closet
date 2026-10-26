import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/garment.dart';
import '../services/wardrobe_repository.dart';

class GarmentPhoto extends StatefulWidget {
  const GarmentPhoto({
    super.key,
    required this.garment,
    required this.repository,
    this.fit = BoxFit.cover,
  });
  final Garment garment;
  final WardrobeRepository repository;
  final BoxFit fit;
  @override
  State<GarmentPhoto> createState() => _GarmentPhotoState();
}

class _GarmentPhotoState extends State<GarmentPhoto> {
  late Future<Uint8List> _photo;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(GarmentPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.garment.updatedAt != widget.garment.updatedAt ||
        oldWidget.garment.id != widget.garment.id ||
        oldWidget.repository != widget.repository) {
      _load();
    }
  }

  void _load() => _photo = widget.repository.readImage(widget.garment.id);
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _photo,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const PhotoError();
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return Image.memory(
        snapshot.data!,
        fit: widget.fit,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: widget.fit == BoxFit.cover ? 500 : 1200,
        semanticLabel: '${widget.garment.name} 사진',
        errorBuilder: (_, _, _) => const PhotoError(),
      );
    },
  );
}

class PhotoError extends StatelessWidget {
  const PhotoError({super.key});
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: const Center(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, size: 32),
            SizedBox(height: 8),
            Text(
              '사진을 불러올 수 없어요.\n수정에서 다시 선택해 주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}
