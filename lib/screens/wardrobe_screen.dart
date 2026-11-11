import 'package:flutter/material.dart';

import '../models/garment.dart';
import '../models/wardrobe_filters.dart';
import '../services/garment_photo_service.dart';
import '../services/wardrobe_repository.dart';
import '../services/revisioned_wardrobe_repository.dart';
import '../services/server_photo_repository.dart';
import '../widgets/common.dart';
import '../widgets/garment_photo.dart';
import 'garment_detail_screen.dart';
import 'garment_editor_screen.dart';

class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({
    super.key,
    required this.repository,
    required this.photoService,
  });
  final WardrobeRepository repository;
  final GarmentPhotoService photoService;
  bool get metadataOnly => repository is MetadataOnlyWardrobeRepository;
  @override
  State<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
  List<Garment> _items = [];
  GarmentCategory? _category;
  String? _subtype;
  String _query = '';
  bool _loading = true;
  String? _error;
  final _search = TextEditingController();
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.repository.list();
      if (mounted && request == _request) {
        setState(() {
          _items = items;
          if (_subtype != null &&
              !wardrobeSubtypes(
                items,
                category: _category,
              ).any((v) => v.toLowerCase() == _subtype!.toLowerCase())) {
            _subtype = null;
          }
        });
      }
    } catch (e) {
      if (mounted && request == _request) {
        setState(() => _error = wardrobeError(e));
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final saved = await Navigator.push<Garment>(
      context,
      MaterialPageRoute(
        builder: (_) => GarmentEditorScreen(
          repository: widget.repository,
          photoService: widget.photoService,
        ),
      ),
    );
    if (!mounted) return;
    if (saved == null) {
      // Metadata may have committed before a photo failure or cancelled form.
      if (widget.repository is ServerPhotoRepository) await _load();
      return;
    }
    setState(() {
      _category = null;
      _subtype = null;
      _query = '';
      _search.clear();
    });
    await _load();
  }

  Future<void> _open(Garment garment) async {
    try {
      final repository = widget.repository;
      if (repository is RevisionedWardrobeRepository) {
        garment = await repository.refresh(garment);
      }
    } catch (e) {
      if (mounted) setState(() => _error = wardrobeError(e));
      return;
    }
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => GarmentDetailScreen(
          garment: garment,
          repository: widget.repository,
          photoService: widget.photoService,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final base = MediaQuery.sizeOf(context).width >= 900 ? 48.0 : 22.0;
      final contentWidth = (constraints.maxWidth - base * 2).clamp(0.0, 1060.0);
      final horizontal = (constraints.maxWidth - contentWidth) / 2;
      final visible = filterWardrobeBySubtype(
        _items,
        _query,
        _subtype,
        category: _category,
      );
      final subtypeFilters = wardrobeSubtypes(_items, category: _category);
      final categoryChips = <Widget>[
        for (final category in <GarmentCategory?>[
          null,
          ...GarmentCategory.values,
        ])
          ChoiceChip(
            key: ValueKey('category-filter-${category?.name ?? 'all'}'),
            label: Text(_categoryLabel(category)),
            labelStyle: const TextStyle(fontWeight: FontWeight.w700),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            selectedColor: Theme.of(context).colorScheme.primaryContainer,
            selected: _category == category,
            onSelected: (_) => setState(() {
              _category = category;
              _subtype = null;
            }),
          ),
      ];
      final filterChips = <Widget>[
        ChoiceChip(
          key: const ValueKey('subtype-filter-all'),
          label: const Text('전체'),
          selected: _subtype == null,
          onSelected: (_) => setState(() => _subtype = null),
          visualDensity: VisualDensity.compact,
        ),
        ...subtypeFilters.map(
          (value) => ChoiceChip(
            key: ValueKey('subtype-filter-value:$value'),
            label: Text(subtypeFilterLabel(value)),
            visualDensity: VisualDensity.compact,
            selected:
                _subtype != null &&
                _subtype!.toLowerCase() == value.toLowerCase(),
            onSelected: (selected) =>
                setState(() => _subtype = selected ? value : null),
          ),
        ),
      ];
      final columns = contentWidth < 350
          ? 1
          : contentWidth < 650
          ? 2
          : contentWidth < 920
          ? 3
          : 4;
      return CustomScrollView(
        key: const PageStorageKey('wardrobe-scroll'),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(horizontal, base, horizontal, 24),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PageHeading(
                    eyebrow: widget.metadataOnly
                        ? 'LOCAL SUPABASE · DEVELOPMENT'
                        : 'MY WARDROBE',
                    title: widget.metadataOnly ? '서버 개발 옷장' : '내 취향이 모이는 곳',
                    description: widget.metadataOnly
                        ? '이 기기의 내 옷장과 별개예요. 서버가 검증한 사진만 표시해요.'
                        : '자주 입는 옷부터, 아껴 둔 한 벌까지. 나만의 옷장을 채워보세요.',
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      Text(
                        '전체 ${_items.length}벌',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (widget.metadataOnly)
                        OutlinedButton.icon(
                          key: const ValueKey('refresh-server-wardrobe'),
                          onPressed: _loading ? null : _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('서버 새로고침'),
                        ),
                      FilledButton.icon(
                        key: const ValueKey('add-garment'),
                        onPressed: _loading || _error != null ? null : _add,
                        icon: const Icon(Icons.add),
                        label: const Text('옷 추가'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    key: const ValueKey('garment-search'),
                    controller: _search,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: '의류 이름으로 검색',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '검색 지우기',
                              onPressed: () => setState(() {
                                _query = '';
                                _search.clear();
                              }),
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '대분류',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  _filterRow(context, 'category', categoryChips),
                  if (_category != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      key: const ValueKey('subcategory-section'),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '소분류 · ${_categoryLabel(_category)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _filterRow(context, 'subtype', filterChips),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (!_loading && _error == null)
                    Text(
                      '검색 결과 ${visible.length}벌',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_error != null)
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: horizontal),
              sliver: SliverToBoxAdapter(
                child: SurfaceCard(
                  child: Column(
                    children: [
                      const Icon(Icons.cloud_off_outlined, size: 40),
                      const SizedBox(height: 16),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _load,
                        child: const Text('다시 불러오기'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (visible.isEmpty)
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: horizontal),
              sliver: SliverToBoxAdapter(
                child: SurfaceCard(
                  child: Column(
                    children: [
                      const SizedBox(height: 24),
                      Icon(
                        _items.isEmpty
                            ? Icons.checkroom_outlined
                            : Icons.search_off,
                        size: 64,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _category != null
                            ? '아직 등록된 옷이 없어요'
                            : _items.isEmpty && _query.trim().isEmpty
                            ? '첫 번째 옷을 등록해 보세요'
                            : '조건에 맞는 옷이 없어요',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _category != null
                            ? '선택한 분류에 옷을 등록하거나 검색 조건을 바꿔보세요.'
                            : _items.isEmpty
                            ? '옷 사진과 이름을 남기면 나만의 디지털 옷장이 시작돼요.'
                            : '검색어나 대분류·소분류를 바꿔보세요.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      _items.isEmpty
                          ? FilledButton(
                              onPressed: _add,
                              child: const Text('첫 옷 등록하기'),
                            )
                          : OutlinedButton(
                              onPressed: () => setState(() {
                                _query = '';
                                _category = null;
                                _subtype = null;
                                _search.clear();
                              }),
                              child: const Text('검색 조건 초기화'),
                            ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: horizontal),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final garment = visible[index];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    margin: EdgeInsets.zero,
                    child: Semantics(
                      button: true,
                      child: InkWell(
                        key: ValueKey('garment-${garment.id}'),
                        onTap: () => _open(garment),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child:
                                  widget.metadataOnly &&
                                      widget.repository
                                          is! ServerPhotoRepository
                                  ? const ServerPhotoPlaceholder()
                                  : GarmentPhoto(
                                      garment: garment,
                                      repository: widget.repository,
                                    ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    garment.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    garment.category.label,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }, childCount: visible.length),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  mainAxisExtent: columns == 1 ? 330 : 300,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 48)),
        ],
      );
    },
  );

  String _categoryLabel(GarmentCategory? category) => category == null
      ? '전체'
      : category == GarmentCategory.dresses
      ? '원피스·세트'
      : category.label;

  Widget _filterRow(BuildContext context, String id, List<Widget> chips) =>
      MediaQuery.sizeOf(context).width < 900
      ? SingleChildScrollView(
          key: ValueKey('$id-filter-scroll'),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final chip in chips)
                Padding(padding: const EdgeInsets.only(right: 8), child: chip),
            ],
          ),
        )
      : Wrap(
          key: ValueKey('$id-filter-wrap'),
          spacing: 8,
          runSpacing: 6,
          children: chips,
        );
}
