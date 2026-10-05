import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/stash_api.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'merge_page.dart';
import 'performer_detail_page.dart';
import 'scrape_page.dart';
import 'scene_edit_page.dart';
import 'studio_detail_page.dart';


/// 短片详情页：工作室 / 演员 / 标签可点击进入对应详情。
class SceneDetailPage extends StatefulWidget {
  const SceneDetailPage({super.key, required this.sceneId, this.onChanged});

  final String sceneId;
  final VoidCallback? onChanged;

  @override
  State<SceneDetailPage> createState() => _SceneDetailPageState();
}

class _SceneDetailPageState extends State<SceneDetailPage> {
  Scene? _scene;
  bool _loading = true;
  String _error = '';
  bool _favBusy = false;
  bool _genBusy = false;

  StashApi get _api => buildApi();

  /// 为当前短片生成封面（服务端后台任务，只补缺失，不覆盖已有封面）。
  Future<void> _generateCover() async {
    setState(() => _genBusy = true);
    try {
      await _api.generateCovers([widget.sceneId]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已提交生成封面任务，可到「Stash 任务」查看进度')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('生成封面失败：$e')));
    } finally {
      if (mounted) setState(() => _genBusy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    _error = '';
    try {
      final s = await _api.findScene(widget.sceneId);
      if (!mounted) return;
      setState(() {
        _scene = s;
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

  Future<void> _toggleFavorite() async {
    final s = _scene;
    if (s == null || _favBusy) return;
    setState(() => _favBusy = true);
    final target = !s.organized;
    try {
      await _api.updateScene({'id': widget.sceneId, 'organized': target});
      if (mounted) setState(() => _scene = s.copyWith(organized: target));
    } catch (_) {
      // 忽略失败
    }
    if (mounted) setState(() => _favBusy = false);
  }

  Future<void> _openEdit() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => SceneEditPage(sceneId: widget.sceneId)),
    );
    if (changed == true) {
      _load();
      widget.onChanged?.call();
    }
  }

  void _openScrape() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScrapePage(
          kind: ScrapeKind.scene,
          targetId: widget.sceneId,
          targetTitle: _scene?.title ?? '',
        ),
      ),
    ).then((applied) {
      if (applied == true) {
        _load();
        widget.onChanged?.call();
      }
    });
  }

  void _openMerge() {
    final nav = Navigator.of(context);
    nav
        .push(
      MaterialPageRoute(
        builder: (_) => MergePage(
          targetId: widget.sceneId,
          targetTitle: _scene?.title ?? '',
        ),
      ),
    )
        .then((merged) {
      if (merged == true && mounted) {
        nav.pop();
        widget.onChanged?.call();
      }
    });
  }

  void _toastCopy(String path) {
    Clipboard.setData(ClipboardData(text: path));
    showToast(context, '路径已复制');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _scene;
    return Scaffold(
      appBar: AppBar(
        title: Text(s != null && s.title.isNotEmpty ? s.title : '短片详情',
            overflow: TextOverflow.ellipsis),
        actions: [
          if (s != null)
            IconButton(
              tooltip: '生成封面',
              onPressed: _genBusy ? null : () => _generateCover(),
              icon: const Icon(Icons.image_outlined),
            ),
          if (s != null)
            IconButton(
              tooltip: s.organized ? '取消收藏' : '收藏',
              onPressed: _favBusy ? null : _toggleFavorite,
              icon: Icon(s.organized ? Icons.star : Icons.star_border,
                  color: s.organized ? const Color(0xFFFF9F0A) : null),
            ),
        ],
      ),
      body: _loading
          ? StatusView(loading: true, empty: '', onRetry: _load)
          : s == null
              ? StatusView(
                  loading: false,
                  empty: _error.isNotEmpty ? _error : '加载失败',
                  error: _error,
                  onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Stack(
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: AuthImage(
                            rawPath: s.paths.raw,
                            fit: BoxFit.contain,
                            radius: 12,
                            fallbackIcon: Icons.movie_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s.title.isNotEmpty ? s.title : '（无标题）',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: OutlinedButton(
                              onPressed: _openEdit,
                              child: const Text('编辑'))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: OutlinedButton(
                              onPressed: _openScrape,
                              child: const Text('削刮'))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: OutlinedButton(
                              onPressed: _openMerge,
                              child: const Text('合并'))),
                    ]),

                    const SectionTitle('基本信息'),
                    if (s.date.isNotEmpty) InfoRow('日期', s.date),
                    if (s.rating100 > 0)
                      InfoRow('评分', '${(s.rating100 / 20).toStringAsFixed(1)} / 5.0'),
                    InfoRow('O 计数', '${s.oCounter}'),

                    if (s.studio != null) ...[
                      const SectionTitle('工作室'),
                      InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  StudioDetailPage(studioId: s.studio!.id)),
                        ),
                        child: Text(
                          s.studio!.name,
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],

                    if (s.performers.isNotEmpty) ...[
                      SectionTitle('演员（${s.performers.length}）'),
                      Wrap(
                        children: [
                          for (final p in s.performers)
                            TapChip(
                              label: p.name,
                              kind: ChipKind.performer,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        PerformerDetailPage(performerId: p.id)),
                              ),
                            ),
                        ],
                      ),
                    ],

                    if (s.urls.isNotEmpty) ...[
                      const SectionTitle('URL'),
                      for (final u in s.urls)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(u,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.primary)),
                        ),
                    ],

                    if (s.files.isNotEmpty) ...[
                      const SectionTitle('文件路径'),
                      for (final f in s.files)
                        InkWell(
                          onTap: () => _toastCopy(f.path),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(f.path,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant)),
                          ),
                        ),
                    ],

                    if (s.tags.isNotEmpty) ...[
                      SectionTitle('标签（${s.tags.length}）'),
                      Wrap(
                        children: [
                          for (final t in s.tags)
                            TapChip(
                              label: t.name,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => TagDetailPage(tagId: t.id)),
                              ),
                            ),
                        ],
                      ),
                    ],

                    if (s.details.isNotEmpty) ...[
                      const SectionTitle('简介'),
                      Text(s.details,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(height: 1.6)),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }
}
