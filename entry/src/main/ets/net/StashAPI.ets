import http from '@ohos.net.http';
import { util } from '@kit.ArkTS';
import { GraphQLClient } from './GraphQLClient';
import {
  AllPerformersResp, AllStudiosResp, AllTagsResp,
  ListScrapersResp, ScrapePerformerURLResp,
  ScrapeSceneURLResp, ScrapeSinglePerformerResp, ScrapeSingleSceneResp,
  ScrapeSingleStudioResp, Scraper, StashBoxesResp, StashBoxInfo,
  ScrapedPerformer, ScrapedScene, ScrapedStudio, ScrapedTag,
  Studio, Performer, Tag, Scene
} from '../model/Models';

// 鸿蒙版 Stash API：集中所有查询 / 变更 / 削刮操作（对齐 iOS StashAPI.swift）
export class StashAPI {
  // ---------- 分类全量（编辑表单用） ----------
  static async allStudios(c: GraphQLClient): Promise<Studio[]> {
    const r = await c.send('query { allStudios { id name } }') as AllStudiosResp;
    return r.allStudios !== undefined && r.allStudios !== null ? r.allStudios : [];
  }

  static async allPerformers(c: GraphQLClient): Promise<Performer[]> {
    const r = await c.send('query { allPerformers { id name } }') as AllPerformersResp;
    return r.allPerformers !== undefined && r.allPerformers !== null ? r.allPerformers : [];
  }

  static async allTags(c: GraphQLClient): Promise<Tag[]> {
    const r = await c.send('query { allTags { id name } }') as AllTagsResp;
    return r.allTags !== undefined && r.allTags !== null ? r.allTags : [];
  }

  // ---------- 削刮源 ----------
  // listScrapers(types: [ScrapeContentType!]!)，SCENE / PERFORMER
  static async scrapers(c: GraphQLClient, typeName: string): Promise<Scraper[]> {
    const q = `query ListScrapers($types: [ScrapeContentType!]!) {
      listScrapers(types: $types) { id name scene { supported_scrapes } performer { supported_scrapes } }
    }`;
    const types: string[] = [typeName];
    const vars: Record<string, Object> = { 'types': types };
    const r = await c.send(q, vars) as ListScrapersResp;
    return r.listScrapers !== undefined && r.listScrapers !== null ? r.listScrapers : [];
  }

  // 服务端已配置的 Stash-box 端点（数组顺序即 stash_box_index）
  static async stashBoxes(c: GraphQLClient): Promise<StashBoxInfo[]> {
    const r = await c.send(
      'query { configuration { general { stashBoxes { name endpoint } } } }') as StashBoxesResp;
    const g = r.configuration !== undefined && r.configuration !== null ? r.configuration.general : undefined;
    if (g === undefined || g === null || g.stashBoxes === undefined || g.stashBoxes === null) {
      return [];
    }
    return g.stashBoxes;
  }

  // ---------- 削刮 - 短片 ----------
  private static readonly sceneSelection =
    'title details date duration urls image ' +
    'studio { stored_id name urls image } ' +
    'performers { stored_id name disambiguation birthdate details country ethnicity measurements urls tags { stored_id name } } ' +
    'tags { stored_id name }';

  static async scrapeSceneFragment(c: GraphQLClient, source: Record<string, Object>, sceneId: string): Promise<ScrapedScene[]> {
    const q = `query ScrapeSingleScene($source: ScraperSourceInput!, $input: ScrapeSingleSceneInput!) {
      scrapeSingleScene(source: $source, input: $input) { ${StashAPI.sceneSelection} }
    }`;
    const input: Record<string, Object> = { 'scene_id': sceneId };
    const vars: Record<string, Object> = { 'source': source, 'input': input };
    const r = await c.send(q, vars, GraphQLClient.longTimeout) as ScrapeSingleSceneResp;
    return StashAPI.compactScenes(r.scrapeSingleScene);
  }

