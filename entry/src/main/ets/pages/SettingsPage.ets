import { AppSettings } from '../net/AppSettings';
import { NetLog } from '../net/NetLog';
import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';

// 设置页（鸿蒙官方分组列表风格）
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
    List() {
      ListItemGroup({ header: this.groupHeader('当前服务器') }) {
        ListItem() {
          Column({ space: 4 }) {
            Text(this.currentProfileLabel()).fontSize(14).width('100%').lineHeight(20)
            Text('切换/编辑服务器请返回登录页重新配置')
              .fontSize(12)
              .fontColor('#999999')
              .width('100%')
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
          .alignItems(HorizontalAlign.Start)
        }
      }

      ListItemGroup({ header: this.groupHeader('网络日志') }) {
        ListItem() {
          Text('记录每次 GraphQL 请求的结果，可一键复制用于排障')
            .fontSize(13)
            .fontColor('#666666')
            .width('100%')
            .padding({ top: 8, bottom: 8 })
        }
        ListItem() {
          Row({ space: 10 }) {
            Button(this.showLog ? '收起日志' : '查看日志', { type: ButtonType.Normal })
              .fontSize(13)
              .height(36)
              .layoutWeight(1)
              .onClick(() => {
                this.showLog = !this.showLog;
                if (this.showLog) {
                  this.logText = NetLog.instance.exportText();
                }
              })
            Button('复制日志', { type: ButtonType.Normal })
              .fontSize(13)
              .height(36)
              .layoutWeight(1)
              .onClick(() => {
                this.copyLog();
              })
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
        }
        if (this.showLog) {
          ListItem() {
            Text(this.logText)
              .fontSize(11)
              .fontColor('#666666')
              .width('100%')
              .maxLines(12)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
      }

      ListItemGroup({ header: this.groupHeader('账号') }) {
        ListItem() {
          Button('重置服务器配置（返回登录页）')
            .fontSize(14)
            .height(44)
            .width('100%')
            .fontColor('#D94838')
            .backgroundColor('#FDF0EF')
            .borderRadius(10)
            .onClick(() => {
              this.resetConfig();
            })
        }
      }

      ListItemGroup({ header: this.groupHeader('说明') }) {
        ListItem() {
          Row() {
            Text('版本').fontSize(14)
            Blank()
            Text(this.version).fontSize(14).fontColor('#666666')
          }
          .width('100%')
          .height(44)
        }
        ListItem() {
          Row() {
            Text('适配').fontSize(14)
            Blank()
            Text('HarmonyOS 6+ · 纯血鸿蒙 NEXT').fontSize(14).fontColor('#666666')
          }
          .width('100%')
          .height(44)
        }
      }
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  @Builder
  private groupHeader(text: string) {
    Text(text)
      .fontSize(13)
      .fontColor('#666666')
      .width('100%')
      .padding({ left: 16, top: 14, bottom: 6 })
  }
}
