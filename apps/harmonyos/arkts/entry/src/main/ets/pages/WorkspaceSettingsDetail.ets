import { bundleManager } from '@kit.AbilityKit';
import type { UiLanguage, UiLanguagePreference } from './UiLanguage';
import { uiText } from './UiLanguage';
import {
  workspaceForegroundColor, workspaceHeaderColor, workspaceMutedColor, workspaceSurfaceColor,
} from './WorkspaceChrome';
import type { WorkspaceSettingsPage } from './WorkspaceSettings';
import type { SettingsRowContent } from './WorkspaceSettingsRows';
import { WorkspaceSettingsRows } from './WorkspaceSettingsRows';

interface DetailGroup {
  title: string;
  rows: SettingsRowContent[];
}

type TranslatedTitle = [string, string];

const TITLES: Record<WorkspaceSettingsPage, TranslatedTitle> = {
  'general': ['通用', 'General'],
  'language': ['语言', 'Language'],
  'chat': ['聊天', 'Chat'],
  'keyboard': ['键盘', 'Keyboard'],
  'about': ['关于', 'About'],
  'client-storage': ['客户端存储', 'Client storage'],
  'diagnostics': ['诊断', 'Diagnostics'],
  'licenses': ['开源许可', 'Open source licenses'],
  'legal': ['法律信息', 'Legal'],
  'notifications': ['通知', 'Notifications'],
  'providers': ['提供商', 'Providers'],
  'thread-preferences': ['会话', 'Threads'],
  'scheduled-tasks': ['定时任务', 'Scheduled tasks'],
  'source-control': ['源码控制与工单', 'Source control & issues'],
  'worktrees': ['工作树', 'Worktrees'],
  'maintenance': ['维护', 'Maintenance'],
  'labs': ['实验室', 'Labs'],
};

const LANGUAGES: UiLanguagePreference[] = ['system', 'en', 'zh'];

function link(id: string, label: string, icon: Resource, detail?: string): SettingsRowContent {
  return { id: 'settings-detail-' + id, label, icon, detail, kind: 'link' };
}

function choice(label: string, detail?: string): SettingsRowContent {
  return { id: label, label, detail, kind: 'choice' };
}

function toggle(label: string, detail?: string): SettingsRowContent {
  return { id: label, label, detail, kind: 'switch' };
}

function group(title: string, ...rows: SettingsRowContent[]): DetailGroup {
  return { title, rows };
}

@Component
export struct WorkspaceSettingsDetail {
  @Prop page: WorkspaceSettingsPage = 'general';
  @Prop language: UiLanguage = 'zh';
  @Prop languagePreference: UiLanguagePreference = 'system';
  @Prop dark: boolean = false;
  @Prop connected: boolean = false;
  @Prop signedIn: boolean = false;
  @Prop environmentLabel: string = '';
  @State private version: string = '';
  onLanguage: (value: UiLanguagePreference) => void = () => {};
  onBack: () => void = () => {};
  onOpenPage: (page: WorkspaceSettingsPage) => void = () => {};
  onAccount: () => void = () => {};
  onEnvironments: () => void = () => {};
  onActiveEnvironment: () => void = () => {};

  aboutToAppear(): void {
    try {
      const bundle = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.version = bundle.versionName ? `${bundle.versionName} (${bundle.versionCode})` : '';
    } catch (_) {
      this.version = '';
    }
  }

  private text(zh: string, en: string): string {
    return uiText(this.language, zh, en);
  }

  private languageName(value: UiLanguagePreference): string {
    switch (value) {
      case 'system': return this.text('跟随系统', 'System default');
      case 'zh': return '简体中文';
      case 'en': return 'English';
    }
  }

