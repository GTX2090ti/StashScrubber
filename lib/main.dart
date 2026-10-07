import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'pages/home_page.dart';
import 'pages/lock_page.dart';
import 'pages/login_page.dart';
import 'pages/settings_page.dart';
import 'settings/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // release 下 build 异常默认显示纯灰屏，换成可见的报错文本，便于定位问题
  ErrorWidget.builder = (details) => ColoredBox(
        color: const Color(0xFF111318),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '页面渲染出错\n${details.exception}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
  // 存储初始化失败也必须进入 runApp，否则永久白屏
  try {
    await AppSettings.instance.load();
  } catch (e) {
    debugPrint('AppSettings load failed: $e');
  }
  runApp(const StashScrubberApp());
}

class StashScrubberApp extends StatefulWidget {
  const StashScrubberApp({super.key});

  @override
  State<StashScrubberApp> createState() => _StashScrubberAppState();
}

class _StashScrubberAppState extends State<StashScrubberApp>
    with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  bool _lockShowing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppSettings.instance.addListener(_onSettingsChanged);
    // 首帧渲染后检查是否需要面容解锁（App 启动场景）
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowLock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppSettings.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从后台回到前台时重新验证（若已开启面容解锁）
    if (state == AppLifecycleState.resumed) {
      final cfg = AppSettings.instance;
      if (cfg.biometricLock) {
        cfg.resetUnlocked();
        _maybeShowLock();
      }
    }
  }

  /// 已开启面容解锁且本次会话未验证时，弹出锁屏页。
  void _maybeShowLock() {
    final cfg = AppSettings.instance;
    if (!cfg.biometricLock || cfg.unlockedThisSession || _lockShowing) return;
    _lockShowing = true;
    _navKey.currentState?.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LockPage(
          onUnlocked: () => _lockShowing = false,
        ),
      ),
    );
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  ThemeData _buildTheme(Brightness brightness) {
    const seed = Color(0xFF3D7EFF);
    final dark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
      scaffoldBackgroundColor: dark ? const Color(0xFF0E0F13) : const Color(0xFFF2F2F7),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF15181F) : null,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: dark ? const Color(0xFF1A1E26) : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
        isDense: true,
      ),
      dividerTheme: const DividerThemeData(space: 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mode = switch (AppSettings.instance.appearance) {
      Appearance.light => ThemeMode.light,
      Appearance.dark => ThemeMode.dark,
      Appearance.system => ThemeMode.system,
    };
    final home =
        AppSettings.instance.hasProfile ? const HomePage() : const LoginPage();
    return MaterialApp(
      title: 'Stash',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navKey,
      themeMode: mode,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      locale: const Locale('zh', 'CN'),
      routes: {
        '/login': (_) => const LoginPage(),
        '/home': (_) => const HomePage(),
        '/settings': (_) => const SettingsPage(),
      },
      home: home,
    );
  }
}
