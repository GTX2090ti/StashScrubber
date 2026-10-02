import router from '@ohos.router';
import { Scene, ScenePage, FindScenesResp, rewriteImage } from '../model/Models';
import { GraphQLClient, makeClient } from '../net/GraphQLClient';
import { AppSettings } from '../net/AppSettings';
import { SceneCard } from '../common/SceneCard';

// 短片列表页：120 个/页 + 翻页栏（顶部/底部）+ 搜索 + 排序
@Component
export struct SceneListPage {
  @State private scenes: Scene[] = [];
  @State private total: number = 0;
  @State private currentPage: number = 1;
  @State private loading: boolean = false;
  @State private timedOut: boolean = false;
  @State private error: string = '';
  @State private query: string = '';
  @State private sort: string = 'date';
  @State private sortDirection: string = 'DESC';

  private perPage: number = 120;

  private get base(): string {
    return AppSettings.instance.activeBaseURL();
  }

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
    this.reload();
  }

  private async reload(): Promise<void> {
    await this.goToPage(1);
  }

  private async goToPage(page: number): Promise<void> {
    this.loading = true;
    this.timedOut = false;
    this.error = '';
    try {
      const client = makeClient();
      const q = `
        query FindScenes($filter: FindFilterType!, $sf: SceneFilterType) {
          findScenes(filter: $filter, scene_filter: $sf) {
            count
            scenes {
              id title details date rating100 o_counter organized
              urls
              studio { id name }
              performers { id name }
              tags { id name }
              paths { screenshot webp }
            }
          }
        }`;
      const filter: Record<string, Object> = {
        'page': page,
        'per_page': this.perPage,
        'sort': this.sort,
        'direction': this.sortDirection
      };
      if (this.query.trim() !== '') {
        filter['q'] = this.query.trim();
      }
      const data = await client.send(q, { 'filter': filter }) as FindScenesResp;
      const fs = data.findScenes;
      if (fs !== undefined && fs !== null) {
        this.scenes = fs.scenes !== undefined ? fs.scenes : [];
        this.total = fs.count !== undefined ? fs.count : 0;
      }
      this.currentPage = page;
    } catch (e) {
      const ge = e as Error;
      this.error = ge !== null ? ge.message : '加载失败';
      if (this.scenes.length === 0) {
        this.timedOut = true;
      }
    }
    this.loading = false;
  }

  private searchSubmit(): void {
    this.reload();
  }

  private changeSort(s: string): void {
    this.sort = s;
    this.reload();
  }

  private toggleDirection(): void {
    this.sortDirection = this.sortDirection === 'DESC' ? 'ASC' : 'DESC';
    this.reload();
  }

  private openScene(id: string): void {
    router.pushUrl({ url: 'pages/SceneDetailPage', params: { 'id': id } });
  }

  @Builder
  private pageBar() {
    Row() {
      Button('上一页')
        .fontSize(13)
        .height(34)
        .fontColor('#D1D5DB')
        .backgroundColor('#1F2937')
        .borderRadius(8)
        .enabled(this.canPrev && !this.loading)
        .onClick(() => {
          this.goToPage(this.currentPage - 1);
        })
      Blank()
      Text('第 ' + this.currentPage + ' / ' + this.totalPages + ' 页（共 ' + this.total + '）')
        .fontSize(12)
        .fontColor('#9CA3AF')
      Blank()
      Button('下一页')
        .fontSize(13)
        .height(34)
        .fontColor('#D1D5DB')
        .backgroundColor('#1F2937')
        .borderRadius(8)
        .enabled(this.canNext && !this.loading)
        .onClick(() => {
          this.goToPage(this.currentPage + 1);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  build() {
    Column() {
      // 搜索 + 排序栏
      Row({ space: 8 }) {
        TextInput({ placeholder: '搜索短片标题 / 简介', text: this.query })
          .fontSize(14)
          .height(40)
          .layoutWeight(1)
          .backgroundColor('#16161E')
          .borderRadius(8)
          .onChange((v: string) => {
            this.query = v;
          })
          .onSubmit(() => {
            this.searchSubmit();
          })
        Button('搜索')
          .fontSize(13)
          .height(40)
          .fontColor('#FFFFFF')
          .backgroundColor('#3B82F6')
          .borderRadius(8)
          .onClick(() => {
            this.searchSubmit();
          })
        Button(this.sort === 'date' ? '日期' : (this.sort === 'title' ? '标题' : '评分'))
          .fontSize(12)
          .height(40)
          .fontColor('#D1D5DB')
          .backgroundColor('#1F2937')
          .borderRadius(8)
          .onClick(() => {
            this.changeSort(this.sort === 'date' ? 'title' : (this.sort === 'title' ? 'rating' : 'date'));
          })
        Button(this.sortDirection === 'DESC' ? '↓' : '↑')
          .fontSize(12)
          .height(40)
          .width(40)
          .fontColor('#D1D5DB')
          .backgroundColor('#1F2937')
          .borderRadius(8)
          .onClick(() => {
            this.toggleDirection();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8 })

      // 顶部翻页栏
      this.pageBar()

      // 内容区
      if (this.loading && this.scenes.length === 0) {
        Column({ space: 10 }) {
          LoadingProgress()
            .width(40)
            .height(40)
            .color('#3B82F6')
          Text(this.timedOut ? '加载超时，检查网络或查看设置' : '加载中…')
            .fontSize(13)
            .fontColor('#9CA3AF')
          if (this.timedOut) {
            Button('重试')
              .fontSize(13)
              .height(34)
              .fontColor('#FFFFFF')
              .backgroundColor('#3B82F6')
              .borderRadius(8)
              .onClick(() => {
                this.reload();
              })
          }
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.scenes.length === 0) {
        Column({ space: 10 }) {
          Text(this.error !== '' ? this.error : '没有短片')
            .fontSize(14)
            .fontColor('#9CA3AF')
          Button('重试')
            .fontSize(13)
            .height(34)
            .fontColor('#FFFFFF')
            .backgroundColor('#3B82F6')
            .borderRadius(8)
            .onClick(() => {
              this.reload();
            })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            Grid() {
              ForEach(this.scenes, (s: Scene) => {
                GridItem() {
                  SceneCard({ scene: s, base: this.base })
                    .onClick(() => {
                      this.openScene(s.id);
                    })
                }
              }, (s: Scene) => s.id)
            }
            .columnsTemplate('1fr 1fr 1fr')
            .columnsGap(12)
            .rowsGap(14)
            .width('100%')
            .padding({ left: 12, right: 12 })
          }
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }

      // 底部翻页栏
      this.pageBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0B0B0F')
  }
}