  private groups(): DetailGroup[] {
    switch (this.page) {
      case 'general':
        return [
          group('', link('language', this.text('语言', 'Language'), $r('sys.symbol.keyboard_badge_globe'),
            this.languageName(this.languagePreference))),
          group(this.text('项目分组', 'Project grouping'),
            choice(this.text('按仓库分组', 'Group by repository'),
              this.text('相同仓库合并显示为一个项目。', 'Show checkouts of the same repository as one project.')),
            choice(this.text('按仓库路径分组', 'Group by repository path'),
              this.text('单体仓库中的不同路径分别显示。', 'Show different paths in a monorepo separately.')),
            choice(this.text('分别显示', 'Show separately'),
              this.text('每个工作区显示为独立项目。', 'Show each workspace as a separate project.'))),
          group(this.text('侧栏', 'Sidebar'), toggle(this.text('聊天优先', 'Chats first'))),
          group(this.text('新会话', 'New chats'),
            toggle(this.text('使用上次的项目', 'Use last project'),
              this.text('新会话默认使用此设备最近打开的项目。', 'Start new chats in the last project used on this device.'))),
        ];
      case 'language':
        return [group('', ...LANGUAGES.map((value): SettingsRowContent => ({
          id: 'settings-detail-language-' + value,
          label: this.languageName(value),
          kind: 'choice',
          selected: this.languagePreference === value,
        })))];
      case 'chat':
        return [group(this.text('代理运行时', 'While the agent is running'),
          choice(this.text('排队', 'Queue'),
            this.text('当前轮次完成后再处理消息。', 'Handle the message after the current turn.')),
          choice(this.text('介入', 'Steer'),
            this.text('立即将消息发给代理，调整当前工作。', 'Send the message to the agent immediately to adjust its work.')))];
      case 'keyboard':
        return [group(this.text('回车键', 'Return key'),
          choice(this.text('发送消息', 'Send message'),
            this.text('Return 发送消息，Shift + Return 插入新行。', 'Return sends a message. Shift + Return inserts a new line.')),
          choice(this.text('插入新行', 'Insert new line'),
            this.text('Return 插入新行，Ctrl + Return 发送消息。', 'Return inserts a new line. Ctrl + Return sends a message.')))];
      case 'thread-preferences':
        return [
          group(this.text('默认工作区', 'Default workspace'),
            choice(this.text('继承', 'Inherit'),
              this.text('使用仓库的 t3.json，或当前检出目录。', 'Use the repository’s t3.json or the current checkout.')),
            choice(this.text('当前检出目录', 'Current checkout')), choice(this.text('新工作树', 'New worktree'))),
          group(this.text('默认权限', 'Default permissions'),
            choice(this.text('继承', 'Inherit')), choice(this.text('需要批准', 'Approval required')),
            choice(this.text('自动接受编辑', 'Auto-accept edits')), choice(this.text('自动', 'Auto')),
            choice(this.text('完全访问', 'Full access'))),
          group(this.text('回复流式显示', 'Response streaming'),
            choice(this.text('轮次完成后显示', 'Show when the turn ends'),
              this.text('等待代理完成本轮回复。', 'Wait for the agent to finish its reply.')),
            choice(this.text('显示已完成的段落', 'Show completed sections'),
              this.text('每个段落或代码块完成后立即显示。', 'Show each paragraph or code block as it finishes.'))),
          group(this.text('预览浏览器', 'Preview browser'),
            toggle(this.text('允许代理使用浏览器', 'Allow agents to use the browser'))),
          group(this.text('用量限额', 'Usage limits'),
            toggle(this.text('限额重置后恢复', 'Resume after limit resets')),
            toggle(this.text('暂缓至限额重置', 'Snooze until limit resets'))),
          group(this.text('自动收尾', 'Auto-settle'),
            toggle(this.text('自动收尾已合并的会话', 'Auto-settle merged threads')),
            toggle(this.text('自动收尾不活跃会话', 'Auto-settle inactive threads'))),
        ];
      case 'source-control':
        return [
          group(this.text('拉取请求', 'Pull requests'),
            toggle(this.text('合并时移除代理署名', 'Remove agent credits when merging'))),
          group(this.text('默认分支', 'Default branch'), toggle(this.text('自动拉取', 'Pull automatically'))),
          group(this.text('克隆', 'Clone'), toggle(this.text('按主机目录克隆', 'Clone into host folders'))),
        ];
      case 'worktrees':
        return [
          group(this.text('新工作树', 'New worktrees'),
            toggle(this.text('从远程分支开始', 'Start from the remote branch'))),
          group(this.text('工作树子模块', 'Worktree submodules'),
            choice(this.text('继承', 'Inherit')), choice(this.text('初始化子模块', 'Initialize submodules')),
            choice(this.text('跳过子模块', 'Skip submodules'))),
        ];
      case 'about':
        return [group(this.text('应用', 'App'),
          link('storage', this.text('客户端存储', 'Client storage'), $r('sys.symbol.archivebox')),
          link('diagnostics', this.text('诊断', 'Diagnostics'), $r('sys.symbol.stethoscope')),
          link('licenses', this.text('开源许可', 'Open source licenses'), $r('sys.symbol.doc_plaintext')),
          link('legal', this.text('法律信息', 'Legal'), $r('sys.symbol.doc_text')),
          { id: 'settings-detail-version', label: this.text('版本', 'Version'),
            value: this.version || this.text('不可用', 'Unavailable') })];
      case 'notifications':
        return [
          group(this.text('代理活动', 'Agent activity'),
            toggle(this.text('设备通知', 'Device notifications')),
            toggle(this.text('持续代理活动', 'Live agent activity'))),
          ...(!this.signedIn ? [group('', link('account', this.text('登录 T3 账号', 'Sign in to T3 Account'),
            $r('sys.symbol.person_head_on_circle')))] : []),
        ];
      case 'maintenance':
        return [
          group(this.text('管理环境', 'Manage environments'), this.connected && this.environmentLabel
            ? link('active-environment', this.environmentLabel, $r('sys.symbol.computer'))
            : link('environments', this.text('环境', 'Environments'), $r('sys.symbol.computer'))),
          group(this.text('更新', 'Updates'),
            toggle(this.text('检查提供商更新', 'Check for provider updates')),
            toggle(this.text('重启后继续', 'Resume after restart')),
            toggle(this.text('代理工作时保持唤醒', 'Keep awake while agents work'))),
        ];
      case 'client-storage':
        return [
          group(this.text('环境缓存', 'Environment cache'), { id: 'settings-detail-cache-unavailable',
            label: this.text('暂无法读取缓存状态', 'Cache status is unavailable') }),
          group(this.text('操作', 'Actions'), { id: 'settings-detail-clear-cache',
            label: this.text('清理缓存', 'Clear cache'), kind: 'link', disabled: true }),
        ];
      case 'diagnostics':
        return [
          group(this.text('启动崩溃', 'Startup crashes'), { id: 'settings-detail-crashes-unavailable',
            label: this.text('暂无法读取启动崩溃日志', 'Startup crash logs are unavailable') }),
          group(this.text('操作', 'Actions'), { id: 'settings-detail-copy-crash',
            label: this.text('复制崩溃报告', 'Copy crash report'), kind: 'link', disabled: true }),
        ];
      default: return [];
    }
  }

