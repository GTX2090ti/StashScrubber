import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../settings/app_settings.dart';
import 'diagnostics_page.dart';
import 'net_log_page.dart';
import 'server_settings_page.dart';
import 'stash_tasks_page.dart';
import 'tags_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AppSettings get _cfg => AppSettings.instance;

  final LocalAuthentication _auth = LocalAuthentication();
  bool _bioAvailable = false;

  @override
  void initState() {
    super.initState();
    _cfg.addListener(_onCfg);
    _checkBiometrics();
  }

  @override
  void dispose() {
    _cfg.removeListener(_onCfg);
    super.dispose();
  }

  Future<void> _checkBiometrics() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      if (!mounted) return;
      setState(() => _bioAvailable = supported && canCheck);
    } catch (e) {
      if (!mounted) return;
      setState(() => _bioAvailable = false);
    }
  }

  Future<void> _toggleBiometricLock(bool v) async {
    if (v && !_bioAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('此设备不支持生物识别，无法开启面容解锁')),
      );
      return;
    }
    await _cfg.setBiometricLock(v);
    if (v) {
      // 开启后立即要求验证一次（首次生效）
      try {
        final ok = await _auth.authenticate(
          localizedReason: '验证您的身份以启用面容解锁',
          options: const AuthenticationOptions(biometricOnly: true),
        );
        if (ok) {
          _cfg.markUnlocked();
        }
      } catch (e) {
        debugPrint('biometric enable auth failed: $e');
      }
    }
  }

  void _onCfg() {
    if (mounted) setState(() {});
  }

  String normalizeLabel(String url) {
    final m = RegExp(r'^https?://').firstMatch(url);
    return m == null ? url : url.substring(m.end);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('外观', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<Appearance>(
          segments: const [
            ButtonSegment(
                value: Appearance.system,
                label: Text('跟随系统'),
                icon: Icon(Icons.brightness_auto_outlined)),
            ButtonSegment(
                value: Appearance.light,
                label: Text('白天'),
                icon: Icon(Icons.light_mode_outlined)),
            ButtonSegment(
                value: Appearance.dark,
                label: Text('黑暗'),
                icon: Icon(Icons.dark_mode_outlined)),
          ],
          selected: {_cfg.appearance},
          onSelectionChanged: (sel) => _cfg.setAppearance(sel.first),
        ),

        const SizedBox(height: 24),
        Text('服务器', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.dns_outlined),
          title: const Text('服务器档案 / 生效地址'),
          subtitle: Text(
            _cfg.hasProfile
                ? '${_cfg.currentProfileName} · ${normalizeLabel(_cfg.baseUrl)}'
                : '尚未配置服务器',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ServerSettingsPage()),
          ),
        ),

        const SizedBox(height: 24),
        Text('浏览', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.label_outline),
          title: const Text('标签浏览'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TagsPage()),
          ),
        ),

        const SizedBox(height: 24),
        Text('隐私', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.visibility_off_outlined),
          title: const Text('安全模式'),
          subtitle: const Text('缩略图打码，长按可临时查看'),
          value: _cfg.safeMode,
          onChanged: (v) => _cfg.setSafeMode(v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.face_retouching_natural),
          title: const Text('面容解锁'),
          subtitle: Text(
            _bioAvailable ? '启动 App 与回到前台时需 Face ID / 指纹验证' : '此设备不支持生物识别',
          ),
          value: _cfg.biometricLock,
          onChanged: _bioAvailable ? _toggleBiometricLock : null,
        ),

        const SizedBox(height: 24),
        Text('网络', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.document_scanner_outlined),
          title: const Text('Stash 扫描'),
          subtitle: const Text('扫描新短片与图片'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const StashTasksPage()),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.network_check),
          title: const Text('网络诊断'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DiagnosticsPage()),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.article_outlined),
          title: const Text('网络日志'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NetLogPage()),
          ),
        ),

        const SizedBox(height: 24),
        Text('关于', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('StashScrubber Flutter 1.6.68', style: theme.textTheme.bodySmall),
        if (!_cfg.storageAvailable)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('本地存储不可用，设置不会持久化',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: const Color(0xFFE5533D))),
          ),
        const SizedBox(height: 24),
      ],
    );

    if (widget.embedded) return Scaffold(body: body);
    return Scaffold(appBar: AppBar(title: const Text('设置')), body: body);
  }
}
