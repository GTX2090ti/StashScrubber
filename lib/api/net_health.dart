import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'net_log.dart';

/// 是否为「链路层」失败：只有这类失败才值得重建会话 / 重新选路
/// （业务错误 HTTP 401 / GraphQL errors / 解析失败说明链路是通的，换地址也没用）。
bool isConnectivity(Object e) {
  if (e is TimeoutException) return true;
  if (e is SocketException) return true;
  if (e is HandshakeException) return true;
  if (e is http.ClientException) return true;
  return false;
}

/// 共享 API 会话：持有全局 http.Client，可整体重建（close + 新建）。
/// 连接池被吊死的连接占满时，新请求会卡在等连接且不触发超时
/// （「用一段时间后突然连不上」的机制），重建即丢弃全部死连接。
class ApiSession {
  ApiSession._();

  static final ApiSession instance = ApiSession._();

  http.Client _client = http.Client();

  http.Client get client => _client;

  /// 重建会话并丢弃旧连接；旧 client 的 close 会取消其在途请求。
  void reset(String reason) {
    final old = _client;
    _client = http.Client();
    old.close();
    NetLog.instance.record(
        category: 'Network', level: 'WARN', title: '重建网络会话', message: reason);
  }
}

/// 请求健康度：只统计「链路层」失败，连续失败达到阈值即回调一次
/// （由 AppSettings 重新在内外网间选路），触发后计数归零并进入冷却。
class NetHealth {
  NetHealth._();

  static final NetHealth instance = NetHealth._();

  /// 连续失败阈值：一次抖动不切，两次才认为这一侧真不通。
  static const int threshold = 2;

  /// 两次自愈之间的最小间隔。
  static const Duration cooldown = Duration(seconds: 20);

  int _consecutive = 0;
  DateTime _lastKick = DateTime.fromMillisecondsSinceEpoch(0);

  /// 连续失败触发自愈时的回调（参数为最后一次失败原因）。
  Future<void> Function(String reason)? onRepeatedFailure;

  void noteSuccess() {
    _consecutive = 0;
  }

  /// 记录一次链路失败；返回 true 表示本次触发了自愈。
  bool noteFailure(String reason) {
    _consecutive += 1;
    final n = _consecutive;
    final cooling = DateTime.now().difference(_lastKick) < cooldown;
    final fire = (n >= threshold) && !cooling;
    if (fire) {
      _consecutive = 0;
      _lastKick = DateTime.now();
    }
    if (fire) {
      unawaited(onRepeatedFailure?.call(reason));
    }
    return fire;
  }

  /// 手动改地址 / 重置配置后清零计数。
  void reset() {
    _consecutive = 0;
  }
}
