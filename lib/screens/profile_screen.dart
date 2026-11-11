import 'package:flutter/material.dart';

import '../models/user_preferences.dart';
import '../widgets/common.dart';
import '../widgets/preference_fields.dart';
import '../services/auth_controller.dart';
import '../services/server_wardrobe_reader.dart';
import '../widgets/auth_account_card.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.preferences,
    required this.onSave,
    this.auth,
    this.serverReader,
    this.serverCrudEnabled = false,
  });
  final UserPreferences preferences;
  final Future<void> Function(UserPreferences) onSave;
  final AuthController? auth;
  final ServerWardrobeReader? serverReader;
  final bool serverCrudEnabled;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late UserPreferences _draft;
  bool _saving = false;
  String? _error;
  bool get _dirty =>
      _draft.design != widget.preferences.design ||
      _draft.temperature != widget.preferences.temperature ||
      !_sameStyles(_draft.styles, widget.preferences.styles);
  bool _sameStyles(List<String> a, List<String> b) =>
      a.length == b.length && a.every(b.contains);
  @override
  void initState() {
    super.initState();
    _draft = widget.preferences;
  }

  @override
  void didUpdateWidget(ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preferences != widget.preferences) {
      _draft = widget.preferences;
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_draft);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('나의 취향을 저장했어요.')));
      }
    } catch (_) {
      if (mounted) setState(() => _error = '설정을 저장하지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const PageHeading(
        eyebrow: 'MY PREFERENCES',
        title: '취향은 언제든 달라지니까요.',
        description: '지금의 나에게 맞게, 나만의 옷장을 다시 꾸며보세요.',
      ),
      const SizedBox(height: 32),
      if (widget.auth != null) ...[
        AuthAccountCard(
          auth: widget.auth!,
          reader: widget.serverReader,
          serverCrudEnabled: widget.serverCrudEnabled,
        ),
        const SizedBox(height: 32),
      ],
      _title('01', '앱 디자인', '세 가지 분위기 중 마음에 드는 디자인을 골라보세요.'),
      const SizedBox(height: 16),
      AbsorbPointer(
        absorbing: _saving,
        child: DesignSelector(
          value: _draft.design,
          onChanged: (v) => setState(() => _draft = _draft.copyWith(design: v)),
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        '카드에서 색상을 미리 볼 수 있어요. 저장하면 앱 전체에 적용돼요.',
        style: TextStyle(fontSize: 12),
      ),
      const SizedBox(height: 32),
      _title('02', '패션 추구미', '좋아하는 스타일을 한 가지 이상 골라주세요. 복수 선택이 가능해요.'),
      const SizedBox(height: 16),
      AbsorbPointer(
        absorbing: _saving,
        child: StyleSelector(
          values: _draft.styles,
          onChanged: (v) => setState(() => _draft = _draft.copyWith(styles: v)),
        ),
      ),
      if (_draft.styles.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            '한 가지 이상 선택해 주세요.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      const SizedBox(height: 32),
      _title('03', '체감온도 성향', '평소 몸이 느끼는 온도를 알려주세요.'),
      const SizedBox(height: 16),
      AbsorbPointer(
        absorbing: _saving,
        child: TemperatureSelector(
          value: _draft.temperature,
          onChanged: (v) =>
              setState(() => _draft = _draft.copyWith(temperature: v)),
        ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      const SizedBox(height: 24),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton(
            onPressed: _saving || !_dirty || _draft.styles.isEmpty
                ? null
                : _save,
            child: Text(_saving ? '저장 중…' : '설정 저장하기'),
          ),
          OutlinedButton(
            onPressed: _saving || !_dirty
                ? null
                : () => setState(() {
                    _draft = widget.preferences;
                    _error = null;
                  }),
            child: const Text('변경 취소'),
          ),
        ],
      ),
      const SizedBox(height: 20),
      const Text(
        '설정은 이 기기의 브라우저 또는 앱에 저장돼요.\n브라우저 데이터를 삭제하면 설정도 초기화될 수 있어요.',
        style: TextStyle(fontSize: 12, color: Color(0xFF777777)),
      ),
    ],
  );

  Widget _title(String number, String title, String description) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$number  $title', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(description),
    ],
  );
}
