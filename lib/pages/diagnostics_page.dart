import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import '../widgets/common.dart';

/// 网络诊断页（对齐 iOS DiagnosticsView）：连接状态、Stash 版本、两侧地址延迟、选路结论。
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  bool _busy = false;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _version = '';
    });
    final cfg = AppSettings.instance;
    await cfg.probeBoth();
    if (cfg.baseUrl.isNotEmpty) {
      try {
        _version = await buildApi().version();
      } catch (e) {
        _version = '查询失败：$e';
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
  }

  String _latency(int ms) {
    if (ms == -1) return '未配置';
    if (ms == -2) return '不可达';
    return '$ms ms';
  }

  @override
  Widget build(BuildContext context) {
    final cfg = AppSettings.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('网络诊断'),
        actions: [
          IconButton(
              tooltip: '重新诊断',
              icon: const Icon(Icons.refresh),
              onPressed: _busy ? null : _run),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          const SectionTitle('当前档案'),
          InfoRow('档案名', cfg.profileName),
          InfoRow('生效地址', cfg.activeSlot.label),
          InfoRow('生效 URL', cfg.baseUrl.isEmpty ? '（未配置）' : cfg.baseUrl),
          InfoRow('选路结论',
              cfg.lastSwitchReason.isEmpty ? '—' : cfg.lastSwitchReason),
          const SectionTitle('地址探测'),
          InfoRow('内网地址', _latency(cfg.lanLatencyMs)),
          InfoRow('外网地址', _latency(cfg.wanLatencyMs)),
          const SectionTitle('服务端'),
          InfoRow('Stash 版本', _version.isEmpty ? '（未检测）' : _version),
          const SectionTitle('操作'),
          FilledButton.tonal(
            onPressed: _busy
                ? null
                : () async {
                    await cfg.probeBoth();
                    await cfg.autoSelect('诊断页重新选路');
                  },
            child: const Text('重新测速并选路'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
