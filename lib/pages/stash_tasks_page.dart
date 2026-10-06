import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/common.dart';
import '../widgets/zh_toolbar.dart';

/// Stash 后台任务：扫描 / 生成 / 清理 / 自动打标签 + 实时任务列表。
class StashTasksPage extends StatefulWidget {
  const StashTasksPage({super.key});

  @override
  State<StashTasksPage> createState() => _StashTasksPageState();
}

class _StashTasksPageState extends State<StashTasksPage> {
  List<dynamic> _queue = [];
  bool _busy = false;
  String? _error;

  // 扫描选项
  bool _scanUseFileMetadata = false;
  bool _scanCovers = false;
  bool _scanPreviews = false;
  bool _scanImagePreviews = false;
  bool _scanPhashes = false;
  bool _scanSprites = false;
  bool _submitting = false;

  // 扫描路径：空集合 = 全部文件夹；勾选则只扫所选路径（可多选）
  List<String> _libraryPaths = [];
  final Set<String> _scanPaths = {};
  String? _pathsError;
  bool _scanRescan = false;

  // 生成选项
  bool _genOverwrite = false;
  bool _genCovers = true;
  bool _genPreviews = true;
  bool _genImagePreviews = true;
  bool _genPhashes = false;
  bool _genSprites = false;
  bool _genHeatmaps = false;

  // 清理
  bool _cleanDryRun = true;

  // 自动打标签
  bool _tagPerformers = true;
  bool _tagStudios = true;
  bool _tagTags = true;

  Timer? _timer;

  // Stash 实际支持的 mutation 集合（introspection 探测）。
  // 0.31+ 将 generate/autoTag/clean 改名为 metadataGenerate/metadataAutoTag/metadataClean。
  Set<String> _mutations = {};
  Set<String> _scanInputFields = {};

  /// 从候选名中选第一个服务器支持的；探测失败（空集合）时用第一个候选。
  String _pick(List<String> candidates) {
    for (final c in candidates) {
      if (_mutations.contains(c)) return c;
    }
    return candidates.first;
  }

  /// 服务器是否支持给定候选名之一（空集合=未探测，默认支持）。
  bool _canUse(List<String> candidates) =>
      _mutations.isEmpty || candidates.any(_mutations.contains);

  /// 是否有 Job 任务系统（0.19+）；探测到 mutation 但完全没有任务类字段才判定为无
  bool get _supportsJobs =>
      _mutations.isEmpty ||
      _mutations.contains('metadataGenerate') ||
      _mutations.contains('generate') ||
      _mutations.contains('metadataAutoTag') ||
      _mutations.contains('autoTag');

