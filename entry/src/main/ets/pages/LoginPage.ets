import { AppSettings, ProfileInfo } from '../net/AppSettings';
import { probeGraphQL } from '../net/GraphQLClient';
import { normalizeBase } from '../model/Models';

// 登录 / 服务器配置页：填写档案名 + 内网/外网地址 + API Key，实测连接后保存
// 由 Index 按需内嵌渲染（非独立路由页）
@Component
export struct LoginPage {
  onSaved: () => void = () => {
  };
  @State private profileName: string = '';
  @State private lanUrl: string = '';
  @State private wanUrl: string = '';
  @State private apiKey: string = '';
  @State private testing: boolean = false;
  @State private saving: boolean = false;
  @State private testResult: string = '';
  @State private testOk: boolean = false;

  aboutToAppear(): void {
    const p = AppSettings.instance.currentProfile();
    if (p !== null) {
      this.profileName = p.name;
      this.lanUrl = p.lanUrl;
      this.wanUrl = p.wanUrl;
      this.apiKey = p.apiKey;
    }
  }

  private async testConnection(): Promise<void> {
    const base = normalizeBase(this.lanUrl.trim());
    if (base === '') {
      this.testResult = '请先填写内网地址';
      this.testOk = false;
      return;
    }
    this.testing = true;
    this.testResult = '正在测试内网…';
    this.testOk = false;
    const err = await probeGraphQL(base, this.apiKey.trim(),
      '{ version { version } }', 8000);
    this.testing = false;
    if (err === '') {
      this.testResult = '内网连接成功 ✓';
      this.testOk = true;
    } else {
      // 内网失败时试外网
      const wanBase = normalizeBase(this.wanUrl.trim());
      if (wanBase !== '') {
        this.testResult = '内网失败（' + err + '），正在测试外网…';
        const err2 = await probeGraphQL(wanBase, this.apiKey.trim(),
          '{ version { version } }', 8000);
        if (err2 === '') {
          this.testResult = '内网失败，外网连接成功 ✓';
          this.testOk = true;
        } else {
          this.testResult = '内网失败（' + err + '）；外网也失败（' + err2 + '）';
          this.testOk = false;
        }
      } else {
        this.testResult = '连接失败：' + err;
        this.testOk = false;
      }
    }
  }

  private save(): void {
    const name = this.profileName.trim();
    if (name === '') {
      this.testResult = '请填写档案名称';
      this.testOk = false;
      return;
    }
    this.saving = true;
    const profile: ProfileInfo = {
      name: name,
      lanUrl: this.lanUrl.trim(),
      wanUrl: this.wanUrl.trim(),
      apiKey: this.apiKey.trim()
    };
    AppSettings.instance.saveProfile(profile);
    this.saving = false;
    this.onSaved();
  }

  build() {
    Column({ space: 14 }) {
      Text('StashScrubber')
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor('#F9FAFB')
        .margin({ top: 60, bottom: 8 })

      Text('配置 Stash 服务器（支持内网/外网双地址）')
        .fontSize(13)
        .fontColor('#9CA3AF')
        .margin({ bottom: 24 })

      this.inputField('档案名称', '例如：家里', (v: string) => {
        this.profileName = v;
      }, this.profileName, false)

      this.inputField('内网地址', 'http://192.168.x.x:9999', (v: string) => {
        this.lanUrl = v;
      }, this.lanUrl, false)

      this.inputField('外网地址（可留空）', 'https://stash.example.com', (v: string) => {
        this.wanUrl = v;
      }, this.wanUrl, false)

      this.inputField('API Key', 'Stash 设置 → 安全 → API Key', (v: string) => {
        this.apiKey = v;
      }, this.apiKey, true)

      // 测试连接
      Button(this.testing ? '测试中…' : '测试连接')
        .width('100%')
        .height(44)
        .fontSize(16)
        .fontColor('#FFFFFF')
        .backgroundColor('#3B82F6')
        .borderRadius(10)
        .enabled(!this.testing && !this.saving)
        .onClick(() => {
          this.testConnection();
        })

      // 测试结果
      if (this.testResult !== '') {
        Text(this.testResult)
          .fontSize(13)
          .fontColor(this.testOk ? '#34D399' : '#F87171')
          .textAlign(TextAlign.Center)
          .width('100%')
      }

      // 保存
      Button(this.saving ? '保存中…' : '保存并进入')
        .width('100%')
        .height(44)
        .fontSize(16)
        .fontColor('#FFFFFF')
        .backgroundColor('#10B981')
        .borderRadius(10)
        .enabled(!this.testing && !this.saving)
        .onClick(() => {
          this.save();
        })

      Blank()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24 })
    .backgroundColor('#0B0B0F')
  }

  @Builder
  private inputField(label: string, placeholder: string, onChange: (v: string) => void, value: string, isPassword: boolean) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(13)
        .fontColor('#9CA3AF')
        .width('100%')
      TextInput({ placeholder: placeholder, text: value })
        .type(isPassword ? InputType.Password : InputType.Normal)
        .fontSize(15)
        .fontColor('#F9FAFB')
        .placeholderColor('#6B7280')
        .height(46)
        .backgroundColor('#16161E')
        .borderRadius(10)
        .onChange((v: string) => {
          onChange(v);
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
