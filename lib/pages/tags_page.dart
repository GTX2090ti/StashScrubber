import 'package:flutter/material.dart';

import '../models/models.dart';
import '../widgets/common.dart';
import '../widgets/zh_toolbar.dart';
import 'studio_detail_page.dart';

/// 标签浏览：全部标签列表 + 搜索（对齐 iOS 独立标签板块）。
class TagsPage extends StatefulWidget {
  const TagsPage({super.key, this.embedded = false});

  /// true 时由外层（资料库页）提供 Scaffold，本页只出内容。
  final bool embedded;

  @override
  State<TagsPage> createState() => _TagsPageState();
}

class _TagsPageState extends State<TagsPage> {
  final _api = buildApi();
  List<Tag> _tags = [];
  bool _loading = true;
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    try {
      final tags = await _api.allTags();
      if (!mounted) return;
      setState(() {
        _tags = tags;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(context, '加载标签失败：$e', error: true);
    }
  }

  List<Tag> get _filtered {
    final q = _query.toLowerCase();
    if (q.isEmpty) return _tags;
    return _tags.where((t) => t.name.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: TextField(
            controller: _searchCtrl,
            contextMenuBuilder: zhContextMenuBuilder,
            decoration: InputDecoration(
              hintText: '搜索标签',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _filtered.isEmpty
                  ? StatusView(loading: false, empty: '没有标签', onRetry: _load)
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _filtered.length,
                      itemBuilder: (context, i) {
                        final t = _filtered[i];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          child: ListTile(
                            leading: Icon(Icons.label_outline,
                                color: theme.colorScheme.primary),
                            title: Text(t.name),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TagDetailPage(tagId: t.id),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
        ),
      ],
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: Text('标签（${_tags.length}）'),
        actions: [
          IconButton(tooltip: '刷新', icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: body,
    );
  }
}
