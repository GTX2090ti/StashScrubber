import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import '../widgets/common.dart';
import 'login_page.dart';

/// 服务器设置子页：服务器档案 + 生效地址 + 连接状态。
class ServerSettingsPage extends StatefulWidget {
  const ServerSettingsPage({super.key});

  @override
  State<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends State<ServerSettingsPage> {
  AppSettings get _cfg => AppSettings.instance;

  @override
  void initState() {
    super.initState();
    _cfg.addListener(_onCfg);
  }

  @override
  void dispose() {
    _cfg.removeListener(_onCfg);
    super.dispose();
  }

  void _onCfg() {
    if (mounted) setState(() {});
  }

  String _slotLabel(AddrSlot slot) {
    final url = _cfg.slotUrl(slot);
    final lat = slot == AddrSlot.lan ? _cfg.lanLatencyMs : _cfg.wanLatencyMs;
    var s = slot.label;
    if (_cfg.activeSlot == slot) s = '✓ $s';
    s += '（${url.isEmpty ? "未配置" : normalizeLabel(url)}）';
    if (lat >= 0) s += ' · ${lat}ms';
    if (lat == -2) s += ' · 不可达';
    return s;
  }

  String normalizeLabel(String url) {
    final m = RegExp(r'^https?://').firstMatch(url);
    return m == null ? url : url.substring(m.end);
  }

  Future<void> _editProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  Future<void> _deleteProfile(Profile p) async {
    final cfg = AppSettings.instance;
    if (cfg.profiles.length <= 1) {
      showToast(context, '至少保留一个档案', error: true);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除连接「${p.name}」？'),
        content: const Text('删除后需重新填写地址与 API Key。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      await cfg.removeProfile(p.name);
      _onCfg();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('服务器')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('服务器档案', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_cfg.profiles.isEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: const Text('尚未配置'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _editProfile,
            )
          else
            for (final p in _cfg.profiles)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(p.name == _cfg.currentProfileName
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                title: Text(p.name),
                subtitle: Text(
                    [p.lanUrl, p.wanUrl]
                        .where((e) => e.isNotEmpty)
                        .join('  ·  '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                onTap: () => _cfg.switchTo(p.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_cfg.profiles.length > 1)
                      IconButton(
                        tooltip: '删除',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteProfile(p),
                      ),
                    IconButton(
                      tooltip: '编辑',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: _editProfile,
                    ),
                  ],
                ),
              ),
          OutlinedButton.icon(
            onPressed: _editProfile,
            icon: const Icon(Icons.add),
            label: const Text('添加 / 编辑连接'),
          ),

          const Divider(height: 24),
          for (final slot in AddrSlot.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                _cfg.activeSlot == slot
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(_slotLabel(slot)),
              onTap: () => _cfg.setSlot(slot, true),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _cfg.manualLock,
            title: const Text('手动锁定当前地址'),
            subtitle: Text(_cfg.manualLock
                ? '已锁定，自动选路不会覆盖'
                : '自动选择（优先内网，不可达自动切外网）'),
            onChanged: (v) async {
              if (v) {
                await _cfg.setSlot(_cfg.activeSlot, true);
              } else {
                await _cfg.restoreAuto();
              }
            },
          ),
          OutlinedButton.icon(
            onPressed: _cfg.isProbing ? null : () => _cfg.probeBoth(),
            icon: _cfg.isProbing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.network_ping_outlined, size: 16),
            label: Text(_cfg.isProbing ? '测速中…' : '重新测速'),
          ),
          if (_cfg.lastSwitchReason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_cfg.lastSwitchReason,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),

          const SizedBox(height: 24),
          Text('连接状态', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          FutureBuilder<String>(
            future: _cfg.hasProfile ? buildApi().version() : Future.value(''),
            builder: (context, snap) {
              if (!_cfg.hasProfile) {
                return Text('未配置服务器', style: theme.textTheme.bodySmall);
              }
              if (snap.connectionState == ConnectionState.waiting) {
                return Text('连接中…', style: theme.textTheme.bodySmall);
              }
              if (snap.hasError) {
                return Text('连接失败：${snap.error}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: const Color(0xFFE5533D)));
              }
              return Text('Stash ${snap.data} · ${_cfg.baseUrl}',
                  style: theme.textTheme.bodySmall);
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
