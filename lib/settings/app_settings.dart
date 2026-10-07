import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

enum Appearance { system, light, dark }

enum AddrSlot { lan, wan }

extension AddrSlotX on AddrSlot {
  String get label => this == AddrSlot.lan ? '内网' : '外网';
}

/// 服务器档案：内网/外网双地址 + 独立 ApiKey。
class Profile {
  String name;
  String lanUrl;
  String wanUrl;
  String apiKey;

  Profile({
    this.name = '',
    this.lanUrl = '',
    this.wanUrl = '',
    this.apiKey = '',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'lanUrl': lanUrl,
        'wanUrl': wanUrl,
        'apiKey': apiKey,
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        name: (j['name'] ?? '').toString(),
        lanUrl: (j['lanUrl'] ?? '').toString(),
        wanUrl: (j['wanUrl'] ?? '').toString(),
        apiKey: (j['apiKey'] ?? '').toString(),
      );

  Profile copy() => Profile(
        name: name,
        lanUrl: lanUrl,
        wanUrl: wanUrl,
        apiKey: apiKey,
      );

  /// 旧版单地址键迁移：把 base_url 当作内网地址。
  static Profile fromFlat(String baseUrl, String apiKey) => Profile(
        name: 'Stash',
        lanUrl: baseUrl,
        wanUrl: '',
        apiKey: apiKey,
      );
}

/// 全局设置：多档案 + 双槽选路 + 外观三模式。
/// 存储异常时降级为内存态（storageAvailable=false），不阻塞启动。
class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  static const _kProfiles = 'profiles_v1';
  static const _kCurrent = 'current_profile';
  static const _kBaseUrl = 'base_url';
  static const _kApiKey = 'api_key';
  static const _kAppearance = 'appearance';
  static const _kSlot = 'active_slot';
  static const _kManualLock = 'manual_lock';
  static const _kReason = 'switch_reason';
  static const _kSafeMode = 'safe_mode';

  List<Profile> profiles = [];
  String currentProfileName = '';
  Appearance appearance = Appearance.system;

  AddrSlot activeSlot = AddrSlot.lan;
  bool manualLock = false;
  String lastSwitchReason = '';
  int lastLatencyMs = -1;
  int lanLatencyMs = -1;
  int wanLatencyMs = -1;

  /// 安全模式（Stash NSFW Toggle）：开启后缩略图打码，长按临时查看。
  bool _safeMode = false;
  bool get safeMode => _safeMode;

  bool storageAvailable = true;
  bool _loaded = false;
  bool _probing = false;

  bool get loaded => _loaded;
  bool get isProbing => _probing;

  Profile? get currentProfile {
    for (final p in profiles) {
      if (p.name == currentProfileName) return p;
    }
    return profiles.isEmpty ? null : profiles.first;
  }

  bool get hasProfile {
    final p = currentProfile;
    if (p == null) return false;
    // API Key 可空（对齐 iOS：Stash 未开启认证时无需 Key）
    return normalizeBase(p.lanUrl).isNotEmpty || normalizeBase(p.wanUrl).isNotEmpty;
  }

  // ---------- 基址 ----------

  String slotUrl(AddrSlot slot) {
    final p = currentProfile;
    if (p == null) return '';
    final raw = slot == AddrSlot.lan ? p.lanUrl : p.wanUrl;
    return normalizeBase(raw);
  }

  String get lanUrl => slotUrl(AddrSlot.lan);
  String get wanUrl => slotUrl(AddrSlot.wan);

  /// 生效基址：当前槽位优先，该侧未配置时回退另一侧。
  String get baseUrl {
    final cur = slotUrl(activeSlot);
    if (cur.isNotEmpty) return cur;
    final other = activeSlot == AddrSlot.lan ? AddrSlot.wan : AddrSlot.lan;
    final fb = slotUrl(other);
    if (fb.isNotEmpty) {
      activeSlot = other;
      manualLock = false;
    }
    return fb;
  }

  String get apiKey => currentProfile?.apiKey ?? '';