  @override
  void initState() {
    super.initState();
    _refresh();
    _loadPaths();
    _loadMutations();
    // 每 5 秒自动刷新任务列表，实时显示后台任务进度。
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  Future<void> _loadMutations() async {
    try {
      final m = await buildApi().mutationFields();
      final s = await buildApi().inputFields('ScanMetadataInput');
      if (mounted) {
        setState(() {
          _mutations = m;
          _scanInputFields = s;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadPaths() async {
    try {
      final paths = await buildApi().libraryPaths();
      if (mounted) {
        setState(() {
          _libraryPaths = paths;
          _pathsError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _pathsError = '$e');
    }
  }

  /// 路径短名：取最后两段（如 /data/PT/SET/CSPL → …/SET/CSPL）。
  String _pathShort(String p) {
    final parts = p
        .replaceAll('\\', '/')
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.length <= 2) return p;
    return '…/${parts.sublist(parts.length - 2).join('/')}';
  }

  /// 选择性扫描：底部面板多选文件夹。
  Future<void> _pickPaths() async {
    final sel = <String>{..._scanPaths};
    final ctrl = TextEditingController();
    String query = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final visible = query.isEmpty
            ? _libraryPaths
            : _libraryPaths
                .where((p) => p.toLowerCase().contains(query.toLowerCase()))
                .toList();
        return StatefulBuilder(builder: (ctx, setSheet) {
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.75),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text('选择扫描文件夹（可多选）',
                        style: Theme.of(ctx).textTheme.titleMedium),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: ctrl,
                      contextMenuBuilder: zhContextMenuBuilder,
                      decoration: InputDecoration(
                        labelText: '搜索文件夹',
                        prefixIcon: Icon(Icons.search, size: 18),
                        isDense: true,
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: '清空',
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  ctrl.clear();
                                  setSheet(() => query = '');
                                },
                              ),
                      ),
                      style: const TextStyle(fontSize: 13),
                      onChanged: (v) => setSheet(() => query = v.trim()),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Row(children: [
                      TextButton(
                        onPressed: () =>
                            setSheet(() => sel.addAll(_libraryPaths)),
                        child: const Text('全选', style: TextStyle(fontSize: 13)),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: () => setSheet(() => sel.clear()),
                        child: const Text('清空', style: TextStyle(fontSize: 13)),
                      ),
                      const Spacer(),
                      Text('已选 ${sel.length} 个',
                          style: Theme.of(ctx).textTheme.bodySmall),
                    ]),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: visible.length,
                      itemBuilder: (ctx, i) {
                        final p = visible[i];
                        final checked = sel.contains(p);
                        return CheckboxListTile(
                          dense: true,
                          value: checked,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(_pathShort(p),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text(p,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(ctx)
                                      .colorScheme
                                      .onSurfaceVariant)),
                          onChanged: (v) => setSheet(() {
                            if (v == true) {
                              sel.add(p);
                            } else {
                              sel.remove(p);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          _scanPaths
                            ..clear()
                            ..addAll(sel);
                          setState(() {});
                          Navigator.pop(ctx);
                        },
                        child: Text(sel.isEmpty ? '扫描全部文件夹' : '确定（${sel.length} 个）'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
    ctrl.dispose();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    if (!_supportsJobs) return; // 老版本无 Job 队列，跳过轮询
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final q = await buildApi().jobQueue();
      if (!mounted) return;
      setState(() => _queue = q);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<void> Function() fn, String okText) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await fn();
      messenger.showSnackBar(SnackBar(content: Text(okText)));
      await _refresh();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('提交失败：$e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _statusText(String s) {
    switch (s.toUpperCase()) {
      case 'READY':
        return '排队中';
      case 'RUNNING':
        return '执行中';
      case 'FINISHED':
        return '已完成';
      case 'FAILED':
        return '失败';
      case 'CANCELLED':
        return '已取消';
      default:
        return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Stash 任务')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _card(
            theme,
            icon: Icons.document_scanner_outlined,
            title: '扫描',
            subtitle: '扫描 Stash 配置的媒体目录，把新增/变更的短片与图片入库。',
            children: [
              if (_pathsError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('路径加载失败：$_pathsError',
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.error)),
                ),
              if (_libraryPaths.isNotEmpty) ...[
                const Text('扫描范围',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickPaths,
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: Text(
                        _scanPaths.isEmpty
                            ? '全部文件夹'
                            : '已选 ${_scanPaths.length} 个文件夹',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (_scanPaths.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: '清空选择',
                      icon: const Icon(Icons.clear_all, size: 18),
                      onPressed: () => setState(() => _scanPaths.clear()),
                    ),
                  ],
                ]),
                if (_scanPaths.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '未勾选任何文件夹时扫描全部；勾选后只扫描所选文件夹。',
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                const SizedBox(height: 6),
              ],
              if (_scanInputFields.isEmpty ||
                  _scanInputFields.contains('rescan'))
                _switch('强制重新扫描', _scanRescan, (v) => _scanRescan = v,
                    hint: '即使文件修改时间未变也重新处理，耗时更长'),
              if (_scanInputFields.isEmpty ||
                  _scanInputFields.contains('useFileMetadata'))
                _switch('使用文件元数据', _scanUseFileMetadata,
                    (v) => _scanUseFileMetadata = v,
                    hint: '从文件读取元数据（分辨率、时长等），更准确但较慢'),
              _switch('生成封面', _scanCovers, (v) => _scanCovers = v),
              _switch('生成视频预览', _scanPreviews, (v) => _scanPreviews = v),
              _switch('生成图片预览', _scanImagePreviews,
                  (v) => _scanImagePreviews = v),
              _switch('生成感知哈希', _scanPhashes, (v) => _scanPhashes = v,
                  hint: '用于以图搜图 / 重复检测'),
              _switch('生成预览缩略图', _scanSprites, (v) => _scanSprites = v),
              const SizedBox(height: 6),
              _submitButton(
                _scanPaths.isEmpty
                    ? '开始扫描（全部文件夹）'
                    : '开始扫描（${_scanPaths.length} 个文件夹）',
                Icons.document_scanner_outlined,
                () => _run(
                  () => buildApi().metadataScan(
                    paths: _scanPaths.isEmpty ? null : _scanPaths.toList(),
                    useFileMetadata: _scanUseFileMetadata,
                    rescan: _scanRescan,
                    scanGenerateCovers: _scanCovers,
                    scanGeneratePreviews: _scanPreviews,
                    scanGenerateImagePreviews: _scanImagePreviews,
                    scanGeneratePhashes: _scanPhashes,
                    scanGenerateSpritePreviews: _scanSprites,
                  ),
                  '扫描已提交，可在下方任务列表查看进度',
                ),
              ),
            ],
          ),
          if (_canUse(['metadataGenerate', 'generate']))
            _card(
              theme,
              icon: Icons.auto_awesome_motion_outlined,
              title: '生成',
              subtitle: '为已有媒体按类别生成封面/视频预览等（适合升级后补充素材）。',
            children: [
              _switch('覆盖已存在', _genOverwrite, (v) => _genOverwrite = v,
                  hint: '关闭时只补缺失的素材'),
              _switch('封面', _genCovers, (v) => _genCovers = v),
              _switch('视频预览', _genPreviews, (v) => _genPreviews = v),
              _switch('图片预览', _genImagePreviews, (v) => _genImagePreviews = v),
              _switch('感知哈希', _genPhashes, (v) => _genPhashes = v),
              _switch('预览缩略图', _genSprites, (v) => _genSprites = v),
              _switch('交互热图', _genHeatmaps, (v) => _genHeatmaps = v),
              const SizedBox(height: 6),
              _submitButton(
                '开始生成',
                Icons.auto_awesome_motion_outlined,
                () => _run(
                  () => buildApi().generate(
                    mutation: _pick(['metadataGenerate', 'generate']),
                    covers: _genCovers,
                    sprites: _genSprites,
                    previews: _genPreviews,
                    imagePreviews: _genImagePreviews,
                    phashes: _genPhashes,
                    interactiveHeatmaps: _genHeatmaps,
                    overwrite: _genOverwrite,
                  ),
                  '生成任务已提交',
                ),
              ),
            ],
          ),
          if (_canUse(['metadataClean', 'metadataCleanGenerated', 'clean']))
            _card(
              theme,
              icon: Icons.cleaning_services_outlined,
              title: '清理',
              subtitle: '删除孤儿媒体文件等垃圾数据，释放空间。',
            children: [
              _switch('仅预览（不实际删除）', _cleanDryRun, (v) => _cleanDryRun = v,
                  hint: '先以预览方式查看要清理的内容，确认后再关闭预览执行'),
              const SizedBox(height: 6),
              _submitButton(
                _cleanDryRun ? '预览清理' : '执行清理',
                Icons.cleaning_services_outlined,
                () => _run(
                  () => buildApi().clean(
                    mutation: _pick(
                        ['metadataClean', 'metadataCleanGenerated', 'clean']),
                    dryRun: _cleanDryRun,
                  ),
                  _cleanDryRun ? '清理预览已提交，查看任务详情' : '清理已提交',
                ),
              ),
            ],
          ),
          if (_canUse(['metadataAutoTag', 'autoTag']))
            _card(
              theme,
              icon: Icons.sell_outlined,
              title: '自动打标签',
              subtitle: '按路径规则把演员/工作室/标签自动关联到短片。',
            children: [
              _switch('演员', _tagPerformers, (v) => _tagPerformers = v),
              _switch('工作室', _tagStudios, (v) => _tagStudios = v),
              _switch('标签', _tagTags, (v) => _tagTags = v),
              const SizedBox(height: 6),
              _submitButton(
                '开始自动打标签',
                Icons.sell_outlined,
                () => _run(
                  () => buildApi().autoTag(
                    mutation: _pick(['metadataAutoTag', 'autoTag']),
                    performers: _tagPerformers,
                    studios: _tagStudios,
                    tags: _tagTags,
                  ),
                  '自动打标签已提交',
                ),
              ),
            ],
          ),
          if (!_supportsJobs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '当前 Stash 版本较旧（无 Job 任务系统），不显示任务列表；'
                '扫描提交后请到 Stash 网页端查看进度。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text('当前任务列表', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text('每 5 秒自动刷新',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                IconButton(
                  tooltip: '立即刷新',
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh, size: 20),
                  onPressed: _busy ? null : _refresh,
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('加载失败：$_error',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: const Color(0xFFE5533D))),
              ),
            if (_queue.isEmpty && !_busy && _error == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('暂无任务',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
              )
            else
              for (final job in _queue)
                Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      _statusIcon(job['status']?.toString() ?? ''),
                      size: 20,
                      color: _statusColor(job['status']?.toString() ?? ''),
                    ),
                    title: Text(
                      job['description']?.toString() ?? '任务',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      _statusText(job['status']?.toString() ?? ''),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    subtitle: _jobSubtitle(job, theme),
                  ),
                ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _jobSubtitle(dynamic job, ThemeData theme) {
    final st = job['subTasks'];
    if (st is List && st.isNotEmpty) {
      final parts = <String>[];
      for (final s in st) {
        if (s is Map) {
          final d = s['description'];
          if (d != null) parts.add(d.toString());
        } else if (s != null) {
          parts.add(s.toString());
        }
      }
      return Text(
        parts.join(' / '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      );
    }
    return Text(job['id']?.toString() ?? '',
        style: theme.textTheme.bodySmall);
  }

  Widget _card(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(title, style: theme.textTheme.titleMedium),
            ]),
            const SizedBox(height: 4),
            Text(subtitle,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged,
      {String? hint}) {    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: value,
      title: Text(label, style: const TextStyle(fontSize: 13)),
      subtitle: hint == null
          ? null
          : Text(hint,
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
      onChanged: onChanged,
    );
  }

  Widget _submitButton(String label, IconData icon, VoidCallback onPressed) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(36)),
      onPressed: _submitting ? null : onPressed,
      icon: _submitting
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(icon, size: 18),
      label: Text(_submitting ? '提交中…' : label),
    );
  }

  IconData _statusIcon(String s) {
    switch (s.toUpperCase()) {
      case 'RUNNING':
        return Icons.hourglass_top;
      case 'FINISHED':
        return Icons.check_circle_outline;
      case 'FAILED':
        return Icons.error_outline;
      case 'CANCELLED':
        return Icons.cancel_outlined;
      default:
        return Icons.schedule;
    }
  }

  Color? _statusColor(String s) {
    switch (s.toUpperCase()) {
      case 'FINISHED':
        return const Color(0xFF3F9E4D);
      case 'FAILED':
        return const Color(0xFFE5533D);
      case 'CANCELLED':
        return const Color(0xFF9E9E9E);
      default:
        return null;
    }
  }
}
