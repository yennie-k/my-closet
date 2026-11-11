import 'package:flutter/material.dart';

import '../models/garment.dart';
import '../services/garment_photo_service.dart';
import '../services/wardrobe_repository.dart';
import '../services/revisioned_wardrobe_repository.dart';
import '../services/server_photo_repository.dart';
import '../widgets/server_photo_actions.dart';
import '../widgets/common.dart';
import '../widgets/garment_photo.dart';
import 'garment_editor_screen.dart';

class GarmentDetailScreen extends StatefulWidget {
  const GarmentDetailScreen({
    super.key,
    required this.garment,
    required this.repository,
    required this.photoService,
  });
  final Garment garment;
  final WardrobeRepository repository;
  final GarmentPhotoService photoService;
  bool get metadataOnly => repository is MetadataOnlyWardrobeRepository;
  @override
  State<GarmentDetailScreen> createState() => _GarmentDetailScreenState();
}

class _GarmentDetailScreenState extends State<GarmentDetailScreen> {
  late Garment _garment;
  bool _deleting = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _garment = widget.garment;
  }

  Future<void> _edit() async {
    final updated = await Navigator.push<Garment>(
      context,
      MaterialPageRoute(
        builder: (_) => GarmentEditorScreen(
          repository: widget.repository,
          photoService: widget.photoService,
          garment: _garment,
        ),
      ),
    );
    if (mounted && updated != null) {
      setState(() => _garment = updated);
    } else if (mounted && widget.repository is ServerPhotoRepository) {
      try {
        final current =
            await (widget.repository as RevisionedWardrobeRepository).refresh(
              _garment,
            );
        if (mounted) setState(() => _garment = current);
      } catch (e) {
        if (mounted) setState(() => _error = wardrobeError(e));
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('이 옷을 삭제할까요?'),
        content: Text(
          widget.metadataOnly
              ? '“${_garment.name}”의 서버 정보를 삭제해요. 사진·예약이 연결된 의류는 이 단계에서 삭제할 수 없어요. 이 기기의 옷장에는 영향을 주지 않아요.'
              : '“${_garment.name}”의 사진과 정보가 함께 삭제돼요. 삭제한 옷은 복원할 수 없어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제하기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      final repository = widget.repository;
      if (repository is RevisionedWardrobeRepository) {
        await repository.deleteWithOriginal(_garment);
      } else {
        await repository.delete(_garment.id);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = wardrobeError(e));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_deleting,
    child: Scaffold(
      appBar: AppBar(title: const Text('옷 상세 보기')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 850),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SurfaceCard(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      height: 350,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child:
                            widget.metadataOnly &&
                                widget.repository is! ServerPhotoRepository
                            ? const ServerPhotoPlaceholder()
                            : GarmentPhoto(
                                garment: _garment,
                                repository: widget.repository,
                                fit: BoxFit.contain,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (widget.repository is ServerPhotoRepository) ...[
                    ServerPhotoActions(
                      repository: widget.repository as ServerPhotoRepository,
                      garment: _garment,
                      onChanged: (value) => setState(() => _garment = value),
                    ),
                    const SizedBox(height: 24),
                  ],
                  Text(
                    _garment.name,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(_garment.category.label),
                  const SizedBox(height: 24),
                  SurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _info('세부 종류', _garment.subtype),
                        _info('대표 색상', _garment.primaryColor),
                        _info('추가 색상', _garment.additionalColors.join(' · ')),
                        _info(
                          '계절',
                          _garment.seasons.map((v) => v.label).join(' · '),
                        ),
                        _info('두께', _garment.thickness?.label ?? ''),
                        _info('스타일', _garment.styleTags.join(' · ')),
                        _info('소재', _garment.materials.join(' · ')),
                        _info('핏', _garment.fit),
                        _info('메모', _garment.notes),
                        const Divider(),
                        _info('등록일', _date(_garment.createdAt)),
                        _info('수정일', _date(_garment.updatedAt)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: _deleting ? null : _edit,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('정보 수정'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _deleting ? null : _delete,
                        icon: const Icon(Icons.delete_outline),
                        label: Text(_deleting ? '삭제 중…' : '의류 삭제'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  String _date(DateTime value) {
    final d = value.toLocal();
    return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget _info(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Text(value.isEmpty ? '입력하지 않음' : value)),
      ],
    ),
  );
}
