import router from '@ohos.router';
import { Performer, Tag, FindPerformerResp, rewriteImage } from '../model/Models';
import { makeClient } from '../net/GraphQLClient';
import { AppSettings } from '../net/AppSettings';

// 演员详情页
@Entry
@Component
struct PerformerDetailPage {
  @State private performerId: string = '';
  @State private performer: Performer | null = null;
  @State private loading: boolean = true;
  @State private error: string = '';
  @State private loadFailed: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    if (params !== null && params['id'] !== undefined) {
      this.performerId = params['id'];
    }
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.error = '';
    try {
      const client = makeClient();
      const q = `
        query FindPerformer($id: ID!) {
          findPerformer(id: $id) {
            id name disambiguation image_path birthdate country ethnicity
            measurements career_length details rating100
            tags { id name }
          }
        }`;
      const data = await client.send(q, { 'id': this.performerId }) as FindPerformerResp;
      const p = data.findPerformer;
      if (p !== undefined && p !== null) {
        this.performer = p;
      }
    } catch (e) {
      const ge = e as Error;
      this.error = ge !== null ? ge.message : '加载失败';
    }
    this.loading = false;
  }

  private get avatarUrl(): string {
    const p = this.performer;
    if (p === null || p.image_path === undefined || p.image_path === null || p.image_path === '') {
      return '';
    }
    return rewriteImage(p.image_path, AppSettings.instance.activeBaseURL());
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
      } else if (this.performer === null) {
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
            // 头像
            Stack() {
              if (this.avatarUrl !== '' && !this.loadFailed) {
                Image(this.avatarUrl)
                  .objectFit(ImageFit.Cover)
                  .width(160)
                  .height(160)
                  .borderRadius(80)
                  .onError(() => {
                    this.loadFailed = true;
                  })
              } else {
                Text(this.performer.name.substring(0, 1))
                  .fontSize(56)
                  .fontColor('#9CA3AF')
                  .width(160)
                  .height(160)
                  .textAlign(TextAlign.Center)
                  .backgroundColor('#16161E')
                  .borderRadius(80)
              }
            }
            .width('100%')
            .alignContent(Alignment.Center)

            Text(this.performer.name)
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor('#F9FAFB')
              .width('100%')
              .textAlign(TextAlign.Center)

            if (this.performer.disambiguation !== undefined && this.performer.disambiguation !== '') {
              Text(this.performer.disambiguation)
                .fontSize(13)
                .fontColor('#9CA3AF')
                .width('100%')
                .textAlign(TextAlign.Center)
            }

            // 基本信息
            Column({ space: 8 }) {
              if (this.performer.birthdate !== undefined && this.performer.birthdate !== '') {
                this.infoRow('出生日期', this.performer.birthdate)
              }
              if (this.performer.country !== undefined && this.performer.country !== '') {
                this.infoRow('国家', this.performer.country)
              }
              if (this.performer.ethnicity !== undefined && this.performer.ethnicity !== '') {
                this.infoRow('种族', this.performer.ethnicity)
              }
              if (this.performer.measurements !== undefined && this.performer.measurements !== '') {
                this.infoRow('三围', this.performer.measurements)
              }
              if (this.performer.career_length !== undefined && this.performer.career_length !== '') {
                this.infoRow('从业年限', this.performer.career_length)
              }
              if (this.performer.rating100 !== undefined && this.performer.rating100 !== null && this.performer.rating100 > 0) {
                this.infoRow('评分', (this.performer.rating100 / 20).toFixed(1) + ' ★')
              }
            }
            .width('100%')
            .padding(14)
            .backgroundColor('#131318')
            .borderRadius(12)

            // 标签
            if (this.performer.tags !== undefined && this.performer.tags !== null && this.performer.tags.length > 0) {
              Column({ space: 8 }) {
                Text('标签（' + this.performer.tags.length + '）')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#E5E7EB')
                  .width('100%')
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.performer.tags, (t: Tag) => {
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

            // 简介（最后）
            if (this.performer.details !== undefined && this.performer.details !== null && this.performer.details !== '') {
              Column({ space: 8 }) {
                Text('简介')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#E5E7EB')
                  .width('100%')
                Text(this.performer.details)
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
        .width(84)
      Text(value)
        .fontSize(14)
        .fontColor('#E5E7EB')
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
}
