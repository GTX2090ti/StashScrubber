import router from '@ohos.router';
import { Scene, FindScenesResp } from '../model/Models';
import { makeClient } from '../net/GraphQLClient';
import { StashAPI } from '../net/StashAPI';

// 合并短片页：搜索源短片（可多选）→ 合并到目标短片（sceneMerge）
@Entry
@Component
struct MergePage {
  @State private targetId: string = '';
  @State private targetTitle: string = '';
  @State private query: string = '';
  @State private scenes: Scene[] = [];
  @State private selected: string[] = [];
  @State private loading: boolean = false;
  @State private merging: boolean = false;
  @State private error: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    if (params !== null) {
      if (params['id'] !== undefined) {
        this.targetId = params['id'];
      }
      if (params['title'] !== undefined) {
        this.targetTitle = params['title'];
      }
    }
    this.search();
  }

  private toggle(id: string): void {
    const idx = this.selected.indexOf(id);
    if (idx >= 0) {
      this.selected.splice(idx, 1);
    } else {
      this.selected.push(id);
    }
  }

  private async search(): Promise<void> {
    this.loading = true;
    this.error = '';
    try {
      const client = makeClient();
      const q = `query FindScenes($filter: SceneFilterType!) {
        findScenes(filter: $filter) {
          scenes { id title date paths { screenshot webp } }
        }
      }`;
      const filter: Record<string, Object> = {
        'q': this.query.trim() === '' ? '' : this.query.trim(),
        'page': 1,
        'per_page': 100
      };
      const vars: Record<string, Object> = { 'filter': filter };
      const data = await client.send(q, vars) as FindScenesResp;
      const page = data.findScenes;
      this.scenes = page !== undefined && page !== null && page.scenes !== undefined && page.scenes !== null
        ? page.scenes : [];
    } catch (e) {
      this.error = '搜索失败';
    }
    this.loading = false;
  }

  private async merge(): Promise<void> {
    if (this.selected.length === 0) {
      return;
    }
    this.merging = true;
    this.error = '';
    try {
      const client = makeClient();
      await StashAPI.mergeScenes(client, this.selected, this.targetId);
      router.back();
    } catch (e) {
      this.error = '合并失败';
    }
    this.merging = false;
  }

  build() {
    Navigation() {
      Column({ space: 10 }) {
        TextInput({ text: this.query, placeholder: '搜索短片标题' })
          .onChange((v: string) => { this.query = v })
          .onSubmit(() => { this.search() })
        if (this.selected.length > 0) {
          Text('已选 ' + this.selected.length.toString() + ' 个源短片').fontSize(13)
            .fontColor('#666666')
            .width('100%')
        }
        if (this.loading) {
          LoadingProgress().margin({ top: 40 })
        } else {
          List({ space: 2 }) {
            ForEach(this.scenes, (s: Scene) => {
              ListItem() {
                Row({ space: 12 }) {
                  if (s.paths !== undefined && s.paths !== null &&
                    ((s.paths.screenshot !== undefined && s.paths.screenshot !== null && s.paths.screenshot !== '') ||
                      (s.paths.webp !== undefined && s.paths.webp !== null && s.paths.webp !== ''))) {
                    Image(s.paths.screenshot !== undefined && s.paths.screenshot !== null && s.paths.screenshot !== ''
                      ? s.paths.screenshot : (s.paths.webp !== undefined ? s.paths.webp : ''))
                      .width(64)
                      .height(36)
                      .borderRadius(6)
                      .objectFit(ImageFit.Cover)
                  } else {
                    Column()
                      .width(64)
                      .height(36)
                      .borderRadius(6)
                      .backgroundColor('#E8E8E8')
                  }
                  Column({ space: 2 }) {
                    Text(s.title !== undefined && s.title !== '' ? s.title : '（无标题）')
                      .fontSize(15)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (s.date !== undefined && s.date !== null && s.date !== '') {
                      Text(s.date).fontSize(12).fontColor('#999999')
                    }
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  Checkbox()
                    .select(this.selected.indexOf(s.id) >= 0)
                    .onChange((v: boolean) => { this.toggle(s.id) })
                }
                .width('100%')
                .height(52)
              }
            }, (s: Scene) => s.id)
          }
          .width('100%')
          .layoutWeight(1)
          if (this.scenes.length === 0 && !this.loading) {
            Text('没有匹配的短片').fontSize(13).fontColor('#999999')
          }
        }
        if (this.error !== '') {
          Text(this.error).fontSize(13).fontColor('#D94838')
        }
        Text('选择要并入「' + (this.targetTitle !== '' ? this.targetTitle : '当前短片') + '」的短片（可多选）。合并后演员/标签/文件取并集，源短片条目删除（视频文件挂到本片），播放与 O 记录一并合并。')
          .fontSize(12)
          .fontColor('#999999')
          .width('100%')
        Button(this.merging ? '合并中…' : '合并（' + this.selected.length.toString() + '）', { type: ButtonType.Capsule })
          .fontSize(16)
          .width('100%')
          .height(44)
          .enabled(!this.merging && this.selected.length > 0)
          .onClick(() => { this.merge() })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 16 })
    }
    .title('合并短片')
    .hideTitleBar(false)
    .width('100%')
    .height('100%')
  }
}
