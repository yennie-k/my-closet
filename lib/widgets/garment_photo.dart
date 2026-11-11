import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/garment.dart';
import '../services/wardrobe_repository.dart';
import '../services/server_photo_repository.dart';

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
  Uint8List? _serverBytes;
  int _generation = 0;
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
        oldWidget.repository != widget.repository ||
        (widget.repository is ServerPhotoRepository &&
            (widget.repository as ServerPhotoRepository).photoKey(
                  oldWidget.garment,
                ) !=
                (widget.repository as ServerPhotoRepository).photoKey(
                  widget.garment,
                ))) {
      _load();
    }
  }

  void _load() {
    _generation++;
    final old = _serverBytes;
    _serverBytes = null;
    if (old != null) MemoryImage(old).evict();
    final repository = widget.repository;
    if (repository is ServerPhotoRepository &&
        !repository.photoStatus(widget.garment).ready) {
      _photo = Future.value(Uint8List(0));
      return;
    }
    _photo = repository is ServerPhotoRepository
        ? repository.readVerifiedPhoto(widget.garment)
        : repository.readImage(widget.garment.id);
  }

  @override
  void dispose() {
    final bytes = _serverBytes;
    if (bytes != null) MemoryImage(bytes).evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final server = widget.repository is ServerPhotoRepository;
    if (server &&
        !(widget.repository as ServerPhotoRepository)
            .photoStatus(widget.garment)
            .ready) {
      return const ServerPhotoPlaceholder();
    }
    return FutureBuilder<Uint8List>(
      key: ValueKey(_generation),
      future: _photo,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return server
              ? const Center(
                  child: Text(
                    '검증된 사진을 불러오지 못했어요.\n로그인 상태와 연결을 확인해 주세요.',
                    textAlign: TextAlign.center,
                  ),
                )
              : const PhotoError();
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (server) _serverBytes = snapshot.data;
        return Image.memory(
          snapshot.data!,
          fit: widget.fit,
          width: double.infinity,
          height: double.infinity,
          cacheWidth: server
              ? null
              : widget.fit == BoxFit.cover
              ? 500
              : 1200,
          semanticLabel: '${widget.garment.name} 사진',
          errorBuilder: (_, _, _) => const PhotoError(),
        );
      },
    );
  }
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

/// No network request and no synthetic picture presented as a user's photo.
class ServerPhotoPlaceholder extends StatelessWidget {
  const ServerPhotoPlaceholder({super.key});
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: const Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.checkroom_outlined, size: 42),
            SizedBox(height: 8),
            Text('사진 연결 전\n의류 정보만 관리해요.', textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}
