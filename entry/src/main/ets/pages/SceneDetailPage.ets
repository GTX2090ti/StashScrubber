import router from '@ohos.router';
import { Scene, Performer, Tag, FindSceneResp, rewriteImage } from '../model/Models';
import { makeClient } from '../net/GraphQLClient';
import { AppSettings } from '../net/AppSettings';

// 短片详情页
@Entry
@Component
struct SceneDetailPage {
  @State private sceneId: string = '';
  @State private scene: Scene | null = null;
  @State private loading: boolean = true;
  @State private error: string = '';
  @State private loadFailed: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    if (params !== null && params['id'] !== undefined) {
      this.sceneId = params['id'];
    }
    this.load();
  }

  private async load(): Promise<void> {
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

  build() {
    Column() {
      if (this.loading) {
        Column({ space: 10 }) {
          LoadingProgress().width(40).height(40).color('#3B82F6')
          Text('加载中…').fontSize(13).fontColor('#9CA3AF')
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.scene === null) {
        Column({ space: 10 }) {
          Text(this.error !== '' ? this.error : '加载失败')
            .fontSize(14)
            .fontColor('#F87171')
          Button('重试')
            .fontSize(13)
            .height(34)
            .fontColor('#FFFFFF')
            .backgroundColor('#3B82F6')
            .borderRadius(8)
            .onClick(() => {
              this.load();
            })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 14 }) {
            // 封面
            Stack() {
              if (this.imageUrl !== '' && !this.loadFailed) {
                Image(this.imageUrl)
                  .objectFit(ImageFit.Contain)
                  .width('100%')
                  .aspectRatio(16 / 9)
                  .onError(() => {
                    this.loadFailed = true;
                  })
              } else {
                Column() {
                  Text('无封面')
                    .fontSize(13)
                    .fontColor('#6B7280')
                }
                .width('100%')
                .aspectRatio(16 / 9)
                .justifyContent(FlexAlign.Center)
                .backgroundColor('#16161E')
              }
              if (this.scene.organized === true) {
                Text('★ 已收藏')
                  .fontSize(12)
                  .fontColor('#F59E0B')
                  .padding(6)
                  .backgroundColor('#00000088')
                  .borderRadius(8)
                  .position({ x: '76%', y: 8 })
              }
            }
            .width('100%')
            .clip(true)
            .borderRadius(12)
            .backgroundColor('#16161E')

            // 标题
            Text(this.scene.title !== undefined && this.scene.title !== '' ? this.scene.title : '（无标题）')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#F9FAFB')
              .width('100%')

            // 信息行
            if (this.scene.studio !== undefined && this.scene.studio !== null) {
              this.infoRow('工作室', this.scene.studio.name)
            }
            if (this.scene.date !== undefined && this.scene.date !== null && this.scene.date !== '') {
              this.infoRow('日期', this.scene.date)
            }
            if (this.scene.rating100 !== undefined && this.scene.rating100 !== null && this.scene.rating100 > 0) {
              this.infoRow('评分', (this.scene.rating100 / 20).toFixed(1) + ' ★')
            }
            if (this.scene.o_counter !== undefined && this.scene.o_counter !== null) {
              this.infoRow('O 计数', this.scene.o_counter.toString())
            }

            // 演员
            if (this.scene.performers !== undefined && this.scene.performers !== null && this.scene.performers.length > 0) {
              Column({ space: 8 }) {
                Text('演员（' + this.scene.performers.length + '）')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#E5E7EB')
                  .width('100%')
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.scene.performers, (p: Performer) => {
                    Text(p.name)
                      .fontSize(13)
                      .fontColor('#93C5FD')
                      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                      .backgroundColor('#1E3A5F')
                      .borderRadius(14)
                      .margin({ right: 8, bottom: 8 })
                  }, (p: Performer) => p.id)
                }
                .width('100%')
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }

            // 标签
            if (this.scene.tags !== undefined && this.scene.tags !== null && this.scene.tags.length > 0) {
              Column({ space: 8 }) {
                Text('标签（' + this.scene.tags.length + '）')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#E5E7EB')
                  .width('100%')
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.scene.tags, (t: Tag) => {
                    Text(t.name)
                      .fontSize(13)
                      .fontColor('#FCD34D')
                      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                      .backgroundColor('#3F3A1E')
                      .borderRadius(14)
                      .margin({ right: 8, bottom: 8 })
                  }, (t: Tag) => t.id)
                }
                .width('100%')
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }

            // 简介（放最后）
            if (this.scene.details !== undefined && this.scene.details !== null && this.scene.details !== '') {
              Column({ space: 8 }) {
                Text('简介')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#E5E7EB')
                  .width('100%')
                Text(this.scene.details)
                  .fontSize(13)
                  .fontColor('#9CA3AF')
                  .lineHeight(20)
                  .width('100%')
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
          }
          .width('100%')
          .padding(16)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0B0B0F')
  }

  @Builder
  private infoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor('#9CA3AF')
        .width(72)
      Text(value)
        .fontSize(14)
        .fontColor('#E5E7EB')
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
}
