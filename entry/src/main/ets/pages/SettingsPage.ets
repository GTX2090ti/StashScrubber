import { AppSettings } from '../net/AppSettings';
import { NetLog } from '../net/NetLog';
import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';

// 设置页：档案信息、网络日志、重置配置、版本
@Component
export struct SettingsPage {
  onReset: () => void = () => {
  };
  @State private showLog: boolean = false;
  @State private logText: string = '';
  @State private version: string = '1.0.0';

  private currentProfileLabel(): string {
    const p = AppSettings.instance.currentProfile();
    if (p === null) {
      return '未配置';
    }
    return p.name + '  ·  内网 ' + p.lanUrl + (p.wanUrl !== '' ? '  ·  外网 ' + p.wanUrl : '');
  }

  private copyLog(): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, NetLog.instance.exportText());
    pasteboard.getSystemPasteboard().setData(data);
    promptAction.showToast({ message: '日志已复制到剪贴板', duration: 1500 });
  }

  private resetConfig(): void {
    const p = AppSettings.instance.currentProfile();
    if (p !== null) {
      AppSettings.instance.removeProfile(p.name);
    }
    this.onReset();
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text('设置')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F9FAFB')
          .width('100%')
          .margin({ top: 16 })

        // 当前档案
        Column({ space: 10 }) {
          Text('当前服务器')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#E5E7EB')
            .width('100%')
          Text(this.currentProfileLabel())
            .fontSize(13)
            .fontColor('#E5E7EB')
            .width('100%')
            .lineHeight(20)
          Text('切换/编辑服务器请返回登录页重新配置')
            .fontSize(11)
            .fontColor('#6B7280')
            .width('100%')
        }
        .width('100%')
        .padding(14)
        .backgroundColor('#131318')
        .borderRadius(12)
        .alignItems(HorizontalAlign.Start)

        // 网络日志
        Column({ space: 10 }) {
          Text('网络日志')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#E5E7EB')
            .width('100%')
          Text('记录每次 GraphQL 请求的结果，可一键复制用于排障')
            .fontSize(11)
            .fontColor('#6B7280')
            .width('100%')
          Row({ space: 8 }) {
            Button(this.showLog ? '收起日志' : '查看日志')
              .fontSize(13)
              .height(36)
              .fontColor('#D1D5DB')
              .backgroundColor('#1F2937')
              .borderRadius(8)
              .onClick(() => {
                this.showLog = !this.showLog;
                if (this.showLog) {
                  this.logText = NetLog.instance.exportText();
                }
              })
            Button('复制日志')
              .fontSize(13)
              .height(36)
              .fontColor('#D1D5DB')
              .backgroundColor('#1F2937')
              .borderRadius(8)
              .onClick(() => {
                this.copyLog();
              })
          }
          .width('100%')
          if (this.showLog) {
            Text(this.logText)
              .fontSize(11)
              .fontColor('#9CA3AF')
              .width('100%')
              .maxLines(12)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')
        .padding(14)
        .backgroundColor('#131318')
        .borderRadius(12)
        .alignItems(HorizontalAlign.Start)

        // 账号
        Column({ space: 10 }) {
          Text('账号')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#E5E7EB')
            .width('100%')
          Button('重置服务器配置（返回登录页）')
            .fontSize(14)
            .height(44)
            .width('100%')
            .fontColor('#FCA5A5')
            .backgroundColor('#3B1D1D')
            .borderRadius(10)
            .onClick(() => {
              this.resetConfig();
            })
        }
        .width('100%')
        .padding(14)
        .backgroundColor('#131318')
        .borderRadius(12)
        .alignItems(HorizontalAlign.Start)

        // 说明
        Column({ space: 10 }) {
          Text('说明')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#E5E7EB')
            .width('100%')
          Row() {
            Text('版本').fontSize(13).fontColor('#E5E7EB')
            Blank()
            Text(this.version).fontSize(13).fontColor('#9CA3AF')
          }
          .width('100%')
          Row() {
            Text('适配').fontSize(13).fontColor('#E5E7EB')
            Blank()
            Text('HarmonyOS 6+ · 纯血鸿蒙 NEXT').fontSize(13).fontColor('#9CA3AF')
          }
          .width('100%')
        }
        .width('100%')
        .padding(14)
        .backgroundColor('#131318')
        .borderRadius(12)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 32 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0B0B0F')
  }
}
