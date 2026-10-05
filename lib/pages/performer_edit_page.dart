import 'package:flutter/material.dart';

import '../api/stash_api.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import '../widgets/zh_toolbar.dart';

/// 演员编辑页（新建与编辑共用）。
class PerformerEditPage extends StatefulWidget {
  const PerformerEditPage({super.key, required this.performerId});

  final String performerId;

  @override
  State<PerformerEditPage> createState() => _PerformerEditPageState();
}

class _PerformerEditPageState extends State<PerformerEditPage> {
  final _nameCtrl = TextEditingController();
  final _disambigCtrl = TextEditingController();
  final _birthCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _ethnicityCtrl = TextEditingController();
  final _measureCtrl = TextEditingController();
  final _careerCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();

  int _rating = 0;
  Set<String> _tagIds = {};
  List<Tag> _tags = [];

  bool _loading = true;
  bool _saving = false;
  String _error = '';

  StashApi get _api => buildApi();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _disambigCtrl,
      _birthCtrl,
      _countryCtrl,
      _ethnicityCtrl,
      _measureCtrl,
      _careerCtrl,
      _detailsCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final p = await _api.findPerformer(widget.performerId);
      if (p != null) {
        _nameCtrl.text = p.name;
        _disambigCtrl.text = p.disambiguation;
        _birthCtrl.text = p.birthdate;
        _countryCtrl.text = p.country;
        _ethnicityCtrl.text = p.ethnicity;
        _measureCtrl.text = p.measurements;
        _careerCtrl.text = p.careerLength;
        _detailsCtrl.text = p.details;
        _rating = p.rating100;
        _tagIds = p.tags.map((e) => e.id).toSet();
      }
      _tags = await _api.allTags();
    } catch (e) {
      _error = '加载失败：$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = '';
    });
    final input = <String, dynamic>{'id': widget.performerId};
    void put(String k, String v) {
      if (v.trim().isNotEmpty) input[k] = v.trim();
    }

    put('name', _nameCtrl.text);
    put('disambiguation', _disambigCtrl.text);
    put('birthdate', _birthCtrl.text);
    put('country', _countryCtrl.text);
    put('ethnicity', _ethnicityCtrl.text);
    put('measurements', _measureCtrl.text);
    put('career_length', _careerCtrl.text);
    put('details', _detailsCtrl.text);
    if (_rating > 0) input['rating100'] = _rating;
    if (_tagIds.isNotEmpty) input['tag_ids'] = _tagIds.toList();

    try {
      await _api.updatePerformer(input);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('编辑演员')),
      body: _loading
          ? StatusView(loading: true, empty: '', onRetry: _load)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                const SectionTitle('基本信息'),
                TextField(
                    controller: _nameCtrl,
                    contextMenuBuilder: zhContextMenuBuilder,
                    decoration: const InputDecoration(labelText: '名称')),
                const SizedBox(height: 12),
                TextField(
                    controller: _disambigCtrl,
                    contextMenuBuilder: zhContextMenuBuilder,
                    decoration: const InputDecoration(labelText: '区别名')),
                const SizedBox(height: 12),
                TextField(
                    controller: _birthCtrl,
                    contextMenuBuilder: zhContextMenuBuilder,
                    decoration: const InputDecoration(
                        labelText: '出生日期（yyyy-MM-dd）')),
                const SizedBox(height: 12),
                TextField(
                    controller: _countryCtrl,
                    contextMenuBuilder: zhContextMenuBuilder,
                    decoration: const InputDecoration(labelText: '国籍')),
                Row(children: [
                  const Text('评分'),
                  const Spacer(),
                  Text(
                    _rating > 0
                        ? '${(_rating / 20).toStringAsFixed(1)} / 5.0'
                        : '未评分',
                    style: theme.textTheme.bodySmall,
                  ),
                ]),
                Slider(
                  value: _rating.toDouble(),
                  max: 100,
                  divisions: 20,
                  onChanged: (v) => setState(() => _rating = v.round()),
                ),

                const SectionTitle('档案'),
                TextField(
                    controller: _ethnicityCtrl,
                    contextMenuBuilder: zhContextMenuBuilder,
                    decoration: const InputDecoration(labelText: '族裔')),
                const SizedBox(height: 12),
                TextField(
                    controller: _measureCtrl,
                    contextMenuBuilder: zhContextMenuBuilder,
                    decoration: const InputDecoration(labelText: '三围')),
                const SizedBox(height: 12),
                TextField(
                    controller: _careerCtrl,
                    contextMenuBuilder: zhContextMenuBuilder,
                    decoration: const InputDecoration(
                        labelText: '从业年限（如 2015-2020）')),

                SectionTitle('标签（${_tagIds.length}）'),
                OutlinedButton.icon(
                  onPressed: () async {
                    final r = await showMultiSelectSheet(
                      context,
                      title: '选择标签',
                      options: [for (final t in _tags) (t.id, t.name)],
                      selected: _tagIds,
                    );
                    if (r != null) setState(() => _tagIds = r);
                  },
                  icon: const Icon(Icons.sell_outlined, size: 16),
                  label: const Text('选择标签'),
                ),

                const SectionTitle('简介'),
                TextField(
                  controller: _detailsCtrl,
                  maxLines: 5,
                  contextMenuBuilder: zhContextMenuBuilder,
                  decoration: const InputDecoration(hintText: '简介…'),
                ),

                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(_error,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: const Color(0xFFE5533D))),
                ],
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 46,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '保存中…' : '保存'),
            ),
          ),
        ),
      ),
    );
  }
}
