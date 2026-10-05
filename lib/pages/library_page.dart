import 'package:flutter/material.dart';

import 'performer_list_page.dart';
import 'studio_list_page.dart';
import 'tags_page.dart';

/// 资料库：标签 / 演员 / 工作室 合并到一个页面（对齐 Stash web 打包 app）。
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, this.embedded = false});

  /// true 时由 HomePage 提供 Scaffold/AppBar，本页只出内容。
  final bool embedded;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage>
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
          Tab(text: '标签'),
          Tab(text: '演员'),
          Tab(text: '工作室'),
        ],
      ),
      Expanded(
        child: TabBarView(
          controller: _tab,
          children: const [
            TagsPage(embedded: true),
            PerformerListPage(embedded: true),
            StudioListPage(embedded: true),
          ],
        ),
      ),
    ]);

    if (widget.embedded) return Scaffold(body: body);
    return Scaffold(appBar: AppBar(title: const Text('资料库')), body: body);
  }
}
