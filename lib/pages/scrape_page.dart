import 'package:flutter/material.dart';

import '../models/models.dart';
import '../widgets/common.dart';
import '../widgets/zh_toolbar.dart';

enum ScrapeKind { scene, performer, studio }

/// 名称削刮的源项：stash-box + 本地刮削器（工作室仅 stash-box）。
class _QuerySource {
  final String label;
  final Map<String, dynamic> dict;
  const _QuerySource(this.label, this.dict);
}

/// 削刮页：短片 / 演员 / 工作室通用。
/// 流程：选择方式 → 点削刮源 → 启动削刮 → 结果列表 → 查看预览 → 应用写回。
class ScrapePage extends StatefulWidget {
  const ScrapePage({
    super.key,
    required this.kind,
    required this.targetId,
    required this.targetTitle,
  });

  final ScrapeKind kind;
  final String targetId;
  final String targetTitle;

  @override
  State<ScrapePage> createState() => _ScrapePageState();
}

class _ScrapePageState extends State<ScrapePage> {
  List<Scraper> _scrapers = [];
  List<StashBoxInfo> _boxes = [];

  List<ScrapedScene> _sceneResults = [];
  List<ScrapedPerformer> _performerResults = [];
  List<ScrapedStudio> _studioResults = [];

  int _mode = 0; // 0=片段 1=名称 2=URL
  bool _started = false;
  bool _loading = false;
  String _error = '';
  final _queryCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();

  int _previewIndex = -1;
  bool _includeImage = true;
  bool _applying = false;
  String _applyMsg = '';
  bool _applyError = false;

  bool get _isScene => widget.kind == ScrapeKind.scene;
  bool get _isPerformer => widget.kind == ScrapeKind.performer;
  bool get _isStudio => widget.kind == ScrapeKind.studio;