  String get profileName => currentProfile?.name ?? '';

  // ---------- 持久化 ----------

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      profiles = _decodeProfiles(p.getString(_kProfiles));
      if (profiles.isEmpty) {
        // 迁移旧版单地址
        final legacyBase = p.getString(_kBaseUrl) ?? '';
        final legacyKey = p.getString(_kApiKey) ?? '';
        if (legacyBase.isNotEmpty || legacyKey.isNotEmpty) {
          profiles = [Profile.fromFlat(legacyBase, legacyKey)];
          currentProfileName = profiles.first.name;
        }
      }
      final cur = p.getString(_kCurrent) ?? '';
      if (cur.isNotEmpty && profiles.any((e) => e.name == cur)) {
        currentProfileName = cur;
      } else if (profiles.isNotEmpty) {
        currentProfileName = profiles.first.name;
      }
      final ap = p.getString(_kAppearance) ?? 'system';
      appearance = Appearance.values.firstWhere(
        (a) => a.name == ap,
        orElse: () => Appearance.system,
      );
      final slot = p.getString(_kSlot) ?? 'lan';
      activeSlot = slot == 'wan' ? AddrSlot.wan : AddrSlot.lan;
      manualLock = p.getBool(_kManualLock) ?? false;
      lastSwitchReason = p.getString(_kReason) ?? '';
      _safeMode = p.getBool(_kSafeMode) ?? false;
      storageAvailable = true;
    } catch (e) {
      storageAvailable = false;
      profiles = [];
    }
    _loaded = true;
    notifyListeners();
  }

  static List<Profile> _decodeProfiles(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final arr = jsonDecode(raw);
      if (arr is! List) return [];
      return arr
          .whereType<Map>()
          .map((e) => Profile.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _flush() async {
    notifyListeners();
    if (!storageAvailable) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          _kProfiles, jsonEncode(profiles.map((e) => e.toJson()).toList()));
      await p.setString(_kCurrent, currentProfileName);
      await p.setString(_kAppearance, appearance.name);
      await p.setString(_kSlot, activeSlot.name);
      await p.setBool(_kManualLock, manualLock);
      await p.setString(_kReason, lastSwitchReason);
      await p.setBool(_kSafeMode, _safeMode);
    } catch (e) {
      storageAvailable = false;
      notifyListeners();
    }
  }

  // ---------- 档案管理 ----------

  Future<void> upsertProfile(Profile p) async {
    final idx = profiles.indexWhere((e) => e.name == p.name);
    if (idx >= 0) {
      profiles[idx] = p;
    } else {
      profiles.add(p);
    }
    currentProfileName = p.name;
    await _flush();
  }

  Future<void> removeProfile(String name) async {
    profiles.removeWhere((e) => e.name == name);
    if (currentProfileName == name) {
      currentProfileName = profiles.isEmpty ? '' : profiles.first.name;
    }
    await _flush();
  }

  Future<void> switchTo(String name) async {
    if (!profiles.any((e) => e.name == name)) return;
    currentProfileName = name;
    lastLatencyMs = -1;
    await _flush();
    unawaited(autoSelect('切换档案'));
  }

  /// 兼容旧调用：直接写当前档案的单一内网地址 + ApiKey。
  Future<void> saveFlat({String? baseUrl, String? apiKey}) async {
    final p = currentProfile ?? Profile();
    if (baseUrl != null) p.lanUrl = normalizeBase(baseUrl);
    if (apiKey != null) p.apiKey = apiKey;
    if (p.name.isEmpty) p.name = 'Stash';
    await upsertProfile(p);
  }

  Future<void> setAppearance(Appearance mode) async {
    appearance = mode;
    await _flush();
  }

  /// 切换安全模式（缩略图打码）。
  Future<void> setSafeMode(bool v) async {
    _safeMode = v;
    await _flush();
  }

  // ---------- 选路 ----------

  Future<void> setSlot(AddrSlot slot, bool manual) async {
    if (slotUrl(slot).isEmpty) {
      lastSwitchReason = '切换到${slot.label}失败：该侧地址未配置';
      notifyListeners();
      return;
    }
    activeSlot = slot;
    manualLock = manual;
    lastLatencyMs = -1;
    lastSwitchReason = manual ? '已手动锁定${slot.label}地址' : '已切换到${slot.label}地址';
    await _flush();
  }

  Future<void> restoreAuto() async {
    manualLock = false;
    lastSwitchReason = '恢复自动选择（优先内网）';
    await _flush();
    await autoSelect('解除锁定');
  }

  /// 实测某地址可达性与延迟；可达返回延迟 ms，不可达返回 -2，未配置返回 -1。
  static Future<int> probeLatency(String base, String apiKey) async {
    if (base.isEmpty) return -1;
    final uri = Uri.parse('$base/graphql');
    final client = http.Client();
    final sw = Stopwatch()..start();
    try {
      final resp = await client
          .post(uri,
              headers: {
                'Content-Type': 'application/json',
                if (apiKey.isNotEmpty) 'ApiKey': apiKey,
              },
              body: jsonEncode({
                'query': 'query { version { version } }',
                'variables': <String, dynamic>{}
              }))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return -2;
      return sw.elapsedMilliseconds;
    } catch (_) {
      return -2;
    } finally {
      client.close();
    }
  }

  Future<void> probeBoth() async {
    if (_probing) return;
    _probing = true;
    notifyListeners();
    final key = apiKey;
    lanLatencyMs = await probeLatency(lanUrl, key);
    wanLatencyMs = await probeLatency(wanUrl, key);
    lastLatencyMs = activeSlot == AddrSlot.lan ? lanLatencyMs : wanLatencyMs;
    if (lanLatencyMs < 0 && wanLatencyMs < 0) {
      lastSwitchReason = '内网与外网地址均不可达（测速）';
    } else if (lastSwitchReason.isEmpty) {
      lastSwitchReason = '测速完成';
    }
    _probing = false;
    await _flush();
  }

  Future<void> autoSelect(String reason) async {
    if (_probing) return;
    final lan = lanUrl;
    final wan = wanUrl;
    if (lan.isEmpty && wan.isEmpty) return;
    if (lan.isNotEmpty && wan.isEmpty) {
      if (activeSlot != AddrSlot.lan) {
        activeSlot = AddrSlot.lan;
        lastSwitchReason = '仅配置了内网地址';
        await _flush();
      }
      return;
    }
    if (lan.isEmpty && wan.isNotEmpty) {
      if (activeSlot != AddrSlot.wan) {
        activeSlot = AddrSlot.wan;
        lastSwitchReason = '仅配置了外网地址';
        await _flush();
      }
      return;
    }
    _probing = true;
    notifyListeners();
    try {
      if (manualLock) {
        lastSwitchReason = '已手动锁定${activeSlot.label}地址（$reason）';
        notifyListeners();
        return;
      }
      final t1 = await probeLatency(lan, apiKey);
      lanLatencyMs = t1;
      if (t1 >= 0) {
        lastLatencyMs = t1;
        if (activeSlot != AddrSlot.lan) {
          activeSlot = AddrSlot.lan;
          lastSwitchReason = '内网实测可达，自动切换（${t1}ms）';
          await _flush();
        } else {
          lastSwitchReason = '内网实测可达（${t1}ms，$reason）';
          notifyListeners();
        }
        return;
      }
      final t2 = await probeLatency(wan, apiKey);
      wanLatencyMs = t2;
      if (t2 >= 0) {
        lastLatencyMs = t2;
        if (activeSlot != AddrSlot.wan) {
          activeSlot = AddrSlot.wan;
          lastSwitchReason = '内网不可达，自动切换外网（${t2}ms）';
          await _flush();
        } else {
          lastSwitchReason = '外网实测可达（${t2}ms）';
          notifyListeners();
        }
        return;
      }
      lastSwitchReason = '内网与外网地址均不可达';
      await _flush();
    } finally {
      _probing = false;
      notifyListeners();
    }
  }

  void notifyChanged() => notifyListeners();
}
