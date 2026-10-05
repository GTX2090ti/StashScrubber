import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'net_health.dart';
import 'net_log.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

/// Stash GraphQL 客户端：ApiKey 走请求头（对齐 ArkTS 版 StashAPI）。
class StashApi {
  StashApi(this.baseUrl, this.apiKey);

  final String baseUrl;
  final String apiKey;

  Uri get _endpoint => Uri.parse('${normalizeBase(baseUrl)}/graphql');

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (apiKey.isNotEmpty) 'ApiKey': apiKey,
      };

  /// 查询（query）失败自动重试一次；变更（mutation）不重试（对齐 iOS GraphQLClient）。
  /// 链路层失败（超时 / 连接错误）时先重建会话丢弃吊死连接，再重试一次。
  Future<dynamic> query(String q,
      [Map<String, dynamic>? vars, Duration? timeout]) async {
    final isMutation = q.trimLeft().toLowerCase().startsWith('mutation');
    try {
      final r = await _queryOnce(q, vars, timeout);
      NetHealth.instance.noteSuccess();
      return r;
    } catch (e) {
      if (isConnectivity(e)) {
        final reason = _friendly(e);
        ApiSession.instance
            .reset('查询链路失败（$reason），重建会话丢弃吊死连接');
        if (!isMutation) {
          try {
            final r = await _queryOnce(q, vars, timeout);
            NetHealth.instance.noteSuccess();
            NetLog.instance.record(
                category: 'Network',
                level: 'WARN',
                title: '自动重试成功',
                message: '首次失败（$reason），重建会话后重试成功');
            return r;
          } catch (_) {}
        }
        // 连续链路失败累加：达到阈值触发自愈选路（内外网翻面）。
        NetHealth.instance.noteFailure(reason);
      }
      rethrow;
    }
  }

  String _friendly(Object e) {
    if (e is TimeoutException) return '超时';
    if (e is http.ClientException) return e.message;
    return '$e';
  }

  Future<dynamic> _queryOnce(String q,
      [Map<String, dynamic>? vars, Duration? timeout]) async {
    final body = jsonEncode({'query': q, 'variables': vars ?? const {}});
    final sw = Stopwatch()..start();
    final kind = q.trimLeft().toLowerCase().startsWith('mutation')
        ? 'mutation'
        : 'query';
    final firstLine = q.trim().split('\n').first.trim();
    final title = firstLine.length > 60 ? firstLine.substring(0, 60) : firstLine;
    http.Response resp;
    try {
      resp = await ApiSession.instance.client
          .post(_endpoint, headers: _headers, body: body)
          .timeout(timeout ?? const Duration(seconds: 10));
    } on TimeoutException {
      NetLog.instance.record(
          category: 'Network',
          level: 'ERROR',
          title: '$kind $title',
          message: '连接超时',
          method: 'POST',
          url: _endpoint.toString(),
          ms: sw.elapsedMilliseconds);
      throw ApiException('连接超时');
    } catch (e) {
      NetLog.instance.record(
          category: 'Network',
          level: 'ERROR',
          title: '$kind $title',
          message: '网络错误: $e',
          method: 'POST',
          url: _endpoint.toString(),
          ms: sw.elapsedMilliseconds);
      throw ApiException('网络错误: $e');
    }
    if (resp.statusCode != 200) {
      // 尽力带出服务端返回的具体错误信息（GraphQL errors / message / body 片段）。
      var detail = 'HTTP ${resp.statusCode}';
      try {
        final d = jsonDecode(resp.body);
        final es = d?['errors'];
        if (es is List && es.isNotEmpty) {
          final msgs = es
              .map((e) => e is Map ? e['message']?.toString() : null)
              .whereType<String>()
              .where((m) => m.isNotEmpty)
              .toList();
          if (msgs.isNotEmpty) detail += '：${msgs.join('；')}';
        } else if (d is Map && d['message'] != null) {
          detail += '：${d['message']}';
        }
      } catch (_) {
        if (resp.body.isNotEmpty) {
          detail +=
              '：${resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body}';
        }
      }
      NetLog.instance.record(
          category: 'Network',
          level: 'ERROR',
          title: '$kind $title',
          message: detail,
          method: 'POST',
          url: _endpoint.toString(),
          status: resp.statusCode,
          ms: sw.elapsedMilliseconds);
      throw ApiException(detail);
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(resp.body);
    } catch (_) {
      NetLog.instance.record(
          category: 'Network',
          level: 'ERROR',
          title: '$kind $title',
          message: '响应解析失败',
          method: 'POST',
          url: _endpoint.toString(),
          status: resp.statusCode,
          ms: sw.elapsedMilliseconds);
      throw ApiException('响应解析失败');
    }
    final errors = decoded?['errors'];
    if (errors is List && errors.isNotEmpty) {
      NetLog.instance.record(
          category: 'Network',
          level: 'ERROR',
          title: '$kind $title',
          message: errors.first?['message']?.toString() ?? 'GraphQL 错误',
          method: 'POST',
          url: _endpoint.toString(),
          status: resp.statusCode,
          ms: sw.elapsedMilliseconds);
      throw ApiException(errors.first?['message']?.toString() ?? 'GraphQL 错误');
    }
    NetLog.instance.record(
        category: 'Network',
        title: '$kind $title',
        method: 'POST',
        url: _endpoint.toString(),
        status: resp.statusCode,
        ms: sw.elapsedMilliseconds);
    return decoded?['data'];
  }

  Future<String> version() async {
    final data = await query('query { version { version } }');
    return data?['version']?['version']?.toString() ?? '';
  }

  // ---------- Stash 任务（扫描） ----------

  /// 触发扫描：发现并入库新短片与图片。
  /// [paths] 为 null 时扫描全部已配置路径；指定则只扫描该文件夹。
  /// 可选生成选项仅在开启时传入（GraphQL 变量声明同步动态生成），
  /// 避免旧版 Stash schema 缺字段时因"变量未使用/字段不存在"报 422。
  Future<void> metadataScan({
    List<String>? paths,
    bool useFileMetadata = false,
    bool rescan = false,
    bool scanGenerateCovers = false,
    bool scanGeneratePreviews = false,
    bool scanGenerateImagePreviews = false,
    bool scanGeneratePhashes = false,
    bool scanGenerateSpritePreviews = false,
  }) async {
    final vars = <String, dynamic>{};
    final varDecls = <String>[];
    final inputFields = <String>[];
    void addBool(String name, bool v) {
      if (v) {
        vars[name] = true;
        varDecls.add('\$$name: Boolean');
        inputFields.add('$name: \$$name');
      }
    }

    if (paths != null) {
      vars['paths'] = paths;
      varDecls.add('\$paths: [String!]');
      inputFields.add('paths: \$paths');
    }
    addBool('useFileMetadata', useFileMetadata);
    addBool('rescan', rescan);
    addBool('scanGenerateCovers', scanGenerateCovers);
    addBool('scanGeneratePreviews', scanGeneratePreviews);
    addBool('scanGenerateImagePreviews', scanGenerateImagePreviews);
    addBool('scanGeneratePhashes', scanGeneratePhashes);
    addBool('scanGenerateSpritePreviews', scanGenerateSpritePreviews);

    final head = varDecls.isEmpty ? 'mutation' : 'mutation(${varDecls.join(', ')})';
    final gq = '$head { metadataScan(input: { ${inputFields.join(', ')} }) }';
    await query(gq, vars, const Duration(seconds: 15));
  }

  /// 生成任务：按类别为已有媒体生成封面/预览/图片预览/Phash/精灵图/交互热图。
  /// mutation 名按服务器实际字段传入（0.31+ 为 metadataGenerate，旧版为 generate）。
  /// [sceneIDs] 非空时只对指定短片生成（0.31+ GenerateMetadataInput.sceneIDs）。
  Future<void> generate({
    required String mutation,
    required bool covers,
    required bool sprites,
    required bool previews,
    required bool imagePreviews,
    required bool phashes,
    bool interactiveHeatmaps = false,
    bool clipPreviews = false,
    bool overwrite = false,
    List<String> sceneIDs = const [],
  }) async {
    final hasIds = sceneIDs.isNotEmpty;
    final input = 'covers: \$covers, sprites: \$sprites, '
        'previews: \$previews, imagePreviews: \$imagePreviews, '
        'phashes: \$phashes, interactiveHeatmaps: \$interactiveHeatmaps, '
        'clipPreviews: \$clipPreviews, overwrite: \$overwrite'
        '${hasIds ? ', sceneIDs: \$sceneIDs' : ''}';
    final gq = hasIds
        ? 'mutation(\$covers: Boolean!, \$sprites: Boolean!, '
            '\$previews: Boolean!, \$imagePreviews: Boolean!, '
            '\$phashes: Boolean!, \$interactiveHeatmaps: Boolean, '
            '\$clipPreviews: Boolean, \$overwrite: Boolean, '
            '\$sceneIDs: [ID!]!) '
            '{ $mutation(input: { $input }) }'
        : 'mutation(\$covers: Boolean!, \$sprites: Boolean!, '
            '\$previews: Boolean!, \$imagePreviews: Boolean!, '
            '\$phashes: Boolean!, \$interactiveHeatmaps: Boolean, '
            '\$clipPreviews: Boolean, \$overwrite: Boolean) '
            '{ $mutation(input: { $input }) }';
    final vars = <String, dynamic>{
      'covers': covers,
      'sprites': sprites,
      'previews': previews,
      'imagePreviews': imagePreviews,
      'phashes': phashes,
      'interactiveHeatmaps': interactiveHeatmaps,
      'clipPreviews': clipPreviews,
      'overwrite': overwrite,
      if (hasIds) 'sceneIDs': sceneIDs,
    };
    await query(gq, vars, const Duration(seconds: 15));
  }

  /// 给指定短片生成封面（0.31+ 按 sceneIDs 定向生成；mutation 名动态探测）。
  Future<void> generateCovers(
    List<String> sceneIds, {
    bool overwrite = false,
    String? mutation,
  }) async {
    final m = mutation ?? (await _detectGenerateMutation());
    await generate(
      mutation: m,
      covers: true,
      sprites: false,
      previews: false,
      imagePreviews: false,
      phashes: false,
      overwrite: overwrite,
      sceneIDs: sceneIds,
    );
  }

  /// 探测当前服务端可用的生成 mutation 名（metadataGenerate 优先，兼容旧版 generate）。
  Future<String> _detectGenerateMutation() async {
    final ms = await mutationFields();
    if (ms.contains('metadataGenerate')) return 'metadataGenerate';
    if (ms.contains('generate')) return 'generate';
    return 'metadataGenerate';
  }

  /// 清理：删除孤儿媒体文件等（dryRun=true 只预览不实际删除）。
  /// mutation 名按服务器实际字段传入（0.31+ 为 metadataClean / metadataCleanGenerated，
  /// 旧版为 clean）。CleanInput.dryRun 为非空字段（Boolean!）。
  Future<void> clean({required String mutation, bool dryRun = false}) async {
    await query(
      'mutation(\$dryRun: Boolean!) { $mutation(input: { dryRun: \$dryRun }) }',
      {'dryRun': dryRun},
      const Duration(seconds: 15),
    );
  }

  /// 自动打标签。mutation 名按服务器实际字段传入
  /// （0.31+ 为 metadataAutoTag，旧版为 autoTag）。
  Future<void> autoTag({
    required String mutation,
    bool performers = true,
    bool studios = true,
    bool tags = true,
  }) async {
    await query(
      'mutation(\$performers: Boolean, \$studios: Boolean, \$tags: Boolean) '
      '{ $mutation(input: { performers: \$performers, studios: \$studios, '
      'tags: \$tags }) }',
      {'performers': performers, 'studios': studios, 'tags': tags},
      const Duration(seconds: 15),
    );
  }

  /// Stash 的媒体库路径（可扫描范围）：
  /// 1. 0.31+：configuration.general.stashes（配置的媒体库路径，含用户添加的二级目录）；
  /// 2. 0.19~0.30：configuration.general.libraryFolders；
  /// 3. 更老：configuration.general.libraryPath；
  /// 4. 兜底：findFolders（所有含媒体文件的文件夹）。
  Future<List<String>> libraryPaths() async {
    try {
      final d = await query(
          'query { configuration { general { stashes { path } } } }');
      final list = d?['configuration']?['general']?['stashes'];
      if (list is List && list.isNotEmpty) {
        final paths = list
            .map((e) => e is Map ? e['path']?.toString() : null)
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        if (paths.isNotEmpty) return paths;
      }
    } catch (_) {}
    try {
      final d = await query(
          'query { configuration { general { libraryFolders { path } } } }');
      final list = d?['configuration']?['general']?['libraryFolders'];
      if (list is List) {
        final paths = list
            .map((e) => e is Map ? e['path']?.toString() : null)
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .toList();
        if (paths.isNotEmpty) return paths;
      }
    } catch (_) {}
    try {
      final d = await query(
          'query { configuration { general { libraryPath } } }');
      final p = d?['configuration']?['general']?['libraryPath']?.toString();
      if (p != null && p.isNotEmpty) return [p];
    } catch (_) {}
    try {
      final d = await query('query { findFolders { folders { path } } }');
      final list = d?['findFolders']?['folders'];
      if (list is List && list.isNotEmpty) {
        final paths = list
            .map((e) => e is Map ? e['path']?.toString() : null)
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        if (paths.isNotEmpty) return paths;
      }
    } catch (_) {}
    return [];
  }

  /// 探测 Mutation 类型支持哪些字段（GraphQL introspection）。
  /// 0.31+ 将 generate/autoTag/clean 改名为 metadataGenerate/metadataAutoTag/metadataClean。
  Future<Set<String>> mutationFields() async {
    try {
      final d = await query(
          'query { __type(name: "Mutation") { fields { name } } }');
      final fs = d?['__type']?['fields'];
      if (fs is List) {
        return fs
            .map((e) => e is Map ? e['name']?.toString() ?? '' : '')
            .where((s) => s.isNotEmpty)
            .toSet();
      }
    } catch (_) {}
    return {};
  }

  /// 探测某个 Input 类型支持哪些字段（用于按版本显示扫描选项等）。
  Future<Set<String>> inputFields(String typeName) async {
    try {
      final d = await query(
          'query { __type(name: "$typeName") { inputFields { name } } }');
      final fs = d?['__type']?['inputFields'];
      if (fs is List) {
        return fs
            .map((e) => e is Map ? e['name']?.toString() ?? '' : '')
            .where((s) => s.isNotEmpty)
            .toSet();
      }
    } catch (_) {}
    return {};
  }

  /// 当前任务队列（Stash 后台任务：id/状态/描述/子任务）。
  Future<List<dynamic>> jobQueue() async {
    final data = await query(
        'query { jobQueue { id status description subTasks } }',
        null,
        const Duration(seconds: 15));
    final list = data?['jobQueue'];
    return list is List ? list : [];
  }

  // ---------- 分类全量（编辑表单用） ----------

  Future<List<Studio>> allStudios() async {
    final d = await query('query { allStudios { id name } }');
    return Studio.listFrom(d?['allStudios']);
  }

  Future<List<Performer>> allPerformers() async {
    final d = await query('query { allPerformers { id name } }');
    return Performer.listFrom(d?['allPerformers']);
  }

  Future<List<Tag>> allTags() async {
    final d = await query('query { allTags { id name } }');
    return Tag.listFrom(d?['allTags']);
  }

  /// 按名称精确查找标签（0.31.1 不允许重名，新建前先查重）。
  Future<List<Tag>> findTagsByName(String name) async {
    final q = '''
      query FindTagByName(\$n: String!) {
        findTags(tag_filter: { name: { value: \$n, modifier: EQUALS } },
                 filter: { per_page: 5 }) {
          count tags { id name }
        }
      }''';
    try {
      final d = await query(q, {'n': name});
      return Tag.listFrom(d?['findTags']?['tags']);
    } catch (_) {
      return const [];
    }
  }

  /// 按关键词模糊查标签（搜索用）。
  Future<List<Tag>> findTagsByQ(String term, {int perPage = 50}) async {
    const q = '''
      query FindTags(\$filter: FindFilterType!) {
        findTags(filter: \$filter) { count tags { id name } }
      }''';
    try {
      final d = await query(q, {
        'filter': {'page': 1, 'per_page': perPage, 'q': term.trim()}
      });
      return Tag.listFrom(d?['findTags']?['tags']);
    } catch (_) {
      return const [];
    }
  }

  /// 按名称精确查找工作室（新建前先查重）。
  Future<List<Studio>> findStudiosByName(String name) async {
    final q = '''
      query FindStudioByName(\$n: String!) {
        findStudios(studio_filter: { name: { value: \$n, modifier: EQUALS } },
                    filter: { per_page: 5 }) {
          count studios { id name }
        }
      }''';
    try {
      final d = await query(q, {'n': name});
      return Studio.listFrom(d?['findStudios']?['studios']);
    } catch (_) {
      return const [];
    }
  }

  // ---------- 削刮源 ----------

  Future<List<Scraper>> scrapers(String typeName) async {
    const q = '''
      query ListScrapers(\$types: [ScrapeContentType!]!) {
        listScrapers(types: \$types) { id name scene { supported_scrapes } performer { supported_scrapes } }
      }''';
    final d = await query(q, {'types': [typeName]});
    final v = d?['listScrapers'];
    if (v is! List) return const [];
    return v.map((e) => Scraper.fromJson(e)).toList();
  }

  /// 服务端已配置的 Stash-box 端点（数组顺序即 stash_box_index）。
  Future<List<StashBoxInfo>> stashBoxes() async {
    const q = 'query { configuration { general { stashBoxes { name endpoint } } } }';
    final d = await query(q);
    final conf = d?['configuration'];
    final arr = conf?['general']?['stashBoxes'];
    if (arr is! List) return const [];
    return arr.map((e) => StashBoxInfo.fromJson(e)).toList();
  }

  // ---------- 短片查询 ----------

  static const _sceneCardFields = '''
      id title details date created_at rating100 o_counter organized
      urls studio { id name } performers { id name } tags { id name }
      paths { screenshot webp } files { path height width duration }
      captions { language_code caption_type }
  ''';

  Future<FindResult<Scene>> findScenes({
    int page = 1,
    int perPage = 120,
    String? q,
    String sort = 'date',
    String direction = 'DESC',
    Map<String, dynamic>? sceneFilter,
  }) async {
    const gq = '''
      query FindScenes(\$filter: FindFilterType!, \$sf: SceneFilterType) {
        findScenes(filter: \$filter, scene_filter: \$sf) {
          count
          scenes { $_sceneCardFields }
        }
      }''';
    final filter = <String, dynamic>{
      'page': page,
      'per_page': perPage,
      'sort': sort,
      'direction': direction,
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
    };
    final vars = <String, dynamic>{'filter': filter};
    if (sceneFilter != null && sceneFilter.isNotEmpty) {
      vars['sf'] = sceneFilter;
    }
    final d = await query(gq, vars);
    final fs = d?['findScenes'];
    if (fs == null) return const FindResult<Scene>(count: 0, items: []);
    return FindResult<Scene>(
      count: fs['count'] is int ? fs['count'] as int : 0,
      items: Scene.listFrom(fs['scenes']),
    );
  }

  /// 关键词合并搜索：标题/路径/详情（q）+ 演员名 + 标签名 + 工作室名。
  /// 各路由取全量匹配后按 sort 在客户端排序并本地分页。
  Future<FindResult<Scene>> searchScenes({
    required String term,
    required int page,
    required int perPage,
    String sort = 'date',
    String direction = 'DESC',
    Map<String, dynamic>? sceneFilter,
  }) async {
    final map = <String, Scene>{};

    Future<void> collect(String? q, Map<String, dynamic>? sf) async {
      var p = 1;
      for (;;) {
        final r = await findScenes(
          page: p,
          perPage: 1000,
          q: q,
          sort: sort,
          direction: direction,
          sceneFilter: sf,
        );
        for (final s in r.items) {
          map[s.id] = s;
        }
        if (r.items.isEmpty || p * 1000 >= r.count || p >= 8) break;
        p++;
      }
    }

    // 1) 标题/路径/详情
    await collect(term, sceneFilter);

    // 2) 演员名
    try {
      final ps = await findPerformers(page: 1, perPage: 50, q: term);
      if (ps.items.isNotEmpty) {
        await collect(null, {
          ...?sceneFilter,
          'performers': {
            'value': ps.items.map((e) => e.id).toList(),
            'modifier': 'INCLUDES',
          },
        });
      }
    } catch (_) {}

    // 3) 标签名
    try {
      final ts = await findTagsByQ(term);
      if (ts.isNotEmpty) {
        await collect(null, {
          ...?sceneFilter,
          'tags': {
            'value': ts.map((e) => e.id).toList(),
            'modifier': 'INCLUDES',
          },
        });
      }
    } catch (_) {}

    // 4) 工作室名
    try {
      final ss = await findStudios(page: 1, perPage: 50, q: term);
      if (ss.items.isNotEmpty) {
        await collect(null, {
          ...?sceneFilter,
          'studio_id': ss.items.map((e) => e.id).toList(),
        });
      }
    } catch (_) {}

    final all = map.values.toList();
    _sortScenesClient(all, sort, direction);
    final total = all.length;
    final start = (page - 1) * perPage;
    final items = start >= total
        ? <Scene>[]
        : all.sublist(start, (start + perPage) > total ? total : start + perPage);
    return FindResult<Scene>(count: total, items: items);
  }

  /// 客户端排序（合并搜索用），空日期/空值永远排最后。
  static void _sortScenesClient(List<Scene> list, String sort, String direction) {
    int cmp(Scene a, Scene b) {
      switch (sort) {
        case 'title':
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case 'rating':
          return a.rating100.compareTo(b.rating100);
        case 'o_counter':
          return a.oCounter.compareTo(b.oCounter);
        case 'duration':
          return a.duration.compareTo(b.duration);
        case 'created_at':
          return a.createdAt.compareTo(b.createdAt);
        case 'performer_count':
          return a.performers.length.compareTo(b.performers.length);
        case 'tag_count':
          return a.tags.length.compareTo(b.tags.length);
        case 'studio':
          return (a.studio?.name ?? '').compareTo(b.studio?.name ?? '');
        default:
          return a.date.compareTo(b.date);
      }
    }

    list.sort((a, b) {
      final av = _sortKey(a, sort);
      final bv = _sortKey(b, sort);
      final aEmpty = av.isEmpty;
      final bEmpty = bv.isEmpty;
      if (aEmpty && bEmpty) return 0;
      if (aEmpty) return 1; // 空值永远排最后
      if (bEmpty) return -1;
      final c = cmp(a, b);
      return direction == 'DESC' ? -c : c;
    });
  }

  static String _sortKey(Scene s, String sort) {
    switch (sort) {
      case 'title':
        return s.title;
      case 'rating':
        return s.rating100.toString();
      case 'o_counter':
        return s.oCounter.toString();
      case 'duration':
        return s.duration.toString();
      case 'created_at':
        return s.createdAt;
      case 'performer_count':
        return s.performers.length.toString();
      case 'tag_count':
        return s.tags.length.toString();
      case 'studio':
        return s.studio?.name ?? '';
      default:
        return s.date;
    }
  }

  Future<Scene?> findScene(String id) async {
    const q = '''
      query FindScene(\$id: ID!) {
        findScene(id: \$id) {
          id title details date rating100 o_counter organized
          urls studio { id name }
          performers { id name image_path birthdate details }
          tags { id name }
          paths { screenshot webp }
          files { path }
        }
      }''';
    final d = await query(q, {'id': id});
    final s = d?['findScene'];
    return s == null ? null : Scene.fromJson(s);
  }

  Future<Performer?> findPerformer(String id) async {
    const q = '''
      query FindPerformer(\$id: ID!) {
        findPerformer(id: \$id) {
          id name disambiguation alias_list image_path birthdate country ethnicity
          measurements career_length details rating100
          tags { id name }
        }
      }''';
    final d = await query(q, {'id': id});
    final p = d?['findPerformer'];
    return p == null ? null : Performer.fromJson(p);
  }

  Future<Studio?> findStudio(String id) async {
    const q = '''
      query FindStudio(\$id: ID!) {
        findStudio(id: \$id) { id name image_path rating100 scene_count }
      }''';
    final d = await query(q, {'id': id});
    final s = d?['findStudio'];
    return s == null ? null : Studio.fromJson(s);
  }

  Future<Tag?> findTag(String id) async {
    const q = 'query FindTag(\$id: ID!) { findTag(id: \$id) { id name } }';
    final d = await query(q, {'id': id});
    final t = d?['findTag'];
    return t == null ? null : Tag.fromJson(t);
  }

  Future<FindResult<Performer>> findPerformers({
    int page = 1,
    int perPage = 120,
    String? q,
  }) async {
    const gq = '''
      query FindPerformers(\$filter: FindFilterType!) {
        findPerformers(filter: \$filter) {
          count
          performers { id name disambiguation image_path birthdate country rating100 scene_count tags { id name } }
        }
      }''';
    final filter = <String, dynamic>{
      'page': page,
      'per_page': perPage,
      'sort': 'name',
      'direction': 'ASC',
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
    };
    final d = await query(gq, {'filter': filter});
    final fp = d?['findPerformers'];
    if (fp == null) return const FindResult<Performer>(count: 0, items: []);
    return FindResult<Performer>(
      count: fp['count'] is int ? fp['count'] as int : 0,
      items: Performer.listFrom(fp['performers']),
    );
  }

  Future<FindResult<Studio>> findStudios({
    int page = 1,
    int perPage = 120,
    String? q,
  }) async {
    const gq = '''
      query FindStudios(\$filter: FindFilterType!) {
        findStudios(filter: \$filter) {
          count
          studios { id name image_path rating100 scene_count }
        }
      }''';
    final filter = <String, dynamic>{
      'page': page,
      'per_page': perPage,
      'sort': 'name',
      'direction': 'ASC',
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
    };
    final d = await query(gq, {'filter': filter});
    final fp = d?['findStudios'];
    if (fp == null) return const FindResult<Studio>(count: 0, items: []);
    return FindResult<Studio>(
      count: fp['count'] is int ? fp['count'] as int : 0,
      items: Studio.listFrom(fp['studios']),
    );
  }

  // ---------- 削刮 ----------

  static const _long = Duration(seconds: 180);

  static const _sceneSelection = '''
    title details date duration urls image
    studio { stored_id name urls image }
    performers { stored_id name disambiguation birthdate details country ethnicity measurements urls tags { stored_id name } }
    tags { stored_id name }''';

  static const _performerSelection = '''
    stored_id name disambiguation aliases birthdate gender country ethnicity hair_color eye_color height weight
    measurements fake_tits tattoos piercings career_start career_end details urls images tags { stored_id name }''';

  Future<List<ScrapedScene>> scrapeSceneFragment(
      Map<String, dynamic> source, String sceneId) async {
    const gq = '''
      query ScrapeSingleScene(\$source: ScraperSourceInput!, \$input: ScrapeSingleSceneInput!) {
        scrapeSingleScene(source: \$source, input: \$input) { $_sceneSelection }
      }''';
    final d = await query(gq, {
      'source': source,
      'input': {'scene_id': sceneId},
    }, _long);
    final list = d?['scrapeSingleScene'];
    if (list is! List) return const [];
    return list
        .where((e) => e != null)
        .map((e) => ScrapedScene.fromJson(e))
        .toList();
  }

  Future<List<ScrapedScene>> scrapeSceneByName(
      Map<String, dynamic> source, String term) async {
    const gq = '''
      query ScrapeSingleScene(\$source: ScraperSourceInput!, \$input: ScrapeSingleSceneInput!) {
        scrapeSingleScene(source: \$source, input: \$input) { $_sceneSelection }
      }''';
    final d = await query(gq, {
      'source': source,
      'input': {'query': term},
    }, _long);
    final list = d?['scrapeSingleScene'];
    if (list is! List) return const [];
    return list
        .where((e) => e != null)
        .map((e) => ScrapedScene.fromJson(e))
        .toList();
  }

  Future<List<ScrapedScene>> scrapeSceneUrl(String url) async {
    const gq = '''
      query ScrapeSceneURL(\$url: String!) {
        scrapeSceneURL(url: \$url) { $_sceneSelection }
      }''';
    final d = await query(gq, {'url': url}, _long);
    final s = d?['scrapeSceneURL'];
    return s == null ? const [] : [ScrapedScene.fromJson(s)];
  }

  Future<List<ScrapedPerformer>> scrapePerformerFragment(
      Map<String, dynamic> source, String performerId) async {
    const gq = '''
      query ScrapeSinglePerformer(\$source: ScraperSourceInput!, \$input: ScrapeSinglePerformerInput!) {
        scrapeSinglePerformer(source: \$source, input: \$input) { $_performerSelection }
      }''';
    final d = await query(gq, {
      'source': source,
      'input': {'performer_id': performerId},
    }, _long);
    final list = d?['scrapeSinglePerformer'];
    if (list is! List) return const [];
    return list
        .where((e) => e != null)
        .map((e) => ScrapedPerformer.fromJson(e))
        .toList();
  }

  Future<List<ScrapedPerformer>> scrapePerformerByName(
      Map<String, dynamic> source, String term) async {
    const gq = '''
      query ScrapeSinglePerformer(\$source: ScraperSourceInput!, \$input: ScrapeSinglePerformerInput!) {
        scrapeSinglePerformer(source: \$source, input: \$input) { $_performerSelection }
      }''';
    final d = await query(gq, {
      'source': source,
      'input': {'query': term},
    }, _long);
    final list = d?['scrapeSinglePerformer'];
    if (list is! List) return const [];
    return list
        .where((e) => e != null)
        .map((e) => ScrapedPerformer.fromJson(e))
        .toList();
  }

  Future<List<ScrapedPerformer>> scrapePerformerUrl(String url) async {
    const gq = '''
      query ScrapePerformerURL(\$url: String!) {
        scrapePerformerURL(url: \$url) { $_performerSelection }
      }''';
    final d = await query(gq, {'url': url}, _long);
    final p = d?['scrapePerformerURL'];
    return p == null ? const [] : [ScrapedPerformer.fromJson(p)];
  }

  Future<ScrapedStudio?> scrapeStudioByName(
      Map<String, dynamic> source, String term) async {
    const gq = '''
      query ScrapeSingleStudio(\$source: ScraperSourceInput!, \$input: ScrapeSingleStudioInput!) {
        scrapeSingleStudio(source: \$source, input: \$input) { stored_id name urls image }
      }''';
    final d = await query(gq, {
      'source': source,
      'input': {'query': term},
    }, _long);
    final s = d?['scrapeSingleStudio'];
    return s == null ? null : ScrapedStudio.fromJson(s);
  }

  // ---------- 元数据写回 ----------

  Future<void> updateScene(Map<String, dynamic> input) async {
    const m =
        'mutation UpdateScene(\$input: SceneUpdateInput!) { sceneUpdate(input: \$input) { id } }';
    final d = await query(m, {'input': input});
    if (d?['sceneUpdate'] == null) throw ApiException('sceneUpdate 失败');
  }

  Future<void> updatePerformer(Map<String, dynamic> input) async {
    const m =
        'mutation UpdatePerformer(\$input: PerformerUpdateInput!) { performerUpdate(input: \$input) { id } }';
    final d = await query(m, {'input': input});
    if (d?['performerUpdate'] == null) throw ApiException('performerUpdate 失败');
  }

  Future<void> updateStudio(Map<String, dynamic> input) async {
    const m =
        'mutation UpdateStudio(\$input: StudioUpdateInput!) { studioUpdate(input: \$input) { id } }';
    final d = await query(m, {'input': input});
    if (d?['studioUpdate'] == null) throw ApiException('studioUpdate 失败');
  }

  Future<String> createPerformer(Map<String, dynamic> input) async {
    const m =
        'mutation CreatePerformer(\$input: PerformerCreateInput!) { performerCreate(input: \$input) { id } }';
    final d = await query(m, {'input': input});
    final v = d?['performerCreate'];
    if (v == null || v['id'] == null) throw ApiException('performerCreate 失败');
    return v['id'].toString();
  }

  Future<String> createTag(String name) async {
    final fields = await mutationFields();
    final m = fields.contains('tagCreate') ? 'tagCreate' : 'createTag';
    final q =
        'mutation CreateTag(\$input: TagCreateInput!) { $m(input: \$input) { id } }';
    final d = await query(q, {'input': {'name': name}});
    final v = d?[m];
    if (v == null || v['id'] == null) throw ApiException('$m 失败');
    return v['id'].toString();
  }

  Future<String> createStudio(String name, [Map<String, dynamic>? extra]) async {
    final fields = await mutationFields();
    final m = fields.contains('studioCreate') ? 'studioCreate' : 'createStudio';
    final q =
        'mutation CreateStudio(\$input: StudioCreateInput!) { $m(input: \$input) { id } }';
    final d = await query(q, {
      'input': {'name': name, ...?extra}
    });
    final v = d?[m];
    if (v == null || v['id'] == null) throw ApiException('$m 失败');
    return v['id'].toString();
  }

  /// 删除演员（0.31+ mutation 名为 performerDestroy，兼容旧版 destroyPerformer）。
  Future<void> destroyPerformer(String id) async {
    final fields = await mutationFields();
    final m =
        fields.contains('performerDestroy') ? 'performerDestroy' : 'destroyPerformer';
    final q =
        'mutation DestroyPerformer(\$input: PerformerDestroyInput!) { $m(input: \$input) }';
    await query(q, {'input': {'id': id}});
  }

  /// 删除工作室（0.31+ mutation 名为 studioDestroy，兼容旧版 destroyStudio）。
  Future<void> destroyStudio(String id) async {
    final fields = await mutationFields();
    final m =
        fields.contains('studioDestroy') ? 'studioDestroy' : 'destroyStudio';
    final q =
        'mutation DestroyStudio(\$input: StudioDestroyInput!) { $m(input: \$input) }';
    await query(q, {'input': {'id': id}});
  }

  /// 短片合并（服务端原生 sceneMerge）。
  Future<void> mergeScenes(
      List<String> sourceIds, String destinationId) async {
    const m =
        'mutation SceneMerge(\$input: SceneMergeInput!) { sceneMerge(input: \$input) { id } }';
    final d = await query(m, {
      'input': {
        'source': sourceIds,
        'destination': destinationId,
        'play_history': true,
        'o_history': true,
      }
    });
    if (d?['sceneMerge'] == null) throw ApiException('sceneMerge 失败');
  }

  // ---------- 削刮结果写回 ----------

  /// 下载图片转 base64 data URI；失败返回空串（不影响文字字段）。
  Future<String> fetchImageAsBase64(String ref) async {
    if (ref.startsWith('data:')) return ref;
    if (!ref.startsWith('http://') && !ref.startsWith('https://')) return '';
    try {
      final resp = await ApiSession.instance.client
          .get(Uri.parse(ref))
          .timeout(const Duration(seconds: 25));
      if (resp.statusCode < 200 || resp.statusCode > 299) return '';
      final bytes = resp.bodyBytes;
      if (bytes.isEmpty) return '';
      return 'data:image/jpeg;base64,${base64Encode(bytes)}';
    } catch (_) {
      return '';
    }
  }

  Future<String> _resolvePerformerId(ScrapedPerformer p) async {
    if (p.storedId.isNotEmpty) return p.storedId;
    if (p.name.isEmpty) throw ApiException('削刮演员无名称');
    return createPerformer({'name': p.name});
  }

  Future<String> _resolveTagId(ScrapedTag t) async {
    if (t.storedId.isNotEmpty) return t.storedId;
    if (t.name.isEmpty) throw ApiException('削刮标签无名称');
    return createTag(t.name);
  }

  Future<String> _resolveStudioId(ScrapedStudio s) async {
    if (s.storedId.isNotEmpty) return s.storedId;
    if (s.name.isEmpty) throw ApiException('削刮工作室无名称');
    return createStudio(s.name);
  }

  /// 写回削刮结果：仅写非空字段；库内不存在自动创建；可选图片。
  Future<int> applyScrapedScene(
      ScrapedScene s, String targetId, bool includeImage) async {
    final input = <String, dynamic>{'id': targetId};
    var changed = 0;
    if (s.title.isNotEmpty) {
      input['title'] = s.title;
      changed++;
    }
    if (s.details.isNotEmpty) {
      input['details'] = s.details;
      changed++;
    }
    if (s.date.isNotEmpty) {
      input['date'] = s.date;
      changed++;
    }
    if (s.studio != null) {
      input['studio_id'] = await _resolveStudioId(s.studio!);
      changed++;
    }
    if (s.performers.isNotEmpty) {
      final ids = <String>[];
      for (final p in s.performers) {
        ids.add(await _resolvePerformerId(p));
      }
      if (ids.isNotEmpty) {
        input['performer_ids'] = ids;
        changed++;
      }
    }
    if (s.tags.isNotEmpty) {
      final ids = <String>[];
      for (final t in s.tags) {
        ids.add(await _resolveTagId(t));
      }
      if (ids.isNotEmpty) {
        input['tag_ids'] = ids;
        changed++;
      }
    }
    if (s.urls.isNotEmpty) {
      input['urls'] = s.urls;
      changed++;
    }
    if (includeImage && s.image.isNotEmpty) {
      final b64 = await fetchImageAsBase64(s.image);
      if (b64.isNotEmpty) {
        input['cover_image'] = b64;
        changed++;
      }
    }
    if (changed > 0) await updateScene(input);
    return changed;
  }

  /// 写回演员削刮结果（全部字段）。
  Future<int> applyScrapedPerformer(
      ScrapedPerformer p, String targetId, bool includeImage,
      {bool keepOriginalName = true}) async {
    final input = <String, dynamic>{'id': targetId};
    var changed = 0;
    void put(String key, String v) {
      if (v.isNotEmpty) {
        input[key] = v;
        changed++;
      }
    }

    // 默认保持原名：写回名字时用本地已有名字，不改名；
    // 仅当本地无名字（如新演员）时才用刮削结果的名字。
    var nameToWrite = p.name;
    if (keepOriginalName) {
      try {
        final local = await findPerformer(targetId);
        final localName = local?.name.trim() ?? '';
        if (localName.isNotEmpty) nameToWrite = localName;
      } catch (_) {}
    }
    put('name', nameToWrite);
    put('disambiguation', p.disambiguation);
    // 0.31.1 起别名字段为 alias_list（ScrapedPerformer.aliases 为逗号分隔）
    if (p.aliases.trim().isNotEmpty) {
      final list = p.aliases
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (list.isNotEmpty) {
        input['alias_list'] = list;
        changed++;
      }
    }
    put('birthdate', p.birthdate);
    put('gender', p.gender);
    put('country', p.country);
    put('ethnicity', p.ethnicity);
    put('hair_color', p.hairColor);
    put('eye_color', p.eyeColor);
    put('measurements', p.measurements);
    put('fake_tits', p.fakeTits);
    put('tattoos', p.tattoos);
    put('piercings', p.piercings);
    put('details', p.details);
    final h = int.tryParse(p.height);
    if (h != null && h > 0) {
      // 0.31.1 起字段名为 height_cm（旧版 height 已移除）
      input['height_cm'] = h;
      changed++;
    }
    final w = int.tryParse(p.weight);
    if (w != null && w > 0) {
      input['weight'] = w;
      changed++;
    }
    final careerParts = <String>[];
    if (p.careerStart.isNotEmpty) careerParts.add(p.careerStart);
    if (p.careerEnd.isNotEmpty) careerParts.add(p.careerEnd);
    final career = careerParts.join(' - ');
    if (career.isNotEmpty) {
      input['career_length'] = career;
      changed++;
    }
    if (p.urls.isNotEmpty) {
      input['urls'] = p.urls;
      changed++;
    }
    if (p.tags.isNotEmpty) {
      final ids = <String>[];
      for (final t in p.tags) {
        ids.add(await _resolveTagId(t));
      }
      if (ids.isNotEmpty) {
        input['tag_ids'] = ids;
        changed++;
      }
    }
    if (includeImage && p.images.isNotEmpty) {
      final b64 = await fetchImageAsBase64(p.images.first);
      if (b64.isNotEmpty) {
        input['image'] = b64;
        changed++;
      }
    }
    if (changed > 0) await updatePerformer(input);
    return changed;
  }

  Future<int> applyScrapedStudio(
      ScrapedStudio s, String targetId, bool includeImage) async {
    final input = <String, dynamic>{'id': targetId};
    var changed = 0;
    if (s.urls.isNotEmpty) {
      input['urls'] = s.urls;
      changed++;
    }
    if (includeImage && s.image.isNotEmpty) {
      final b64 = await fetchImageAsBase64(s.image);
      if (b64.isNotEmpty) {
        input['image'] = b64;
        changed++;
      }
    }
    if (changed > 0) await updateStudio(input);
    return changed;
  }

  // ---------- 图片鉴权 ----------

  /// Flutter Image.network 支持自定义头，直接带 ApiKey，无需 URL 参数。
  Map<String, String> get imageHeaders =>
      apiKey.isEmpty ? const {} : {'ApiKey': apiKey};

  String imageUrl(String raw) => rewriteImage(raw, baseUrl);

  String coverUrl(Scene s) => imageUrl(s.paths.raw);

  void close() {}
}

/// 供 TypedData 导入使用（base64Encode 需要 Uint8List）。
typedef Bytes = Uint8List;
