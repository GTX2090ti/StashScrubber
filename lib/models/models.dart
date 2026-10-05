/// Stash GraphQL 数据模型（对齐 ArkTS 版 model/Models.ets）。
/// Dart 用 Map + dynamic 直接点访问，无 ArkTS JSON.parse 动态字典坑。
library;

String _s(dynamic v) => v == null ? '' : v.toString();
int _i(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);
List<String> _sl(dynamic v) {
  if (v is List) return v.map(_s).where((e) => e.isNotEmpty).toList();
  return const [];
}
List<Map<String, dynamic>> _ml(dynamic v) {
  if (v is List) {
    return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }
  return const [];
}

class Tag {
  final String id;
  final String name;

  const Tag({required this.id, required this.name});

  factory Tag.fromJson(dynamic j) =>
      Tag(id: _s(j?['id']), name: _s(j?['name']));

  static List<Tag> listFrom(dynamic v) =>
      _ml(v).map(Tag.fromJson).toList();
}

class Studio {
  final String id;
  final String name;
  final String imagePath;
  final int rating100;
  final int sceneCount;

  const Studio({
    required this.id,
    required this.name,
    this.imagePath = '',
    this.rating100 = 0,
    this.sceneCount = 0,
  });

  factory Studio.fromJson(dynamic j) => Studio(
        id: _s(j?['id']),
        name: _s(j?['name']),
        imagePath: _s(j?['image_path']),
        rating100: _i(j?['rating100']),
        sceneCount: _i(j?['scene_count']),
      );

  static List<Studio> listFrom(dynamic v) =>
      _ml(v).map(Studio.fromJson).toList();
}

class Performer {
  final String id;
  final String name;
  final String disambiguation;
  final String aliases;
  final String imagePath;
  final String birthdate;
  final String country;
  final String ethnicity;
  final String measurements;
  final String careerLength;
  final String details;
  final int rating100;
  final int sceneCount;
  final List<Tag> tags;

  const Performer({
    required this.id,
    required this.name,
    this.disambiguation = '',
    this.aliases = '',
    this.imagePath = '',
    this.birthdate = '',
    this.country = '',
    this.ethnicity = '',
    this.measurements = '',
    this.careerLength = '',
    this.details = '',
    this.rating100 = 0,
    this.sceneCount = 0,
    this.tags = const [],
  });

  factory Performer.fromJson(dynamic j) => Performer(
        id: _s(j?['id']),
        name: _s(j?['name']),
        disambiguation: _s(j?['disambiguation']),
        // 本地 Performer 的别名字段为 alias_list（String 数组）
        aliases: _sl(j?['alias_list']).join(', '),
        imagePath: _s(j?['image_path']),
        birthdate: _s(j?['birthdate']),
        country: _s(j?['country']),
        ethnicity: _s(j?['ethnicity']),
        measurements: _s(j?['measurements']),
        careerLength: _s(j?['career_length']),
        details: _s(j?['details']),
        rating100: _i(j?['rating100']),
        sceneCount: _i(j?['scene_count']),
        tags: Tag.listFrom(j?['tags']),
      );

  static List<Performer> listFrom(dynamic v) =>
      _ml(v).map(Performer.fromJson).toList();
}

class ScenePaths {
  final String screenshot;
  final String webp;
  final String stream;

  const ScenePaths({this.screenshot = '', this.webp = '', this.stream = ''});

  factory ScenePaths.fromJson(dynamic j) => ScenePaths(
        screenshot: _s(j?['screenshot']),
        webp: _s(j?['webp']),
        stream: _s(j?['stream']),
      );

  String get raw => screenshot.isNotEmpty ? screenshot : webp;
}

class SceneFile {
  final String path;
  final int height;
  final int width;
  const SceneFile({this.path = '', this.height = 0, this.width = 0});
  factory SceneFile.fromJson(dynamic j) => SceneFile(
        path: _s(j?['path']),
        height: _i(j?['height']),
        width: _i(j?['width']),
      );
}

class Scene {
  final String id;
  final String title;
  final String details;
  final String date;
  final String createdAt;
  final int rating100;
  final int oCounter;
  final int duration;
  final bool organized;
  final List<String> urls;
  final Studio? studio;
  final List<Performer> performers;
  final List<Tag> tags;
  final ScenePaths paths;
  final List<SceneFile> files;
  final List<String> captions;

