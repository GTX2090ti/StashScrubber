import router from '@ohos.router';
import { Performer, PerformerPage, FindPerformersResp, rewriteImage } from '../model/Models';
import { makeClient } from '../net/GraphQLClient';
import { AppSettings } from '../net/AppSettings';

// 演员列表页：头像网格 + 翻页 + 搜索
@Component
export struct PerformerListPage {
  @State private performers: Performer[] = [];
  @State private total: number = 0;
  @State private currentPage: number = 1;
  @State private loading: boolean = false;
  @State private error: string = '';
  @State private query: string = '';

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
    this.error = '';
    try {
      const client = makeClient();
      const q = `
        query FindPerformers($filter: FindFilterType!) {
          findPerformers(filter: $filter) {
            count
            performers {
              id name disambiguation image_path birthdate country rating100
              tags { id name }
            }
          }
        }`;
      const filter: Record<string, Object> = {
        'page': page,
        'per_page': this.perPage,
        'sort': 'name',
        'direction': 'ASC'
      };
      if (this.query.trim() !== '') {
        filter['q'] = this.query.trim();
      }
      const data = await client.send(q, { 'filter': filter }) as FindPerformersResp;
      const fp = data.findPerformers;
      if (fp !== undefined && fp !== null) {
        this.performers = fp.performers !== undefined ? fp.performers : [];
        this.total = fp.count !== undefined ? fp.count : 0;
      }
      this.currentPage = page;
    } catch (e) {
      const ge = e as Error;
      this.error = ge !== null ? ge.message : '加载失败';
    }
    this.loading = false;
  }

  private openPerformer(id: string): void {
    router.pushUrl({ url: 'pages/PerformerDetailPage', params: { 'id': id } });
  }

  private avatarUrl(p: Performer): string {
    if (p.image_path === undefined || p.image_path === null || p.image_path === '') {
      return '';
    }
    return rewriteImage(p.image_path, this.base);
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
      Row({ space: 8 }) {
        TextInput({ placeholder: '搜索演员', text: this.query })
          .fontSize(14)
          .height(40)
          .layoutWeight(1)
          .backgroundColor('#16161E')
          .borderRadius(8)
          .onChange((v: string) => {
            this.query = v;
          })
          .onSubmit(() => {
            this.reload();
          })
        Button('搜索')
          .fontSize(13)
          .height(40)
          .fontColor('#FFFFFF')
          .backgroundColor('#3B82F6')
          .borderRadius(8)
          .onClick(() => {
            this.reload();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8 })

      this.pageBar()

      if (this.loading && this.performers.length === 0) {
        Column({ space: 10 }) {
          LoadingProgress().width(40).height(40).color('#3B82F6')
          Text('加载中…').fontSize(13).fontColor('#9CA3AF')
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.performers.length === 0) {
        Column({ space: 10 }) {
          Text(this.error !== '' ? this.error : '没有演员')
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
          Grid() {
            ForEach(this.performers, (p: Performer) => {
              GridItem() {
                Column({ space: 6 }) {
                  Stack() {
                    if (this.avatarUrl(p) !== '') {
                      Image(this.avatarUrl(p))
                        .objectFit(ImageFit.Cover)
                        .width('100%')
                        .height('100%')
                    } else {
                      Text(p.name.substring(0, 1))
                        .fontSize(22)
                        .fontColor('#9CA3AF')
                    }
                  }
                  .width('100%')
                  .aspectRatio(1)
                  .clip(true)
                  .borderRadius(10)
                  .backgroundColor('#16161E')

                  Text(p.name)
                    .fontSize(11)
                    .fontColor('#E5E7EB')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                    .textAlign(TextAlign.Center)
                }
                .width('100%')
                .onClick(() => {
                  this.openPerformer(p.id);
                })
              }
            }, (p: Performer) => p.id)
          }
          .columnsTemplate('1fr 1fr 1fr 1fr')
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
    .backgroundColor('#0B0B0F')
  }
}
