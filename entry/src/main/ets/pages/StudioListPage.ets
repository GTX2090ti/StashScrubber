import router from '@ohos.router';
import { Studio, FindStudiosResp } from '../model/Models';
import { makeClient } from '../net/GraphQLClient';

// 工作室列表页：行式列表 + 翻页 + 搜索（鸿蒙官方风格）
@Component
export struct StudioListPage {
  @State private studios: Studio[] = [];
  @State private total: number = 0;
  @State private currentPage: number = 1;
  @State private loading: boolean = false;
  @State private error: string = '';
  @State private query: string = '';

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
        query FindStudios($filter: FindFilterType!) {
          findStudios(filter: $filter) {
            count
            studios { id name image_path rating100 scene_count }
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
      const data = await client.send(q, { 'filter': filter }) as FindStudiosResp;
      const fp = data.findStudios;
      if (fp !== undefined && fp !== null) {
        this.studios = fp.studios !== undefined ? fp.studios : [];
        this.total = fp.count !== undefined ? fp.count : 0;
      }
      this.currentPage = page;
    } catch (e) {
      const ge = e as Error;
      this.error = ge !== null ? ge.message : '加载失败';
    }
    this.loading = false;
  }

  private openStudio(id: string): void {
    router.pushUrl({ url: 'pages/StudioDetailPage', params: { 'id': id } });
  }

  @Builder
  private pageBar() {
    Row() {
      Button('上一页', { type: ButtonType.Normal })
        .fontSize(13)
        .height(34)
        .enabled(this.canPrev && !this.loading)
        .onClick(() => {
          this.goToPage(this.currentPage - 1);
        })
      Blank()
      Text('第 ' + this.currentPage + ' / ' + this.totalPages + ' 页（共 ' + this.total + '）')
        .fontSize(12)
        .fontColor('#666666')
      Blank()
      Button('下一页', { type: ButtonType.Normal })
        .fontSize(13)
        .height(34)
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
        TextInput({ placeholder: '搜索工作室', text: this.query })
          .fontSize(14)
          .height(40)
          .layoutWeight(1)
          .borderRadius(8)
          .onChange((v: string) => {
            this.query = v;
          })
          .onSubmit(() => {
            this.reload();
          })
        Button('搜索', { type: ButtonType.Capsule })
          .fontSize(13)
          .height(36)
          .onClick(() => {
            this.reload();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8 })

      this.pageBar()

      if (this.loading && this.studios.length === 0) {
        Column({ space: 10 }) {
          LoadingProgress().width(40).height(40)
          Text('加载中…').fontSize(13).fontColor('#666666')
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.studios.length === 0) {
        Column({ space: 10 }) {
          Text(this.error !== '' ? this.error : '没有工作室')
            .fontSize(14)
            .fontColor('#666666')
          Button('重试', { type: ButtonType.Capsule })
            .fontSize(13)
            .height(34)
            .onClick(() => {
              this.reload();
            })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 2 }) {
          ForEach(this.studios, (s: Studio) => {
            ListItem() {
              Row({ space: 12 }) {
                Text('🏢')
                  .fontSize(24)
                Column({ space: 4 }) {
                  Text(s.name)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (s.scene_count !== undefined && s.scene_count !== null) {
                    Text('短片数：' + s.scene_count.toString())
                      .fontSize(12)
                      .fontColor('#999999')
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Text('›')
                  .fontSize(22)
                  .fontColor('#CCCCCC')
              }
              .width('100%')
              .height(56)
              .onClick(() => {
                this.openStudio(s.id);
              })
            }
          }, (s: Studio) => s.id)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 16, right: 16 })
        .scrollBar(BarState.Off)
      }

      this.pageBar()
    }
    .width('100%')
    .height('100%')
  }
}
