import router from '@ohos.router';
import { Performer, Tag, FindPerformerResp } from '../model/Models';
import { makeClient } from '../net/GraphQLClient';
import { StashAPI } from '../net/StashAPI';

// 演员编辑页（鸿蒙官方组件风格）
@Entry
@Component
struct PerformerEditPage {
  @State private performerId: string = '';
  @State private performer: Performer | null = null;
  @State private loading: boolean = true;
  @State private error: string = '';

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

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    if (params !== null && params['id'] !== undefined) {
      this.performerId = params['id'];
    }
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.error = '';
    try {
      const client = makeClient();
      const q = `
        query FindPerformer($id: ID!) {
          findPerformer(id: $id) {
            id name disambiguation birthdate country ethnicity measurements
            career_length details rating100 tags { id name }
          }
        }`;
      const data = await client.send(q, { 'id': this.performerId }) as FindPerformerResp;
      const p = data.findPerformer;
      if (p !== undefined && p !== null) {
        this.performer = p;
        this.name = p.name !== undefined ? p.name : '';
        this.disambiguation = p.disambiguation !== undefined ? p.disambiguation : '';
        this.birthdate = p.birthdate !== undefined ? p.birthdate : '';
        this.country = p.country !== undefined ? p.country : '';
        this.ethnicity = p.ethnicity !== undefined ? p.ethnicity : '';
        this.measurements = p.measurements !== undefined ? p.measurements : '';
        this.careerLength = p.career_length !== undefined ? p.career_length : '';
        this.details = p.details !== undefined ? p.details : '';
        this.rating = p.rating100 !== undefined && p.rating100 !== null ? p.rating100 : 0;
        this.tagIds = p.tags !== undefined && p.tags !== null ? p.tags.map((t: Tag) => t.id) : [];
      }
      this.tags = await StashAPI.allTags(client);
    } catch (e) {
      this.error = '加载失败';
    }
    this.loading = false;
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
    this.saving = true;
    this.error = '';
    try {
      const client = makeClient();
      const input: Record<string, Object> = { 'id': this.performerId };
      if (this.name.trim() !== '') {
        input['name'] = this.name.trim();
      }
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
      await StashAPI.updatePerformer(client, input);
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
      if (this.loading) {
        Column({ space: 12 }) {
          LoadingProgress()
          Text('加载中…').fontSize(13)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 8 }) {
            this.sectionTitle('基本信息')
            TextInput({ text: this.name, placeholder: '名称' })
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
    }
    .title('编辑演员')
    .hideTitleBar(false)
    .width('100%')
    .height('100%')
  }
}
