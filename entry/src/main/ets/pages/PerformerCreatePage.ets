import router from '@ohos.router';
import { Tag } from '../model/Models';
import { makeClient } from '../net/GraphQLClient';
import { StashAPI } from '../net/StashAPI';

// 手动添加演员页（鸿蒙官方组件风格）
@Entry
@Component
struct PerformerCreatePage {
  @State private name: string = '';
  @State private disambiguation: string = '';
  @State private birthdate: string = '';
  @State private country: string = '';
  @State private ethnicity: string = '';
  @State private measurements: string = '';
  @State private careerLength: string = '';
  @State private details: string = '';
  @State private rating: number = 0;
  @State private tagIds: string[] = [];
  @State private tags: Tag[] = [];
  @State private saving: boolean = false;
  @State private error: string = '';

  aboutToAppear(): void {
    this.loadTags();
  }

  private async loadTags(): Promise<void> {
    try {
      const client = makeClient();
      this.tags = await StashAPI.allTags(client);
    } catch (e) {
      // 标签加载失败不阻塞保存
    }
  }

  private toggleTag(id: string): void {
    const idx = this.tagIds.indexOf(id);
    if (idx >= 0) {
      this.tagIds.splice(idx, 1);
    } else {
      this.tagIds.push(id);
    }
  }

  private async save(): Promise<void> {
    const trimmed = this.name.trim();
    if (trimmed === '') {
      this.error = '演员名称不能为空';
      return;
    }
    this.saving = true;
    this.error = '';
    try {
      const client = makeClient();
      const input: Record<string, Object> = { 'name': trimmed };
      if (this.disambiguation.trim() !== '') {
        input['disambiguation'] = this.disambiguation.trim();
      }
      if (this.birthdate.trim() !== '') {
        input['birthdate'] = this.birthdate.trim();
      }
      if (this.country.trim() !== '') {
        input['country'] = this.country.trim();
      }
      if (this.ethnicity.trim() !== '') {
        input['ethnicity'] = this.ethnicity.trim();
      }
      if (this.measurements.trim() !== '') {
        input['measurements'] = this.measurements.trim();
      }
      if (this.careerLength.trim() !== '') {
        input['career_length'] = this.careerLength.trim();
      }
      if (this.details.trim() !== '') {
        input['details'] = this.details.trim();
      }
      if (this.rating > 0) {
        input['rating100'] = this.rating;
      }
      if (this.tagIds.length > 0) {
        input['tag_ids'] = this.tagIds;
      }
      const newId = await StashAPI.createPerformer(client, input);
      // 通知来源页自动选中
      AppStorage.setOrCreate('createdPerformer', newId);
      router.back();
    } catch (e) {
      this.error = '保存失败';
    }
    this.saving = false;
  }

  @Builder
  sectionTitle(text: string) {
    Text(text)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .width('100%')
      .margin({ top: 12, bottom: 4 })
  }

  build() {
    Navigation() {
      Scroll() {
        Column({ space: 8 }) {
          this.sectionTitle('基本信息')
          TextInput({ text: this.name, placeholder: '名称（必填）' })
            .onChange((v: string) => { this.name = v })
          TextInput({ text: this.disambiguation, placeholder: '区别名' })
            .onChange((v: string) => { this.disambiguation = v })
          TextInput({ text: this.birthdate, placeholder: '出生日期（yyyy-MM-dd）' })
            .onChange((v: string) => { this.birthdate = v })
          TextInput({ text: this.country, placeholder: '国籍' })
            .onChange((v: string) => { this.country = v })
          Row({ space: 12 }) {
            Text('评分').fontSize(15)
            Text(this.rating > 0 ? (this.rating / 20).toFixed(1) + ' / 5.0' : '未评分')
              .fontSize(13)
              .fontColor('#666666')
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          Slider({ value: this.rating, min: 0, max: 100, step: 5 })
            .onChange((v: number) => { this.rating = v })

          this.sectionTitle('档案')
          TextInput({ text: this.ethnicity, placeholder: '族裔' })
            .onChange((v: string) => { this.ethnicity = v })
          TextInput({ text: this.measurements, placeholder: '三围' })
            .onChange((v: string) => { this.measurements = v })
          TextInput({ text: this.careerLength, placeholder: '从业年限（如 2015-2020）' })
            .onChange((v: string) => { this.careerLength = v })

          this.sectionTitle('标签')
          List({ space: 2 }) {
            ForEach(this.tags, (t: Tag) => {
              ListItem() {
                Row({ space: 10 }) {
                  Checkbox()
                    .select(this.tagIds.indexOf(t.id) >= 0)
                    .onChange((v: boolean) => { this.toggleTag(t.id) })
                  Text(t.name).fontSize(15)
                }
                .width('100%')
                .height(44)
              }
            }, (t: Tag) => t.id)
          }
          .height(Math.min(this.tags.length * 46, 220))
          .width('100%')

          this.sectionTitle('简介')
          TextArea({ text: this.details, placeholder: '简介…' })
            .height(120)
            .width('100%')
            .onChange((v: string) => { this.details = v })

          if (this.error !== '') {
            Text(this.error).fontSize(13).fontColor('#D94838')
          }
          Button(this.saving ? '保存中…' : '保存', { type: ButtonType.Capsule })
            .fontSize(16)
            .width('100%')
            .height(44)
            .enabled(!this.saving)
            .margin({ top: 12, bottom: 24 })
            .onClick(() => { this.save() })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
    }
    .title('添加演员')
    .hideTitleBar(false)
    .width('100%')
    .height('100%')
  }
}
