import router from '@ohos.router';
import { Studio, FindStudioResp, rewriteImage } from '../model/Models';
import { makeClient } from '../net/GraphQLClient';
import { AppSettings } from '../net/AppSettings';

// 工作室详情页
@Entry
@Component
struct StudioDetailPage {
  @State private studioId: string = '';
  @State private studio: Studio | null = null;
  @State private loading: boolean = true;
  @State private error: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    if (params !== null && params['id'] !== undefined) {
      this.studioId = params['id'];
    }
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.error = '';
    try {
      const client = makeClient();
      const q = `
        query FindStudio($id: ID!) {
          findStudio(id: $id) { id name image_path rating100 scene_count }
        }`;
      const data = await client.send(q, { 'id': this.studioId }) as FindStudioResp;
      const st = data.findStudio;
      if (st !== undefined && st !== null) {
        this.studio = st;
      }
    } catch (e) {
      const ge = e as Error;
      this.error = ge !== null ? ge.message : '加载失败';
    }
    this.loading = false;
  }

  private get imageUrl(): string {
    const s = this.studio;
    if (s === null || s.image_path === undefined || s.image_path === null || s.image_path === '') {
      return '';
    }
    return rewriteImage(s.image_path, AppSettings.instance.activeBaseURL());
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
      } else if (this.studio === null) {
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
            // 图标
            Stack() {
              if (this.imageUrl !== '') {
                Image(this.imageUrl)
                  .objectFit(ImageFit.Cover)
                  .width(120)
                  .height(120)
                  .borderRadius(60)
              } else {
                Text('🏢')
                  .fontSize(52)
                  .width(120)
                  .height(120)
                  .textAlign(TextAlign.Center)
                  .backgroundColor('#16161E')
                  .borderRadius(60)
              }
            }
            .width('100%')
            .alignContent(Alignment.Center)

            Text(this.studio.name)
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor('#F9FAFB')
              .width('100%')
              .textAlign(TextAlign.Center)

            if (this.studio.scene_count !== undefined && this.studio.scene_count !== null) {
              Text('短片数：' + this.studio.scene_count.toString())
                .fontSize(13)
                .fontColor('#9CA3AF')
                .width('100%')
                .textAlign(TextAlign.Center)
            }
            if (this.studio.rating100 !== undefined && this.studio.rating100 !== null && this.studio.rating100 > 0) {
              Text('评分：' + (this.studio.rating100 / 20).toFixed(1) + ' ★')
                .fontSize(13)
                .fontColor('#9CA3AF')
                .width('100%')
                .textAlign(TextAlign.Center)
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
}