  const Scene({
    required this.id,
    this.title = '',
    this.details = '',
    this.date = '',
    this.createdAt = '',
    this.rating100 = 0,
    this.oCounter = 0,
    this.duration = 0,
    this.organized = false,
    this.urls = const [],
    this.studio,
    this.performers = const [],
    this.tags = const [],
    this.paths = const ScenePaths(),
    this.files = const [],
    this.captions = const [],
  });

  factory Scene.fromJson(dynamic j) => Scene(
        id: _s(j?['id']),
        title: _s(j?['title']),
        details: _s(j?['details']),
        date: _s(j?['date']),
        createdAt: _s(j?['created_at']),
        rating100: _i(j?['rating100']),
        oCounter: _i(j?['o_counter']),
        // 时长不在 Scene 顶层，取第一个文件的 duration（同一文件组时长一致）。
        duration: j?['files'] is List && (j['files'] as List).isNotEmpty
            ? _i((j['files'] as List).first?['duration'])
            : _i(j?['duration']),
        organized: j?['organized'] == true,
        urls: _sl(j?['urls']),
        studio: j?['studio'] == null ? null : Studio.fromJson(j['studio']),
        performers: Performer.listFrom(j?['performers']),
        tags: Tag.listFrom(j?['tags']),
        paths: ScenePaths.fromJson(j?['paths']),
        files: j?['files'] is List
            ? (j['files'] as List)
                .map((e) => SceneFile.fromJson(e))
                .toList()
            : const [],
        // 外挂字幕：captions[{language_code, caption_type}] → caption_type 列表
        captions: _ml(j?['captions'])
            .map((e) => _s(e['caption_type']))
            .where((s) => s.isNotEmpty)
            .toList(),
      );

  static List<Scene> listFrom(dynamic v) =>
      _ml(v).map(Scene.fromJson).toList();

  String get displayTitle => title.isNotEmpty ? title : '（无标题）';

  Scene copyWith({bool? organized}) => Scene(
        id: id,
        title: title,
        details: details,
        date: date,
        rating100: rating100,
        oCounter: oCounter,
        duration: duration,
        organized: organized ?? this.organized,
        urls: urls,
        studio: studio,
        performers: performers,
        tags: tags,
        paths: paths,
        files: files,
        captions: captions,
      );
}

class FindResult<T> {
  final int count;
  final List<T> items;
  const FindResult({required this.count, required this.items});
}

// ---------- 削刮 ----------

class Scraper {
  final String id;
  final String name;
  final List<String> sceneScrapes;
  final List<String> performerScrapes;

  const Scraper({
    required this.id,
    required this.name,
    this.sceneScrapes = const [],
    this.performerScrapes = const [],
  });

  factory Scraper.fromJson(dynamic j) => Scraper(
        id: _s(j?['id']),
        name: _s(j?['name']),
        sceneScrapes: _sl(j?['scene']?['supported_scrapes']),
        performerScrapes: _sl(j?['performer']?['supported_scrapes']),
      );
}

class StashBoxInfo {
  final String name;
  final String endpoint;
  const StashBoxInfo({this.name = '', this.endpoint = ''});
  factory StashBoxInfo.fromJson(dynamic j) =>
      StashBoxInfo(name: _s(j?['name']), endpoint: _s(j?['endpoint']));
}

class ScrapedTag {
  final String storedId;
  final String name;
  const ScrapedTag({this.storedId = '', this.name = ''});
  factory ScrapedTag.fromJson(dynamic j) =>
      ScrapedTag(storedId: _s(j?['stored_id']), name: _s(j?['name']));
}

class ScrapedStudio {
  final String storedId;
  final String name;
  final List<String> urls;
  final String image;
  const ScrapedStudio({
    this.storedId = '',
    this.name = '',
    this.urls = const [],
    this.image = '',
  });
  factory ScrapedStudio.fromJson(dynamic j) => ScrapedStudio(
        storedId: _s(j?['stored_id']),
        name: _s(j?['name']),
        urls: _sl(j?['urls']),
        image: _s(j?['image']),
      );
}