  private status(): string {
    switch (this.page) {
      case 'providers':
        return this.connected ? this.text('暂无法读取提供商。', 'Providers are unavailable.')
          : this.text('选择一个已连接的环境。', 'Select a connected environment.');
      case 'scheduled-tasks':
        return this.connected ? this.text('暂无法读取定时任务。', 'Scheduled tasks are unavailable.')
          : this.text('连接环境后即可查看和创建定时任务。', 'Connect an environment to view and create scheduled tasks.');
      case 'licenses': return this.text('暂无法读取开源许可。', 'Open source licenses are unavailable.');
      case 'legal': return this.text('暂无法加载法律信息。', 'Legal information is unavailable.');
      case 'chat': return this.text('聊天偏好暂不可用。', 'Chat preferences are unavailable.');
      case 'keyboard': return this.text('硬件键盘偏好暂不可用。', 'Hardware keyboard preferences are unavailable.');
      case 'notifications': return this.text('通知设置暂不可用。', 'Notification settings are unavailable.');
      case 'labs':
        return this.connected ? this.text('暂无法读取此环境的实验功能。', 'Labs for this environment are unavailable.')
          : this.text('连接环境后可查看实验功能。', 'Connect an environment to view Labs.');
      case 'general': return this.text('其他设置暂不可修改。', 'Other settings are unavailable.');
      case 'thread-preferences':
      case 'source-control':
      case 'worktrees':
      case 'maintenance': return this.text('设置修改暂不可用。', 'Settings changes are unavailable.');
      default: return '';
    }
  }

  private open(row: SettingsRowContent): void {
    switch (row.id) {
      case 'settings-detail-language': this.onOpenPage('language'); break;
      case 'settings-detail-language-system': this.onLanguage('system'); break;
      case 'settings-detail-language-en': this.onLanguage('en'); break;
      case 'settings-detail-language-zh': this.onLanguage('zh'); break;
      case 'settings-detail-storage': this.onOpenPage('client-storage'); break;
      case 'settings-detail-diagnostics': this.onOpenPage('diagnostics'); break;
      case 'settings-detail-licenses': this.onOpenPage('licenses'); break;
      case 'settings-detail-legal': this.onOpenPage('legal'); break;
      case 'settings-detail-account': this.onAccount(); break;
      case 'settings-detail-environments': this.onEnvironments(); break;
      case 'settings-detail-active-environment': this.onActiveEnvironment(); break;
    }
  }

  build() {
    Column() {
      Row() {
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.arrow_left')).fontSize(24).fontColor([workspaceForegroundColor(this.dark)])
        }
        .id('settings-detail-back')
        .width(48)
        .height(48)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText(this.text('返回', 'Back'))
        .onClick(() => this.onBack())
        Text(this.text(TITLES[this.page][0], TITLES[this.page][1]))
          .id('settings-detail-title')
          .fontSize(21)
          .fontWeight(FontWeight.Medium)
          .fontColor(workspaceForegroundColor(this.dark))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: 4, right: 16 })
      Scroll() {
        Column({ space: 16 }) {
          ForEach(this.groups(), (section: DetailGroup) => {
            WorkspaceSettingsRows({
              title: section.title, rows: section.rows, dark: this.dark,
              onSelect: (row: SettingsRowContent) => this.open(row),
            })
          }, (section: DetailGroup) => this.page + ':' + this.language + ':' + this.languagePreference +
            ':' + this.environmentLabel + ':' + section.title)
          if (this.status()) {
            Text(this.status()).fontSize(14).lineHeight('19fp').fontColor(workspaceMutedColor(this.dark))
              .width('100%').padding({ left: 16, right: 16, top: 4, bottom: 6 })
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 36 })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .backgroundColor(workspaceSurfaceColor(this.dark))
      .borderRadius({ topLeft: 28, topRight: 28 })
      .clip(true)
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor(workspaceHeaderColor(this.dark))
  }
}