  static async scrapeSceneByName(c: GraphQLClient, source: Record<string, Object>, query: string): Promise<ScrapedScene[]> {
    const q = `query ScrapeSingleScene($source: ScraperSourceInput!, $input: ScrapeSingleSceneInput!) {
      scrapeSingleScene(source: $source, input: $input) { ${StashAPI.sceneSelection} }
    }`;
    const input: Record<string, Object> = { 'query': query };
    const vars: Record<string, Object> = { 'source': source, 'input': input };
    const r = await c.send(q, vars, GraphQLClient.longTimeout) as ScrapeSingleSceneResp;
    return StashAPI.compactScenes(r.scrapeSingleScene);
  }

  static async scrapeSceneURL(c: GraphQLClient, url: string): Promise<ScrapedScene[]> {
    const q = `query ScrapeSceneURL($url: String!) {
      scrapeSceneURL(url: $url) { ${StashAPI.sceneSelection} }
    }`;
    const r = await c.send(q, { 'url': url }, GraphQLClient.longTimeout) as ScrapeSceneURLResp;
    const s = r.scrapeSceneURL;
    if (s === undefined || s === null) {
      return [];
    }
    return [s];
  }

  // ---------- 削刮 - 演员 ----------
  private static readonly performerSelection =
    'stored_id name disambiguation aliases birthdate gender country ethnicity hair_color eye_color height weight ' +
    'measurements fake_tits tattoos piercings career_start career_end details urls images tags { stored_id name }';

  static async scrapePerformerFragment(c: GraphQLClient, source: Record<string, Object>, performerId: string): Promise<ScrapedPerformer[]> {
    const q = `query ScrapeSinglePerformer($source: ScraperSourceInput!, $input: ScrapeSinglePerformerInput!) {
      scrapeSinglePerformer(source: $source, input: $input) { ${StashAPI.performerSelection} }
    }`;
    const input: Record<string, Object> = { 'performer_id': performerId };
    const vars: Record<string, Object> = { 'source': source, 'input': input };
    const r = await c.send(q, vars, GraphQLClient.longTimeout) as ScrapeSinglePerformerResp;
    return StashAPI.compactPerformers(r.scrapeSinglePerformer);
  }

  static async scrapePerformerByName(c: GraphQLClient, source: Record<string, Object>, query: string): Promise<ScrapedPerformer[]> {
    const q = `query ScrapeSinglePerformer($source: ScraperSourceInput!, $input: ScrapeSinglePerformerInput!) {
      scrapeSinglePerformer(source: $source, input: $input) { ${StashAPI.performerSelection} }
    }`;
    const input: Record<string, Object> = { 'query': query };
    const vars: Record<string, Object> = { 'source': source, 'input': input };
    const r = await c.send(q, vars, GraphQLClient.longTimeout) as ScrapeSinglePerformerResp;
    return StashAPI.compactPerformers(r.scrapeSinglePerformer);
  }

  static async scrapePerformerURL(c: GraphQLClient, url: string): Promise<ScrapedPerformer[]> {
    const q = `query ScrapePerformerURL($url: String!) {
      scrapePerformerURL(url: $url) { ${StashAPI.performerSelection} }
    }`;
    const r = await c.send(q, { 'url': url }, GraphQLClient.longTimeout) as ScrapePerformerURLResp;
    const p = r.scrapePerformerURL;
    if (p === undefined || p === null) {
      return [];
    }
    return [p];
  }

  // ---------- 削刮 - 工作室（仅 stash-box） ----------
  static async scrapeStudioByName(c: GraphQLClient, source: Record<string, Object>, query: string): Promise<ScrapedStudio[]> {
    const q = `query ScrapeSingleStudio($source: ScraperSourceInput!, $input: ScrapeSingleStudioInput!) {
      scrapeSingleStudio(source: $source, input: $input) { stored_id name urls image }
    }`;
    const input: Record<string, Object> = { 'query': query };
    const vars: Record<string, Object> = { 'source': source, 'input': input };
    const r = await c.send(q, vars, GraphQLClient.longTimeout) as ScrapeSingleStudioResp;
    const s = r.scrapeSingleStudio;
    if (s === undefined || s === null) {
      return [];
    }
    return [s];
  }