class ScrapedPerformer {
  final String storedId;
  final String name;
  final String disambiguation;
  final String aliases;
  final String birthdate;
  final String gender;
  final String country;
  final String ethnicity;
  final String hairColor;
  final String eyeColor;
  final String height;
  final String weight;
  final String measurements;
  final String fakeTits;
  final String tattoos;
  final String piercings;
  final String careerStart;
  final String careerEnd;
  final String details;
  final List<String> urls;
  final List<String> images;
  final List<ScrapedTag> tags;

  const ScrapedPerformer({
    this.storedId = '',
    this.name = '',
    this.disambiguation = '',
    this.aliases = '',
    this.birthdate = '',
    this.gender = '',
    this.country = '',
    this.ethnicity = '',
    this.hairColor = '',
    this.eyeColor = '',
    this.height = '',
    this.weight = '',
    this.measurements = '',
    this.fakeTits = '',
    this.tattoos = '',
    this.piercings = '',
    this.careerStart = '',
    this.careerEnd = '',
    this.details = '',
    this.urls = const [],
    this.images = const [],
    this.tags = const [],
  });

  factory ScrapedPerformer.fromJson(dynamic j) {
    final tg = _ml(j?['tags']).map(ScrapedTag.fromJson).toList();
    return ScrapedPerformer(
      storedId: _s(j?['stored_id']),
      name: _s(j?['name']),
      disambiguation: _s(j?['disambiguation']),
      aliases: _s(j?['aliases']),
      birthdate: _s(j?['birthdate']),
      gender: _s(j?['gender']),
      country: _s(j?['country']),
      ethnicity: _s(j?['ethnicity']),
      hairColor: _s(j?['hair_color']),
      eyeColor: _s(j?['eye_color']),
      height: _s(j?['height']),
      weight: _s(j?['weight']),
      measurements: _s(j?['measurements']),
      fakeTits: _s(j?['fake_tits']),
      tattoos: _s(j?['tattoos']),
      piercings: _s(j?['piercings']),
      careerStart: _s(j?['career_start']),
      careerEnd: _s(j?['career_end']),
      details: _s(j?['details']),
      urls: _sl(j?['urls']),
      images: _sl(j?['images']),
      tags: tg,
    );
  }
}

class ScrapedScene {
  final String title;
  final String details;
  final String date;
  final int duration;
  final List<String> urls;
  final String image;
  final ScrapedStudio? studio;
  final List<ScrapedPerformer> performers;
  final List<ScrapedTag> tags;

  const ScrapedScene({
    this.title = '',
    this.details = '',
    this.date = '',
    this.duration = 0,
    this.urls = const [],
    this.image = '',
    this.studio,
    this.performers = const [],
    this.tags = const [],
  });

  factory ScrapedScene.fromJson(dynamic j) => ScrapedScene(
        title: _s(j?['title']),
        details: _s(j?['details']),
        date: _s(j?['date']),
        duration: _i(j?['duration']),
        urls: _sl(j?['urls']),
        image: _s(j?['image']),
        studio:
            j?['studio'] == null ? null : ScrapedStudio.fromJson(j['studio']),
        performers: _ml(j?['performers'])
            .map(ScrapedPerformer.fromJson)
            .toList(),
        tags: _ml(j?['tags']).map(ScrapedTag.fromJson).toList(),
      );
}

// ---------- 地址工具 ----------

/// 归一化基址：去尾斜杠；缺 scheme 时补 http://（手输 IP:端口 是常态）。
String normalizeBase(String base) {
  var s = base.trim();
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.isNotEmpty && !s.startsWith('http://') && !s.startsWith('https://')) {
    s = 'http://$s';
  }
  return s;
}

/// 图片地址重写：相对路径拼基址；主机不一致时改写为「基址根 + 原路径」。
/// Flutter 的 Image.network 可带 ApiKey 请求头，故不再追加 apikey 查询参数。
String rewriteImage(String raw, String base) {
  if (raw.isEmpty) return raw;
  final bs = normalizeBase(base);
  var out = raw;
  if (!out.startsWith('http://') && !out.startsWith('https://')) {
    if (bs.isEmpty) return out;
    out = bs + (out.startsWith('/') ? out : '/$out');
  } else if (bs.isNotEmpty) {
    final schemeEnd = out.indexOf('://');
    if (schemeEnd >= 0) {
      final afterScheme = out.substring(schemeEnd + 3);
      final hostEnd = afterScheme.indexOf('/');
      final rawHost = hostEnd < 0 ? afterScheme : afterScheme.substring(0, hostEnd);
      final bsSchemeEnd = bs.indexOf('://');
      if (bsSchemeEnd >= 0) {
        final bsAfter = bs.substring(bsSchemeEnd + 3);
        final bsHostEnd = bsAfter.indexOf('/');
        final bsHost = bsHostEnd < 0 ? bsAfter : bsAfter.substring(0, bsHostEnd);
        if (rawHost != bsHost) {
          final rawPath = hostEnd < 0 ? '/' : afterScheme.substring(hostEnd);
          out = bs + rawPath;
        }
      }
    }
  }
  return out;
}

