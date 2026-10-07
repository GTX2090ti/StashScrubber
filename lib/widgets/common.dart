import 'dart:async';
import 'dart:ui' show ImageFilter, TileMode;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'zh_toolbar.dart';

import '../api/stash_api.dart';
import '../settings/app_settings.dart';

/// 全局 API 客户端：跟随当前档案 / 生效地址重建。
StashApi buildApi() =>
    StashApi(AppSettings.instance.baseUrl, AppSettings.instance.apiKey);

/// 日期输入格式化：只保留数字并自动按 YYYY-MM-DD 插入连字符，
/// 用户无需手动输入 "-"，输入 20261003 即显示 2026-10-03。
class DateDashInputFormatter extends TextInputFormatter {
  const DateDashInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(selection: TextSelection.collapsed(offset: 0));
    }
    final limited = digits.length > 8 ? digits.substring(0, 8) : digits;
    final buf = StringBuffer();
    for (var i = 0; i < limited.length; i++) {
      if (i == 4 || i == 6) buf.write('-');
      buf.write(limited[i]);
    }
    final text = buf.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// 通用多选弹窗（编辑页演员/标签等使用）：半屏列表 + 搜索框 + 完成按钮。
/// options 为 (id, 显示名) 列表；返回用户确认后的选中 id 集合（取消返回 null）。
Future<Set<String>?> showMultiSelectSheet(
  BuildContext context, {
  required String title,
  required List<(String, String)> options,
  required Set<String> selected,
}) {
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        _SelectSheet(title: title, options: options, multi: true, selected: selected),
  );
}

/// 通用单选弹窗（编辑页工作室等使用）：半屏列表 + 搜索框，点击选项即返回。
/// 返回选中的 id（取消返回 null）。
Future<String?> showSingleSelectSheet(
  BuildContext context, {
  required String title,
  required List<(String, String)> options,
  String? selectedId,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SelectSheet(
        title: title, options: options, multi: false, selectedId: selectedId),
  );
}

class _SelectSheet extends StatefulWidget {
  const _SelectSheet({
    required this.title,
    required this.options,
    required this.multi,
    this.selected,
    this.selectedId,
  });

  final String title;
  final List<(String, String)> options;
  final bool multi;
  final Set<String>? selected;
  final String? selectedId;

  @override
  State<_SelectSheet> createState() => _SelectSheetState();
}

