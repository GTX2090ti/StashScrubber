import { Scene, rewriteImage } from '../model/Models';

// 短片卡片（鸿蒙官方风格：浅底占位 + 系统文字色）
@Component
export struct SceneCard {
  @Prop scene: Scene;
  @Prop base: string;
  @State private loadFailed: boolean = false;

  private get imageUrl(): string {
    const p = this.scene.paths;
    if (p === undefined || p === null) {
      return '';
    }
    const raw = p.screenshot !== undefined ? p.screenshot : p.webp;
    if (raw === undefined || raw === null || raw === '') {
      return '';
    }
    return rewriteImage(raw, this.base);
  }

  build() {
    Column({ space: 6 }) {
      // 海报区（2:3 竖版）
      Stack() {
        if (this.imageUrl !== '' && !this.loadFailed) {
          Image(this.imageUrl)
            .objectFit(ImageFit.Cover)
            .width('100%')
            .height('100%')
            .onError(() => {
              this.loadFailed = true;
            })
        } else {
          Column() {
            Text('无封面')
              .fontSize(11)
              .fontColor('#999999')
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#F2F2F2')
        }
        // 收藏角标
        if (this.scene.organized === true) {
          Text('★')
            .fontSize(14)
            .fontColor('#FF9500')
            .padding(4)
            .backgroundColor('#66FFFFFF')
            .borderRadius(8)
            .position({ x: '78%', y: 4 })
        }
        // 评分角标
        if (this.scene.rating100 !== undefined && this.scene.rating100 !== null && this.scene.rating100 > 0) {
          Text((this.scene.rating100 / 20).toFixed(0) + '★')
            .fontSize(11)
            .fontColor('#FFFFFF')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('#88000000')
            .borderRadius(6)
            .position({ x: 4, y: 4 })
        }
      }
      .width('100%')
      .aspectRatio(2 / 3)
      .clip(true)
      .borderRadius(10)
      .backgroundColor('#F2F2F2')

      // 标题
      Text(this.scene.title !== undefined && this.scene.title !== '' ? this.scene.title : '（无标题）')
        .fontSize(12)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
