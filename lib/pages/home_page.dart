import 'package:flutter/material.dart';

import '../widgets/slot_badge.dart';
import 'favorites_page.dart';
import 'library_page.dart';
import 'scene_list_page.dart';
import 'settings_page.dart';

/// 首页：底部 4 个入口（短片 / 收藏 / 资料库 / 设置，对齐 Stash web 打包 app）。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  static const _titles = ['短片', '收藏', '资料库', '设置'];

  @override
  Widget build(BuildContext context) {
    final pages = [
      SceneListPage(embedded: true),
      const FavoritesPage(embedded: true),
      const LibraryPage(embedded: true),
      const SettingsPage(embedded: true),
    ];
    return Scaffold(
      appBar: AppBar(
        title: _tab == 0
            ? const Row(children: [
                Text('短片'),
                SizedBox(width: 10),
                Expanded(child: SlotBadge()),
              ])
            : Text(_titles[_tab]),
        automaticallyImplyLeading: false,
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBarTheme(
        data: const NavigationBarThemeData(
          height: 52,
          labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 10.5, height: 1.0)),
          iconTheme: WidgetStatePropertyAll(IconThemeData(size: 19)),
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.movie_outlined), selectedIcon: Icon(Icons.movie), label: '短片'),
            NavigationDestination(icon: Icon(Icons.star_outline), selectedIcon: Icon(Icons.star), label: '收藏'),
            NavigationDestination(icon: Icon(Icons.video_library_outlined), selectedIcon: Icon(Icons.video_library), label: '资料库'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '设置'),
          ],
        ),
      ),
    );
  }
}
