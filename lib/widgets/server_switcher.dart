import 'package:flutter/material.dart';

import '../settings/app_settings.dart';

/// 服务器快速切换菜单（对齐 iOS ServerSwitcherMenu）：
/// 档案切换 + 内网/外网槽位 + 手动锁定 + 重新测速。
class ServerSwitcherMenu extends StatelessWidget {
  const ServerSwitcherMenu({super.key});

  Future<void> _handle(String key) async {
    final cfg = AppSettings.instance;
    if (key.startsWith('profile:')) {
      await cfg.switchTo(key.substring('profile:'.length));
    } else if (key == 'slot:lan') {
      await cfg.setSlot(AddrSlot.lan, true);
    } else if (key == 'slot:wan') {
      await cfg.setSlot(AddrSlot.wan, true);
    } else if (key == 'lock') {
      await cfg.setSlot(cfg.activeSlot, true);
    } else if (key == 'unlock') {
      await cfg.restoreAuto();
    } else if (key == 'probe') {
      await cfg.probeBoth();
      await cfg.autoSelect('菜单重新测速');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = AppSettings.instance;
    return PopupMenuButton<String>(
      tooltip: '服务器',
      icon: const Icon(Icons.dns_outlined),
      onSelected: _handle,
      itemBuilder: (context) {
        final items = <PopupMenuEntry<String>>[];
        for (final p in cfg.profiles) {
          items.add(CheckedPopupMenuItem(
            value: 'profile:${p.name}',
            checked: p.name == cfg.currentProfileName,
            child: Text(p.name,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ));
        }
        items.add(const PopupMenuDivider());
        items.add(CheckedPopupMenuItem(
          value: 'slot:lan',
          checked: cfg.activeSlot == AddrSlot.lan,
          child: Text(
              '内网${cfg.lanUrl.isNotEmpty ? '（${cfg.lanLatencyMs >= 0 ? "${cfg.lanLatencyMs}ms" : "未测"}）' : ' · 未配置'}'),
        ));
        items.add(CheckedPopupMenuItem(
          value: 'slot:wan',
          checked: cfg.activeSlot == AddrSlot.wan,
          child: Text(
              '外网${cfg.wanUrl.isNotEmpty ? '（${cfg.wanLatencyMs >= 0 ? "${cfg.wanLatencyMs}ms" : "未测"}）' : ' · 未配置'}'),
        ));
        items.add(PopupMenuDivider());
        items.add(CheckedPopupMenuItem(
          value: cfg.manualLock ? 'unlock' : 'lock',
          checked: cfg.manualLock,
          child: const Text('手动锁定当前地址'),
        ));
        items.add(const PopupMenuItem(value: 'probe', child: Text('重新测速')));
        if (cfg.lastSwitchReason.isNotEmpty) {
          items.add(PopupMenuItem(
            enabled: false,
            child: Text(cfg.lastSwitchReason,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
          ));
        }
        return items;
      },
    );
  }
}
