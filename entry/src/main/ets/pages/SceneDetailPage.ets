import router from '@ohos.router';
import { Scene, Performer, Tag, FindSceneResp, rewriteImage } from '../model/Models';
import { makeClient } from '../net/GraphQLClient';
import { AppSettings } from '../net/AppSettings';
import { StashAPI } from '../net/StashAPI';

// 短片详情页（鸿蒙官方组件风格）
@Entry
@Component
struct SceneDetailPage {
  @State private sceneId: string = '';
  @State private scene: Scene | null = null;
  @State private loading: boolean = true;
  @State private error: string = '';
  @State private loadFailed: boolean = false;
  @State private favBusy: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    if (params !== null && params['id'] !== undefined) {
      this.sceneId = params['id'];
    }
  }

  onPageShow(): void {
    this.load();
  }

  private async load(): Promise<void> {
    if (this.sceneId === '') {
      return;
    }
    this.loading = true;
    this.error = '';
    try {
      const client = makeClient();
      const q = `
        query FindScene($id: ID!) {
          findScene(id: $id) {
            id title details date rating100 o_counter organized
            urls
            studio { id name }
            performers { id name image_path birthdate details }
            tags { id name }
            paths { screenshot webp }
            files { path }
          }
        }`;
      const data = await client.send(q, { 'id': this.sceneId }) as FindSceneResp;
      const s = data.findScene;
      if (s !== undefined && s !== null) {
        this.scene = s;
      }
    } catch (e) {
      const ge = e as Error;
      this.error = ge !== null ? ge.message : '加载失败';
    }
    this.loading = false;
  }

  private get imageUrl(): string {
    const s = this.scene;
    if (s === null || s.paths === undefined || s.paths === null) {
      return '';
    }
    const raw = s.paths.screenshot !== undefined ? s.paths.screenshot : s.paths.webp;
    if (raw === undefined || raw === null || raw === '') {
      return '';
    }
    return rewriteImage(raw, AppSettings.instance.activeBaseURL());
  }

  private async toggleFavorite(): Promise<void> {
    if (this.scene === null || this.favBusy) {
      return;
    }
    this.favBusy = true;
    try {
      const client = makeClient();
      const target = !(this.scene.organized === true);
      await StashAPI.updateScene(client, { 'id': this.sceneId, 'organized': target });
      this.scene.organized = target;
    } catch (e) {
      // 忽略失败
    }
    this.favBusy = false;
  }

  private openEdit(): void {
    router.pushUrl({ url: 'pages/SceneEditPage', params: { 'id': this.sceneId } });
  }

  private openScrape(): void {
    const title = this.scene !== null && this.scene.title !== undefined ? this.scene.title : '';
    router.pushUrl({
      url: 'pages/ScrapePage',
      params: { 'kind': 'scene', 'id': this.sceneId, 'title': title }
    });
  }

  private openMerge(): void {
    const title = this.scene !== null && this.scene.title !== undefined ? this.scene.title : '';
    router.pushUrl({
      url: 'pages/MergePage',
      params: { 'id': this.sceneId, 'title': title }
    });
  }

  private openPerformer(id: string): void {
    router.pushUrl({ url: 'pages/PerformerDetailPage', params: { 'id': id } });
  }

  @Builder
  sectionTitle(text: string) {
    Text(text)
      .fontSize(15)
      .fontWeight(FontWeight.Medium)
      .width('100%')
      .margin({ top: 16, bottom: 6 })
  }

  @Builder
  chip(name: string, isPerformer: boolean, id: string) {
    Text(name)
      .fontSize(14)
      .fontColor(isPerformer ? '#1E5EFF' : '#8A5A00')
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .backgroundColor(isPerformer ? '#EDF1FF' : '#FFF4E0')
      .borderRadius(16)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        if (isPerformer) {
          this.openPerformer(id);
        }
      })
  }

  build() {
    Navigation() {
      if (this.loading) {
        Column({ space: 10 }) {
          LoadingProgress().width(40).height(40)
          Text('加载中…').fontSize(13)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.scene === null) {
        Column({ space: 10 }) {
          Text(this.error !== '' ? this.error : '加载失败').fontSize(14)
          Button('重试', { type: ButtonType.Capsule })
            .fontSize(13)
            .height(34)
            .onClick(() => { this.load() })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 10 }) {
            // 封面
            Stack({ alignContent: Alignment.BottomEnd }) {
              if (this.imageUrl !== '' && !this.loadFailed) {
                Image(this.imageUrl)
                  .objectFit(ImageFit.Contain)
                  .width('100%')
                  .aspectRatio(16 / 9)
                  .backgroundColor('#F2F2F2')
                  .borderRadius(12)
                  .onError(() => { this.loadFailed = true })
              } else {
                Column() {
                  Text('无封面').fontSize(13).fontColor('#999999')
                }
                .width('100%')
                .aspectRatio(16 / 9)
                .justifyContent(FlexAlign.Center)
                .backgroundColor('#F2F2F2')
                .borderRadius(12)
              }
              // 收藏按钮
              Button({ type: ButtonType.Circle, stateEffect: true }) {
                Text(this.scene.organized === true ? '★' : '☆')
                  .fontSize(18)
                  .fontColor(this.scene.organized === true ? '#FF9500' : '#666666')
              }
              .width(44)
              .height(44)
              .backgroundColor('#FFFFFF99')
              .margin(12)
              .onClick(() => { this.toggleFavorite() })
            }
            .width('100%')
            .clip(true)
            .borderRadius(12)

            // 标题
            Text(this.scene.title !== undefined && this.scene.title !== '' ? this.scene.title : '（无标题）')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .width('100%')
              .margin({ top: 6 })

            // 操作行
            Row({ space: 10 }) {
              Button('编辑', { type: ButtonType.Normal })
                .fontSize(14)
                .layoutWeight(1)
                .onClick(() => { this.openEdit() })
              Button('削刮', { type: ButtonType.Normal })
                .fontSize(14)
                .layoutWeight(1)
                .onClick(() => { this.openScrape() })
              Button('合并', { type: ButtonType.Normal })
                .fontSize(14)
                .layoutWeight(1)
                .onClick(() => { this.openMerge() })
            }
            .width('100%')

            // 基本信息
            this.sectionTitle('基本信息')
            Column({ space: 6 }) {
              if (this.scene.date !== undefined && this.scene.date !== null && this.scene.date !== '') {
                this.infoRow('日期', this.scene.date)
              }
              if (this.scene.rating100 !== undefined && this.scene.rating100 !== null && this.scene.rating100 > 0) {
                this.infoRow('评分', (this.scene.rating100 / 20).toFixed(1) + ' / 5.0')
              }
              if (this.scene.o_counter !== undefined && this.scene.o_counter !== null) {
                this.infoRow('O 计数', this.scene.o_counter.toString())
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            // 工作室（基本信息下面）
            if (this.scene.studio !== undefined && this.scene.studio !== null) {
              this.sectionTitle('工作室')
              Text(this.scene.studio.name)
                .fontSize(14)
                .fontColor('#1E5EFF')
                .width('100%')
            }

            // 演员（基本信息下面，url 前面）
            if (this.scene.performers !== undefined && this.scene.performers !== null && this.scene.performers.length > 0) {
              this.sectionTitle('演员（' + this.scene.performers.length.toString() + '）')
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.scene.performers, (p: Performer) => {
                  this.chip(p.name, true, p.id)
                }, (p: Performer) => p.id)
              }
              .width('100%')
            }

            // URL（演员后面）
            if (this.scene.urls !== undefined && this.scene.urls !== null && this.scene.urls.length > 0) {
              this.sectionTitle('URL')
              Column({ space: 4 }) {
                ForEach(this.scene.urls, (u: string) => {
                  Text(u)
                    .fontSize(13)
                    .fontColor('#1E5EFF')
                    .width('100%')
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }, (u: string) => u)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }

            // 标签
            if (this.scene.tags !== undefined && this.scene.tags !== null && this.scene.tags.length > 0) {
              this.sectionTitle('标签（' + this.scene.tags.length.toString() + '）')
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.scene.tags, (t: Tag) => {
                  this.chip(t.name, false, '')
                }, (t: Tag) => t.id)
              }
              .width('100%')
            }

            // 简介（最后）
            if (this.scene.details !== undefined && this.scene.details !== null && this.scene.details !== '') {
              this.sectionTitle('简介')
              Text(this.scene.details)
                .fontSize(14)
                .lineHeight(22)
                .width('100%')
            }
          }
          .width('100%')
          .padding(16)
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
      }
    }
    .title(this.scene !== null && this.scene.title !== undefined && this.scene.title !== '' ? this.scene.title : '短片详情')
    .hideTitleBar(false)
    .menus([
      { value: '编辑', action: () => { this.openEdit() } },
      { value: '削刮', action: () => { this.openScrape() } },
      { value: '合并', action: () => { this.openMerge() } }
    ])
    .width('100%')
    .height('100%')
  }

  @Builder
  private infoRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(14).fontColor('#666666').width(72)
      Text(value).fontSize(14).layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
}
