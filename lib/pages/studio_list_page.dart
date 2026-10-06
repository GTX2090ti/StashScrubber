import 'package:flutter/material.dart';

import '../models/models.dart';
import '../settings/app_settings.dart';
import '../widgets/common.dart';
import '../widgets/zh_toolbar.dart';
import 'studio_create_page.dart';
import 'studio_detail_page.dart';

/// 工作室列表页：行式列表 + 翻页 + 搜索。
class StudioListPage extends StatefulWidget {
  const StudioListPage({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<StudioListPage> createState() => _StudioListPageState();
}

class _StudioListPageState extends State<StudioListPage> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  List<Studio> _items = [];
  int _total = 0;
  int _page = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String _error = '';
  String _query = '';
  String _sort = 'name';
  String _direction = 'ASC';

  /// 排序选项（Stash 0.31.1 Studio 排序白名单内的常用字段）。
  static const List<(String, String)> _sortOptions = [
    ('name', '名称'),
    ('scenes_count', '短片数'),
    ('rating', '评分'),
    ('created_at', '添加时间'),
    ('updated_at', '更新时间'),
    ('latest_scene', '最近短片'),
  ];

  String get _sortLabel {
    for (final (s, l) in _sortOptions) {
      if (s == _sort) return l;
    }
    return _sort;
  }

  static const int _perPage = 60;

  String _lastBase = '';
  String _lastKey = '';

  @override
  void initState() {
    super.initState();
    _lastBase = AppSettings.instance.baseUrl;
    _lastKey = AppSettings.instance.apiKey;
    AppSettings.instance.addListener(_onCfg);
    _scroll.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_onCfg);
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onCfg() {
    final b = AppSettings.instance.baseUrl;
    final k = AppSettings.instance.apiKey;
    if (b != _lastBase || k != _lastKey) {
      _lastBase = b;
      _lastKey = k;
      _reload();
    } else if (mounted) {
      setState(() {});
    }
  }

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
      _items = [];
    });
    await _loadMore();
  }

  /// 打开手动添加工作室页，成功后刷新列表。
  Future<void> _openCreate() async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const StudioCreatePage()),
    );
    if (id != null) _reload();
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

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final next = _page + 1;
    setState(() {
      _loading = true;
      _loadingMore = _page > 0;
    });
    _error = '';
    try {
      final r = await buildApi().findStudios(
          page: next,
          perPage: _perPage,
          q: _query,
          sort: _sort,
          direction: _direction);
      if (!mounted) return;
      setState(() {
        _total = r.count;
        final known = _items.map((e) => e.id).toSet();
        _items = [..._items, ...r.items.where((e) => !known.contains(e.id))];
        _page = next;
        if (_items.length >= _total) _hasMore = false;
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

  @override
  Widget build(BuildContext context) {
    final body = Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontSize: 13),
              textInputAction: TextInputAction.search,
              contextMenuBuilder: zhContextMenuBuilder,
              onChanged: (v) => setState(() => _query = v),
              onSubmitted: (_) => _reload(),
              decoration: InputDecoration(
                hintText: '搜索工作室',
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
              style:
                  FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
              onPressed: _reload,
              child: const Text('搜索', style: TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 30,
            child: OutlinedButton(
              style:
                  OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
              onPressed: _openSortSheet,
              child: Text(_sortLabel,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 30,
            child: OutlinedButton.icon(
              style:
                  OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
              onPressed: _openCreate,
              icon: const Icon(Icons.add, size: 15),
              label: const Text('添加', style: TextStyle(fontSize: 12)),
            ),
          ),
        ]),
      ),
      Expanded(
        child: _items.isEmpty && !_loadingMore
            ? StatusView(
                loading: _loading,
                empty: _error.isNotEmpty ? _error : '没有工作室',
                error: _error,
                onRetry: _reload)
            : RefreshIndicator(
                onRefresh: _reload,
                child: GridView.builder(
                  key: const PageStorageKey('studio_grid'),
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.0,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 12,
                  ),
                  itemCount:
                      _items.length + ((_hasMore || _loadingMore) ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i >= _items.length) return _footer();
                    final s = _items[i];
                    return InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => StudioDetailPage(studioId: s.id)),
                      ).then((v) {
                        if (v == true) _reload();
                      }),
                      child: Column(children: [
                        Expanded(
                          child: AuthImage(
                            rawPath: s.imagePath,
                            radius: 10,
                            fallbackIcon: Icons.business_outlined,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          '${s.sceneCount} 个短片',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 10,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                        ),
                      ]),
                    );
                  },
                ),
              ),
      ),
    ]);

    if (widget.embedded) return Scaffold(body: body);
    return Scaffold(
        appBar: AppBar(title: Text(_total > 0 ? '工作室 ($_total)' : '工作室')),
        body: body);
  }
}