// ---------- 场景筛选器（对齐 iOS SceneFilterState） ----------

/// 完整场景筛选状态：工作室/演员/标签多选 + 评分/O计数/时长/日期/分辨率 + 已整理。
/// [toJson] 仅输出非空字段，直接作为 findScenes 的 scene_filter 参数。
class SceneFilterState {
  List<String> studios = [];
  List<String> tags = [];
  List<String> performers = [];

  int rating100 = 0; // 0 = 不限；>0 表示 ≥ 该值
  int oCounter = 0; // 0 = 不限
  int durationSeconds = 0; // 0 = 不限
  int resolution = 0; // 0 = 不限；720/1080/2160

  String dateFrom = ''; // YYYY-MM-DD；空 = 不限
  String dateTo = '';

  bool organized = false;
  bool coversOnly = false;

  SceneFilterState();

  SceneFilterState copy() {
    final c = SceneFilterState()
      ..studios = List.of(studios)
      ..tags = List.of(tags)
      ..performers = List.of(performers)
      ..rating100 = rating100
      ..oCounter = oCounter
      ..durationSeconds = durationSeconds
      ..resolution = resolution
      ..dateFrom = dateFrom
      ..dateTo = dateTo
      ..organized = organized
      ..coversOnly = coversOnly;
    return c;
  }

  /// 已激活的筛选条件数量（导航角标用）。
  int get activeCount {
    var n = 0;
    if (studios.isNotEmpty) n++;
    if (tags.isNotEmpty) n++;
    if (performers.isNotEmpty) n++;
    if (rating100 > 0) n++;
    if (oCounter > 0) n++;
    if (durationSeconds > 0) n++;
    if (resolution > 0) n++;
    if (dateFrom.isNotEmpty || dateTo.isNotEmpty) n++;
    if (organized) n++;
    if (coversOnly) n++;
    return n;
  }

  bool get isEmpty => activeCount == 0;

  /// 组装 GraphQL SceneFilterType（与 iOS SceneFilterState.encode 对齐）。
  Map<String, dynamic> toJson() {
    final j = <String, dynamic>{};
    if (studios.isNotEmpty) {
      j['studios'] = {'value': studios, 'modifier': 'INCLUDES', 'depth': -1};
    }
    if (tags.isNotEmpty) {
      j['tags'] = {'value': tags, 'modifier': 'INCLUDES', 'depth': -1};
    }
    if (performers.isNotEmpty) {
      j['performers'] = {'value': performers, 'modifier': 'INCLUDES'};
    }
    if (rating100 > 0) {
      j['rating100'] = {
        'value': rating100 - 1,
        'modifier': 'GREATER_THAN',
      };
    }
    if (oCounter > 0) {
      j['o_counter'] = {'value': oCounter - 1, 'modifier': 'GREATER_THAN'};
    }
    if (durationSeconds > 0) {
      j['duration'] = {
        'value': durationSeconds - 1,
        'modifier': 'GREATER_THAN',
      };
    }
    if (resolution > 0) {
      j['resolution'] = {'value': resolution, 'modifier': 'GREATER_THAN'};
    }
    if (dateFrom.isNotEmpty || dateTo.isNotEmpty) {
      final v = <String>[
        if (dateFrom.isNotEmpty) dateFrom,
        if (dateTo.isNotEmpty) dateTo,
      ];
      if (v.length == 1) {
        j['date'] = {'value': v.first, 'modifier': 'GREATER_THAN'};
      } else {
        j['date'] = {'value': v, 'modifier': 'BETWEEN'};
      }
    }
    if (organized) j['organized'] = true;
    if (coversOnly) j['covers_only'] = true;
    return j;
  }
}
