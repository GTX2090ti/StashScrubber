import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppSettings } from '../net/AppSettings';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'StashScrubber', 'Ability onCreate');
    AppSettings.instance.init(this.context);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'StashScrubber', 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(0x0000, 'StashScrubber', 'Content loaded');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, 'StashScrubber', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(0x0000, 'StashScrubber', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(0x0000, 'StashScrubber', 'Ability onBackground');
  }
}