  static async applyScrapedStudio(c: GraphQLClient, s: ScrapedStudio, targetId: string, includeImage: boolean): Promise<number> {
    const input: Record<string, Object> = { 'id': targetId };
    let changed = 0;
    if (s.urls !== undefined && s.urls !== null && s.urls.length > 0) {
      input['urls'] = s.urls;
      changed++;
    }
    if (includeImage && s.image !== undefined && s.image !== null && s.image !== '') {
      const b64 = await StashAPI.fetchImageAsBase64(s.image);
      if (b64 !== '') {
        input['image'] = b64;
        changed++;
      }
    }
    if (changed > 0) {
      const r = await c.send(
        'mutation UpdateStudio($input: StudioUpdateInput!) { studioUpdate(input: $input) { id } }',
        { 'input': input }) as IdResp;
      if (r === null || r.studioUpdate === undefined || r.studioUpdate === null) {
        throw new Error('studioUpdate 失败');
      }
    }
    return changed;
  }

  private static compactScenes(list: (ScrapedScene | null)[] | undefined): ScrapedScene[] {
    if (list === undefined || list === null) {
      return [];
    }
    const out: ScrapedScene[] = [];
    for (const it of list) {
      if (it !== undefined && it !== null) {
        out.push(it);
      }
    }
    return out;
  }

  private static compactPerformers(list: (ScrapedPerformer | null)[] | undefined): ScrapedPerformer[] {
    if (list === undefined || list === null) {
      return [];
    }
    const out: ScrapedPerformer[] = [];
    for (const it of list) {
      if (it !== undefined && it !== null) {
        out.push(it);
      }
    }
    return out;
  }

  // ---------- 元数据写回 ----------
  static async updateScene(c: GraphQLClient, input: Record<string, Object>): Promise<void> {
    const r = await c.send(
      'mutation UpdateScene($input: SceneUpdateInput!) { sceneUpdate(input: $input) { id } }',
      { 'input': input }) as IdResp;
    if (r === null || r.sceneUpdate === undefined || r.sceneUpdate === null) {
      throw new Error('sceneUpdate 失败');
    }
  }

  static async updatePerformer(c: GraphQLClient, input: Record<string, Object>): Promise<void> {
    const r = await c.send(
      'mutation UpdatePerformer($input: PerformerUpdateInput!) { performerUpdate(input: $input) { id } }',
      { 'input': input }) as IdResp;
    if (r === null || r.performerUpdate === undefined || r.performerUpdate === null) {
      throw new Error('performerUpdate 失败');
    }
  }

  static async createPerformer(c: GraphQLClient, input: Record<string, Object>): Promise<string> {
    const r = await c.send(
      'mutation CreatePerformer($input: PerformerCreateInput!) { performerCreate(input: $input) { id } }',
      { 'input': input }) as IdResp;
    const id = r.performerCreate;
    if (id === undefined || id === null || id.id === undefined || id.id === null) {
      throw new Error('performerCreate 失败');
    }
    return id.id;
  }

  static async createTag(c: GraphQLClient, name: string): Promise<string> {
    const input: Record<string, Object> = { 'name': name };
    const r = await c.send(
      'mutation CreateTag($input: TagCreateInput!) { tagCreate(input: $input) { id } }',
      { 'input': input }) as IdResp;
    const id = r.tagCreate;
    if (id === undefined || id === null || id.id === undefined || id.id === null) {
      throw new Error('tagCreate 失败');
    }
    return id.id;
  }

  static async createStudio(c: GraphQLClient, name: string): Promise<string> {
    const input: Record<string, Object> = { 'name': name };
    const r = await c.send(
      'mutation CreateStudio($input: StudioCreateInput!) { studioCreate(input: $input) { id } }',
      { 'input': input }) as IdResp;
    const id = r.studioCreate;
    if (id === undefined || id === null || id.id === undefined || id.id === null) {
      throw new Error('studioCreate 失败');
    }
    return id.id;
  }

