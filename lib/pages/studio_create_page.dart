import 'package:flutter/material.dart';

import '../api/stash_api.dart';
import '../widgets/common.dart';
import '../widgets/zh_toolbar.dart';

/// 手动添加工作室页；成功后 pop 新工作室 id，供来源页刷新。
class StudioCreatePage extends StatefulWidget {
  const StudioCreatePage({super.key});

  @override
  State<StudioCreatePage> createState() => _StudioCreatePageState();
}

class _StudioCreatePageState extends State<StudioCreatePage> {
  final _nameCtrl = TextEditingController();
  final _urlsCtrl = TextEditingController();

  bool _saving = false;
  String _error = '';

  StashApi get _api => buildApi();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlsCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '工作室名称不能为空');
      return;
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    final urls = _urlsCtrl.text
        .split(RegExp(r'[\s,，]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    try {
      final id = await _api.createStudio(name, {
        if (urls.isNotEmpty) 'urls': urls,
      });
      if (!mounted) return;
      Navigator.pop(context, id);
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
      appBar: AppBar(title: const Text('添加工作室')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            controller: _nameCtrl,
            contextMenuBuilder: zhContextMenuBuilder,
            decoration: const InputDecoration(labelText: '名称（必填）'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlsCtrl,
            contextMenuBuilder: zhContextMenuBuilder,
            decoration: const InputDecoration(
                labelText: 'URL（多个用空格或逗号分隔，可留空）'),
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
