import router from '@ohos.router';
import { Scraper, StashBoxInfo, ScrapedScene, ScrapedPerformer, ScrapedStudio } from '../model/Models';
import { makeClient, GraphQLClient } from '../net/GraphQLClient';
import { StashAPI } from '../net/StashAPI';

// 名称削刮的源项
interface QuerySource {
  label: string;
  dict: Record<string, Object>;
}

// 削刮页：短片 / 演员通用
// 流程：选择方式 → 点削刮器 → 启动削刮（隐藏削刮器列表）→ 直接显示削刮数据 → 点击预览 → 应用写回
@Entry
@Component
struct ScrapePage {
  @State private kind: string = 'scene';        // scene | performer
  @State private targetId: string = '';
  @State private targetTitle: string = '';

  @State private mode: number = 0;              // 0=片段 1=名称 2=URL
  @State private started: boolean = false;
  @State private loading: boolean = false;
  @State private error: string = '';
  @State private queryText: string = '';
  @State private urlText: string = '';

  @State private localScrapers: Scraper[] = [];
  @State private boxes: StashBoxInfo[] = [];
  @State private sceneResults: ScrapedScene[] = [];
  @State private performerResults: ScrapedPerformer[] = [];
  @State private studioResults: ScrapedStudio[] = [];

  @State private previewIndex: number = -1;     // -1=未进入预览
  @State private includeImage: boolean = true;
  @State private applying: boolean = false;
  @State private applyMsg: string = '';

  private isScene(): boolean {
    return this.kind === 'scene';
  }

  private isPerformer(): boolean {
    return this.kind === 'performer';
  }

