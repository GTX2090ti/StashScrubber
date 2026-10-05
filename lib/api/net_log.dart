import 'package:flutter/foundation.dart';

/// 网络日志（对齐 iOS NetLog）：记录每次请求的结果，500 条上限，支持复制导出。
class NetLog extends ChangeNotifier {
  NetLog._();

  static final NetLog instance = NetLog._();

  static const int maxEntries = 500;

  final List<NetEntry> _entries = [];

  List<NetEntry> get entries => List.unmodifiable(_entries);

  void record({
    required String category,
    required String title,
    String message = '',
    String method = '',
    String url = '',
    int? status,
    int ms = 0,
    String level = 'INFO',
  }) {
    _entries.add(NetEntry(
      category: category,
      title: title,
      message: message,
      method: method,
      url: url,
      status: status,
      ms: ms,
      level: level,
    ));
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  String get exportText => _entries
      .map((e) =>
          '[${e.level}] ${e.category} ${e.title}${e.message.isNotEmpty ? ' · ${e.message}' : ''}'
          '${e.url.isNotEmpty ? ' · ${e.method} ${e.url}' : ''}'
          '${e.status != null ? ' · HTTP ${e.status}' : ''} · ${msText(e.ms)}')
      .join('\n');

  static String msText(int ms) => ms <= 0 ? '' : '${ms}ms';
}

class NetEntry {
  final String category;
  final String title;
  final String message;
  final String method;
  final String url;
  final int? status;
  final int ms;
  final String level;

  const NetEntry({
    required this.category,
    required this.title,
    this.message = '',
    this.method = '',
    this.url = '',
    this.status,
    this.ms = 0,
    this.level = 'INFO',
  });
}
