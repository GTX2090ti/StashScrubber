import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/net_log.dart';
import '../widgets/common.dart';

/// 网络日志查看页（对齐 iOS NetLogView）：每次请求结果 + 一键复制。
class NetLogPage extends StatefulWidget {
  const NetLogPage({super.key});

  @override
  State<NetLogPage> createState() => _NetLogPageState();
}

class _NetLogPageState extends State<NetLogPage> {
  @override
  void initState() {
    super.initState();
    NetLog.instance.addListener(_onLog);
  }

  @override
  void dispose() {
    NetLog.instance.removeListener(_onLog);
    super.dispose();
  }

  void _onLog() {
    if (mounted) setState(() {});
  }

  Future<void> _copyAll() async {
    final text = NetLog.instance.exportText;
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showToast(context, '日志已复制');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = NetLog.instance.entries;
    return Scaffold(
      appBar: AppBar(
        title: Text('网络日志（${entries.length}）'),
        actions: [
          IconButton(
              tooltip: '复制全部',
              icon: const Icon(Icons.copy),
              onPressed: _copyAll),
          IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => NetLog.instance.clear()),
        ],
      ),
      body: entries.isEmpty
          ? const Center(child: Text('暂无网络日志'))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final e = entries[i];
                final color = e.level == 'ERROR'
                    ? theme.colorScheme.error
                    : e.level == 'WARN'
                        ? Colors.orange
                        : theme.colorScheme.onSurfaceVariant;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${e.category} ${e.level}',
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: color),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(e.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium),
                            ),
                            Text(NetLog.msText(e.ms),
                                style: theme.textTheme.labelSmall),
                          ],
                        ),
                        if (e.message.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(e.message, style: theme.textTheme.bodySmall),
                        ],
                        if (e.url.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${e.method} ${e.url}${e.status != null ? ' · HTTP ${e.status}' : ''}',
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: theme.colorScheme.outline),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
