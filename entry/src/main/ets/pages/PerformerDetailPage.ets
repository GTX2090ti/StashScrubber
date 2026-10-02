import router from '@ohos.router';
import { Performer, Tag, FindPerformerResp, rewriteImage } from '../model/Models';
import { makeClient } from '../net/GraphQLClient';
import { AppSettings } from '../net/AppSettings';

// 演员详情页（鸿蒙官方组件风格）
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
  }

  onPageShow(): void {
    this.load();
  }

  private async load(): Promise<void> {
    if (this.performerId === '') {
      return;
    }
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

  private openEdit(): void {
    router.pushUrl({ url: 'pages/PerformerEditPage', params: { 'id': this.performerId } });
  }

  private openScrape(): void {
    const name = this.performer !== null && this.performer.name !== undefined ? this.performer.name : '';
    router.pushUrl({
      url: 'pages/ScrapePage',
      params: { 'kind': 'performer', 'id': this.performerId, 'title': name }
    });
  }

  @Builder
  sectionTitle(text: string) {
    Text(text)
      .fontSize(15)
      .fontWeight(FontWeight.Medium)
      .width('100%')
      .margin({ top: 16, bottom: 6 })
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
      } else if (this.performer === null) {
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
            // 头像
            Stack() {
              if (this.avatarUrl !== '' && !this.loadFailed) {
                Image(this.avatarUrl)
                  .objectFit(ImageFit.Cover)
                  .width(160)
                  .height(160)
                  .borderRadius(80)
                  .onError(() => { this.loadFailed = true })
              } else {
                Text(this.performer.name.length > 0 ? this.performer.name.substring(0, 1) : '?')
                  .fontSize(56)
                  .fontColor('#999999')
                  .width(160)
                  .height(160)
                  .textAlign(TextAlign.Center)
                  .backgroundColor('#F2F2F2')
                  .borderRadius(80)
              }
            }
            .width('100%')
            .alignContent(Alignment.Center)
            .margin({ top: 8 })

            Text(this.performer.name)
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .width('100%')
              .textAlign(TextAlign.Center)

            if (this.performer.disambiguation !== undefined && this.performer.disambiguation !== '') {
              Text(this.performer.disambiguation)
                .fontSize(13)
                .fontColor('#666666')
                .width('100%')
                .textAlign(TextAlign.Center)
            }

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
            }
            .width('100%')
            .margin({ top: 10 })

            // 基本信息
            this.sectionTitle('基本信息')
            Column({ space: 6 }) {
              if (this.performer.birthdate !== undefined && this.performer.birthdate !== '') {
                this.infoRow('出生日期', this.performer.birthdate)
              }
              if (this.performer.country !== undefined && this.performer.country !== '') {
                this.infoRow('国家', this.performer.country)
              }
              if (this.performer.ethnicity !== undefined && this.performer.ethnicity !== '') {
                this.infoRow('族裔', this.performer.ethnicity)
              }
              if (this.performer.measurements !== undefined && this.performer.measurements !== '') {
                this.infoRow('三围', this.performer.measurements)
              }
              if (this.performer.career_length !== undefined && this.performer.career_length !== '') {
                this.infoRow('从业年限', this.performer.career_length)
              }
              if (this.performer.rating100 !== undefined && this.performer.rating100 !== null && this.performer.rating100 > 0) {
                this.infoRow('评分', (this.performer.rating100 / 20).toFixed(1) + ' / 5.0')
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            // 标签
            if (this.performer.tags !== undefined && this.performer.tags !== null && this.performer.tags.length > 0) {
              this.sectionTitle('标签（' + this.performer.tags.length.toString() + '）')
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.performer.tags, (t: Tag) => {
                  Text(t.name)
                    .fontSize(14)
                    .fontColor('#8A5A00')
                    .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                    .backgroundColor('#FFF4E0')
                    .borderRadius(16)
                    .margin({ right: 8, bottom: 8 })
                }, (t: Tag) => t.id)
              }
              .width('100%')
            }

            // 简介（最后）
            if (this.performer.details !== undefined && this.performer.details !== null && this.performer.details !== '') {
              this.sectionTitle('简介')
              Text(this.performer.details)
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
    .title(this.performer !== null && this.performer.name !== undefined ? this.performer.name : '演员详情')
    .hideTitleBar(false)
    .menus([
      { value: '编辑', action: () => { this.openEdit() } },
      { value: '削刮', action: () => { this.openScrape() } }
    ])
    .width('100%')
    .height('100%')
  }

  @Builder
  private infoRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(14).fontColor('#666666').width(84)
      Text(value).fontSize(14).layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
}
