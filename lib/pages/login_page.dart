import 'package:flutter/material.dart';

import '../api/stash_api.dart';
import '../models/models.dart';
import '../settings/app_settings.dart';
import '../widgets/zh_toolbar.dart';

/// 登录页：档案管理（多档案 + 内网/外网双地址）+ 连接测试。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _nameCtrl = TextEditingController();
  final _lanCtrl = TextEditingController();
  final _wanCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();

  bool _testing = false;
  bool _saving = false;
  bool _obscure = true;
  String _status = '';
  bool _statusError = false;

  @override
  void initState() {
    super.initState();
    final p = AppSettings.instance.currentProfile;
    if (p != null) {
      _nameCtrl.text = p.name;
      _lanCtrl.text = p.lanUrl;
      _wanCtrl.text = p.wanUrl;
      _keyCtrl.text = p.apiKey;
    } else {
      _nameCtrl.text = 'Stash';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _lanCtrl.dispose();
    _wanCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Profile _collect() {
    final name = _nameCtrl.text.trim().isEmpty
        ? 'Stash'
        : _nameCtrl.text.trim();
    return Profile(
      name: name,
      lanUrl: normalizeBase(_lanCtrl.text.trim()),
      wanUrl: normalizeBase(_wanCtrl.text.trim()),
      apiKey: _keyCtrl.text.trim(),
    );
  }

  bool get _valid =>
      _lanCtrl.text.trim().isNotEmpty || _wanCtrl.text.trim().isNotEmpty;

  Future<void> _test() async {
    if (!_valid) {
      setState(() {
        _statusError = true;
        _status = '请至少填写一个地址';
      });
      return;
    }
    setState(() {
      _testing = true;
      _statusError = false;
      _status = '测试连接中…';
    });
    final p = _collect();
    final base = p.lanUrl.isNotEmpty ? p.lanUrl : p.wanUrl;
    try {
      final v = await StashApi(base, p.apiKey).version();
      if (!mounted) return;
      setState(() {
        _statusError = false;
        _status = '连接成功，Stash 版本 $v';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusError = true;
        _status = '连接失败：$e';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    if (!_valid) {
      setState(() {
        _statusError = true;
        _status = '请至少填写一个地址';
      });
      return;
    }
    setState(() => _saving = true);
    await AppSettings.instance.upsertProfile(_collect());
    if (!mounted) return;
    await AppSettings.instance.autoSelect('保存档案');
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cfg = AppSettings.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Stash')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('连接到 Stash 服务器', style: theme.textTheme.titleLarge),
                const SizedBox(height: 20),
                TextField(
                  controller: _nameCtrl,
                  contextMenuBuilder: zhContextMenuBuilder,
                  decoration: const InputDecoration(labelText: '档案名称'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _lanCtrl,
                  keyboardType: TextInputType.url,
                  contextMenuBuilder: zhContextMenuBuilder,
                  decoration: const InputDecoration(
                    labelText: '内网地址',
                    hintText: 'http://192.168.2.180:9999',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _wanCtrl,
                  keyboardType: TextInputType.url,
                  contextMenuBuilder: zhContextMenuBuilder,
                  decoration: const InputDecoration(
                    labelText: '外网地址',
                    hintText: 'http://stash.example.com:9999',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _keyCtrl,
                  obscureText: _obscure,
                  contextMenuBuilder: zhContextMenuBuilder,
                  decoration: InputDecoration(
                    labelText: 'ApiKey',
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '填写内外网双地址后，App 会实测延迟并自动选路。',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: _testing ? null : _test,
                      child: Text(_testing ? '测试中…' : '测试连接'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? '保存中…' : '保存并进入'),
                    ),
                  ),
                ]),
                if (_status.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    _status,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: _statusError
                            ? const Color(0xFFE5533D)
                            : const Color(0xFF35C77B)),
                  ),
                ],
                if (cfg.profiles.length > 1) ...[
                  const SizedBox(height: 28),
                  Text('已有档案', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  for (final p in cfg.profiles)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        p.name == cfg.currentProfileName
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                      ),
                      title: Text(p.name),
                      subtitle: Text(
                          [p.lanUrl, p.wanUrl].where((e) => e.isNotEmpty).join('  ·  ')),
                      onTap: () async {
                        await cfg.switchTo(p.name);
                        if (!mounted) return;
                        setState(() {
                          _nameCtrl.text = p.name;
                          _lanCtrl.text = p.lanUrl;
                          _wanCtrl.text = p.wanUrl;
                          _keyCtrl.text = p.apiKey;
                        });
                      },
                      trailing: cfg.profiles.length <= 1
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => cfg.removeProfile(p.name),
                            ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
