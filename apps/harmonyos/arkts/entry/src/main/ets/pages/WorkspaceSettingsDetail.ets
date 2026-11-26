import { bundleManager } from '@kit.AbilityKit';
import { defaultOpenSourceLicenses, formatDiagnosticsReport } from '../client/AboutDiagnosticsProtocol';
import type { DiagnosticCrashEntry } from '../client/AboutDiagnosticsProtocol';
import { defaultClientPreferences, formatStorageBytes } from '../client/ClientPreferencesProtocol';
import type { ClientPreferenceKey, ClientPreferencesSnapshot, ClientPreferenceValue, ClientStorageSummary } from '../client/ClientPreferencesProtocol';
import type { EnvironmentPreferencesSnapshot } from '../client/EnvironmentPreferencesProtocol';
import type { NativeProviderSummary } from '../client/ProvidersProtocol';
import type { NativeScheduledTask } from '../client/ScheduledTasksProtocol';
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

function choice(id: string, label: string, selected: boolean, detail?: string): SettingsRowContent {
  return { id, label, detail, kind: 'choice', selected };
}

function toggle(id: string, label: string, selected: boolean, detail?: string): SettingsRowContent {
  return { id, label, detail, kind: 'switch', selected };
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
  @Prop clientPreferences: ClientPreferencesSnapshot = defaultClientPreferences();
  @Prop environmentPreferences: EnvironmentPreferencesSnapshot | undefined = undefined;
  @Prop providers: NativeProviderSummary[] = [];
  @Prop scheduledTasks: NativeScheduledTask[] = [];
  @Prop storageSummary: ClientStorageSummary | undefined = undefined;
  @Prop crashes: DiagnosticCrashEntry[] = [];
  @State private version: string = '';
  onLanguage: (value: UiLanguagePreference) => void = () => {};
  onClientPreference: (key: ClientPreferenceKey, value: ClientPreferenceValue) => void = () => {};
  onEnvironmentPatch: (patch: Record<string, Object | null | undefined>) => void = () => {};
  onToggleProvider: (instanceId: string, enabled: boolean, driver: string) => void = () => {};
  onToggleScheduledTask: (taskId: string, enabled: boolean) => void = () => {};
  onRunScheduledTask: (taskId: string) => void = () => {};
  onClearStorage: () => void = () => {};
  onCopyDiagnostics: (report: string) => void = () => {};
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
    const prefs = this.clientPreferences;
    const env = this.environmentPreferences;
    switch (this.page) {
      case 'general':
        return [
          group('', link('language', this.text('语言', 'Language'), $r('sys.symbol.keyboard_badge_globe'),
            this.languageName(this.languagePreference))),
          group(this.text('项目分组', 'Project grouping'),
            choice('pref:projectGrouping:repository', this.text('按仓库分组', 'Group by repository'),
              prefs.projectGrouping === 'repository',
              this.text('相同仓库合并显示为一个项目。', 'Show checkouts of the same repository as one project.')),
            choice('pref:projectGrouping:repository-path', this.text('按仓库路径分组', 'Group by repository path'),
              prefs.projectGrouping === 'repository-path',
              this.text('单体仓库中的不同路径分别显示。', 'Show different paths in a monorepo separately.')),
            choice('pref:projectGrouping:separate', this.text('分别显示', 'Show separately'),
              prefs.projectGrouping === 'separate',
              this.text('每个工作区显示为独立项目。', 'Show each workspace as a separate project.'))),
          group(this.text('侧栏', 'Sidebar'),
            toggle('pref:sidebarChatsFirst', this.text('聊天优先', 'Chats first'), prefs.sidebarChatsFirst)),
          group(this.text('新会话', 'New chats'),
            toggle('pref:useLastProject', this.text('使用上次的项目', 'Use last project'), prefs.useLastProject,
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
          choice('pref:runningAgentBehavior:queue', this.text('排队', 'Queue'),
            prefs.runningAgentBehavior === 'queue',
            this.text('当前轮次完成后再处理消息。', 'Handle the message after the current turn.')),
          choice('pref:runningAgentBehavior:steer', this.text('介入', 'Steer'),
            prefs.runningAgentBehavior === 'steer',
            this.text('立即将消息发给代理，调整当前工作。', 'Send the message to the agent immediately to adjust its work.')))];
      case 'keyboard':
        return [group(this.text('回车键', 'Return key'),
          choice('pref:composerReturnBehavior:send', this.text('发送消息', 'Send message'),
            prefs.composerReturnBehavior === 'send',
            this.text('Return 发送消息，Shift + Return 插入新行。', 'Return sends a message. Shift + Return inserts a new line.')),
          choice('pref:composerReturnBehavior:newline', this.text('插入新行', 'Insert new line'),
            prefs.composerReturnBehavior === 'newline',
            this.text('Return 插入新行，Ctrl + Return 发送消息。', 'Return inserts a new line. Ctrl + Return sends a message.')))];
      case 'thread-preferences':
        if (!env) return [];
        return [
          group(this.text('默认工作区', 'Default workspace'),
            choice('env:defaultThreadEnvMode:null', this.text('继承', 'Inherit'),
              env.threadPreferences.defaultThreadEnvMode === null,
              this.text('使用仓库的 t3.json，或当前检出目录。', 'Use the repository’s t3.json or the current checkout.')),
            choice('env:defaultThreadEnvMode:local', this.text('当前检出目录', 'Current checkout'),
              env.threadPreferences.defaultThreadEnvMode === 'local'),
            choice('env:defaultThreadEnvMode:worktree', this.text('新工作树', 'New worktree'),
              env.threadPreferences.defaultThreadEnvMode === 'worktree')),
          group(this.text('默认权限', 'Default permissions'),
            choice('env:defaultRuntimeMode:approval-required', this.text('需要批准', 'Approval required'),
              env.threadPreferences.defaultRuntimeMode === 'approval-required'),
            choice('env:defaultRuntimeMode:auto-accept-edits', this.text('自动接受编辑', 'Auto-accept edits'),
              env.threadPreferences.defaultRuntimeMode === 'auto-accept-edits'),
            choice('env:defaultRuntimeMode:auto', this.text('自动', 'Auto'),
              env.threadPreferences.defaultRuntimeMode === 'auto'),
            choice('env:defaultRuntimeMode:full-access', this.text('完全访问', 'Full access'),
              env.threadPreferences.defaultRuntimeMode === 'full-access')),
          group(this.text('回复流式显示', 'Response streaming'),
            choice('env:responseStreamingMode:turn', this.text('轮次完成后显示', 'Show when the turn ends'),
              env.threadPreferences.responseStreamingMode === 'turn',
              this.text('等待代理完成本轮回复。', 'Wait for the agent to finish its reply.')),
            choice('env:responseStreamingMode:paragraph', this.text('显示已完成的段落', 'Show completed sections'),
              env.threadPreferences.responseStreamingMode === 'paragraph',
              this.text('每个段落或代码块完成后立即显示。', 'Show each paragraph or code block as it finishes.'))),
          group(this.text('预览浏览器', 'Preview browser'),
            toggle('env:enableAgentBrowserAccess', this.text('允许代理使用浏览器', 'Allow agents to use the browser'),
              env.threadPreferences.enableAgentBrowserAccess)),
          group(this.text('用量限额', 'Usage limits'),
            toggle('env:autoResumeLimitedThreads', this.text('限额重置后恢复', 'Resume after limit resets'),
              env.threadPreferences.autoResumeLimitedThreads),
            toggle('env:snoozeLimitedThreads', this.text('暂缓至限额重置', 'Snooze until limit resets'),
              env.threadPreferences.snoozeLimitedThreads)),
          group(this.text('自动收尾', 'Auto-settle'),
            toggle('env:sidebarAutoSettleOnMerge', this.text('自动收尾已合并的会话', 'Auto-settle merged threads'),
              env.threadPreferences.sidebarAutoSettleOnMerge),
            toggle('env:sidebarAutoSettleAfterDays', this.text('自动收尾不活跃会话', 'Auto-settle inactive threads'),
              env.threadPreferences.sidebarAutoSettleAfterDays !== null)),
        ];
      case 'source-control':
        if (!env) return [];
        return [
          group(this.text('拉取请求', 'Pull requests'),
            toggle('env:removeAgentCreditsOnMerge', this.text('合并时移除代理署名', 'Remove agent credits when merging'),
              env.sourceControl.removeAgentCreditsOnMerge)),
          group(this.text('默认分支', 'Default branch'),
            toggle('env:defaultAutoPull', this.text('自动拉取', 'Pull automatically'), env.sourceControl.defaultAutoPull)),
          group(this.text('克隆', 'Clone'),
            toggle('env:ghqCloneLayout', this.text('按主机目录克隆', 'Clone into host folders'), env.sourceControl.ghqCloneLayout)),
        ];
      case 'worktrees':
        if (!env) return [];
        return [
          group(this.text('新工作树', 'New worktrees'),
            toggle('env:newWorktreesStartFromOrigin', this.text('从远程分支开始', 'Start from the remote branch'),
              env.worktrees.newWorktreesStartFromOrigin)),
          group(this.text('工作树子模块', 'Worktree submodules'),
            choice('env:worktreeSubmodules:null', this.text('继承', 'Inherit'),
              env.worktrees.worktreeSubmodules === null),
            choice('env:worktreeSubmodules:recursive', this.text('初始化子模块', 'Initialize submodules'),
              env.worktrees.worktreeSubmodules === 'recursive'),
            choice('env:worktreeSubmodules:none', this.text('跳过子模块', 'Skip submodules'),
              env.worktrees.worktreeSubmodules === 'none')),
        ];
      case 'providers':
        return [group(this.text('已安装的提供商', 'Installed providers'), ...this.providers.map((item): SettingsRowContent => ({
          id: 'provider:' + item.instanceId,
          label: item.displayName,
          detail: item.driver + ' · ' + (item.authStatus === 'authenticated'
            ? this.text('已认证', 'Authenticated')
            : this.text('未认证', 'Unauthenticated')),
          kind: 'switch',
          selected: item.enabled,
          disabled: !item.installed,
        })))];
      case 'scheduled-tasks':
        return [group(this.text('定时任务', 'Scheduled tasks'), ...this.scheduledTasks.map((task): SettingsRowContent => ({
          id: 'scheduled-task:' + task.id,
          label: task.title || task.id,
          detail: task.lastRunStatus + (task.nextRunAt ? ' · ' + task.nextRunAt : ''),
          kind: 'switch',
          selected: task.enabled,
        })))];
      case 'labs':
        if (!env) return [];
        return [
          group(this.text('实验功能', 'Experimental features'),
            toggle('env:fastWorktreeCheckout', this.text('快速工作树检出', 'Fast worktree checkout'),
              env.labs.fastWorktreeCheckout),
            toggle('env:linkedEnvironmentsEnabled', this.text('关联环境', 'Linked environments'),
              env.labs.linkedEnvironmentsEnabled),
            toggle('env:workflowsEnabled', this.text('工作流', 'Workflows'), env.labs.workflowsEnabled),
            toggle('env:promptSuggestionsEnabled', this.text('提示词建议', 'Prompt suggestions'),
              env.labs.promptSuggestionsEnabled)),
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
            toggle('notif:device', this.text('设备通知', 'Device notifications'), false),
            toggle('notif:live', this.text('持续代理活动', 'Live agent activity'), false)),
          ...(!this.signedIn ? [group('', link('account', this.text('登录 T3 账号', 'Sign in to T3 Account'),
            $r('sys.symbol.person_head_on_circle')))] : []),
        ];
      case 'maintenance':
        return [
          group(this.text('管理环境', 'Manage environments'), this.connected && this.environmentLabel
            ? link('active-environment', this.environmentLabel, $r('sys.symbol.computer'))
            : link('environments', this.text('环境', 'Environments'), $r('sys.symbol.computer'))),
          ...(env ? [group(this.text('更新', 'Updates'),
            toggle('env:enableProviderUpdateChecks', this.text('检查提供商更新', 'Check for provider updates'),
              env.maintenance.enableProviderUpdateChecks),
            toggle('env:continueThreadsAfterServerUpdate', this.text('重启后继续', 'Resume after restart'),
              env.maintenance.continueThreadsAfterServerUpdate),
            toggle('env:keepAwakeWhileAgentsWork', this.text('代理工作时保持唤醒', 'Keep awake while agents work'),
              env.maintenance.keepAwakeWhileAgentsWork))] : []),
        ];
      case 'client-storage':
        return [
          group(this.text('环境缓存', 'Environment cache'), {
            id: 'settings-detail-cache-summary',
            label: this.text('已缓存数据', 'Cached data'),
            value: this.storageSummary ? formatStorageBytes(this.storageSummary.cacheBytes) : '0 B',
          }),
          group(this.text('操作', 'Actions'), {
            id: 'settings-detail-clear-cache',
            label: this.text('清理缓存', 'Clear cache'),
            kind: 'link',
            disabled: !(this.storageSummary?.clearable ?? false),
          }),
        ];
      case 'diagnostics':
        return [
          group(this.text('启动崩溃', 'Startup crashes'),
            this.crashes.length > 0
              ? { id: 'settings-detail-crashes-count', label: this.text('记录到崩溃日志', 'Crash logs recorded'),
                  value: `${this.crashes.length}` }
              : { id: 'settings-detail-crashes-empty', label: this.text('暂无崩溃记录', 'No crash logs recorded') }),
          group(this.text('操作', 'Actions'), {
            id: 'settings-detail-copy-crash',
            label: this.text('复制诊断报告', 'Copy diagnostics report'),
            kind: 'link',
          }),
        ];
      case 'licenses':
        return [group(this.text('开源组件', 'Open source components'),
          ...defaultOpenSourceLicenses().map((item): SettingsRowContent => ({
            id: 'license:' + item.name,
            label: item.name,
            detail: item.repository,
            value: item.license,
          })))];
      case 'legal':
        return [group(this.text('条款与隐私', 'Terms & privacy'),
          { id: 'legal-notice', label: 'T3 Code', detail: 'https://t3.codes/privacy · https://t3.codes/terms' })];
      default: return [];
    }
  }

  private status(): string {
    switch (this.page) {
      case 'providers':
        return !this.connected
          ? this.text('选择一个已连接的环境。', 'Select a connected environment.')
          : (this.providers.length === 0 ? this.text('当前环境未检测到已安装的提供商。', 'No providers reported.') : '');
      case 'scheduled-tasks':
        return !this.connected
          ? this.text('连接环境后即可查看和管理定时任务。', 'Connect an environment to manage scheduled tasks.')
          : (this.scheduledTasks.length === 0 ? this.text('当前环境暂无定时任务。', 'No scheduled tasks.') : '');
      case 'labs':
        return this.connected ? '' : this.text('连接环境后可查看实验功能。', 'Connect an environment to view Labs.');
      case 'thread-preferences':
      case 'source-control':
      case 'worktrees':
      case 'maintenance':
        return this.connected && !this.environmentPreferences
          ? this.text('正在读取环境配置…', 'Loading environment settings…')
          : (this.connected ? '' : this.text('选择一个已连接的环境以修改此项。', 'Select a connected environment.'));
      default: return '';
    }
  }

  private open(row: SettingsRowContent): void {
    if (row.id.startsWith('pref:')) {
      const parts = row.id.split(':');
      const key = parts[1] as ClientPreferenceKey;
      if (parts.length >= 3) {
        this.onClientPreference(key, parts[2] as ClientPreferenceValue);
      } else {
        const current = key === 'sidebarChatsFirst'
          ? this.clientPreferences.sidebarChatsFirst
          : this.clientPreferences.useLastProject;
        this.onClientPreference(key, !current);
      }
      return;
    }
    if (row.id.startsWith('env:')) {
      const parts = row.id.split(':');
      const key = parts[1];
      const patch: Record<string, Object | null | undefined> = {};
      if (parts.length >= 3) {
        patch[key] = parts[2] === 'null' ? null : parts[2];
      } else {
        const nextValue = !(row.selected ?? false);
        patch[key] = key === 'sidebarAutoSettleAfterDays' ? (nextValue ? 7 : null) : nextValue;
      }
      this.onEnvironmentPatch(patch);
      return;
    }
    if (row.id.startsWith('provider:')) {
      const instanceId = row.id.slice('provider:'.length);
      const item = this.providers.find((entry) => entry.instanceId === instanceId);
      if (item) this.onToggleProvider(item.instanceId, !(row.selected ?? false), item.driver);
      return;
    }
    if (row.id.startsWith('scheduled-task:')) {
      const taskId = row.id.slice('scheduled-task:'.length);
      this.onToggleScheduledTask(taskId, !(row.selected ?? false));
      return;
    }
    switch (row.id) {
      case 'settings-detail-language': this.onOpenPage('language'); break;
      case 'settings-detail-language-system': this.onLanguage('system'); break;
      case 'settings-detail-language-en': this.onLanguage('en'); break;
      case 'settings-detail-language-zh': this.onLanguage('zh'); break;
      case 'settings-detail-storage': this.onOpenPage('client-storage'); break;
      case 'settings-detail-diagnostics': this.onOpenPage('diagnostics'); break;
      case 'settings-detail-licenses': this.onOpenPage('licenses'); break;
      case 'settings-detail-legal': this.onOpenPage('legal'); break;
      case 'settings-detail-clear-cache': this.onClearStorage(); break;
      case 'settings-detail-copy-crash':
        this.onCopyDiagnostics(formatDiagnosticsReport(this.version || '0.0.0', 0, this.crashes));
        break;
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
            ':' + this.environmentLabel + ':' + section.title + ':' +
            section.rows.map((row: SettingsRowContent) =>
              row.id + '=' + String(row.selected ?? '') + '=' + (row.value ?? '') + '=' + String(row.disabled ?? false)
            ).join(','))
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