class _SelectSheetState extends State<_SelectSheet> {
  final _searchCtrl = TextEditingController();
  String _q = '';
  late final Set<String> _sel = Set.from(widget.selected ?? {});

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<(String, String)> get _filtered {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return widget.options;
    return [
      for (final o in widget.options)
        if (o.$2.toLowerCase().contains(q)) o
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filtered;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
          child: Row(children: [
            Expanded(
              child: Text(widget.title, style: theme.textTheme.titleMedium),
            ),
            if (widget.multi)
              TextButton(
                onPressed: () => Navigator.pop(context, _sel),
                child: const Text('完成'),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          child: TextField(
            controller: _searchCtrl,
            contextMenuBuilder: zhContextMenuBuilder,
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              hintText: '搜索…',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              suffixIcon: _q.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空',
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _q = '');
                      },
                    ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text('无匹配项', style: TextStyle(fontSize: 12)))
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final (id, label) = filtered[i];
                    if (widget.multi) {
                      return CheckboxListTile(
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        value: _sel.contains(id),
                        title: Text(label),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _sel.add(id);
                          } else {
                            _sel.remove(id);
                          }
                        }),
                      );
                    }
                    final active = id == widget.selectedId;
                    return ListTile(
                      dense: true,
                      title: Text(label),
                      trailing: active
                          ? Icon(Icons.check,
                              size: 18, color: theme.colorScheme.primary)
                          : null,
                      onTap: () => Navigator.pop(context, id),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

/// 带鉴权头的网络图（Stash 图片端点强制鉴权）。
/// 与 ArkTS 版不同：Flutter 原生支持请求头，无需 URL 参数改写。
/// 安全模式开启时自动打码（模糊），长按缩略图可临时查看 3 秒。
class AuthImage extends StatefulWidget {
  const AuthImage({
    super.key,
    required this.rawPath,
    this.fit = BoxFit.cover,
    this.radius = 10,
    this.width,
    this.height,
    this.fallbackIcon = Icons.movie_outlined,
  });

  final String rawPath;
  final BoxFit fit;
  final double radius;
  final double? width;
  final double? height;
  final IconData fallbackIcon;

  @override
  State<AuthImage> createState() => _AuthImageState();
}

class _AuthImageState extends State<AuthImage> {
  Timer? _revealTimer;
  bool _revealed = false;

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  void _reveal() {
    setState(() => _revealed = true);
    _revealTimer?.cancel();
    _revealTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _revealed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final api = buildApi();
    final url = api.imageUrl(widget.rawPath);
    final placeholder = Container(
      color: theme.colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child:
          Icon(widget.fallbackIcon, size: 20, color: theme.colorScheme.outline),
    );
    Widget child;
    if (url.isEmpty) {
      child = placeholder;
    } else {
      child = Image.network(
        url,
        headers: api.imageHeaders,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        errorBuilder: (_, __, ___) => placeholder,
        loadingBuilder: (ctx, child, progress) =>
            progress == null ? child : placeholder,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: ListenableBuilder(
          listenable: AppSettings.instance,
          builder: (context, _) {
            final safe = AppSettings.instance.safeMode;
            if (!safe || _revealed) return child;
            return GestureDetector(
              onLongPress: _reveal,
              child: Stack(
                children: [
                  child,
                  Positioned.fill(
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(
                          sigmaX: 14, sigmaY: 14, tileMode: TileMode.clamp),
                      child: child,
                    ),
                  ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.lock_outline,
                          size: 12, color: Colors.white70),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 短片卡片：海报 + 标题 + 发行时间 + 收藏/评分角标（SenPlayer 风格）。
class SceneCard extends StatelessWidget {
  const SceneCard({
    super.key,
    required this.title,
    required this.rawCover,
    this.date = '',
    this.rating100 = 0,
    this.organized = false,
    this.onTap,
    this.trailing,
    this.aspect = 2 / 3,
  });

  final String title;
  final String rawCover;
  final String date;
  final int rating100;
  final bool organized;
  final VoidCallback? onTap;
  final Widget? trailing;
  final double aspect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: aspect,
                child: AuthImage(rawPath: rawCover, radius: 10),
              ),
              if (organized)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.star,
                        size: 14, color: Color(0xFFFF9F0A)),
                  ),
                ),
              if (rating100 > 0)
                Positioned(
                  left: 4,
                  top: 4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3D7EFF),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${(rating100 / 20).round()}★',
                      style: const TextStyle(
                          fontSize: 10, color: Colors.white, height: 1.4),
                    ),
                  ),
                ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 5),
          Expanded(
            child: Text(
              title.isEmpty ? '（无标题）' : title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(height: 1.2),
            ),
          ),
          if (date.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              date,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10,
                height: 1.2,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 单列大卡片（对齐 Stash web 打包 app 场景列表样式）：
/// 16:9 封面 + 分辨率/时长角标 + 标题 + 作者/标签/星级 + 已整理标记。
class SceneListCard extends StatelessWidget {
  const SceneListCard({
    super.key,
    required this.title,
    required this.rawCover,
    this.date = '',
    this.rating100 = 0,
    this.organized = false,
    this.duration = 0,
    this.height = 0,
    this.artist = '',
    this.tagCount = 0,
    this.hasCaption = false,
    this.onTap,
    this.trailing,
  });

  final String title;
  final String rawCover;
  final String date;
  final int rating100;
  final bool organized;
  final int duration;
  final int height;
  final String artist;
  final int tagCount;
  final bool hasCaption;
  final VoidCallback? onTap;
  final Widget? trailing;

  String get _durationText {
    if (duration <= 0) return '';
    final h = duration ~/ 3600;
    final m = (duration % 3600) ~/ 60;
    final s = duration % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String get _resText {
    if (height >= 2000) return '4K';
    if (height >= 1000) return '1080P';
    if (height >= 700) return '720P';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final res = _resText;
    final dur = _durationText;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: AuthImage(rawPath: rawCover, radius: 0),
                ),
                if (res.isNotEmpty)
                  Positioned(
                    left: 6,
                    top: 6,
                    child: _badge(res,
                        bg: const Color(0xFF3D7EFF)),
                  ),
                if (dur.isNotEmpty)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: _badge(dur, bg: Colors.black.withValues(alpha: 0.62)),
                  ),
                if (hasCaption)
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.subtitles,
                                size: 12, color: Colors.white),
                            SizedBox(width: 2),
                            Text('字幕',
                                style: TextStyle(
                                    fontSize: 10, color: Colors.white)),
                          ]),
                    ),
                  ),
                if (organized)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child:
                          const Icon(Icons.star, size: 14, color: Color(0xFFFF9F0A)),
                    ),
                  ),
                if (trailing != null) trailing!,
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.isEmpty ? '（无标题）' : title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600, height: 1.25),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          artist.isNotEmpty
                              ? artist
                              : (date.isNotEmpty ? date : ''),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                      if (rating100 > 0) ...[
                        const Icon(Icons.star,
                            size: 12, color: Color(0xFFFF9F0A)),
                        const SizedBox(width: 2),
                        Text((rating100 / 20).toStringAsFixed(1),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontSize: 11)),
                      ],
                      if (tagCount > 0) ...[
                        const SizedBox(width: 8),
                        Text('#$tagCount',
                            style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                color: theme.colorScheme.primary)),
                      ],
                      if (date.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(date,
                            style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, {required Color bg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, color: Colors.white, height: 1.4),
      ),
    );
  }
}

