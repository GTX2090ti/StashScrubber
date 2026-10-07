import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../settings/app_settings.dart';

/// 面容解锁页：App 启动或回前台且开启了面容解锁时显示，
/// 通过 Face ID / Touch ID 验证后进入主界面。
class LockPage extends StatefulWidget {
  const LockPage({super.key, this.onUnlocked});

  /// 验证成功后的回调（用于上层复位锁屏状态标记）。
  final VoidCallback? onUnlocked;

  @override
  State<LockPage> createState() => _LockPageState();
}

class _LockPageState extends State<LockPage> {
  final LocalAuthentication _auth = LocalAuthentication();
  bool _checking = false;
  bool _hasBiometrics = false;
  String _status = '';
  bool _firstTry = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() {
      _checking = true;
      _status = '';
    });
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      _hasBiometrics = supported && canCheck;
    } catch (e) {
      _hasBiometrics = false;
      debugPrint('biometric check failed: $e');
    }
    setState(() => _checking = false);
    if (_hasBiometrics) {
      // 自动拉起系统验证，失败可点按钮重试
      await _authenticate();
    }
  }

  Future<void> _authenticate() async {
    setState(() {
      _checking = true;
      _status = '';
    });
    try {
      final ok = await _auth.authenticate(
        localizedReason: '验证您的身份以解锁 StashScrubber',
        options: const AuthenticationOptions(
          // 允许回退到系统密码，避免 Face ID 不可用时锁死
          stickyAuth: true,
        ),
      );
      if (!mounted) return;
      if (ok) {
        AppSettings.instance.markUnlocked();
        widget.onUnlocked?.call();
        // 关闭锁屏页，回到主界面
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _checking = false;
          _firstTry = false;
          _status = '验证失败，请重试';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _firstTry = false;
        _status = '无法使用生物识别：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF0E0F13) : const Color(0xFFF2F2F7);
    return Scaffold(
      backgroundColor: bg,
      body: PopScope(
        // 锁屏页不允许返回键/手势退出
        canPop: false,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 72,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'StashScrubber',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _hasBiometrics ? '使用面容或指纹解锁' : '此设备不支持生物识别',
                    style: TextStyle(
                      fontSize: 14,
                      color: dark ? const Color(0xFF9AA0A6) : const Color(0xFF6B6F76),
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (_checking)
                    const CircularProgressIndicator()
                  else ...[
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _hasBiometrics ? _authenticate : null,
                        icon: const Icon(Icons.face_retouching_natural),
                        label: Text(_hasBiometrics ? '面容 / 指纹解锁' : '无法验证'),
                      ),
                    ),
                    if (_status.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        _status,
                        style: TextStyle(
                          fontSize: 13,
                          color: dark ? const Color(0xFFE5533D) : const Color(0xFFC43D1F),
                        ),
                      ),
                    ],
                    if (!_hasBiometrics) ...[
                      const SizedBox(height: 12),
                      Text(
                        '如需解锁保护，请在设置中关闭面容解锁，或检查系统生物识别设置',
                        style: TextStyle(
                          fontSize: 12,
                          color: dark ? const Color(0xFF9AA0A6) : const Color(0xFF6B6F76),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
