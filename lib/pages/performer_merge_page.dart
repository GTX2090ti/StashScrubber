import 'package:flutter/material.dart';

import '../models/models.dart';
import '../widgets/common.dart';
import '../widgets/zh_toolbar.dart';

/// 演员合并页：搜索源演员（可多选）→ 合并到目标演员（performerMerge）。
/// 用于处理同名/重复演员：源演员的短片、标签、别名等归并到目标，源条目删除。
class PerformerMergePage extends StatefulWidget {
  const PerformerMergePage({
    super.key,
    required this.targetId,
    required this.targetName,
  });

  final String targetId;
  final String targetName;

  @override
  State<PerformerMergePage> createState() => _PerformerMergePageState();
}

class _PerformerMergePageState extends State<PerformerMergePage> {
  final _ctrl = TextEditingController();
  List<Performer> _performers = [];
  final Set<String> _selected = {};
  bool _loading = false;
  bool _merging = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final r = await buildApi().findPerformers(
        page: 1,
        perPage: 100,
        q: _ctrl.text.trim(),
        sort: 'name',
        direction: 'ASC',
      );
      if (!mounted) return;
      setState(() => _performers = r.items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '搜索失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _merge() async {
    if (_selected.isEmpty) return;
    setState(() {
      _merging = true;
      _error = '';
    });
    try {
      await buildApi().mergePerformers(_selected.toList(), widget.targetId);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '合并失败：$e');
    } finally {
      if (mounted) setState(() => _merging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('合并演员')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _ctrl,
            textInputAction: TextInputAction.search,
            contextMenuBuilder: zhContextMenuBuilder,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: '搜索演员',
              isDense: true,
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_ctrl.text.isNotEmpty)
                    IconButton(
                      tooltip: '清空',
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _ctrl.clear();
                        setState(() {});
                        _search();
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.search, size: 18),
                    onPressed: _search,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('已选 ${_selected.length} 个源演员',
                  style: theme.textTheme.bodySmall),
            ),
          ),
        Expanded(
          child: _loading
              ? StatusView(loading: true, empty: '', onRetry: _search)
              : _performers.isEmpty
                  ? StatusView(
                      loading: false, empty: '没有匹配的演员', onRetry: _search)
                  : ListView.builder(
                      itemCount: _performers.length,
                      itemBuilder: (_, i) {
                        final p = _performers[i];
                        final isTarget = p.id == widget.targetId;
                        return CheckboxListTile(
                          dense: true,
                          value: _selected.contains(p.id),
                          controlAffinity: ListTileControlAffinity.trailing,
                          secondary: SizedBox(
                            width: 64,
                            height: 36,
                            child: AuthImage(
                                rawPath: p.imagePath, radius: 6),
                          ),
                          title: Row(children: [
                            Flexible(
                              child: Text(p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            if (isTarget)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Text('目标',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.primary,
                                        fontSize: 11)),
                              ),
                          ]),
                          subtitle: p.birthdate.isEmpty ? null : Text(p.birthdate),
                          onChanged: isTarget
                              ? null
                              : (v) => setState(() {
                                    if (v == true) {
                                      _selected.add(p.id);
                                    } else {
                                      _selected.remove(p.id);
                                    }
                                  }),
                        );
                      },
                    ),
        ),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: const Color(0xFFE5533D))),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(children: [
            Text(
              '选择要并入「${widget.targetName.isEmpty ? "当前演员" : widget.targetName}」的源演员（可多选）。'
              '合并后相关短片、标签、别名等归并到目标演员，源演员条目删除。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _merging || _selected.isEmpty ? null : _merge,
              child: Text(_merging
                  ? '合并中…'
                  : '合并 ${_selected.length} 个演员到当前演员'),
            ),
          ]),
        ),
      ]),
    );
  }
}
