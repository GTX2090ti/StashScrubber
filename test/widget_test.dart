// 主题与外观三模式的基础冒烟测试。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stash_scrubber_flutter/settings/app_settings.dart';

void main() {
  testWidgets('Appearance 枚举与设置默认值可用', (WidgetTester tester) async {
    expect(Appearance.values.length, 3);
    expect(Appearance.system.name, 'system');
    expect(Appearance.light.name, 'light');
    expect(Appearance.dark.name, 'dark');
    expect(AppSettings.instance.hasProfile, isFalse);
  });

  testWidgets('MaterialApp 接受 themeMode（构造冒烟）', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      themeMode: ThemeMode.system,
      home: Scaffold(body: Text('stash')),
    ));
    expect(find.text('stash'), findsOneWidget);
  });
}