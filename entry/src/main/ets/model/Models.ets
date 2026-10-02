// Stash GraphQL 数据模型（与 iOS 版一致）

export interface Studio {
  id: string;
  name: string;
  image_path?: string;
  rating100?: number;
  scene_count?: number;
}

export interface Performer {
  id: string;
  name: string;
  disambiguation?: string;
  image_path?: string;
  birthdate?: string;
  country?: string;
  ethnicity?: string;
  measurements?: string;
  career_length?: string;
  details?: string;
  rating100?: number;
  tags?: Tag[];
}

export interface Tag {
  id: string;
  name: string;
}

export interface ScenePaths {
  screenshot?: string;
  webp?: string;
}

export interface SceneFile {
  path?: string;
}

export interface Scene {
  id: string;
  title?: string;
  details?: string;
  date?: string;
  rating100?: number;
  o_counter?: number;
  organized?: boolean;
  urls?: string[];
  studio?: Studio;
  performers?: Performer[];
  tags?: Tag[];
  paths?: ScenePaths;
  files?: SceneFile[];
}

export interface ScenePage {
  count: number;
  scenes: Scene[];
}

export interface PerformerPage {
  count: number;
  performers: Performer[];
}

export interface StudioPage {
  count: number;
  studios: Studio[];
}

// GraphQL 查询响应外壳（JSON as 断言用，字段可选避免严格空校验）
export interface FindScenesResp {
  findScenes?: ScenePage;
}

export interface FindPerformersResp {
  findPerformers?: PerformerPage;
}

export interface FindStudiosResp {
  findStudios?: StudioPage;
}

export interface FindSceneResp {
  findScene?: Scene;
}

export interface FindPerformerResp {
  findPerformer?: Performer;
}

export interface FindStudioResp {
  findStudio?: Studio;
}

export interface FindTagResp {
  findTag?: Tag;
}

// ---------- 削刮 ----------

export interface Scraper {
  id: string;
  name: string;
  scene?: ScraperCap;
  performer?: ScraperCap;
}

export interface ScraperCap {
  supported_scrapes?: string[];
}

export interface StashBoxInfo {
  name?: string;
  endpoint?: string;
}

export interface ScrapedStudio {
  stored_id?: string;
  name?: string;
  urls?: string[];
  image?: string;
}

export interface ScrapedTag {
  stored_id?: string;
  name?: string;
}

export interface ScrapedPerformer {
  stored_id?: string;
  name?: string;
  disambiguation?: string;
  aliases?: string[];
  birthdate?: string;
  gender?: string;
  country?: string;
  ethnicity?: string;
  hair_color?: string;
  eye_color?: string;
  height?: string;
  weight?: string;
  measurements?: string;
  fake_tits?: string;
  tattoos?: string;
  piercings?: string;
  career_start?: string;
  career_end?: string;
  details?: string;
  urls?: string[];
  images?: string[];
  tags?: ScrapedTag[];
}

export interface ScrapedScene {
  title?: string;
  details?: string;
  date?: string;
  duration?: number;
  urls?: string[];
  image?: string;
  studio?: ScrapedStudio;
  performers?: ScrapedPerformer[];
  tags?: ScrapedTag[];
}

// 削刮 / 分类 响应外壳
export interface ListScrapersResp {
  listScrapers?: Scraper[];
}

export interface StashBoxesResp {
  configuration?: StashBoxConf;
}

export interface StashBoxConf {
  general?: StashBoxGeneral;
}

export interface StashBoxGeneral {
  stashBoxes?: StashBoxInfo[];
}

export interface ScrapeSingleSceneResp {
  scrapeSingleScene?: (ScrapedScene | null)[];
}

export interface ScrapeSceneURLResp {
  scrapeSceneURL?: ScrapedScene | null;
}

export interface ScrapeSinglePerformerResp {
  scrapeSinglePerformer?: (ScrapedPerformer | null)[];
}

export interface ScrapePerformerURLResp {
  scrapePerformerURL?: ScrapedPerformer | null;
}

export interface ScrapeSingleStudioResp {
  scrapeSingleStudio?: ScrapedStudio | null;
}

export interface AllStudiosResp {
  allStudios?: Studio[];
}

export interface AllPerformersResp {
  allPerformers?: Performer[];
}

export interface AllTagsResp {
  allTags?: Tag[];
}

// 图片地址重写：主机与当前档案不一致时改写为「档案基址 + 原路径」
export function rewriteImage(raw: string, base: string): string {
  if (raw === '') {
    return raw;
  }
  if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
    return raw;
  }
  let bs: string = base.trim();
  while (bs.endsWith('/')) {
    bs = bs.substring(0, bs.length - 1);
  }
  // 取 raw 的 host:port
  const schemeEnd = raw.indexOf('://');
  if (schemeEnd < 0) {
    return raw;
  }
  const afterScheme = raw.substring(schemeEnd + 3);
  const hostEnd = afterScheme.indexOf('/');
  const rawHost = hostEnd < 0 ? afterScheme : afterScheme.substring(0, hostEnd);
  // 取 base 的 host:port
  const bsSchemeEnd = bs.indexOf('://');
  if (bsSchemeEnd < 0) {
    return raw;
  }
  const bsAfter = bs.substring(bsSchemeEnd + 3);
  const bsHostEnd = bsAfter.indexOf('/');
  const bsHost = bsHostEnd < 0 ? bsAfter : bsAfter.substring(0, bsHostEnd);
  // 主机相同直接返回
  if (rawHost === bsHost) {
    return raw;
  }
  // 改写：base 根 + raw 的路径与查询
  const rawPath = hostEnd < 0 ? '/' : afterScheme.substring(hostEnd);
  let out = bs;
  if (bsHostEnd >= 0) {
    // base 带子路径时保留子路径
    out = bs;
  }
  while (out.endsWith('/')) {
    out = out.substring(0, out.length - 1);
  }
  return out + rawPath;
}

// 归一化档案基址（去尾斜杠）
export function normalizeBase(base: string): string {
  let s = base.trim();
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

// 由基址构造 GraphQL 端点
export function graphqlURL(base: string): string {
  const s = normalizeBase(base);
  if (s.endsWith('/graphql')) {
    return s;
  }
  return s + '/graphql';
}