/// 分页栏（ArkTS 版顶部/底部各一条）。
class PageBar extends StatelessWidget {
  const PageBar({
    super.key,
    required this.page,
    required this.totalPages,
    required this.total,
    required this.loading,
    required this.onPrev,
    required this.onNext,
    this.showTotal = true,
  });

  final int page;
  final int totalPages;
  final int total;
  final bool loading;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final bool showTotal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            height: 32,
            child: OutlinedButton(
              onPressed: (page > 1 && !loading) ? onPrev : null,
              child: const Text('上一页', style: TextStyle(fontSize: 12)),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                showTotal
                    ? '第 $page / $totalPages 页（共 $total）'
                    : '第 $page / $totalPages 页',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          SizedBox(
            height: 32,
            child: OutlinedButton(
              onPressed: (page < totalPages && !loading) ? onNext : null,
              child: const Text('下一页', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 可点击 chip（演员=强调色，标签=星标色）。
class TapChip extends StatelessWidget {
  const TapChip({
    super.key,
    required this.label,
    required this.onTap,
    this.kind = ChipKind.tag,
  });

  final String label;
  final VoidCallback onTap;
  final ChipKind kind;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final fg = kind == ChipKind.performer ? accent : const Color(0xFFFF9F0A);
    final bg = kind == ChipKind.performer
        ? accent.withValues(alpha: 0.14)
        : const Color(0xFFFF9F0A).withValues(alpha: 0.14);
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(label, style: TextStyle(fontSize: 13, color: fg)),
        ),
      ),
    );
  }
}

enum ChipKind { performer, tag }

/// 区块标题。
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      );
}

/// 「标签 / 值」信息行。
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.labelWidth = 84});
  final String label;
  final String value;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(label,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// 通用加载 / 空态 / 错误态。
class StatusView extends StatelessWidget {
  const StatusView({
    super.key,
    required this.loading,
    required this.empty,
    required this.onRetry,
    this.error = '',
  });

  final bool loading;
  final String empty;
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading) ...[
            const SizedBox(
                width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(height: 10),
            Text('加载中…', style: theme.textTheme.bodySmall),
          ] else ...[
            Text(empty,
                textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ],
      ),
    );
  }
}

void showToast(BuildContext context, String msg, {bool error = false}) {
  final theme = Theme.of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg,
          style: TextStyle(
              color: error ? const Color(0xFFE5533D) : null)),
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 1800),
    ),
  );
}
