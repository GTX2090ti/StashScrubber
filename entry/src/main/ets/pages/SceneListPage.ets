import router from '@ohos.router';
import { promptAction } from '@kit.ArkUI';
import { Scene, FindScenesResp, Tag, AllTagsResp } from '../model/Models';
import { makeClient } from '../net/GraphQLClient';
import { AppSettings } from '../net/AppSettings';
import { SceneCard } from '../common/SceneCard';
import { StashAPI } from '../net/StashAPI';

// 短片列表页：120 个/页 + 翻页栏（顶部/底部）+ 搜索 + 排序 + 筛选 + 批量操作
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

  // 筛选
  @State private filterFav: boolean = false;
  @State private filterRating: number = 0;

  // 批量
  @State private selectMode: boolean = false;
  @State private selected: string[] = [];
  @State private showTagSheet: boolean = false;
  @State private tagMode: string = 'add';
  @State private tagPick: string[] = [];
  @State private allTags: Tag[] = [];
  @State private batchBusy: boolean = false;

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

  private get filterSummary(): string {
    const parts: string[] = [];
    if (this.filterFav) {
      parts.push('仅收藏');
    }
    if (this.filterRating > 0) {
      parts.push('评分≥' + (this.filterRating / 20).toFixed(1));
    }
    return parts.length > 0 ? parts.join(' ') : '筛选';
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
      const sf: Record<string, Object> = {};
      if (this.filterFav) {
        sf['organized'] = true;
      }
      if (this.filterRating > 0) {
        const r: Record<string, Object> = { 'value': this.filterRating - 1, 'modifier': 'GREATER_THAN' };
        sf['rating100'] = r;
      }
      const vars: Record<string, Object> = { 'filter': filter };
      if (Object.keys(sf).length > 0) {
        vars['sf'] = sf;
      }
      const data = await client.send(q, vars) as FindScenesResp;
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
    if (this.selectMode) {
      this.toggleSelect(id);
      return;
    }
    router.pushUrl({ url: 'pages/SceneDetailPage', params: { 'id': id } });
  }

  // ---------- 批量 ----------
  private toggleSelect(id: string): void {
    const idx = this.selected.indexOf(id);
    if (idx >= 0) {
      this.selected.splice(idx, 1);
    } else {
      this.selected.push(id);
    }
  }

  private toggleSelectAll(): void {
    if (this.selected.length === this.scenes.length) {
      this.selected = [];
    } else {
      this.selected = this.scenes.map((s: Scene) => s.id);
    }
  }

  private selectedScenes(): Scene[] {
    const out: Scene[] = [];
    for (const s of this.scenes) {
      if (this.selected.indexOf(s.id) >= 0) {
        out.push(s);
      }
    }
    return out;
  }

  private allSelectedOrganized(): boolean {
    const sel = this.selectedScenes();
    return sel.length > 0 && sel.every((s: Scene) => s.organized === true);
  }

  private async batchFav(target: boolean): Promise<void> {
    if (this.selected.length === 0) {
      return;
    }
    this.batchBusy = true;
    const client = makeClient();
    let done = 0;
    let failed = 0;
    for (const id of this.selected) {
      try {
        await StashAPI.updateScene(client, { 'id': id, 'organized': target });
        done++;
      } catch (e) {
        failed++;
      }
    }
    this.finishBatch(target ? '已收藏 ' + done.toString() : '已取消收藏 ' + done.toString(), failed);
  }

  private async batchRating(v: number): Promise<void> {
    if (this.selected.length === 0) {
      return;
    }
    this.batchBusy = true;
    const client = makeClient();
    let done = 0;
    let failed = 0;
    for (const id of this.selected) {
      try {
        await StashAPI.updateScene(client, { 'id': id, 'rating100': v });
        done++;
      } catch (e) {
        failed++;
      }
    }
    this.finishBatch('已设置评分 ' + done.toString() + ' 个', failed);
  }

  private async loadAllTags(): Promise<void> {
    try {
      const client = makeClient();
      this.allTags = await StashAPI.allTags(client);
    } catch (e) {
      this.allTags = [];
    }
  }

  private openTagSheet(mode: string): void {
    this.tagMode = mode;
    this.tagPick = [];
    this.loadAllTags();
    this.showTagSheet = true;
  }

  private toggleTagPick(id: string): void {
    const idx = this.tagPick.indexOf(id);
    if (idx >= 0) {
      this.tagPick.splice(idx, 1);
    } else {
      this.tagPick.push(id);
    }
  }

  private async confirmBatchTags(): Promise<void> {
    if (this.selected.length === 0 || this.tagPick.length === 0) {
      this.showTagSheet = false;
      return;
    }
    this.showTagSheet = false;
    this.batchBusy = true;
    const client = makeClient();
    let done = 0;
    let failed = 0;
    for (const id of this.selected) {
      try {
        const s = this.scenes.find((it: Scene) => it.id === id);
        const cur: string[] = s !== undefined && s.tags !== undefined && s.tags !== null
          ? s.tags.map((t: Tag) => t.id) : [];
        let next: string[];
        if (this.tagMode === 'add') {
          next = cur.slice();
          for (const t of this.tagPick) {
            if (next.indexOf(t) < 0) {
              next.push(t);
            }
          }
        } else {
          next = cur.filter((t: string) => this.tagPick.indexOf(t) < 0);
        }
        await StashAPI.updateScene(client, { 'id': id, 'tag_ids': next });
        done++;
      } catch (e) {
        failed++;
      }
    }
    this.finishBatch((this.tagMode === 'add' ? '已添加标签 ' : '已移除标签 ') + done.toString() + ' 个', failed);
  }

  private finishBatch(okText: string, failed: number): void {
    promptAction.showToast({
      message: failed > 0 ? okText + '，' + failed.toString() + ' 个失败' : okText
    });
    this.batchBusy = false;
    this.selected = [];
    this.selectMode = false;
    this.reload();
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

  @Builder
  private filterSheet() {
    Column({ space: 14 }) {
      Text('筛选').fontSize(17).fontWeight(FontWeight.Medium).width('100%')
      Row({ space: 12 }) {
        Text('仅收藏').fontSize(15).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.filterFav })
          .onChange((v: boolean) => { this.filterFav = v })
      }
      .width('100%')
      Text('评分下限：' + (this.filterRating > 0 ? (this.filterRating / 20).toFixed(1) + ' / 5.0' : '不限'))
        .fontSize(15)
        .width('100%')
      Slider({ value: this.filterRating, min: 0, max: 100, step: 5 })
        .width('100%')
        .onChange((v: number) => { this.filterRating = v })
      Row({ space: 12 }) {
        Button('重置', { type: ButtonType.Normal })
          .fontSize(14)
          .layoutWeight(1)
          .onClick(() => {
            this.filterFav = false;
            this.filterRating = 0;
          })
        Button('应用', { type: ButtonType.Capsule })
          .fontSize(14)
          .layoutWeight(1)
          .onClick(() => {
            this.showFilterSheet = false;
            this.reload();
          })
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .width('100%')
    .padding(20)
  }

  @State private showFilterSheet: boolean = false;

  @Builder
  private tagSheet() {
    Column({ space: 8 }) {
      Text(this.tagMode === 'add' ? '选择要添加的标签' : '选择要移除的标签')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .width('100%')
      List({ space: 2 }) {
        ForEach(this.allTags, (t: Tag) => {
          ListItem() {
            Row({ space: 10 }) {
              Checkbox()
                .select(this.tagPick.indexOf(t.id) >= 0)
                .onChange((v: boolean) => { this.toggleTagPick(t.id) })
              Text(t.name).fontSize(15)
            }
            .width('100%')
            .height(44)
          }
        }, (t: Tag) => t.id)
      }
      .width('100%')
      .layoutWeight(1)
      Row({ space: 12 }) {
        Button('取消', { type: ButtonType.Normal })
          .fontSize(14)
          .layoutWeight(1)
          .onClick(() => { this.showTagSheet = false })
        Button('确定（' + this.tagPick.length.toString() + '）', { type: ButtonType.Capsule })
          .fontSize(14)
          .layoutWeight(1)
          .enabled(this.tagPick.length > 0)
          .onClick(() => { this.confirmBatchTags() })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
  }

  @Builder
  private batchBar() {
    Row({ space: 6 }) {
      Button(this.allSelectedOrganized() ? '取消收藏' : '收藏')
        .fontSize(12)
        .height(34)
        .layoutWeight(1)
        .enabled(!this.batchBusy && this.selected.length > 0)
        .onClick(() => {
          this.batchFav(!this.allSelectedOrganized());
        })
      Button('评分')
        .fontSize(12)
        .height(34)
        .layoutWeight(1)
        .enabled(!this.batchBusy && this.selected.length > 0)
        .onClick(() => { this.showRatingBar = !this.showRatingBar })
      Button('标签')
        .fontSize(12)
        .height(34)
        .layoutWeight(1)
        .enabled(!this.batchBusy && this.selected.length > 0)
        .onClick(() => { this.openTagSheet('add') })
      Button('全选')
        .fontSize(12)
        .height(34)
        .layoutWeight(1)
        .enabled(!this.batchBusy && this.scenes.length > 0)
        .onClick(() => { this.toggleSelectAll() })
      Text(this.selected.length.toString())
        .fontSize(13)
        .fontColor('#666666')
        .width(28)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
  }

  @State private showRatingBar: boolean = false;

  @Builder
  private ratingBar() {
    Row({ space: 6 }) {
      ForEach([20, 40, 60, 80, 100], (v: number) => {
        Button('★' + (v / 20).toFixed(0))
          .fontSize(12)
          .height(32)
          .layoutWeight(1)
          .backgroundColor(v <= (this.ratingPick ?? 0) ? '#FF9500' : '#F2F2F2')
          .fontColor(v <= (this.ratingPick ?? 0) ? '#FFFFFF' : '#333333')
          .onClick(() => {
            this.ratingPick = v;
            this.batchRating(v);
            this.showRatingBar = false;
          })
      }, (v: number) => v.toString())
      Button('清除')
        .fontSize(12)
        .height(32)
        .layoutWeight(1)
        .onClick(() => {
          this.ratingPick = 0;
          this.batchRating(0);
          this.showRatingBar = false;
        })
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 4 })
  }

  @State private ratingPick: number = 0;

  build() {
    Column() {
      // 搜索行
      Row({ space: 8 }) {
        TextInput({ placeholder: '搜索短片标题 / 简介', text: this.query })
          .fontSize(14)
          .height(40)
          .layoutWeight(1)
          .borderRadius(8)
          .onChange((v: string) => { this.query = v })
          .onSubmit(() => { this.searchSubmit() })
        Button('搜索', { type: ButtonType.Capsule })
          .fontSize(13)
          .height(36)
          .onClick(() => { this.searchSubmit() })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8 })

      // 工具行
      Row({ space: 8 }) {
        Button(this.filterSummary, { type: ButtonType.Normal })
          .fontSize(12)
          .height(34)
          .layoutWeight(1)
          .onClick(() => { this.showFilterSheet = true })
        Button(this.sort === 'date' ? '日期' : (this.sort === 'title' ? '标题' : '评分'), { type: ButtonType.Normal })
          .fontSize(12)
          .height(34)
          .layoutWeight(1)
          .onClick(() => {
            this.changeSort(this.sort === 'date' ? 'title' : (this.sort === 'title' ? 'rating' : 'date'));
          })
        Button(this.sortDirection === 'DESC' ? '↓' : '↑', { type: ButtonType.Normal })
          .fontSize(12)
          .height(34)
          .width(44)
          .onClick(() => { this.toggleDirection() })
        Button(this.selectMode ? '完成' : '多选', { type: ButtonType.Normal })
          .fontSize(12)
          .height(34)
          .layoutWeight(1)
          .onClick(() => {
            this.selectMode = !this.selectMode;
            if (!this.selectMode) {
              this.selected = [];
            }
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 6 })

      if (this.showRatingBar) {
        this.ratingBar()
      }

      // 顶部翻页栏
      this.pageBar()

      // 内容区
      if (this.loading && this.scenes.length === 0) {
        Column({ space: 10 }) {
          LoadingProgress().width(40).height(40)
          Text(this.timedOut ? '加载超时，检查网络或查看设置' : '加载中…')
            .fontSize(13)
            .fontColor('#666666')
          if (this.timedOut) {
            Button('重试', { type: ButtonType.Capsule })
              .fontSize(13)
              .height(34)
              .onClick(() => { this.reload() })
          }
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.scenes.length === 0) {
        Column({ space: 10 }) {
          Text(this.error !== '' ? this.error : '没有短片').fontSize(14).fontColor('#666666')
          Button('重试', { type: ButtonType.Capsule })
            .fontSize(13)
            .height(34)
            .onClick(() => { this.reload() })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            Grid() {
              ForEach(this.scenes, (s: Scene) => {
                GridItem() {
                  Stack({ alignContent: Alignment.TopEnd }) {
                    SceneCard({ scene: s, base: this.base })
                    if (this.selectMode) {
                      Text(this.selected.indexOf(s.id) >= 0 ? '✓' : '○')
                        .fontSize(16)
                        .fontColor(this.selected.indexOf(s.id) >= 0 ? '#FFFFFF' : '#999999')
                        .width(24)
                        .height(24)
                        .textAlign(TextAlign.Center)
                        .backgroundColor(this.selected.indexOf(s.id) >= 0 ? '#1E5EFF' : '#FFFFFF')
                        .border({ width: 1, color: '#CCCCCC' })
                        .borderRadius(12)
                        .margin(6)
                    }
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
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }

      // 底部翻页栏
      this.pageBar()

      // 批量操作栏
      if (this.selectMode) {
        this.batchBar()
      }
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showFilterSheet, this.filterSheet(), { height: 320 })
    .bindSheet($$this.showTagSheet, this.tagSheet(), { height: 560 })
  }
}
