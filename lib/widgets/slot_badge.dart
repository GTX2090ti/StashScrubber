import 'package:flutter/material.dart';

import '../settings/app_settings.dart';

/// 服务器槽位/延迟状态条：显示「档案名 · 内网/外网 · 延迟」，
/// 点击弹出完整服务器菜单（档案切换 + 内网/外网槽位 + 手动锁定 + 重新测速）。
/// 供 AppBar 标题行使用。
class SlotBadge extends StatelessWidget {
  const SlotBadge({super.key});

  Future<void> _handle(String v) async {
    final cfg = AppSettings.instance;
    if (v.startsWith('profile:')) {
      await cfg.switchTo(v.substring('profile:'.length));
    } else if (v == 'auto') {
      await cfg.restoreAuto();
    } else if (v == 'probe') {
      await cfg.probeBoth();
      await cfg.autoSelect('菜单重新测速');
    } else if (v == 'lan' || v == 'wan') {
      await cfg.setSlot(v == 'lan' ? AddrSlot.lan : AddrSlot.wan, true);
    } else if (v == 'lock') {
      await cfg.setSlot(cfg.activeSlot, true);
    } else if (v == 'unlock') {
      await cfg.restoreAuto();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final cfg = AppSettings.instance;
        final name = cfg.profileName.isEmpty ? 'Stash' : cfg.profileName;
        final latency =
            cfg.lastLatencyMs >= 0 ? ' · ${cfg.lastLatencyMs}ms' : '';
        return PopupMenuButton<String>(
          padding: EdgeInsets.zero,
          tooltip: '服务器',
          onSelected: _handle,
          itemBuilder: (_) {
            String lat(int v) {
              if (v >= 0) return ' · ${v}ms';
              if (v == -2) return ' · 不可达';
              return '';
            }

            final items = <PopupMenuEntry<String>>[];
            // 档案切换
            for (final p in cfg.profiles) {
              items.add(CheckedPopupMenuItem(
                value: 'profile:${p.name}',
                checked: p.name == cfg.currentProfileName,
                child: Text(p.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ));
            }
            items.add(const PopupMenuDivider());
            // 内网/外网槽位
            for (final slot in AddrSlot.values) {
              final url = cfg.slotUrl(slot);
              var label = '${slot.label}地址';
              if (url.isEmpty) {
                label += '（未配置）';
              } else {
                if (cfg.activeSlot == slot) label = '✓ $label';
                label += lat(slot == AddrSlot.lan
                    ? cfg.lanLatencyMs
                    : cfg.wanLatencyMs);
              }
              items.add(PopupMenuItem(value: slot.name, child: Text(label)));
            }
            items.add(const PopupMenuDivider());
            items.add(CheckedPopupMenuItem(
              value: cfg.manualLock ? 'unlock' : 'lock',
              checked: cfg.manualLock,
              child: const Text('手动锁定当前地址'),
            ));
            items.add(const PopupMenuItem(
                value: 'probe', child: Text('重新测速')));
            return items;
          },
          child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.diamond_outlined,
                    size: 11,
                    color: cfg.activeSlot == AddrSlot.lan
                        ? const Color(0xFF35C77B)
                        : const Color(0xFFFF9F0A),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '$name · ${cfg.activeSlot.label}'
                      '${cfg.manualLock ? "（锁定）" : ""}$latency',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 15),
                ],
              ),
            ),
          );
      },
    );
  }
}
