import router from '@ohos.router';
import { Tag, Scene, FindTagResp, FindScenesResp, rewriteImage } from '../model/Models';
import { makeClient } from '../net/GraphQLClient';
import { AppSettings } from '../net/AppSettings';

// 标签详情页：标签信息 + 该标签下的短片列表（翻页）
@Entry
@Component
struct TagDetailPage {
  @State private tagId: string = '';
  @State private tagName: string = '';
  @State private tag: Tag | null = null;
  @State private loading: boolean = true;
  @State private error: string = '';

  @State private scenes: Scene[] = [];
  @State private total: number = 0;
  @State private currentPage: number = 1;
  @State private listLoading: boolean = false;

  private perPage: number = 120;

  private get totalPages(): number {
    if (this.total <= 0) {
      return 1;
    }
    return Math.ceil(this.total / this.perPage);
  }

  private get canPrev(): boolean {
    return this.currentPage > 1;
  }

  private get canNext(): boolean {
    return this.currentPage < this.totalPages;
  }

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
      const q = `query FindTag($id: ID!) { findTag(id: $id) { id name } }`;
      const data = await client.send(q, { 'id': this.tagId }) as FindTagResp;
      const t = data.findTag;
      this.tag = t !== undefined && t !== null ? t : null;
      if (this.tag !== null) {
        this.tagName = this.tag.name;
      }
      await this.goToPage(1);
    } catch (e) {
      const ge = e as Error;
      this.error = ge !== null ? ge.message : '加载失败';
    }
    this.loading = false;
  }

  private async goToPage(page: number): Promise<void> {
    this.listLoading = true;
    try {
      const client = makeClient();
      const q = `
        query FindScenes($filter: FindFilterType!, $sf: SceneFilterType) {
          findScenes(filter: $filter, scene_filter: $sf) {
            count
            scenes {
              id title date rating100 organized
              studio { id name }
              performers { id name }
              paths { screenshot webp }
            }
          }
        }`;
      const filter: Record<string, Object> = {
        'page': page,
        'per_page': this.perPage,
        'sort': 'date',
        'direction': 'DESC'
      };
      const tagIds: string[] = [this.tagId];
      const tagFilter: Record<string, Object> = { 'value': tagIds, 'modifier': 'INCLUDES_ALL', 'depth': -1 };
      const sf: Record<string, Object> = {
        'tags': tagFilter
      };
      const data = await client.send(q, { 'filter': filter, 'sf': sf }) as FindScenesResp;
      const fs = data.findScenes;
      if (fs !== undefined && fs !== null) {
        this.scenes = fs.scenes !== undefined ? fs.scenes : [];
        this.total = fs.count !== undefined ? fs.count : 0;
      }
      this.currentPage = page;
    } catch (e) {
      // 列表加载失败不阻塞
    }
    this.listLoading = false;
  }

  private openScene(id: string): void {
    router.pushUrl({ url: 'pages/SceneDetailPage', params: { 'id': id } });
  }

  private imageUrl(s: Scene): string {
    if (s.paths === undefined || s.paths === null) {
      return '';
    }
    const raw = s.paths.screenshot !== undefined ? s.paths.screenshot : s.paths.webp;
    if (raw === undefined || raw === null || raw === '') {
      return '';
    }
    return rewriteImage(raw, AppSettings.instance.activeBaseURL());
  }

  @Builder
  private pageBar() {
    Row() {
      Button('上一页', { type: ButtonType.Normal })
        .fontSize(13)
        .height(34)
        .enabled(this.canPrev && !this.listLoading)
        .onClick(() => { this.goToPage(this.currentPage - 1) })
      Blank()
      Text('第 ' + this.currentPage + ' / ' + this.totalPages + ' 页（共 ' + this.total + '）')
        .fontSize(12)
        .fontColor('#666666')
      Blank()
      Button('下一页', { type: ButtonType.Normal })
        .fontSize(13)
        .height(34)
        .enabled(this.canNext && !this.listLoading)
        .onClick(() => { this.goToPage(this.currentPage + 1) })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
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
      } else if (this.tag === null) {
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
        Column() {
          Text('#' + this.tagName + '（' + this.total.toString() + ' 个短片）')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .width('100%')
            .padding({ left: 16, top: 10 })
          this.pageBar()
          if (this.listLoading && this.scenes.length === 0) {
            Column({ space: 10 }) {
              LoadingProgress().width(40).height(40)
              Text('加载中…').fontSize(13).fontColor('#666666')
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.scenes.length === 0) {
            Column({ space: 10 }) {
              Text('该标签下没有短片').fontSize(14).fontColor('#666666')
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            Scroll() {
              Grid() {
                ForEach(this.scenes, (s: Scene) => {
                  GridItem() {
                    Column({ space: 4 }) {
                      if (this.imageUrl(s) !== '') {
                        Image(this.imageUrl(s))
                          .objectFit(ImageFit.Cover)
                          .width('100%')
                          .aspectRatio(16 / 9)
                          .borderRadius(8)
                          .backgroundColor('#F2F2F2')
                      } else {
                        Column()
                          .width('100%')
                          .aspectRatio(16 / 9)
                          .borderRadius(8)
                          .backgroundColor('#F2F2F2')
                      }
                      Text(s.title !== undefined && s.title !== '' ? s.title : '（无标题）')
                        .fontSize(11)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                    }
                    .width('100%')
                    .onClick(() => { this.openScene(s.id) })
                  }
                }, (s: Scene) => s.id)
              }
              .columnsTemplate('1fr 1fr 1fr')
              .columnsGap(12)
              .rowsGap(14)
              .width('100%')
              .padding({ left: 12, right: 12 })
            }
            .layoutWeight(1)
            .scrollBar(BarState.Off)
          }
          this.pageBar()
        }
        .width('100%')
        .height('100%')
      }
    }
    .title('#' + this.tagName)
    .hideTitleBar(false)
    .width('100%')
    .height('100%')
  }
}
