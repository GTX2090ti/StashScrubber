import 'package:flutter/material.dart';

import '../models/models.dart';
import '../widgets/common.dart';
import 'performer_detail_page.dart';
import 'scrape_page.dart';

/// 工作室详情页：图标 + 短片数 + 关联短片。
class StudioDetailPage extends StatefulWidget {
  const StudioDetailPage({super.key, required this.studioId});

  final String studioId;

  @override
  State<StudioDetailPage> createState() => _StudioDetailPageState();
}

class _StudioDetailPageState extends State<StudioDetailPage> {
  Studio? _s;
  bool _loading = true;
  String _error = '';
  final _scroll = ScrollController();

  /// 确认并删除工作室；成功后返回上一页并刷新列表。
  Future<void> _confirmDelete() async {
    final name = _s?.name ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除工作室'),
        content: Text('确定删除「${name.isEmpty ? '此工作室' : name}」吗？\n'
            '已有短片不会受影响，但工作室档案会被永久删除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE5533D)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await buildApi().destroyStudio(widget.studioId);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('删除失败：$e')));
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _error = '';
    try {
      final s = await buildApi().findStudio(widget.studioId);
      if (!mounted) return;
      setState(() {
        _s = s;
        _loading = false;
      });
      if (s == null && mounted) setState(() => _error = '加载失败');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _openScrape() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScrapePage(
          kind: ScrapeKind.studio,
          targetId: widget.studioId,
          targetTitle: _s?.name ?? '',
        ),
      ),
    ).then((v) {
      if (v == true) _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _s;
    return Scaffold(
      appBar: AppBar(
          title: Text(s != null && s.name.isNotEmpty ? s.name : '工作室详情',
              overflow: TextOverflow.ellipsis),
          actions: [
            if (s != null)
              IconButton(
                tooltip: '删除工作室',
                onPressed: () => _confirmDelete(),
                icon: const Icon(Icons.delete_outline),
              ),
          ]),
      body: _loading
          ? StatusView(loading: true, empty: '', onRetry: _load)
          : s == null
              ? StatusView(
                  loading: false,
                  empty: _error.isNotEmpty ? _error : '加载失败',
                  error: _error,
                  onRetry: _load)
              : ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  children: [
                    Center(
                      child: s.imagePath.isEmpty
                          ? CircleAvatar(
                              radius: 60,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              child: Text(
                                s.name.isEmpty ? 'S' : s.name.substring(0, 1),
                                style: TextStyle(
                                    fontSize: 52,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary),
                              ),
                            )
                          : AuthImage(
                              rawPath: s.imagePath,
                              radius: 60,
                              width: 120,
                              height: 120,
                              fallbackIcon: Icons.business_outlined,
                            ),
                    ),
                    const SizedBox(height: 10),
                    Text(s.name,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    if (s.sceneCount > 0)
                      Text('短片数：${s.sceneCount}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    if (s.rating100 > 0)
                      Text('评分：${(s.rating100 / 20).toStringAsFixed(1)} / 5.0',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _openScrape,
                      icon: const Icon(Icons.travel_explore, size: 18),
                      label: const Text('削刮（Stash-box）'),
                    ),

                    RelatedScenes(
                      scrollController: _scroll,
                      sceneFilter: {
                        'studios': {
                          'value': [widget.studioId],
                          'modifier': 'INCLUDES',
                          'depth': -1,
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }
}

/// 标签详情页：标签下的短片列表。
class TagDetailPage extends StatefulWidget {
  const TagDetailPage({super.key, required this.tagId});

  final String tagId;

  @override
  State<TagDetailPage> createState() => _TagDetailPageState();
}

class _TagDetailPageState extends State<TagDetailPage> {
  Tag? _t;
  bool _loading = true;
  String _error = '';
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _error = '';
    try {
      final t = await buildApi().findTag(widget.tagId);
      if (!mounted) return;
      setState(() {
        _t = t;
        _loading = false;
      });
      if (t == null && mounted) setState(() => _error = '加载失败');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    return Scaffold(
      appBar: AppBar(title: Text('#${t?.name ?? ''}')),
      body: _loading
          ? StatusView(loading: true, empty: '', onRetry: _load)
          : t == null
              ? StatusView(
                  loading: false,
                  empty: _error.isNotEmpty ? _error : '加载失败',
                  error: _error,
                  onRetry: _load)
              : ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  children: [
                    RelatedScenes(
                      scrollController: _scroll,
                      sceneFilter: {
                        'tags': {
                          'value': [widget.tagId],
                          'modifier': 'INCLUDES_ALL',
                          'depth': -1,
                        }
                      },
                    ),
                  ],
                ),
    );
  }
}
