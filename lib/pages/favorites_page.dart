import 'package:flutter/material.dart';

import '../models/models.dart';
import '../widgets/common.dart';
import 'adaptive_grid.dart';
import 'performer_detail_page.dart';
import 'scene_list_page.dart';
import 'studio_detail_page.dart';

/// 收藏页：短片（已整理）/ 演员 / 工作室 三个子页。
/// 短片 = organized 收藏；演员 = favorite（0.31.1 无收藏筛选，客户端过滤）；
/// 工作室 = favorite（服务端 studio_filter.favorite）。
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key, this.embedded = false});

  /// true 时由 HomePage 提供 Scaffold/AppBar，本页只出内容。
  final bool embedded;

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Column(children: [
      TabBar(
        controller: _tab,
        labelColor: theme.colorScheme.primary,
        unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
        indicatorColor: theme.colorScheme.primary,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        tabs: const [
          Tab(text: '短片'),
          Tab(text: '演员'),
          Tab(text: '工作室'),
        ],
      ),
      Expanded(
        child: TabBarView(
          controller: _tab,
          children: const [
            SceneListPage(embedded: true, onlyOrganized: true),
            _FavPerformers(),
            _FavStudios(),
          ],
        ),
      ),
    ]);

    if (widget.embedded) return Scaffold(body: body);
    return Scaffold(appBar: AppBar(title: const Text('收藏')), body: body);
  }
}

/// 收藏的演员：0.31.1 PerformerFilterType 无 favorite 筛选，
/// 分页拉全量后客户端过滤 favorite==true。
class _FavPerformers extends StatefulWidget {
  const _FavPerformers();

  @override
  State<_FavPerformers> createState() => _FavPerformersState();
}

class _FavPerformersState extends State<_FavPerformers> {
  List<Performer> _items = [];
  bool _loading = true;
  String _error = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final api = buildApi();
      final fav = <Performer>[];
      var p = 1;
      for (;;) {
        final r = await api.findPerformers(
          page: p,
          perPage: 1000,
          sort: 'name',
          direction: 'ASC',
        );
        fav.addAll(r.items.where((e) => e.favorite));
        if (r.items.isEmpty || p * 1000 >= r.count || p >= 10) break;
        p++;
      }
      if (!mounted) return;
      setState(() => _items = fav);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFav(Performer p) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await buildApi().updatePerformer({'id': p.id, 'favorite': !p.favorite});
      if (!mounted) return;
      setState(() {
        _items = _items.where((e) => e.id != p.id).toList();
      });
      showToast(context, p.favorite ? '已取消收藏' : '已收藏', error: false);
    } catch (e) {
      if (!mounted) return;
      showToast(context, '操作失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return StatusView(loading: true, empty: '', onRetry: _load);
    }
    if (_error.isNotEmpty && _items.isEmpty) {
      return StatusView(
          loading: false, empty: _error, error: _error, onRetry: _load);
    }
    if (_items.isEmpty) {
      return StatusView(loading: false, empty: '没有收藏的演员', onRetry: _load);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(builder: (context, c) {
        return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: adaptiveColumnCount(c.maxWidth, minCols: 3),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.62,
        ),
        itemCount: _items.length,
        itemBuilder: (_, i) {
          final p = _items[i];
          return GestureDetector(
            onTap: () async {
              final ok = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                    builder: (_) => PerformerDetailPage(performerId: p.id)),
              );
              if (ok == true && mounted) _load();
            },
            child: Column(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: p.imagePath.isEmpty
                      ? Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: const Icon(Icons.person_outline, size: 34),
                        )
                      : AuthImage(rawPath: p.imagePath),
                ),
              ),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                  child: Text(p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  tooltip: '取消收藏',
                  icon: Icon(Icons.star,
                      color: theme.colorScheme.primary, size: 16),
                  onPressed: () => _toggleFav(p),
                ),
              ]),
            ]),
          );
        },
      );
      }),
    );
  }
}

/// 收藏的工作室：服务端 studio_filter.favorite 直接筛选。
class _FavStudios extends StatefulWidget {
  const _FavStudios();

  @override
  State<_FavStudios> createState() => _FavStudiosState();
}

class _FavStudiosState extends State<_FavStudios> {
  final _scroll = ScrollController();
  List<Studio> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 0;
  String _error = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _page = 0;
      _hasMore = true;
      _items = [];
      _error = '';
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
    try {
      final r = await buildApi().findStudios(
        page: next,
        perPage: 60,
        sort: 'name',
        direction: 'ASC',
        studioFilter: {'favorite': true},
      );
      if (!mounted) return;
      setState(() {
        final known = _items.map((e) => e.id).toSet();
        _items = [
          ..._items,
          ...r.items.where((e) => !known.contains(e.id)),
        ];
        _page = next;
        if (_items.length >= r.count) _hasMore = false;
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

  Future<void> _toggleFav(Studio s) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await buildApi().updateStudio({'id': s.id, 'favorite': !s.favorite});
      if (!mounted) return;
      setState(() {
        _items = _items.where((e) => e.id != s.id).toList();
      });
      showToast(context, s.favorite ? '已取消收藏' : '已收藏');
    } catch (e) {
      if (!mounted) return;
      showToast(context, '操作失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading && _items.isEmpty) {
      return StatusView(loading: true, empty: '', onRetry: _reload);
    }
    if (_error.isNotEmpty && _items.isEmpty) {
      return StatusView(
          loading: false, empty: _error, error: _error, onRetry: _reload);
    }
    if (_items.isEmpty && !_loading) {
      return StatusView(loading: false, empty: '没有收藏的工作室', onRetry: _reload);
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: LayoutBuilder(builder: (context, c) {
        return GridView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: adaptiveColumnCount(c.maxWidth, minCols: 3),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.62,
        ),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i >= _items.length) {
            return const Center(
                child: Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2))));
          }
          final s = _items[i];
          return GestureDetector(
            onTap: () async {
              final ok = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                    builder: (_) => StudioDetailPage(studioId: s.id)),
              );
              if (ok == true && mounted) _reload();
            },
            child: Column(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: s.imagePath.isEmpty
                      ? Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: const Icon(Icons.business_outlined, size: 34),
                        )
                      : AuthImage(rawPath: s.imagePath),
                ),
              ),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                  child: Text(s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  tooltip: '取消收藏',
                  icon: Icon(Icons.star,
                      color: theme.colorScheme.primary, size: 16),
                  onPressed: () => _toggleFav(s),
                ),
              ]),
            ]),
          );
        },
      );
      }),
    );
  }
}
