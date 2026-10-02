import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { graphqlURL, normalizeBase } from '../model/Models';

// 档案配置：一套 Stash 服务（内网/外网地址 + API Key）
export interface ProfileInfo {
  name: string;
  lanUrl: string;
  wanUrl: string;
  apiKey: string;
}

export class AppSettings {
  static instance: AppSettings = new AppSettings();

  profiles: ProfileInfo[] = [];
  currentProfileName: string = '';
  private pref: preferences.Preferences | null = null;
  private inited: boolean = false;

  private constructor() {
  }

  // 由 EntryAbility.onCreate 调用
  init(context: common.UIAbilityContext): void {
    if (this.inited) {
      return;
    }
    this.inited = true;
    preferences.getPreferences(context, 'stash_settings').then((p) => {
      this.pref = p;
      // 读档案列表
      const rawProfiles = p.getSync('profiles', '[]') as string;
      try {
        const arr = JSON.parse(rawProfiles) as ProfileInfo[];
        if (Array.isArray(arr)) {
          this.profiles = arr;
        }
      } catch (e) {
        this.profiles = [];
      }
      this.currentProfileName = p.getSync('currentProfile', '') as string;
    }).catch((e: Error) => {
      console.error('AppSettings init failed: ' + JSON.stringify(e));
    });
  }

  // 是否已配置且连接过（登录成功过）
  hasProfile(): boolean {
    return this.profiles.length > 0 && this.currentProfileName !== '';
  }

  currentProfile(): ProfileInfo | null {
    if (this.currentProfileName === '') {
      return null;
    }
    for (const p of this.profiles) {
      if (p.name === this.currentProfileName) {
        return p;
      }
    }
    return null;
  }

  // 登录页：新增/更新档案并设为当前
  saveProfile(profile: ProfileInfo): void {
    let found = false;
    const next: ProfileInfo[] = [];
    for (const p of this.profiles) {
      if (p.name === profile.name) {
        next.push(profile);
        found = true;
      } else {
        next.push(p);
      }
    }
    if (!found) {
      next.push(profile);
    }
    this.profiles = next;
    this.currentProfileName = profile.name;
    this.flush();
  }

  removeProfile(name: string): void {
    this.profiles = this.profiles.filter((p) => p.name !== name);
    if (this.currentProfileName === name) {
      this.currentProfileName = this.profiles.length > 0 ? this.profiles[0].name : '';
    }
    this.flush();
  }

  flush(): void {
    if (this.pref === null) {
      return;
    }
    try {
      this.pref.putSync('profiles', JSON.stringify(this.profiles));
      this.pref.putSync('currentProfile', this.currentProfileName);
      this.pref.flush();
    } catch (e) {
      console.error('AppSettings flush failed: ' + JSON.stringify(e));
    }
  }

  // 当前生效地址：优先内网，失败可切外网（简化：先内网）
  activeBaseURL(): string {
    const p = this.currentProfile();
    if (p === null) {
      return '';
    }
    return normalizeBase(p.lanUrl);
  }

  apiKey(): string {
    const p = this.currentProfile();
    return p === null ? '' : p.apiKey;
  }

  profileName(): string {
    return this.currentProfileName;
  }
}
