import router from '@ohos.router';
import { Scene, Performer, Tag, Studio, FindSceneResp } from '../model/Models';
import { makeClient } from '../net/GraphQLClient';
import { StashAPI } from '../net/StashAPI';

// 短片编辑页（鸿蒙官方组件风格）
@Entry
@Component
struct SceneEditPage {
  @State private sceneId: string = '';
  @State private scene: Scene | null = null;
  @State private loading: boolean = true;
  @State private error: string = '';

  @State private title: string = '';
  @State private details: string = '';
  @State private date: string = '';
  @State private rating: number = 0;
  @State private studioId: string = '';
  @State private performerIds: string[] = [];
  @State private tagIds: string[] = [];
  @State private urlsText: string = '';

  @State private studios: Studio[] = [];
  @State private performers: Performer[] = [];
  @State private tags: Tag[] = [];
  @State private saving: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    if (params !== null && params['id'] !== undefined) {
      this.sceneId = params['id'];
    }
    this.load();
  }

  onPageShow(): void {
    // 从新建演员页返回：自动选中新演员
    const created = AppStorage.get<string>('createdPerformer');
    if (created !== undefined && created !== null && created !== '') {
      if (this.performerIds.indexOf(created) < 0) {
        this.performerIds.push(created);
      }
      AppStorage.setOrCreate('createdPerformer', '');
    }
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.error = '';
    try {
      const client = makeClient();
      const q = `
        query FindScene($id: ID!) {
          findScene(id: $id) {
            id title details date rating100 urls
            studio { id name }
            performers { id name }
            tags { id name }
          }
        }`;
      const data = await client.send(q, { 'id': this.sceneId }) as FindSceneResp;
      const s = data.findScene;
      if (s !== undefined && s !== null) {
        this.scene = s;
        this.title = s.title !== undefined ? s.title : '';
        this.details = s.details !== undefined ? s.details : '';
        this.date = s.date !== undefined ? s.date : '';
        this.rating = s.rating100 !== undefined && s.rating100 !== null ? s.rating100 : 0;
        this.studioId = s.studio !== undefined && s.studio !== null ? s.studio.id : '';
        this.performerIds = s.performers !== undefined && s.performers !== null
          ? s.performers.map((p: Performer) => p.id) : [];
        this.tagIds = s.tags !== undefined && s.tags !== null ? s.tags.map((t: Tag) => t.id) : [];
        this.urlsText = s.urls !== undefined && s.urls !== null ? s.urls.join('\n') : '';
      }
      this.studios = await StashAPI.allStudios(client);
      this.performers = await StashAPI.allPerformers(client);
      this.tags = await StashAPI.allTags(client);
    } catch (e) {
      this.error = '加载失败';
    }
    this.loading = false;
  }

  private togglePerformer(id: string): void {
    const idx = this.performerIds.indexOf(id);
    if (idx >= 0) {
      this.performerIds.splice(idx, 1);
    } else {
      this.performerIds.push(id);
    }
  }

  private toggleTag(id: string): void {
    const idx = this.tagIds.indexOf(id);
    if (idx >= 0) {
      this.tagIds.splice(idx, 1);
    } else {
      this.tagIds.push(id);
    }
  }

  private openCreatePerformer(): void {
    router.pushUrl({ url: 'pages/PerformerCreatePage' });
  }

  private async save(): Promise<void> {
    this.saving = true;
    this.error = '';
    try {
      const client = makeClient();
      const input: Record<string, Object> = { 'id': this.sceneId };
      if (this.title.trim() !== '') {
        input['title'] = this.title.trim();
      }
      if (this.details.trim() !== '') {
        input['details'] = this.details.trim();
      }
      if (this.date.trim() !== '') {
        input['date'] = this.date.trim();
      }
      if (this.rating > 0) {
        input['rating100'] = this.rating;
      }
      if (this.studioId !== '') {
        input['studio_id'] = this.studioId;
      }
      input['performer_ids'] = this.performerIds;
      if (this.tagIds.length > 0) {
        input['tag_ids'] = this.tagIds;
      }
      const urls = this.urlsText.split('\n').map((s: string) => s.trim()).filter((s: string) => s !== '');
      if (urls.length > 0) {
        input['urls'] = urls;
      }
      await StashAPI.updateScene(client, input);
      router.back();
    } catch (e) {
      this.error = '保存失败';
    }
    this.saving = false;
  }

  @Builder
  sectionTitle(text: string) {
    Text(text)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .width('100%')
      .margin({ top: 12, bottom: 4 })
  }

  build() {
    Navigation() {
      if (this.loading) {
        Column({ space: 12 }) {
          LoadingProgress()
          Text('加载中…').fontSize(13)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 8 }) {
            // 基本信息
            this.sectionTitle('基本信息')
            TextInput({ text: this.title, placeholder: '标题' })
              .onChange((v: string) => { this.title = v })
            TextInput({ text: this.date, placeholder: '日期（yyyy-MM-dd）' })
              .onChange((v: string) => { this.date = v })
            Row({ space: 12 }) {
              Text('评分').fontSize(15)
              Text(this.rating > 0 ? (this.rating / 20).toFixed(1) + ' / 5.0' : '未评分')
                .fontSize(13)
                .fontColor('#666666')
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            Slider({ value: this.rating, min: 0, max: 100, step: 5 })
              .onChange((v: number) => { this.rating = v })

            // 工作室
            this.sectionTitle('工作室')
            Select(this.studioOptions())
              .selected(this.studioIndex())
              .value(this.studioValue())
              .onSelect((idx: number) => {
                this.studioId = idx <= 0 ? '' : this.studios[idx - 1].id;
              })

            // 演员（多选 + 新建入口）
            this.sectionTitle('演员')
            List({ space: 2 }) {
              ForEach(this.performers, (p: Performer) => {
                ListItem() {
                  Row({ space: 10 }) {
                    Checkbox()
                      .select(this.performerIds.indexOf(p.id) >= 0)
                      .onChange((v: boolean) => { this.togglePerformer(p.id) })
                    Text(p.name).fontSize(15)
                  }
                  .width('100%')
                  .height(44)
                }
              }, (p: Performer) => p.id)
            }
            .height(Math.min(this.performers.length * 46, 220))
            .width('100%')
            Button('新建演员', { type: ButtonType.Normal })
              .fontSize(14)
              .width('100%')
              .onClick(() => { this.openCreatePerformer() })

            // URL（每行一个）
            this.sectionTitle('URL（每行一个）')
            TextArea({ text: this.urlsText, placeholder: 'https://…' })
              .height(72)
              .width('100%')
              .onChange((v: string) => { this.urlsText = v })

            // 标签
            this.sectionTitle('标签')
            List({ space: 2 }) {
              ForEach(this.tags, (t: Tag) => {
                ListItem() {
                  Row({ space: 10 }) {
                    Checkbox()
                      .select(this.tagIds.indexOf(t.id) >= 0)
                      .onChange((v: boolean) => { this.toggleTag(t.id) })
                    Text(t.name).fontSize(15)
                  }
                  .width('100%')
                  .height(44)
                }
              }, (t: Tag) => t.id)
            }
            .height(Math.min(this.tags.length * 46, 220))
            .width('100%')

            // 简介
            this.sectionTitle('简介')
            TextArea({ text: this.details, placeholder: '简介…' })
              .height(120)
              .width('100%')
              .onChange((v: string) => { this.details = v })

            if (this.error !== '') {
              Text(this.error).fontSize(13).fontColor('#D94838')
            }
            Button(this.saving ? '保存中…' : '保存', { type: ButtonType.Capsule })
              .fontSize(16)
              .width('100%')
              .height(44)
              .enabled(!this.saving)
              .margin({ top: 12, bottom: 24 })
              .onClick(() => { this.save() })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
      }
    }
    .title('编辑短片')
    .hideTitleBar(false)
    .width('100%')
    .height('100%')
  }

  private studioOptions(): SelectOption[] {
    const opts: SelectOption[] = [{ value: '无' }];
    for (const s of this.studios) {
      opts.push({ value: s.name });
    }
    return opts;
  }

  private studioIndex(): number {
    if (this.studioId === '') {
      return 0;
    }
    const idx = this.studios.findIndex((s: Studio) => s.id === this.studioId);
    return idx < 0 ? 0 : idx + 1;
  }

  private studioValue(): string {
    if (this.studioId === '') {
      return '无';
    }
    const s = this.studios.find((it: Studio) => it.id === this.studioId);
    return s !== undefined ? s.name : '无';
  }
}