  // ---------- 短片合并（服务端原生 sceneMerge） ----------
  static async mergeScenes(c: GraphQLClient, sourceIds: string[], destinationId: string): Promise<void> {
    const input: Record<string, Object> = {
      'source': sourceIds,
      'destination': destinationId,
      'play_history': true,
      'o_history': true
    };
    const r = await c.send(
      'mutation SceneMerge($input: SceneMergeInput!) { sceneMerge(input: $input) { id } }',
      { 'input': input }) as IdResp;
    if (r === null || r.sceneMerge === undefined || r.sceneMerge === null) {
      throw new Error('sceneMerge 失败');
    }
  }

  // ---------- 削刮结果写回 ----------

  // 下载图片转 base64 data URI；失败返回空串（不影响文字字段）
  static async fetchImageAsBase64(ref: string): Promise<string> {
    if (ref.startsWith('data:')) {
      return ref;
    }
    if (!ref.startsWith('http://') && !ref.startsWith('https://')) {
      return '';
    }
    const req = http.createHttp();
    try {
      const resp = await req.request(ref, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 10000,
        readTimeout: 20000
      });
      const code = resp.responseCode;
      const buf = resp.result as ArrayBuffer;
      if (code < 200 || code > 299 || buf.byteLength === 0) {
        return '';
      }
      const helper = new util.Base64Helper();
      return 'data:image/jpeg;base64,' + helper.encodeToStringSync(new Uint8Array(buf));
    } catch (e) {
      return '';
    }
  }

  private static async resolvePerformerID(c: GraphQLClient, p: ScrapedPerformer): Promise<string> {
    if (p.stored_id !== undefined && p.stored_id !== null && p.stored_id !== '') {
      return p.stored_id;
    }
    if (p.name === undefined || p.name === null || p.name === '') {
      throw new Error('削刮演员无名称');
    }
    return await StashAPI.createPerformer(c, { 'name': p.name });
  }

  private static async resolveTagID(c: GraphQLClient, t: ScrapedTag): Promise<string> {
    if (t.stored_id !== undefined && t.stored_id !== null && t.stored_id !== '') {
      return t.stored_id;
    }
    if (t.name === undefined || t.name === null || t.name === '') {
      throw new Error('削刮标签无名称');
    }
    return await StashAPI.createTag(c, t.name);
  }

  private static async resolveStudioID(c: GraphQLClient, s: ScrapedStudio): Promise<string> {
    if (s.stored_id !== undefined && s.stored_id !== null && s.stored_id !== '') {
      return s.stored_id;
    }
    if (s.name === undefined || s.name === null || s.name === '') {
      throw new Error('削刮工作室无名称');
    }
    return await StashAPI.createStudio(c, s.name);
  }

  // 写回削刮结果：仅写非空字段；库内不存在自动创建；可选图片
  static async applyScrapedScene(c: GraphQLClient, s: ScrapedScene, targetId: string, includeImage: boolean): Promise<number> {
    const input: Record<string, Object> = { 'id': targetId };
    let changed = 0;
    if (s.title !== undefined && s.title !== null && s.title !== '') {
      input['title'] = s.title;
      changed++;
    }
    if (s.details !== undefined && s.details !== null && s.details !== '') {
      input['details'] = s.details;
      changed++;
    }
    if (s.date !== undefined && s.date !== null && s.date !== '') {
      input['date'] = s.date;
      changed++;
    }
    if (s.studio !== undefined && s.studio !== null) {
      const sid = await StashAPI.resolveStudioID(c, s.studio);
      input['studio_id'] = sid;
      changed++;
    }
    if (s.performers !== undefined && s.performers !== null && s.performers.length > 0) {
      const ids: string[] = [];
      for (const p of s.performers) {
        if (p !== undefined && p !== null) {
          ids.push(await StashAPI.resolvePerformerID(c, p));
        }
      }
      if (ids.length > 0) {
        input['performer_ids'] = ids;
        changed++;
      }
    }
    if (s.tags !== undefined && s.tags !== null && s.tags.length > 0) {
      const ids: string[] = [];
      for (const t of s.tags) {
        if (t !== undefined && t !== null) {
          ids.push(await StashAPI.resolveTagID(c, t));
        }
      }
      if (ids.length > 0) {
        input['tag_ids'] = ids;
        changed++;
      }
    }
    if (s.urls !== undefined && s.urls !== null && s.urls.length > 0) {
      input['urls'] = s.urls;
      changed++;
    }
    if (includeImage && s.image !== undefined && s.image !== null && s.image !== '') {
      const b64 = await StashAPI.fetchImageAsBase64(s.image);
      if (b64 !== '') {
        input['cover_image'] = b64;
        changed++;
      }
    }
    if (changed > 0) {
      await StashAPI.updateScene(c, input);
    }
    return changed;
  }

  // 写回演员削刮结果（全部字段）
  static async applyScrapedPerformer(c: GraphQLClient, p: ScrapedPerformer, targetId: string, includeImage: boolean): Promise<number> {
    const input: Record<string, Object> = { 'id': targetId };
    let changed = 0;
    const put = (key: string, v: string | undefined): boolean => {
      if (v !== undefined && v !== null && v !== '') {
        input[key] = v;
        changed++;
        return true;
      }
      return false;
    };
    put('name', p.name);
    put('disambiguation', p.disambiguation);
    put('birthdate', p.birthdate);
    put('gender', p.gender);
    put('country', p.country);
    put('ethnicity', p.ethnicity);
    put('hair_color', p.hair_color);
    put('eye_color', p.eye_color);
    put('measurements', p.measurements);
    put('fake_tits', p.fake_tits);
    put('tattoos', p.tattoos);
    put('piercings', p.piercings);
    put('details', p.details);
    if (p.height !== undefined && p.height !== null && p.height !== '') {
      const n = Number(p.height);
      if (n > 0) {
        input['height'] = n;
        changed++;
      }
    }
    if (p.weight !== undefined && p.weight !== null && p.weight !== '') {
      const n = Number(p.weight);
      if (n > 0) {
        input['weight'] = n;
        changed++;
      }
    }
    const careerParts: string[] = [];
    if (p.career_start !== undefined && p.career_start !== null && p.career_start !== '') {
      careerParts.push(p.career_start);
    }
    if (p.career_end !== undefined && p.career_end !== null && p.career_end !== '') {
      careerParts.push(p.career_end);
    }
    const career = careerParts.join(' - ');
    if (career !== '') {
      input['career_length'] = career;
      changed++;
    }
    if (p.urls !== undefined && p.urls !== null && p.urls.length > 0) {
      input['urls'] = p.urls;
      changed++;
    }
    if (p.tags !== undefined && p.tags !== null && p.tags.length > 0) {
      const ids: string[] = [];
      for (const t of p.tags) {
        if (t !== undefined && t !== null) {
          ids.push(await StashAPI.resolveTagID(c, t));
        }
      }
      if (ids.length > 0) {
        input['tag_ids'] = ids;
        changed++;
      }
    }
    if (includeImage && p.images !== undefined && p.images !== null && p.images.length > 0) {
      const first = p.images.find((v: string): boolean => v !== '');
      if (first !== undefined) {
        const b64 = await StashAPI.fetchImageAsBase64(first);
        if (b64 !== '') {
          input['image'] = b64;
          changed++;
        }
      }
    }
    if (changed > 0) {
      await StashAPI.updatePerformer(c, input);
    }
    return changed;
  }
}

// id 返回外壳
interface IdPayload {
  id: string;
}

interface IdResp {
  sceneUpdate?: IdPayload;
  performerUpdate?: IdPayload;
  performerCreate?: IdPayload;
  tagCreate?: IdPayload;
  studioCreate?: IdPayload;
  sceneMerge?: IdPayload;
  studioUpdate?: IdPayload;
}
