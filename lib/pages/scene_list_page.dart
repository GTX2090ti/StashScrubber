import 'package:flutter/material.dart';

import '../api/stash_api.dart';
import '../models/models.dart';
import '../settings/app_settings.dart';
import '../widgets/common.dart';
import '../widgets/zh_toolbar.dart';
import 'scene_detail_page.dart';
import 'scene_filter_sheet.dart';

/// 短片列表页：单列大卡片（web app 样式）+ 无限滚动 + 搜索 + 排序 + 筛选 + 批量操作。
/// [onlyOrganized] 为 true 时固定显示已收藏（organized）短片，作为独立收藏页。
class SceneListPage extends StatefulWidget {
  const SceneListPage({super.key, this.embedded = false, this.onlyOrganized = false});

  /// true 时由 HomePage 提供 Scaffold/AppBar，本页只出内容。
  final bool embedded;

  /// 收藏页模式：只显示已整理短片。
  final bool onlyOrganized;

  @override
  State<SceneListPage> createState() => _SceneListPageState();
}

class _SceneListPageState extends State<SceneListPage> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  List<Scene> _scenes = [];
  int _total = 0;
  int _page = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String _error = '';
  String _query = '';

  String _sort = 'date';
  String _direction = 'DESC';

  /// 排序选项（与 Stash 0.31.1 SceneSorter 对齐：date_added→created_at、file_size→filesize、studio_name→studio）。
  static const List<(String, String)> _sortOptions = [
    ('date', '发行日期'),
    ('created_at', '添加时间'),
    ('title', '标题'),
    ('rating', '评分'),
    ('o_counter', '播放次数'),
    ('duration', '时长'),
    ('filesize', '文件大小'),
    ('performer_count', '演员数'),
    ('studio', '工作室'),
    ('tag_count', '标签数'),
  ];

  SceneFilterState _filter = SceneFilterState();

  bool _selectMode = false;
  Set<String> _selected = {};

  List<Tag> _allTags = [];
  bool _batchBusy = false;

  static const int _perPage = 60;

  AppSettings get _cfg => AppSettings.instance;

  StashApi get _api => buildApi();

  String _lastBase = '';
  String _lastKey = '';

  @override
  void initState() {
    super.initState();
    if (widget.onlyOrganized) {
      _filter.organized = true;
    }
    _lastBase = _cfg.baseUrl;
    _lastKey = _cfg.apiKey;
    _cfg.addListener(_onSettingsChanged);
    _scroll.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _cfg.removeListener(_onSettingsChanged);
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    final b = _cfg.baseUrl;
    final k = _cfg.apiKey;
    if (b != _lastBase || k != _lastKey) {
      _lastBase = b;
      _lastKey = k;
      _reload();
    } else if (mounted) {
      setState(() {});
    }
  }

  /// 无限滚动：接近底部时加载下一页。
  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _error = '';
      _page = 0;
      _hasMore = true;
      _scenes = [];
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final next = _page + 1;
    setState(() {
      _loading = true;
      _loadingMore = _page > 0;
    });
    _error = '';
    try {
      final r = _query.trim().isNotEmpty
          ? await _api.searchScenes(
              term: _query.trim(),
              page: next,
              perPage: _perPage,
              sort: _sort,
              direction: _direction,
              sceneFilter: _filter.isEmpty ? null : _filter.toJson(),
            )
          : await _api.findScenes(
              page: next,
              perPage: _perPage,
              q: _query,
              sort: _sort,
              direction: _direction,
              sceneFilter: _filter.isEmpty ? null : _filter.toJson(),
            );
      if (!mounted) return;
      setState(() {
        _total = r.count;
        final known = _scenes.map((e) => e.id).toSet();
        _scenes = [
          ..._scenes,
          ...r.items.where((e) => !known.contains(e.id)),
        ];
        _page = next;
        if (_scenes.length >= _total) _hasMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  String get _sortLabel {
    for (final (s, l) in _sortOptions) {
      if (s == _sort) return l;
    }
    return _sort;
  }

  String get _filterSummary {
    final n = _filter.activeCount;
    return n > 0 ? '筛选 ($n)' : '筛选';
  }

  // ---------- 批量 ----------

  List<Scene> get _selectedScenes =>
      _scenes.where((s) => _selected.contains(s.id)).toList();

  bool get _allSelectedOrganized =>
      _selectedScenes.isNotEmpty && _selectedScenes.every((s) => s.organized);

  void _toggleSelect(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selected.length == _scenes.length) {
        _selected.clear();
      } else {
        _selected = _scenes.map((s) => s.id).toSet();
      }
    });
  }

  Future<void> _batchFav(bool target) async {
    if (_selected.isEmpty) return;
    setState(() => _batchBusy = true);
    var done = 0;
    var failed = 0;
    for (final id in _selected) {
      try {
        await _api.updateScene({'id': id, 'organized': target});
        done++;
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    _finishBatch('${target ? "已收藏" : "已取消收藏"} $done 个', failed);
  }

  /// 批量生成封面：一次任务提交所有选中短片（服务端后台执行）。
  Future<void> _batchCovers() async {
    if (_selected.isEmpty) return;
    setState(() => _batchBusy = true);
    try {
      await _api.generateCovers(_selected.toList());
      if (!mounted) return;
      showToast(context, '已提交 ${_selected.length} 个短片的封面生成任务');
    } catch (e) {
      if (!mounted) return;
      showToast(context, '生成封面失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
  }

  Future<void> _batchRating(int v) async {
    if (_selected.isEmpty) return;
    setState(() => _batchBusy = true);
    var done = 0;
    var failed = 0;
    for (final id in _selected) {
      try {
        await _api.updateScene({'id': id, 'rating100': v});
        done++;
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    _finishBatch('已设置评分 $done 个', failed);
  }

  Future<void> _batchTags(Set<String> picks, bool add) async {
    if (_selected.isEmpty || picks.isEmpty) return;
    setState(() => _batchBusy = true);
    var done = 0;
    var failed = 0;
    for (final s in _selectedScenes) {
      try {
        final cur = s.tags.map((t) => t.id).toSet();
        final next = add ? cur.union(picks) : cur.difference(picks);
        await _api.updateScene({'id': s.id, 'tag_ids': next.toList()});
        done++;
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    _finishBatch('${add ? "已添加标签" : "已移除标签"} $done 个', failed);
  }

  void _finishBatch(String okText, int failed) {
    showToast(context, failed > 0 ? '$okText，$failed 个失败' : okText,
        error: failed > 0);
    setState(() {
      _batchBusy = false;
      _selected = {};
      _selectMode = false;
    });
    _reload();
  }

  /// 多选合并：弹窗选择保留的目标短片，其余合入（服务端 sceneMerge）。
  Future<void> _batchMerge() async {
    final scenes = _selectedScenes;
    if (scenes.length < 2 || _batchBusy) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(children: [
                Expanded(
                  child: Text('选择要保留的短片',
                      style: Theme.of(ctx).textTheme.titleMedium),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
              ]),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: scenes.length,
                itemBuilder: (_, i) {
                  final s = scenes[i];
                  return ListTile(
                    dense: true,
                    leading: SizedBox(
                      width: 34,
                      height: 46,
                      child: AuthImage(
                        rawPath: s.paths.raw,
                        radius: 6,
                        width: 34,
                        height: 46,
                      ),
                    ),
                    title: Text(s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                    onTap: () => Navigator.pop(ctx, s.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _batchBusy = true);
    try {
      await _api.mergeScenes(
          scenes.where((s) => s.id != picked).map((s) => s.id).toList(),
          picked);
      if (!mounted) return;
      _finishBatch('已合并 ${scenes.length} 个短片', 0);
    } catch (e) {
      if (!mounted) return;
      setState(() => _batchBusy = false);
      showToast(context, '合并失败：$e', error: true);
    }
  }

  Future<void> _openTagSheet(bool add) async {
    try {
      final tags = await _api.allTags();
      if (!mounted) return;
      setState(() => _allTags = tags);
    } catch (_) {
      if (mounted) setState(() => _allTags = const []);
    }
    if (!mounted) return;
    final picks = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TagPickerSheet(
        title: add ? '选择要添加的标签' : '选择要移除的标签',
        tags: _allTags,
      ),
    );
    if (picks != null && picks.isNotEmpty) {
      await _batchTags(picks, add);
    }
  }

  Future<void> _pickRating() async {
    final v = await showModalBottomSheet<int>(
      context: context,
      builder: (_) => const _RatingSheet(),
    );
    if (v != null) await _batchRating(v);
  }

  /// 排序方式弹窗（与 Stash 对齐，含方向切换）。
  Future<void> _openSortSheet() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Row(children: [
                  Expanded(
                    child: Text('排序方式',
                        style: theme.textTheme.titleMedium),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx, 'toggle_dir');
                    },
                    icon: Icon(
                      _direction == 'DESC'
                          ? Icons.arrow_downward
                          : Icons.arrow_upward,
                      size: 16,
                    ),
                    label: Text(
                      _direction == 'DESC' ? '从新到旧' : '从旧到新',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ]),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final (s, l) in _sortOptions)
                      ListTile(
                        dense: true,
                        title: Text(l, style: const TextStyle(fontSize: 13)),
                        trailing: s == _sort
                            ? Icon(Icons.check,
                                size: 18, color: theme.colorScheme.primary)
                            : null,
                        onTap: () => Navigator.pop(ctx, s),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    if (picked == 'toggle_dir') {
      setState(() => _direction = _direction == 'DESC' ? 'ASC' : 'DESC');
    } else {
      setState(() => _sort = picked);
    }
    _reload();
  }

  Future<void> _openFilter() async {    final result = await Navigator.push<SceneFilterState>(
      context,
      MaterialPageRoute(
        builder: (_) => SceneFilterSheet(initial: _filter),
      ),
    );
    if (result != null) {
      setState(() => _filter = result);
      _reload();
    }
  }

  void _openScene(String id) {
    if (_selectMode) {
      _toggleSelect(id);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => SceneDetailPage(sceneId: id, onChanged: _reload)),
    );
  }

  // ---------- 生效地址栏 ----------

  Widget _searchRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(fontSize: 13),
            textInputAction: TextInputAction.search,
            contextMenuBuilder: zhContextMenuBuilder,
            onSubmitted: (_) => _reload(),
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: '搜索标题 / 演员 / 标签',
              isDense: true,
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空',
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                        _reload();
                      },
                    ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          height: 30,
          child: FilledButton(
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10)),
            onPressed: _reload,
            child: const Text('搜索', style: TextStyle(fontSize: 12)),
          ),
        ),
      ]),
    );
  }

  Widget _toolRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(children: [
        Expanded(
          child: SizedBox(
            height: 28,
            child: OutlinedButton(
              onPressed: _openFilter,
              child: Text(_filterSummary,
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: SizedBox(
            height: 28,
            child: OutlinedButton(
              onPressed: _openSortSheet,
              child: Text(_sortLabel,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 34,
          height: 28,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(34, 28)),
            onPressed: () {
              setState(() =>
                  _direction = _direction == 'DESC' ? 'ASC' : 'DESC');
              _reload();
            },
            child: Icon(
              _direction == 'DESC'
                  ? Icons.arrow_downward
                  : Icons.arrow_upward,
              size: 15,
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          height: 28,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10)),
            onPressed: _scenes.isEmpty
                ? null
                : () {
                    setState(() {
                      if (_selectMode) {
                        _selectMode = false;
                        _selected = {};
                      } else {
                        _selectMode = true;
                      }
                    });
                  },
            child: Text(_selectMode ? '取消' : '多选',
                style: const TextStyle(fontSize: 12)),
          ),
        ),
      ]),
    );
  }

  Widget _footer() {
    final theme = Theme.of(context);
    if (_loadingMore || _loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(
          _error.isNotEmpty ? '加载失败，上拉重试' : '已经到底了',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _batchBar() {
    final has = _selected.isNotEmpty && !_batchBusy;
    final theme = Theme.of(context);
    Widget btn({
      required String label,
      required VoidCallback? onPressed,
      double width = 56,
    }) {
      return SizedBox(
        width: width,
        height: 28,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero, minimumSize: Size(width, 28)),
          onPressed: onPressed,
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      color: theme.colorScheme.surfaceContainerHighest,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          btn(
            label: _allSelectedOrganized ? '取消收藏' : '收藏',
            onPressed: has ? () => _batchFav(!_allSelectedOrganized) : null,
            width: 68,
          ),
          const SizedBox(width: 4),
          btn(
            label: '评分',
            onPressed: has ? _pickRating : null,
          ),
          const SizedBox(width: 4),
          btn(
            label: '标签',
            onPressed: has ? () => _openTagSheet(true) : null,
          ),
          const SizedBox(width: 4),
          btn(
            label: '合并',
            onPressed: _selected.length >= 2 ? _batchMerge : null,
          ),
          const SizedBox(width: 4),
          btn(
            label: '封面',
            onPressed: has ? _batchCovers : null,
            width: 56,
          ),
          const SizedBox(width: 4),
          btn(
            label: '全选',
            onPressed: _scenes.isEmpty
                ? null
                : () {
                    _toggleSelectAll();
                  },
          ),
          const SizedBox(width: 4),
          Container(
            width: 24,
            height: 28,
            alignment: Alignment.center,
            child: Text('${_selected.length}',
                style: theme.textTheme.bodySmall),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(children: [
      _toolRow(),
      _searchRow(),
      Expanded(
        child: _scenes.isEmpty && !_loadingMore
            ? StatusView(
                loading: _loading,
                empty: _error.isNotEmpty ? _error : '没有短片',
                error: _error,
                onRetry: _reload,
              )
            : RefreshIndicator(
                onRefresh: _reload,
                child: GridView.builder(
                  key: PageStorageKey(widget.onlyOrganized ? 'fav_grid' : 'scene_grid'),
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.95,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: _scenes.length +
                      ((_hasMore || _loadingMore) ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= _scenes.length) return _footer();
                    final s = _scenes[i];
                    final sel = _selected.contains(s.id);
                    final artist = [
                      if (s.studio != null) s.studio!.name,
                      ...s.performers.map((p) => p.name),
                    ].join(' · ');
                    return SceneListCard(
                      title: s.title,
                      rawCover: s.paths.raw,
                      date: s.date,
                      rating100: s.rating100,
                      organized: s.organized,
                      duration: s.duration,
                      height: s.files.isEmpty ? 0 : s.files.first.height,
                      artist: artist,
                      tagCount: s.tags.length,
                      hasCaption: s.captions.isNotEmpty,
                      onTap: () => _openScene(s.id),
                      trailing: _selectMode
                          ? Positioned(
                              left: 6,
                              top: 6,
                              child: Container(
                                width: 22,
                                height: 22,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: sel
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Text(
                                  sel ? '✓' : '○',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: sel
                                        ? Colors.white
                                        : Colors.white70,
                                  ),
                                ),
                              ),
                            )
                          : null,
                    );
                  },
                ),
              ),
      ),
      if (_selectMode) _batchBar(),
    ]);

    if (widget.embedded) return Scaffold(body: body);
    return Scaffold(
      appBar: AppBar(
          title: Text(_total > 0
              ? '${widget.onlyOrganized ? '收藏' : '短片'} ($_total)'
              : widget.onlyOrganized ? '收藏' : '短片')),
      body: body,
    );
  }
}

class _TagPickerSheet extends StatefulWidget {
  const _TagPickerSheet({required this.title, required this.tags});
  final String title;
  final List<Tag> tags;

  @override
  State<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<_TagPickerSheet> {
  final Set<String> _picked = {};

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.tags.length,
              itemBuilder: (_, i) {
                final t = widget.tags[i];
                return CheckboxListTile(
                  dense: true,
                  value: _picked.contains(t.id),
                  title: Text(t.name),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _picked.add(t.id);
                    } else {
                      _picked.remove(t.id);
                    }
                  }),
                );
              },
            ),
          ),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _picked.isEmpty
                    ? null
                    : () => Navigator.pop(context, _picked),
                child: Text('确定（${_picked.length}）'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _RatingSheet extends StatelessWidget {
  const _RatingSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final v in [20, 40, 60, 80, 100])
            ListTile(
              dense: true,
              title: Text('★ ${(v / 20).round()}'),
              onTap: () => Navigator.pop(context, v),
            ),
          ListTile(
            dense: true,
            title: const Text('清除评分'),
            onTap: () => Navigator.pop(context, 0),
          ),
        ],
      ),
    );
  }
}
