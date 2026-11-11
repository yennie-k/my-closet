import 'package:flutter/material.dart';

import '../services/auth_controller.dart';
import '../services/server_wardrobe_reader.dart';
import '../widgets/common.dart';
import 'auth_screen.dart';

class ServerWardrobeTestScreen extends StatefulWidget {
  const ServerWardrobeTestScreen({
    super.key,
    required this.auth,
    required this.reader,
  });
  final AuthController auth;
  final ServerWardrobeReader reader;

  @override
  State<ServerWardrobeTestScreen> createState() =>
      _ServerWardrobeTestScreenState();
}

class _ServerWardrobeTestScreenState extends State<ServerWardrobeTestScreen> {
  List<ServerGarmentSummary> _rows = [];
  String? _error;
  bool _loading = false;
  int _request = 0;
  late int _generation;

  @override
  void initState() {
    super.initState();
    _generation = widget.auth.generation;
    widget.auth.addListener(_authChanged);
    _load();
  }

  void _authChanged() {
    if (_generation != widget.auth.generation) {
      _generation = widget.auth.generation;
      _request++;
      _rows = [];
      _error = null;
      _loading = false;
      if (widget.auth.user != null) _load();
    }
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final user = widget.auth.user;
    if (user == null || widget.auth.restoring) return;
    final request = ++_request;
    final generation = widget.auth.generation;
    setState(() {
      _loading = true;
      _error = null;
      _rows = [];
    });
    try {
      final rows = await widget.reader.listOwn(user.id);
      if (mounted &&
          request == _request &&
          generation == widget.auth.generation) {
        setState(() => _rows = rows);
      }
    } catch (_) {
      if (mounted &&
          request == _request &&
          generation == widget.auth.generation) {
        setState(() => _error = '서버 의류를 불러오지 못했어요. 로그인 상태와 로컬 서버 연결을 확인해 주세요.');
      }
    } finally {
      if (mounted &&
          request == _request &&
          generation == widget.auth.generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    widget.auth.removeListener(_authChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('서버 의류 조회 테스트')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PageHeading(
                  eyebrow: 'LOCAL SUPABASE · READ ONLY',
                  title: '서버 테스트 옷장',
                  description: '이 기기의 내 옷장과 별개인 개발 데이터예요.\n의류·사진의 등록, 수정, 삭제, 이전은 하지 않아요.',
                ),
                const SizedBox(height: 24),
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.auth.user == null
                            ? '로그인이 필요해요.'
                            : widget.auth.user!.email,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          if (widget.auth.user == null)
                            FilledButton(
                              onPressed:
                                  widget.auth.busy || !widget.auth.available
                                  ? null
                                  : () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            AuthScreen(auth: widget.auth),
                                      ),
                                    ),
                              child: const Text('로그인 / 회원가입'),
                            )
                          else ...[
                            OutlinedButton(
                              onPressed: _loading || widget.auth.busy
                                  ? null
                                  : _load,
                              child: const Text('다시 조회'),
                            ),
                            TextButton(
                              onPressed: widget.auth.busy
                                  ? null
                                  : widget.auth.signOut,
                              child: const Text('로그아웃'),
                            ),
                          ],
                        ],
                      ),
                      if (widget.auth.error != null) Text(widget.auth.error!),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (_loading) const Center(child: CircularProgressIndicator()),
                if (_error != null)
                  Semantics(liveRegion: true, child: Text(_error!)),
                if (widget.auth.user != null &&
                    !_loading &&
                    _error == null) ...[
                  Text('본인 서버 의류 ${_rows.length}벌 · 최대 100벌 조회'),
                  if (_rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Text(
                        '이 계정에 등록된 서버 테스트 의류가 없어요. 로컬 옷은 자동으로 옮겨지지 않아요.',
                      ),
                    ),
                  for (final row in _rows)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SurfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              row.name,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(
                              '${_categoryLabel(row.category)} · ${row.subtype.isEmpty ? '미분류' : row.subtype}',
                            ),
                            Text(
                              '사진 상태: ${row.photoState == 'ready' ? '서버 검증 완료' : '대기'} · 사진 다운로드는 이번 단계에 포함되지 않아요.',
                            ),
                            SelectableText(
                              '서버 ID: ${row.id}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );

  String _categoryLabel(String category) =>
      const {
        'tops': '상의',
        'bottoms': '하의',
        'outerwear': '아우터',
        'dresses': '원피스·세트',
        'shoes': '신발',
        'bags': '가방',
        'accessories': '액세서리',
        'other': '기타',
      }[category] ??
      category;
}
