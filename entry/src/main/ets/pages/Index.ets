import { AppSettings } from '../net/AppSettings';
import { LoginPage } from './LoginPage';
import { SceneListPage } from './SceneListPage';
import { PerformerListPage } from './PerformerListPage';
import { StudioListPage } from './StudioListPage';
import { SettingsPage } from './SettingsPage';

// 主框架：未配置档案时显示登录页，已配置时显示四个 Tab
@Entry
@Component
struct Index {
  @State private ready: boolean = AppSettings.instance.hasProfile();
  @State private currentTab: number = 0;

  onPageShow(): void {
    this.ready = AppSettings.instance.hasProfile();
  }

  build() {
    if (!this.ready) {
      // 未配置：登录页全屏
      LoginPage({
        onSaved: () => {
          this.ready = true;
        }
      })
    } else {
      Tabs({ barPosition: BarPosition.End, index: this.currentTab }) {
        TabContent() {
          SceneListPage()
        }
        .tabBar(this.tabItem('短片', '▶', this.currentTab === 0))

        TabContent() {
          PerformerListPage()
        }
        .tabBar(this.tabItem('演员', '◉', this.currentTab === 1))

        TabContent() {
          StudioListPage()
        }
        .tabBar(this.tabItem('工作室', '🏢', this.currentTab === 2))

        TabContent() {
          SettingsPage({
            onReset: () => {
              this.ready = false;
            }
          })
        }
        .tabBar(this.tabItem('设置', '⚙', this.currentTab === 3))
      }
      .barMode(BarMode.Fixed)
      .barHeight(56)
      .onChange((index: number) => {
        this.currentTab = index;
      })
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  private tabItem(label: string, symbol: string, active: boolean) {
    Column({ space: 3 }) {
      Text(symbol)
        .fontSize(18)
      Text(label)
        .fontSize(11)
        .fontColor(active ? '#1E5EFF' : '#999999')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
