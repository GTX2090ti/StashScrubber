// 网络请求日志（内存环形缓冲 + 一键复制），与 iOS 版一致

export interface LogEntry {
  id: number;
  date: string;
  level: string;
  category: string;
  title: string;
  detail: string;
}

export class NetLog {
  static instance: NetLog = new NetLog();
  static capacity: number = 400;

  entries: LogEntry[] = [];
  private seq: number = 0;

  private constructor() {
  }

  record(category: string, level: string, title: string, detail: string = ''): void {
    const now = new Date();
    const pad = (n: number): string => n < 10 ? '0' + n.toString() : n.toString();
    const ts = pad(now.getHours()) + ':' + pad(now.getMinutes()) + ':' + pad(now.getSeconds());
    this.entries.push({
      id: this.seq++,
      date: ts,
      level: level,
      category: category,
      title: title,
      detail: detail
    });
    if (this.entries.length > NetLog.capacity) {
      this.entries = this.entries.slice(this.entries.length - NetLog.capacity);
    }
  }

  clear(): void {
    this.entries = [];
  }

  exportText(): string {
    const lines: string[] = [];
    lines.push('StashScrubber · 网络日志（共 ' + this.entries.length + ' 条）');
    for (const e of this.entries) {
      let line = '[' + e.date + '] ' + e.level + ' ' + e.category + ' | ' + e.title;
      if (e.detail !== '') {
        line += '\n    ' + e.detail;
      }
      lines.push(line);
    }
    return lines.join('\n');
  }
}
