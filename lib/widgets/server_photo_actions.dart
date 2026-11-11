import 'package:flutter/material.dart';

import '../models/garment.dart';
import '../services/server_photo_repository.dart';
import '../services/wardrobe_repository.dart';

class ServerPhotoActions extends StatefulWidget {
  const ServerPhotoActions({
    super.key,
    required this.repository,
    required this.garment,
    required this.onChanged,
  });
  final ServerPhotoRepository repository;
  final Garment garment;
  final ValueChanged<Garment> onChanged;
  @override
  State<ServerPhotoActions> createState() => _ServerPhotoActionsState();
}

class _ServerPhotoActionsState extends State<ServerPhotoActions> {
  bool _busy = false;
  String? _error;
  Future<void> _run(
    Future<Garment> Function() action, {
    bool confirmation = false,
  }) async {
    if (_busy) return;
    if (confirmation) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('이 사진 작업을 진행할까요?'),
          content: const Text(
            '서버의 활성 사진은 삭제 예약 후 25시간 보호돼요. 보호 기간에는 다시 교체하거나 의류를 삭제할 수 없어요. 업로드 취소는 기존 활성 사진을 유지해요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('진행하기'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = await action();
      if (mounted) widget.onChanged(value);
    } catch (e) {
      if (mounted) setState(() => _error = wardrobeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.repository.photoStatus(widget.garment);
    final cleanup = state.cleanupAfter;
    const labels = {
      'reserved': '사진 전송 대기',
      'client_confirmed': '전송 완료 · 검증 대기',
      'checking': '서버 검증 중',
      'failed': '실패',
    };
    const reasons = {
      'hash_mismatch': '파일 해시 불일치',
      'size_mismatch': '파일 크기 불일치',
      'mime_mismatch': '사진 형식 불일치',
      'invalid_image': '손상되었거나 지원하지 않는 사진',
      'expired': '예약 만료',
      'not_found': '전송된 파일을 찾지 못함',
      'cancelled': '업로드 취소',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          state.ready
              ? '서버에서 검증된 사진이에요.'
              : '서버에서 승인된 사진이 없어요. 사진 없이 의류 정보를 관리할 수 있어요.',
        ),
        if (state.uploadState != 'none')
          Text(
            '업로드 상태: ${labels[state.uploadState] ?? '확인 필요'}${state.errorCode == null ? '' : ' · ${reasons[state.errorCode] ?? '검증 실패'}'}',
          ),
        if (cleanup != null)
          Text(
            '이전 사진 정리 가능 시각: ${cleanup.toLocal().toString().split('.').first}\n정리 전에는 다음 교체·의류 삭제가 제한돼요.',
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if ([
              'client_confirmed',
              'checking',
              'failed',
            ].contains(state.uploadState))
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => widget.repository.verifyPendingPhoto(
                          widget.garment,
                        ),
                      ),
                child: const Text('검증 재시도'),
              ),
            if (state.uploadState != 'none')
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => widget.repository.cancelPendingPhoto(
                          widget.garment,
                        ),
                        confirmation: true,
                      ),
                child: const Text('남은 업로드 취소'),
              ),
            if (state.ready)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => widget.repository.removePhoto(widget.garment),
                        confirmation: true,
                      ),
                child: const Text('사진 삭제 예약'),
              ),
            if (cleanup != null)
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => widget.repository.cleanupPhoto(widget.garment),
                      ),
                child: const Text('보호 기간 지난 사진 정리'),
              ),
          ],
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('사진 상태를 처리하고 있어요…'),
          ),
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