  private isStudio(): boolean {
    return this.kind === 'studio';
  }

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    if (params !== null) {
      if (params['kind'] !== undefined) {
        this.kind = params['kind'];
      }
      if (params['id'] !== undefined) {
        this.targetId = params['id'];
      }
      if (params['title'] !== undefined) {
        this.targetTitle = params['title'];
      }
    }
    if (this.isStudio()) {
      this.mode = 1;
    }
    this.loadSources();
  }

  private async loadSources(): Promise<void> {
    try {
      const client = makeClient();
      if (!this.isStudio()) {
        this.localScrapers = await StashAPI.scrapers(client, this.isScene() ? 'SCENE' : 'PERFORMER');
      }
      this.boxes = await StashAPI.stashBoxes(client);
    } catch (e) {
      // 源加载失败不阻塞 URL 削刮
    }
  }

  // 名称削刮源：stash-box + 本地刮削器（工作室仅 stash-box）
  private querySources(): QuerySource[] {
    const out: QuerySource[] = [];
    for (let i = 0; i < this.boxes.length; i++) {
      const b = this.boxes[i];
      const dict: Record<string, Object> = { 'stash_box_index': i };
      const item: QuerySource = {
        label: (b.name !== undefined && b.name !== '' ? b.name : 'Stash-box') + '（Stash-box）',
        dict: dict
      };
      out.push(item);
    }
    if (!this.isStudio()) {
      for (const s of this.localScrapers) {
        const dict: Record<string, Object> = { 'scraper_id': s.id };
        const item: QuerySource = { label: s.name, dict: dict };
        out.push(item);
      }
    }
    return out;
  }

  // 片段削刮源：本地刮削器（仅短片 / 演员）
  private fragmentSources(): Scraper[] {
    return this.localScrapers;
  }

  private async runStudio(body: (client: GraphQLClient) => Promise<ScrapedStudio[]>): Promise<void> {
    this.started = true;
    this.loading = true;
    this.error = '';
    this.studioResults = [];
    try {
      const client = makeClient();
      const items = await body(client);
      this.studioResults = items;
      if (items.length === 0) {
        this.error = '没有削刮到结果。可点左上角「换削刮器」重试。';
      }
    } catch (e) {
      this.error = '削刮失败';
    }
    this.loading = false;
  }

  private scrapeStudioQuery(src: QuerySource): void {
    this.runStudio(async (client) => {
      return await StashAPI.scrapeStudioByName(client, src.dict, this.queryText.trim());
    });
  }

  private async runScene(body: (client: GraphQLClient) => Promise<ScrapedScene[]>): Promise<void> {
    this.started = true;
    this.loading = true;
    this.error = '';
    this.sceneResults = [];
    try {
      const client = makeClient();
      const items = await body(client);
      this.sceneResults = items;
      if (items.length === 0) {
        this.error = '没有削刮到结果。可点左上角「换削刮器」换一个源重试。';
      }
    } catch (e) {
      this.error = '削刮失败';
    }
    this.loading = false;
  }

  private async runPerformer(body: (client: GraphQLClient) => Promise<ScrapedPerformer[]>): Promise<void> {
    this.started = true;
    this.loading = true;
    this.error = '';
    this.performerResults = [];
    try {
      const client = makeClient();
      const items = await body(client);
      this.performerResults = items;
      if (items.length === 0) {
        this.error = '没有削刮到结果。可点左上角「换削刮器」换一个源重试。';
      }
    } catch (e) {
      this.error = '削刮失败';
    }
    this.loading = false;
  }

  private scrapeFragment(src: Scraper): void {
    if (this.isScene()) {
      this.runScene(async (client) => {
        return await StashAPI.scrapeSceneFragment(client, { 'scraper_id': src.id }, this.targetId);
      });
    } else {
      this.runPerformer(async (client) => {
        return await StashAPI.scrapePerformerFragment(client, { 'scraper_id': src.id }, this.targetId);
      });
    }
  }

  private scrapeQuery(src: QuerySource): void {
    if (this.isScene()) {
      this.runScene(async (client) => {
        return await StashAPI.scrapeSceneByName(client, src.dict, this.queryText.trim());
      });
    } else {
      this.runPerformer(async (client) => {
        return await StashAPI.scrapePerformerByName(client, src.dict, this.queryText.trim());
      });
    }
  }

  private scrapeURL(): void {
    if (this.isScene()) {
      this.runScene(async (client) => {
        return await StashAPI.scrapeSceneURL(client, this.urlText.trim());
      });
    } else {
      this.runPerformer(async (client) => {
        return await StashAPI.scrapePerformerURL(client, this.urlText.trim());
      });
    }
  }

  // ---------- 预览数据 ----------
  private previewRows(): string[] {
    if (this.previewIndex < 0) {
      return [];
    }
    if (this.isScene()) {
      const s = this.sceneResults[this.previewIndex];
      if (s === undefined) {
        return [];
      }
      const rows: string[] = [];
      this.addRow(rows, '标题', s.title);
      this.addRow(rows, '日期', s.date);
      if (s.studio !== undefined && s.studio !== null) {
        this.addRow(rows, '工作室', s.studio.name);
      }
      this.addRow(rows, '简介', s.details);
      if (s.performers !== undefined && s.performers !== null && s.performers.length > 0) {
        rows.push('演员：' + this.joinNames(s.performers.map((p) => p.name)));
      }
      if (s.tags !== undefined && s.tags !== null && s.tags.length > 0) {
        rows.push('标签：' + this.joinNames(s.tags.map((t) => t.name)));
      }
      if (s.urls !== undefined && s.urls !== null && s.urls.length > 0) {
        rows.push('URL：' + s.urls.join(' '));
      }
      return rows;
    }
    if (this.isPerformer()) {
      const p = this.performerResults[this.previewIndex];
      if (p === undefined) {
        return [];
      }
      const rows: string[] = [];
      this.addRow(rows, '名称', p.name);
      this.addRow(rows, '区别名', p.disambiguation);
      this.addRow(rows, '出生日期', p.birthdate);
      this.addRow(rows, '国籍', p.country);
      this.addRow(rows, '族裔', p.ethnicity);
      this.addRow(rows, '三围', p.measurements);
      const career = [p.career_start, p.career_end].filter((v: string | undefined) => v !== undefined && v !== null && v !== '')
        .join(' - ');
      this.addRow(rows, '从业年限', career === '' ? undefined : career);
      this.addRow(rows, '简介', p.details);
      if (p.tags !== undefined && p.tags !== null && p.tags.length > 0) {
        rows.push('标签：' + this.joinNames(p.tags.map((t) => t.name)));
      }
      return rows;
    }
    const st = this.studioResults[this.previewIndex];
    if (st === undefined) {
      return [];
    }
    const rows: string[] = [];
    this.addRow(rows, '名称', st.name);
    if (st.urls !== undefined && st.urls !== null && st.urls.length > 0) {
      rows.push('URL：' + st.urls.join(' '));
    }
    return rows;
  }

  private addRow(rows: string[], label: string, v: string | undefined): void {
    if (v !== undefined && v !== null && v !== '') {
      rows.push(label + '：' + v);
    }
  }

  private joinNames(names: (string | undefined)[]): string {
    const out: string[] = [];
    for (const n of names) {
      if (n !== undefined && n !== null && n !== '') {
        out.push(n);
      }
    }
    return out.join('、');
  }

  private previewImage(): string {
    if (this.previewIndex < 0) {
      return '';
    }
    if (this.isScene()) {
      const s = this.sceneResults[this.previewIndex];
      return s !== undefined && s.image !== undefined && s.image !== null ? s.image : '';
    }
    if (this.isPerformer()) {
      const p = this.performerResults[this.previewIndex];
      if (p === undefined || p.images === undefined || p.images === null || p.images.length === 0) {
        return '';
      }
      const first = p.images.find((v: string) => v !== '');
      return first !== undefined ? first : '';
    }
    const st = this.studioResults[this.previewIndex];
    return st !== undefined && st.image !== undefined && st.image !== null ? st.image : '';
  }

  private async apply(): Promise<void> {
    this.applying = true;
    this.applyMsg = '';
    try {
      const client = makeClient();
      if (this.isScene()) {
        const s = this.sceneResults[this.previewIndex];
        const n = await StashAPI.applyScrapedScene(client, s, this.targetId, this.includeImage);
        this.applyMsg = '已写入 ' + n.toString() + ' 个字段';
      } else if (this.isPerformer()) {
        const p = this.performerResults[this.previewIndex];
        const n = await StashAPI.applyScrapedPerformer(client, p, this.targetId, this.includeImage);
        this.applyMsg = '已写入 ' + n.toString() + ' 个字段';
      } else {
        const st = this.studioResults[this.previewIndex];
        const n = await StashAPI.applyScrapedStudio(client, st, this.targetId, this.includeImage);
        this.applyMsg = '已写入 ' + n.toString() + ' 个字段';
      }
    } catch (e) {
      this.applyMsg = '写回失败：' + '削刮写回出错';
    }
    this.applying = false;
  }

  build() {
    Navigation() {
      if (this.previewIndex >= 0) {
        // ---------- 预览页 ----------
        Scroll() {
          Column({ space: 12 }) {
            if (this.previewImage() !== '') {
              Image(this.previewImage())
                .width('100%')
                .height(180)
                .objectFit(ImageFit.Cover)
                .borderRadius(12)
                .backgroundColor('#E8E8E8')
            }
            Toggle({ type: ToggleType.Switch, isOn: this.includeImage })
              .onChange((v: boolean) => { this.includeImage = v })
              .margin({ top: 4 })
            Text('应用图片（下载后转为 base64 写入）').fontSize(13)
              .width('100%')
              .margin({ top: -28, left: 8 })

            Text('将写入 ' + this.previewRows().length.toString() + ' 个字段')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .width('100%')
              .margin({ top: 8 })
            Column({ space: 6 }) {
              ForEach(this.previewRows(), (row: string) => {
                Text(row)
                  .fontSize(14)
                  .width('100%')
                  .padding(10)
                  .backgroundColor('#F2F2F2')
                  .borderRadius(8)
              }, (row: string) => row)
            }
            .width('100%')

            Text('空字段不会写入，库内不存在的演员/标签/工作室将自动创建。')
              .fontSize(12)
              .fontColor('#999999')
              .width('100%')

            if (this.applyMsg !== '') {
              Text(this.applyMsg).fontSize(14).fontColor('#2A8C5A')
            }
            Button(this.applying ? '应用中…' : '应用并写回', { type: ButtonType.Capsule })
              .fontSize(16)
              .width('100%')
              .height(44)
              .enabled(!this.applying && this.previewRows().length > 0)
              .onClick(() => { this.apply() })
            Button('返回结果', { type: ButtonType.Normal })
              .fontSize(15)
              .width('100%')
              .height(40)
              .onClick(() => { this.previewIndex = -1 })
          }
          .width('100%')
          .padding(16)
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
      } else if (!this.started) {
        // ---------- 削刮器选择 ----------
        Scroll() {
          Column({ space: 10 }) {
            // 方式切换
            if (this.isStudio()) {
              Text('工作室削刮：通过 Stash-box 按名称匹配').fontSize(12).fontColor('#999999')
                .width('100%')
                .margin({ top: 8 })
            } else {
              Row({ space: 8 }) {
                Button(this.mode === 0 ? '片段削刮' : '片段')
                  .fontSize(14)
                  .backgroundColor(this.mode === 0 ? '#1E5EFF' : '#F2F2F2')
                  .fontColor(this.mode === 0 ? '#FFFFFF' : '#333333')
                  .height(34)
                  .borderRadius(8)
                  .onClick(() => { this.mode = 0 })
                Button(this.mode === 1 ? '名称削刮' : '名称')
                  .fontSize(14)
                  .backgroundColor(this.mode === 1 ? '#1E5EFF' : '#F2F2F2')
                  .fontColor(this.mode === 1 ? '#FFFFFF' : '#333333')
                  .height(34)
                  .borderRadius(8)
                  .onClick(() => { this.mode = 1 })
                Button(this.mode === 2 ? 'URL 削刮' : 'URL')
                  .fontSize(14)
                  .backgroundColor(this.mode === 2 ? '#1E5EFF' : '#F2F2F2')
                  .fontColor(this.mode === 2 ? '#FFFFFF' : '#333333')
                  .height(34)
                  .borderRadius(8)
                  .onClick(() => { this.mode = 2 })
              }
              .width('100%')
              .justifyContent(FlexAlign.Start)
              .margin({ top: 8 })
            }

            if (this.mode === 0) {
              Text('片段削刮：以当前条目的已有信息为上下文削刮').fontSize(12).fontColor('#999999')
              List({ space: 8 }) {
                ForEach(this.fragmentSources(), (s: Scraper) => {
                  ListItem() {
                    Row({ space: 12 }) {
                      Text(s.name)
                        .fontSize(15)
                        .layoutWeight(1)
                      Button('削刮', { type: ButtonType.Capsule })
                        .fontSize(13)
                        .height(32)
                        .enabled(!this.loading)
                        .onClick(() => { this.scrapeFragment(s) })
                    }
                    .width('100%')
                    .padding(12)
                    .backgroundColor('#F7F7F7')
                    .borderRadius(10)
                  }
                }, (s: Scraper) => s.id)
              }
              .width('100%')
              .height(this.fragmentSources().length * 56)
              .scrollBar(BarState.Off)
              if (this.fragmentSources().length === 0) {
                Text('服务端未返回支持片段削刮的本地刮削器').fontSize(13).fontColor('#999999')
              }
            } else if (this.mode === 1) {
              TextInput({ text: this.queryText, placeholder: '输入' + (this.isScene() ? '短片' : (this.isPerformer() ? '演员' : '工作室')) + '名称关键词' })
                .onChange((v: string) => { this.queryText = v })
              List({ space: 8 }) {
                ForEach(this.querySources(), (src: QuerySource, idx: number) => {
                  ListItem() {
                    Row({ space: 12 }) {
                      Text(src.label)
                        .fontSize(15)
                        .layoutWeight(1)
                      Button('削刮', { type: ButtonType.Capsule })
                        .fontSize(13)
                        .height(32)
                        .enabled(!this.loading && this.queryText.trim() !== '')
                        .onClick(() => {
                          if (this.isStudio()) {
                            this.scrapeStudioQuery(src);
                          } else {
                            this.scrapeQuery(src);
                          }
                        })
                    }
                    .width('100%')
                    .padding(12)
                    .backgroundColor('#F7F7F7')
                    .borderRadius(10)
                  }
                }, (src: QuerySource, idx: number) => src.label + idx.toString())
              }
              .width('100%')
              .height(this.querySources().length * 56)
              .scrollBar(BarState.Off)
              if (this.querySources().length === 0) {
                Text('未找到可用削刮源（无 Stash-box 且无本地刮削器）').fontSize(13).fontColor('#999999')
              }
            } else {
              TextInput({ text: this.urlText, placeholder: 'https://example.com/xxx' })
                .onChange((v: string) => { this.urlText = v })
              Button('开始削刮', { type: ButtonType.Capsule })
                .fontSize(15)
                .width('100%')
                .height(40)
                .enabled(!this.loading && this.urlText.trim() !== '')
                .margin({ top: 8 })
                .onClick(() => { this.scrapeURL() })
              Text('需要刮削器支持 URL 类型削刮。').fontSize(12).fontColor('#999999')
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
      } else {
        // ---------- 削刮结果 ----------
        if (this.loading) {
          Column({ space: 12 }) {
            LoadingProgress()
            Text('正在削刮…').fontSize(13)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 10 }) {
              if (this.error !== '') {
                Text(this.error).fontSize(13).fontColor('#D94838')
              }
              List({ space: 8 }) {
                if (this.isScene()) {
                  ForEach(this.sceneResults, (item: ScrapedScene, idx: number) => {
                    ListItem() {
                      Row({ space: 12 }) {
                        Column({ space: 2 }) {
                          Text(this.rowTitle(item)).fontSize(15).fontWeight(FontWeight.Medium)
                          if (this.rowSubtitle(item) !== '') {
                            Text(this.rowSubtitle(item)).fontSize(12).fontColor('#999999')
                          }
                        }
                        .layoutWeight(1)
                        .alignItems(HorizontalAlign.Start)
                        Button('查看', { type: ButtonType.Capsule })
                          .fontSize(13)
                          .height(32)
                          .onClick(() => { this.previewIndex = idx })
                      }
                      .width('100%')
                      .padding(12)
                      .backgroundColor('#F7F7F7')
                      .borderRadius(10)
                    }
                  }, (item: ScrapedScene, idx: number) => idx.toString())
                } else if (this.isPerformer()) {
                  ForEach(this.performerResults, (item: ScrapedPerformer, idx: number) => {
                    ListItem() {
                      Row({ space: 12 }) {
                        Column({ space: 2 }) {
                          Text(this.rowTitle(item)).fontSize(15).fontWeight(FontWeight.Medium)
                          if (this.rowSubtitle(item) !== '') {
                            Text(this.rowSubtitle(item)).fontSize(12).fontColor('#999999')
                          }
                        }
                        .layoutWeight(1)
                        .alignItems(HorizontalAlign.Start)
                        Button('查看', { type: ButtonType.Capsule })
                          .fontSize(13)
                          .height(32)
                          .onClick(() => { this.previewIndex = idx })
                      }
                      .width('100%')
                      .padding(12)
                      .backgroundColor('#F7F7F7')
                      .borderRadius(10)
                    }
                  }, (item: ScrapedPerformer, idx: number) => idx.toString())
                } else {
                  ForEach(this.studioResults, (item: ScrapedStudio, idx: number) => {
                    ListItem() {
                      Row({ space: 12 }) {
                        Column({ space: 2 }) {
                          Text(this.rowTitle(item)).fontSize(15).fontWeight(FontWeight.Medium)
                          if (this.rowSubtitle(item) !== '') {
                            Text(this.rowSubtitle(item)).fontSize(12).fontColor('#999999')
                          }
                        }
                        .layoutWeight(1)
                        .alignItems(HorizontalAlign.Start)
                        Button('查看', { type: ButtonType.Capsule })
                          .fontSize(13)
                          .height(32)
                          .onClick(() => { this.previewIndex = idx })
                      }
                      .width('100%')
                      .padding(12)
                      .backgroundColor('#F7F7F7')
                      .borderRadius(10)
                    }
                  }, (item: ScrapedStudio, idx: number) => idx.toString())
                }
              }
              .width('100%')
              .height((this.isScene() ? this.sceneResults.length : (this.isPerformer() ? this.performerResults.length : this.studioResults.length)) * 62)
              .scrollBar(BarState.Off)
              Button('换削刮器', { type: ButtonType.Normal })
                .fontSize(15)
                .width('100%')
                .height(40)
                .margin({ bottom: 24 })
                .onClick(() => {
                  this.started = false;
                  this.error = '';
                  this.sceneResults = [];
                  this.performerResults = [];
                  this.studioResults = [];
                })
            }
            .width('100%')
            .padding(16)
          }
          .width('100%')
          .height('100%')
          .align(Alignment.Top)
        }
      }
    }
    .title(this.previewIndex >= 0 ? '削刮结果预览' : (this.started ? '削刮结果' : '元数据削刮'))
    .hideTitleBar(false)
    .width('100%')
    .height('100%')
  }

  private rowTitle(item: ScrapedScene | ScrapedPerformer | ScrapedStudio): string {
    if (this.isScene()) {
      const s = item as ScrapedScene;
      return s.title !== undefined && s.title !== '' ? s.title : '（无标题）';
    }
    if (this.isPerformer()) {
      const p = item as ScrapedPerformer;
      return p.name !== undefined && p.name !== '' ? p.name : '（无名称）';
    }
    const st = item as ScrapedStudio;
    return st.name !== undefined && st.name !== '' ? st.name : '（无名称）';
  }

  private rowSubtitle(item: ScrapedScene | ScrapedPerformer | ScrapedStudio): string {
    if (this.isScene()) {
      const s = item as ScrapedScene;
      return s.date !== undefined && s.date !== '' ? s.date : '';
    }
    if (this.isPerformer()) {
      const p = item as ScrapedPerformer;
      const parts: string[] = [];
      if (p.country !== undefined && p.country !== '') {
        parts.push(p.country);
      }
      if (p.birthdate !== undefined && p.birthdate !== '') {
        parts.push(p.birthdate);
      }
      return parts.join(' · ');
    }
    const st = item as ScrapedStudio;
    return st.urls !== undefined && st.urls !== null && st.urls.length > 0 ? st.urls[0] : '';
  }
}
