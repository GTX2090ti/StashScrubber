import 'package:flutter/material.dart';

import '../models/models.dart';
import '../widgets/common.dart';
import '../widgets/zh_toolbar.dart';

/// 完整场景筛选器（对齐 iOS SceneFilterSheet）：
/// 工作室/演员/标签多选 + 评分/O计数/时长/日期/分辨率 + 已整理 + 仅看封面。
class SceneFilterSheet extends StatefulWidget {
  final SceneFilterState initial;

  const SceneFilterSheet({super.key, required this.initial});

  @override
  State<SceneFilterSheet> createState() => _SceneFilterSheetState();
}

class _SceneFilterSheetState extends State<SceneFilterSheet> {
  late final SceneFilterState _f = widget.initial.copy();

  List<Studio> _studios = [];
  List<Performer> _performers = [];
  List<Tag> _tags = [];
  bool _loading = true;

  /// 各多选区（工作室/演员/标签）的搜索词。
  final Map<String, String> _multiSearch = {};

  final _api = buildApi();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _api.allStudios(),
        _api.allPerformers(),
        _api.allTags(),
      ]);
      if (!mounted) return;
      setState(() {
        _studios = results[0] as List<Studio>;
        _performers = results[1] as List<Performer>;
        _tags = results[2] as List<Tag>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(context, '加载筛选选项失败：$e', error: true);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final from = _f.dateFrom.isNotEmpty
        ? DateTime.tryParse(_f.dateFrom)
        : null;
    final to = _f.dateTo.isNotEmpty ? DateTime.tryParse(_f.dateTo) : null;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      initialDateRange: (from != null && to != null)
          ? DateTimeRange(start: from, end: to)
          : null,
      helpText: '选择日期范围（可不选）',
      saveText: '确定',
    );
    if (picked != null && mounted) {
      setState(() {
        _f.dateFrom = _fmtDate(picked.start);
        _f.dateTo = _fmtDate(picked.end);
      });
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _multiSelect<T>({
    required String title,
    required List<T> items,
    required List<String> selected,
    required String Function(T) label,
    required String Function(T) id,
  }) {
    final theme = Theme.of(context);
    final q = (_multiSearch[title] ?? '').trim().toLowerCase();
    final shown = q.isEmpty
        ? items
        : items
            .where((it) => label(it).toLowerCase().contains(q))
            .toList();
    return ExpansionTile(
      title: Text(title),
      subtitle: selected.isEmpty
          ? null
          : Text('已选 ${selected.length} 项',
              style: TextStyle(color: theme.colorScheme.primary)),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: TextField(
            contextMenuBuilder: zhContextMenuBuilder,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: '搜索$title',
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: q.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空',
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () =>
                          setState(() => _multiSearch[title] = ''),
                    ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (v) => setState(() => _multiSearch[title] = v),
          ),
        ),
        if (shown.isEmpty)
          const Padding(padding: EdgeInsets.all(12), child: Text('（无）')),
        for (final it in shown)
          CheckboxListTile(
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title:
                Text(label(it), maxLines: 1, overflow: TextOverflow.ellipsis),
            value: selected.contains(id(it)),
            onChanged: (v) => setState(() {
              if (v == true) {
                if (!selected.contains(id(it))) selected.add(id(it));
              } else {
                selected.remove(id(it));
              }
            }),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('筛选'),
        actions: [
          TextButton(
            onPressed: () => setState(() => _f
              ..studios.clear()
              ..tags.clear()
              ..performers.clear()
              ..rating100 = 0
              ..oCounter = 0
              ..durationSeconds = 0
              ..resolution = 0
              ..dateFrom = ''
              ..dateTo = ''
              ..organized = false
              ..coversOnly = false),
            child: const Text('重置'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _f),
            child: const Text('应用'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _multiSelect<Studio>(
                  title: '工作室',
                  items: _studios,
                  selected: _f.studios,
                  label: (s) => s.name,
                  id: (s) => s.id,
                ),
                _multiSelect<Performer>(
                  title: '演员',
                  items: _performers,
                  selected: _f.performers,
                  label: (p) => p.name,
                  id: (p) => p.id,
                ),
                _multiSelect<Tag>(
                  title: '标签',
                  items: _tags,
                  selected: _f.tags,
                  label: (t) => t.name,
                  id: (t) => t.id,
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('评分 ≥', style: theme.textTheme.titleSmall),
                      Row(
                        children: [
                          for (var i = 1; i <= 10; i++)
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              iconSize: 20,
                              icon: Icon(
                                _f.rating100 >= i * 10
                                    ? Icons.star
                                    : Icons.star_border,
                                color: const Color(0xFFFF9F0A),
                              ),
                              onPressed: () => setState(() {
                                _f.rating100 =
                                    _f.rating100 == i * 10 ? 0 : i * 10;
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('O 计数 ≥', style: theme.textTheme.titleSmall),
                      Row(
                        children: [
                          for (var i = 0; i <= 5; i++)
                            ChoiceChip(
                              label: Text(i == 0 ? '不限' : '$i'),
                              selected: _f.oCounter == i,
                              onSelected: (_) =>
                                  setState(() => _f.oCounter = i),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text('时长 ≥（分钟）', style: theme.textTheme.titleSmall),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final (v, label) in [
                            (0, '不限'),
                            (10, '10'),
                            (30, '30'),
                            (60, '60'),
                            (120, '120'),
                          ])
                            ChoiceChip(
                              label: Text(label),
                              selected: _f.durationSeconds == v * 60,
                              onSelected: (_) => setState(
                                  () => _f.durationSeconds = v * 60),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text('分辨率 ≥', style: theme.textTheme.titleSmall),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final (v, label) in [
                            (0, '不限'),
                            (720, '720p'),
                            (1080, '1080p'),
                            (2160, '4K'),
                          ])
                            ChoiceChip(
                              label: Text(label),
                              selected: _f.resolution == v,
                              onSelected: (_) =>
                                  setState(() => _f.resolution = v),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text('日期范围', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.date_range, size: 18),
                        label: Text(_f.dateFrom.isEmpty && _f.dateTo.isEmpty
                            ? '不限'
                            : '${_f.dateFrom.isNotEmpty ? _f.dateFrom : '…'} ~ '
                                '${_f.dateTo.isNotEmpty ? _f.dateTo : '…'}'),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('仅看已收藏'),
                        value: _f.organized,
                        onChanged: (v) => setState(() => _f.organized = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('仅看有封面'),
                        value: _f.coversOnly,
                        onChanged: (v) => setState(() => _f.coversOnly = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
