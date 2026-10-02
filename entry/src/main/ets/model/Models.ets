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

// 图片地址重写：主机与当前档案不一致时改写为「档案基址 + 原路径」
export function rewriteImage(raw: string, base: string): string {
  if (raw === '') {
    return raw;
  }
  let url: URL;
  try {
    url = new URL(raw);
  } catch (e) {
    return raw;
  }
  if (url.hostname === '') {
    return raw;
  }
  let bs: string = base.trim();
  while (bs.endsWith('/')) {
    bs = bs.substring(0, bs.length - 1);
  }
  let baseUrl: URL;
  try {
    baseUrl = new URL(bs);
  } catch (e) {
    return raw;
  }
  // 主机与端口相同则直接用
  if (url.host === baseUrl.host) {
    return raw;
  }
  // 改写：base 路径 + 原路径与查询
  let path = url.pathname;
  if (!path.startsWith('/')) {
    path = '/' + path;
  }
  let mergedPath = baseUrl.pathname;
  if (mergedPath.endsWith('/')) {
    mergedPath = mergedPath.substring(0, mergedPath.length - 1);
  }
  let out = baseUrl.origin + mergedPath + path;
  if (url.search !== '') {
    out += url.search;
  }
  return out;
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