  @override
  void initState() {
    super.initState();
    if (_isStudio) _mode = 1;
    _loadSources();
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSources() async {
    try {
      final api = buildApi();
      if (!_isStudio) {
        final s = await api.scrapers(_isScene ? 'SCENE' : 'PERFORMER');
        if (mounted) setState(() => _scrapers = s);
      }
      final b = await api.stashBoxes();
      if (mounted) setState(() => _boxes = b);
    } catch (_) {
      // 源加载失败不阻塞 URL 削刮
    }
  }

  List<String> _kindsOf(Scraper s) =>
      _isScene ? s.sceneScrapes : s.performerScrapes;

  List<Scraper> get _fragmentScrapers =>
      _scrapers.where((s) => _kindsOf(s).contains('FRAGMENT')).toList();

  List<_QuerySource> get _querySources {
    final out = <_QuerySource>[];
    for (var i = 0; i < _boxes.length; i++) {
      final b = _boxes[i];
      final label = '${b.name.isNotEmpty ? b.name : 'Stash-box'}（Stash-box）';
      // 0.31.1 中 stash_box_index（deprecated）仍可用；
      // stash_box_endpoint 字段存在但 resolver 未实现（not implemented）。
      out.add(_QuerySource(label, {'stash_box_index': i}));
    }
    if (!_isStudio) {
      for (final s in _scrapers) {
        if (_kindsOf(s).contains('NAME')) {
          out.add(_QuerySource(s.name, {'scraper_id': s.id}));
        }
      }
    }
    return out;
  }

  // ---------- 削刮 ----------

  /// 把服务端/网络错误转成便于理解的中文提示。
  String _friendlyErr(Object e) {
    final s = e.toString();
    if (s.contains('not implemented')) {
      return '该削刮方式服务端不支持，请切换削刮方式或换一个源';
    }
    if (s.contains('404')) {
      return '目标站点返回 404（内容不存在或页面已失效），可换削刮器重试';
    }
    if (s.contains('timeout') || s.contains('超时') || s.contains('SocketException') ||
        s.contains('ClientException') || s.contains('连接')) {
      return '站点响应超时或连接失败，请稍后重试或换一个源';
    }
    final m = RegExp(r'scraper (\S+): failed to load URL').firstMatch(s);
    if (m != null) {
      return '刮削器 ${m.group(1)} 抓取站点失败（站点不可访问或页面变化），可换削刮器';
    }
    return s;
  }

  Future<void> _run(Future<void> Function() body) async {
    setState(() {
      _started = true;
      _loading = true;
      _error = '';
      _sceneResults = [];
      _performerResults = [];
      _studioResults = [];
    });
    try {
      await body();
      if (!mounted) return;
      final empty = _isScene
          ? _sceneResults.isEmpty
          : (_isPerformer ? _performerResults.isEmpty : _studioResults.isEmpty);
      if (empty) {
        setState(() =>
            _error = '没有削刮到结果。可点底部「换削刮器」换一个源重试。');
      }
    } catch (e) {
      if (mounted) setState(() => _error = '削刮失败：${_friendlyErr(e)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrapeFragment(Scraper s) {
    final api = buildApi();
    _run(() async {
      if (_isPerformer) {
        // 0.31.1 本地刮削器 FRAGMENT 需传 performer_input（performer_id 返回
        // not implemented），先取本地演员数据构造。
        final p = await api.findPerformer(widget.targetId);
        final input = <String, dynamic>{
          if (p != null && p.name.isNotEmpty) 'name': p.name,
          // aliases 已是逗号分隔字符串，符合 ScrapedPerformerInput.aliases 格式
          if (p != null && p.aliases.isNotEmpty) 'aliases': p.aliases,
          if (p != null && p.birthdate.isNotEmpty) 'birthdate': p.birthdate,
          if (p != null && p.ethnicity.isNotEmpty) 'ethnicity': p.ethnicity,
          if (p != null && p.country.isNotEmpty) 'country': p.country,
          if (p != null && p.measurements.isNotEmpty)
            'measurements': p.measurements,
          if (p != null && p.details.isNotEmpty) 'details': p.details,
        };
        final r = await api.scrapePerformerFragment({'scraper_id': s.id}, input);
        if (!mounted) return;
        setState(() => _performerResults = r.cast<ScrapedPerformer>());
        return;
      }
      final r = _isScene
          ? await api.scrapeSceneFragment({'scraper_id': s.id}, widget.targetId)
          : const <ScrapedPerformer>[];
      if (!mounted) return;
      setState(() {
        if (_isScene) {
          _sceneResults = r.cast<ScrapedScene>();
        } else {
          _performerResults = const [];
        }
      });
    });
  }

  /// Stash-box 片段削刮：box 不支持片段输入，取本地演员名字自动去 box 搜索。
  void _scrapeBoxFragment(int boxIndex) {
    final api = buildApi();
    _run(() async {
      final p = await api.findPerformer(widget.targetId);
      final name = p?.name.trim() ?? '';
      if (!mounted) return;
      if (name.isEmpty) {
        setState(() => _error = '本地演员无名称，无法用名字搜索 Stash-box');
        return;
      }
      final r = await api.scrapePerformerByName({'stash_box_index': boxIndex}, name);
      if (!mounted) return;
      setState(() => _performerResults = r);
    });
  }

  void _scrapeQuery(_QuerySource src) {
    final term = _queryCtrl.text.trim();
    if (term.isEmpty) return;
    final api = buildApi();
    _run(() async {
      if (_isStudio) {
        final r = await api.scrapeStudioByName(src.dict, term);
        if (!mounted) return;
        setState(() => _studioResults = r == null ? const [] : [r]);
        return;
      }
      if (_isScene) {
        final r = await api.scrapeSceneByName(src.dict, term);
        if (!mounted) return;
        setState(() => _sceneResults = r);
      } else {
        final r = await api.scrapePerformerByName(src.dict, term);
        if (!mounted) return;
        setState(() => _performerResults = r);
      }
    });
  }

  void _scrapeUrl() {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    final api = buildApi();
    _run(() async {
      if (_isScene) {
        final r = await api.scrapeSceneUrl(url);
        if (!mounted) return;
        setState(() => _sceneResults = r);
      } else {
        final r = await api.scrapePerformerUrl(url);
        if (!mounted) return;
        setState(() => _performerResults = r);
      }
    });
  }

  // ---------- 预览 ----------

  List<String> _previewRows() {
    if (_previewIndex < 0) return const [];
    final rows = <String>[];
    void add(String label, String v) {
      if (v.isNotEmpty) rows.add('$label：$v');
    }

    String joinNames(List<String> names) =>
        names.where((e) => e.isNotEmpty).join('、');

    if (_isScene) {
      final s = _sceneResults[_previewIndex];
      add('标题', s.title);
      add('日期', s.date);
      if (s.studio != null) add('工作室', s.studio!.name);
      add('简介', s.details);
      if (s.performers.isNotEmpty) {
        rows.add('演员：${joinNames(s.performers.map((e) => e.name).toList())}');
      }
      if (s.tags.isNotEmpty) {
        rows.add('标签：${joinNames(s.tags.map((e) => e.name).toList())}');
      }
      if (s.urls.isNotEmpty) rows.add('URL：${s.urls.join(' ')}');
      return rows;
    }
    if (_isPerformer) {
      final p = _performerResults[_previewIndex];
      add('名称', p.name);
      add('区别名', p.disambiguation);
      if (p.aliases.trim().isNotEmpty) rows.add('别名：${p.aliases.trim()}');
      add('出生日期', p.birthdate);
      add('国籍', p.country);
      add('族裔', p.ethnicity);
      add('三围', p.measurements);
      final parts = <String>[];
      if (p.careerStart.isNotEmpty) parts.add(p.careerStart);
      if (p.careerEnd.isNotEmpty) parts.add(p.careerEnd);
      final career = parts.join(' - ');
      if (career.isNotEmpty) rows.add('从业年限：$career');
      add('简介', p.details);
      if (p.tags.isNotEmpty) {
        rows.add('标签：${joinNames(p.tags.map((e) => e.name).toList())}');
      }
      return rows;
    }
    final st = _studioResults[_previewIndex];
    add('名称', st.name);
    if (st.urls.isNotEmpty) rows.add('URL：${st.urls.join(' ')}');
    return rows;
  }

  String _previewImage() {
    if (_previewIndex < 0) return '';
    if (_isScene) return _sceneResults[_previewIndex].image;
    if (_isPerformer) {
      final imgs = _performerResults[_previewIndex].images;
      return imgs.isEmpty ? '' : imgs.first;
    }
    return _studioResults[_previewIndex].image;
  }

  Future<void> _apply() async {
    setState(() {
      _applying = true;
      _applyMsg = '';
      _applyError = false;
    });
    final api = buildApi();
    var nameSkipped = false;
    try {
      int n = 0;
      if (_isScene) {
        n = await api.applyScrapedScene(
            _sceneResults[_previewIndex], widget.targetId, _includeImage);
      } else if (_isPerformer) {
        final p = _performerResults[_previewIndex];
        final scrapedName = p.name.trim();
        if (scrapedName.isNotEmpty) {
          String localName = '';
          try {
            localName =
                (await api.findPerformer(widget.targetId))?.name.trim() ?? '';
          } catch (_) {}
          final nameToWrite =
              localName.isNotEmpty ? localName : scrapedName;
          if (nameToWrite.isNotEmpty) {
            try {
              final dup =
                  await api.findPerformers(page: 1, perPage: 50, q: nameToWrite);
              final clash = dup.items.any((x) =>
                  x.id != widget.targetId &&
                  x.name.trim().toLowerCase() == nameToWrite.toLowerCase());
              if (clash) {
                // 库中已有同名演员（performers.name UNIQUE），跳过名字写入其余字段
                nameSkipped = true;
                n = await api.applyScrapedPerformer(
                    p, widget.targetId, _includeImage,
                    writeName: false);
              } else {
                n = await api.applyScrapedPerformer(
                    p, widget.targetId, _includeImage);
              }
            } catch (_) {
              n = await api.applyScrapedPerformer(
                  p, widget.targetId, _includeImage);
            }
          } else {
            n = await api.applyScrapedPerformer(
                p, widget.targetId, _includeImage);
          }
        } else {
          n = await api.applyScrapedPerformer(
              p, widget.targetId, _includeImage);
        }
      } else {
        n = await api.applyScrapedStudio(
            _studioResults[_previewIndex], widget.targetId, _includeImage);
      }
      if (!mounted) return;
      // 写回成功：提示后自动返回，让详情页/列表页刷新查看结果
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              nameSkipped
                  ? '已写入 $n 个字段（名字与库中已有演员冲突，未写入）'
                  : '已写入 $n 个字段',
              style: const TextStyle(fontSize: 13)),
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applyError = true;
        _applyMsg = '写回失败：$e';
      });
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  String _title() {
    if (_previewIndex >= 0) return '削刮结果预览';
    if (_started) return '削刮结果';
    return '元数据削刮';
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_title())),
      body: _previewIndex >= 0 ? _buildPreview(theme) : _buildBody(theme),
    );
  }

  Widget _buildPreview(ThemeData theme) {
    final img = _previewImage();
    final rows = _previewRows();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton(
          onPressed: _applying || rows.isEmpty ? null : _apply,
          child: Text(_applying ? '应用中…' : '应用并写回'),
        ),
        const SizedBox(height: 12),
        if (img.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              img,
              fit: BoxFit.cover,
              height: 180,
              width: double.infinity,
              errorBuilder: (_, __, ___) => Container(
                height: 180,
                color: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _includeImage,
          title: const Text('应用图片（下载后转为 base64 写入）'),
          onChanged: (v) => setState(() => _includeImage = v),
        ),
        const SizedBox(height: 8),
        Text('将写入 ${rows.length} 个字段',
            style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        for (final row in rows)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(row, style: theme.textTheme.bodyMedium),
          ),
        Text('空字段不会写入，库内不存在的演员/标签/工作室将自动创建。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        if (_applyMsg.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            _applyMsg,
            style: theme.textTheme.bodyMedium?.copyWith(
                color: _applyError
                    ? const Color(0xFFE5533D)
                    : const Color(0xFF35C77B)),
          ),
        ],
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => setState(() => _previewIndex = -1),
          child: const Text('返回结果'),
        ),
      ],
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (!_started) return _buildPicker(theme);
    if (_loading) {
      return StatusView(loading: true, empty: '', onRetry: () {});
    }
    final results = _isScene
        ? _sceneResults.map((e) => (e.title.isEmpty ? '（无标题）' : e.title,
            e.date))
            .toList()
        : _isPerformer
            ? _performerResults
                .map((e) => (
                      e.name.isEmpty ? '（无名称）' : e.name,
                      [e.country, e.birthdate]
                          .where((v) => v.isNotEmpty)
                          .join(' · ')
                    ))
                .toList()
            : _studioResults
                .map((e) => (e.name.isEmpty ? '（无名称）' : e.name,
                    e.urls.isEmpty ? '' : e.urls.first))
                .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error.isNotEmpty)
          Text(_error,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: const Color(0xFFE5533D))),
        if (results.isEmpty && _error.isEmpty)
          Text('没有削刮到结果', style: theme.textTheme.bodySmall),
        for (var i = 0; i < results.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(results[i].$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                    if (results[i].$2.isNotEmpty)
                      Text(results[i].$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 30)),
                onPressed: () => setState(() => _previewIndex = i),
                child: const Text('查看', style: TextStyle(fontSize: 11)),
              ),
            ]),
          ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => setState(() {
            _started = false;
            _error = '';
            _sceneResults = [];
            _performerResults = [];
            _studioResults = [];
          }),
          child: const Text('换削刮器'),
        ),
      ],
    );
  }

  Widget _buildPicker(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (_isStudio)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('工作室削刮：通过 Stash-box 按名称匹配',
                style: theme.textTheme.bodySmall),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              for (var i = 0; i < 3; i++) ...[
                Expanded(
                  child: SizedBox(
                    height: 34,
                    child: _modeButton(i, ['片段削刮', '名称', 'URL'][i]),
                  ),
                ),
                if (i < 2) const SizedBox(width: 8),
              ],
            ]),
          ),

        if (_mode == 0) ...[
          const SizedBox(height: 12),
          Text('片段削刮：以当前条目的已有信息为上下文削刮',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          for (final s in _fragmentScrapers)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Expanded(
                    child: Text(s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13))),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 30)),
                  onPressed: _loading ? null : () => _scrapeFragment(s),
                  child: const Text('削刮', style: TextStyle(fontSize: 11)),
                ),
              ]),
            ),
          // Stash-box 不支持片段（FRAGMENT），片段模式用本地演员名自动去 box 搜索。
          if (_isPerformer && _boxes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Stash-box（用当前演员名字搜索）',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            for (var i = 0; i < _boxes.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Expanded(
                      child: Text(
                          '${_boxes[i].name.isNotEmpty ? _boxes[i].name : 'Stash-box'}（Stash-box）',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13))),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 30)),
                    onPressed:
                        _loading ? null : () => _scrapeBoxFragment(i),
                    child: const Text('削刮', style: TextStyle(fontSize: 11)),
                  ),
                ]),
              ),
          ],
          if (_fragmentScrapers.isEmpty && _boxes.isEmpty)
            Text('服务端未返回支持片段削刮的本地刮削器',
                style: theme.textTheme.bodySmall),
        ] else if (_mode == 1) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _queryCtrl,
            contextMenuBuilder: zhContextMenuBuilder,
            decoration: InputDecoration(
              labelText: '输入${_isScene ? "短片" : (_isPerformer ? "演员" : "工作室")}名称关键词',
              isDense: true,
              suffixIcon: _queryCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空',
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _queryCtrl.clear();
                        setState(() {});
                      },
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          for (final src in _querySources)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Expanded(
                    child: Text(src.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13))),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 30)),
                  onPressed: _loading || _queryCtrl.text.trim().isEmpty
                      ? null
                      : () => _scrapeQuery(src),
                  child: const Text('削刮', style: TextStyle(fontSize: 11)),
                ),
              ]),
            ),
          if (_querySources.isEmpty)
            Text('未找到可用削刮源（无 Stash-box 且无本地刮削器）',
                style: theme.textTheme.bodySmall),
        ] else ...[
          const SizedBox(height: 12),
          TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            contextMenuBuilder: zhContextMenuBuilder,
            decoration: const InputDecoration(
              hintText: 'https://example.com/xxx',
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _loading || _urlCtrl.text.trim().isEmpty
                ? null
                : _scrapeUrl,
            child: const Text('开始削刮'),
          ),
          const SizedBox(height: 6),
          Text('需要刮削器支持 URL 类型削刮。', style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }

  Widget _modeButton(int mode, String label) {
    final active = _mode == mode;
    final theme = Theme.of(context);
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: active ? theme.colorScheme.primary : null,
        foregroundColor: active ? Colors.white : theme.colorScheme.onSurface,
        padding: EdgeInsets.zero,
      ),
      onPressed: () => setState(() => _mode = mode),
      child: Text(label,
          style: const TextStyle(fontSize: 12),
          overflow: TextOverflow.ellipsis),
    );
  }
}
