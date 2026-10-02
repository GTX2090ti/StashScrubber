import router from '@ohos.router';
import { Tag, FindTagResp } from '../model/Models';
import { makeClient } from '../net/GraphQLClient';

// 标签详情页（基础版：标签信息；后续轮加该标签下的短片列表）
@Entry
@Component
struct TagDetailPage {
  @State private tagId: string = '';
  @State private tag: Tag | null = null;
  @State private loading: boolean = true;
  @State private error: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    if (params !== null && params['id'] !== undefined) {
      this.tagId = params['id'];
    }
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.error = '';
    try {
      const client = makeClient();
      const q = `
        query FindTag($id: ID!) {
          findTag(id: $id) { id name }
        }`;
      const data = await client.send(q, { 'id': this.tagId }) as FindTagResp;
      const t = data.findTag;
      this.tag = t !== undefined && t !== null ? t : null;
    } catch (e) {
      const ge = e as Error;
      this.error = ge !== null ? ge.message : '加载失败';
    }
    this.loading = false;
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
      } else if (this.tag === null) {
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
        Column({ space: 12 }) {
          Text('#' + this.tag.name)
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FCD34D')
            .margin({ top: 40 })
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0B0B0F')
  }
}
