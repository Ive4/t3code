import type { UiLanguage } from './UiLanguage';
import { uiText } from './UiLanguage';
import type { WorkspaceFilterGroup, WorkspaceSharedTab } from './WorkspaceChrome';
import {
  WorkspaceFilterButton, workspaceForegroundColor, workspaceHeaderColor, workspaceMutedColor, workspaceSurfaceColor,
} from './WorkspaceChrome';
import type { SettingsRowContent } from './WorkspaceSettingsRows';
import { WorkspaceSettingsRows } from './WorkspaceSettingsRows';

export type WorkspaceSettingsPage = 'general' | 'language' | 'chat' | 'keyboard' | 'about' |
  'client-storage' | 'diagnostics' | 'licenses' | 'legal' | 'notifications' | 'providers' | 'thread-preferences' |
  'scheduled-tasks' | 'source-control' | 'worktrees' | 'maintenance' | 'labs';

type SettingsEntryId = WorkspaceSettingsPage | WorkspaceSharedTab | 'account' | 'environments' |
  'projects' | 'archive' | 'voice';

interface SettingsEntry {
  id: SettingsEntryId;
  zh: string;
  en: string;
  icon: Resource;
  terms: string[];
  requiresConnection?: boolean;
}

interface SettingsSection {
  key: string;
  zh: string;
  en: string;
  rows: SettingsEntry[];
}

const PULLS_ENTRY: SettingsEntry = {
  id: 'pullRequests', zh: '拉取请求', en: 'Pull requests',
  icon: $r('sys.symbol.point_bottomleft_forward_to_point_topright_scurvepath'),
  terms: ['pulls', 'pr', '合并请求'],
};

const ISSUES_ENTRY: SettingsEntry = {
  id: 'issues', zh: '工单', en: 'Issues',
  icon: $r('sys.symbol.exclamationmark_circle'), terms: ['issue', 'tickets', '问题'],
};

const SECTIONS: SettingsSection[] = [
  {
    key: 'connections', zh: '连接', en: 'Connections', rows: [
      { id: 'account', zh: 'T3 账号', en: 'T3 Account', icon: $r('sys.symbol.person_head_on_circle'),
        terms: ['t3 账户', '登录', '退出登录', '邮箱', 'sign in', 'sign out', 'login', 'clerk', 'connect'] },
      { id: 'environments', zh: '环境', en: 'Environments', icon: $r('sys.symbol.computer'),
        terms: ['服务器', '配对', '添加环境', '远程', 'server', 'pair', 'remote', 'tailscale'] },
      { id: 'notifications', zh: '通知', en: 'Notifications', icon: $r('sys.symbol.bell'),
        terms: ['提醒', '推送', '活动', 'push', 'alerts', 'agent activity'] },
    ],
  },
  {
    key: 'general', zh: '', en: '', rows: [
      { id: 'general', zh: '通用', en: 'General', icon: $r('sys.symbol.gearshape'),
        terms: ['语言', '项目分组', '侧栏', '新会话', 'language', 'locale', 'english', 'project grouping', 'sidebar'] },
      { id: 'chat', zh: '聊天', en: 'Chat', icon: $r('sys.symbol.message_on_message'),
        terms: ['排队', '跟进', '介入', 'follow-up', 'queue', 'steer'] },
      { id: 'keyboard', zh: '键盘', en: 'Keyboard', icon: $r('sys.symbol.keyboard'),
        terms: ['回车', '发送消息', '换行', '硬件键盘', 'return key', 'new line'] },
      { id: 'voice', zh: '语音', en: 'Voice', icon: $r('sys.symbol.mic'),
        terms: ['麦克风', '听写', '转写', 'microphone', 'dictation', 'transcription'] },
    ],
  },
  {
    key: 'agents', zh: '代理', en: 'Agents', rows: [
      { id: 'providers', zh: '提供商', en: 'Providers', icon: $r('sys.symbol.person_head_on_circle'),
        terms: ['代理账号', '认证', 'codex', 'claude', 'cursor', 'opencode'], requiresConnection: true },
      { id: 'thread-preferences', zh: '会话', en: 'Threads', icon: $r('sys.symbol.message'),
        terms: ['默认工作区', '默认权限', '流式回复', '用量限额', '自动收尾', 'workspace', 'streaming'],
        requiresConnection: true },
      { id: 'scheduled-tasks', zh: '定时任务', en: 'Scheduled tasks', icon: $r('sys.symbol.clock'),
        terms: ['自动化', '计划', 'cron', 'webhook', 'automations', 'recurring'] },
    ],
  },
  {
    key: 'code', zh: '代码', en: 'Code', rows: [
      { id: 'projects', zh: '项目', en: 'Projects', icon: $r('sys.symbol.folder'),
        terms: ['工作区', '项目管理', '仓库', 'workspace', 'checkouts'] },
      { id: 'source-control', zh: '源码控制与工单', en: 'Source control & issues',
        icon: $r('sys.symbol.arrow_triangle_merge'), requiresConnection: true,
        terms: ['git', '拉取请求', '分支', '克隆', 'pull requests', 'clone'] },
      { id: 'worktrees', zh: '工作树', en: 'Worktrees', icon: $r('sys.symbol.square_on_square_fill'),
        terms: ['分支前缀', '子模块', 'submodules', 'branch naming'], requiresConnection: true },
    ],
  },
  {
    key: 'maintenance', zh: '', en: '', rows: [
      { id: 'maintenance', zh: '维护', en: 'Maintenance', icon: $r('sys.symbol.arrow_clockwise'),
        terms: ['更新', '版本', '重启', '环境', 'updates', 'restart'], requiresConnection: true },
      { id: 'labs', zh: '实验室', en: 'Labs', icon: $r('sys.symbol.laboratories'),
        terms: ['测试版', '关联环境', '快速工作树', 'beta', 'linked environments', 'worktree checkout'] },
      { id: 'about', zh: '关于', en: 'About', icon: $r('sys.symbol.info_circle'),
        terms: ['版本', '存储', '诊断', '开源许可', '法律', 'version', 'storage', 'diagnostics', 'licenses', 'legal'] },
      { id: 'archive', zh: '归档', en: 'Archive', icon: $r('sys.symbol.archivebox'),
        terms: ['archived', '归档会话', '归档任务', '恢复', 'restore'] },
    ],
  },
];

const SEARCH_ID = 'workspace-settings-search';

@Component
export struct WorkspaceSettings {
  @Prop language: UiLanguage = 'zh';
  @Prop dark: boolean = false;
  @Prop query: string = '';
  @Prop searchOpen: boolean = false;
  @Prop accountValue: string = '';
  @Prop environmentCount: number = 0;
  @Prop connected: boolean = false;
  @Prop projectLabel: string = '';
  @Prop showNotifications: boolean = true;
  @Prop sharedTab: WorkspaceSharedTab = 'pullRequests';
  @Prop filterGroups: WorkspaceFilterGroup[] = [];
  @Prop filterActive: boolean = false;
  @Prop scrollOffset: number = 0;
  scroller: Scroller | undefined = undefined;
  onQuery: (query: string) => void = () => {};
  onAccount: () => void = () => {};
  onEnvironments: () => void = () => {};
  onArchive: () => void = () => {};
  onProjects: () => void = () => {};
  onSearch: () => void = () => {};
  onCloseSearch: () => void = () => {};
  onSelectSharedTab: (tab: WorkspaceSharedTab) => void = () => {};
  onFilter: (key: string) => void = () => {};
  onOpenPage: (page: WorkspaceSettingsPage) => void = () => {};
  private searchController: TextInputController = new TextInputController();
  private focusSearchOnLayout: boolean = false;

  private sections(): SettingsSection[] {
    const row = this.sharedTab === 'issues' ? PULLS_ENTRY : ISSUES_ENTRY;
    const overflow: SettingsSection = { key: 'overflow:' + row.id, zh: '', en: '', rows: [row] };
    return [overflow].concat(SECTIONS);
  }

  private matches(entry: SettingsEntry, section: SettingsSection): boolean {
    if (entry.id === 'notifications' && !this.showNotifications) return false;
    const query = this.query.normalize('NFKC').trim().toLowerCase();
    if (!query) return true;
    const terms = [entry.zh, entry.en, section.zh, section.en].concat(entry.terms);
    return query.split(/\s+/).every((word: string) =>
      terms.some((term: string) => term.toLowerCase().includes(word)));
  }

  private rows(section: SettingsSection): SettingsRowContent[] {
    return section.rows.filter((entry) => this.matches(entry, section)).map((entry): SettingsRowContent => {
      const content: SettingsRowContent = {
        id: 'settings-' + entry.id, label: uiText(this.language, entry.zh, entry.en), icon: entry.icon, kind: 'link',
      };
      switch (entry.id) {
        case 'account': content.detail = this.accountValue; break;
        case 'environments': content.value = `${this.environmentCount}`; break;
        case 'projects':
          content.detail = this.projectLabel || undefined;
          if (!this.connected) content.value = uiText(this.language, '未连接', 'Disconnected');
          break;
        case 'archive':
          if (!this.connected) content.value = uiText(this.language, '未连接', 'Disconnected');
          break;
        case 'voice': content.disabled = true; break;
        default:
          if (entry.requiresConnection && !this.connected) content.disabled = true;
      }
      return content;
    });
  }

  private select(section: SettingsSection, row: SettingsRowContent): void {
    const entry = section.rows.find((value) => 'settings-' + value.id === row.id);
    if (!entry) return;
    this.searchController.stopEditing();
    switch (entry.id) {
      case 'account': this.onAccount(); break;
      case 'environments': this.onEnvironments(); break;
      case 'projects': this.onProjects(); break;
      case 'archive': this.onArchive(); break;
      case 'issues':
      case 'pullRequests': this.onSelectSharedTab(entry.id); break;
      case 'voice': break;
      default: this.onOpenPage(entry.id);
    }
  }

  private searchLabel(): string {
    return uiText(this.language, '搜索设置', 'Search settings');
  }

  private scrollToTop(): void {
    this.scroller?.scrollTo({ xOffset: 0, yOffset: 0 });
  }

  @Builder
  private SearchButton(id: string, icon: Resource, label: string, action: () => void) {
    Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      SymbolGlyph(icon).fontSize(24).fontColor([workspaceForegroundColor(this.dark)])
    }
    .id(id)
    .width(48)
    .height(48)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .accessibilityText(label)
    .onClick(action)
  }

  @Builder
  private Header() {
    Row() {
      if (this.searchOpen || this.query.length > 0) {
        this.SearchButton('workspace-settings-close-search', $r('sys.symbol.arrow_left'),
          uiText(this.language, '关闭搜索', 'Close search'), () => {
            this.searchController.stopEditing();
            this.onCloseSearch();
            this.scrollToTop();
          })
        TextInput({ text: this.query, placeholder: this.searchLabel(), controller: this.searchController })
          .id(SEARCH_ID)
          .accessibilityText(this.searchLabel())
          .height(44)
          .layoutWeight(1)
          .fontSize(16)
          .fontColor(workspaceForegroundColor(this.dark))
          .placeholderColor(workspaceMutedColor(this.dark))
          .backgroundColor(this.dark ? '#292929' : '#EAEAEB')
          .borderRadius(22)
          .cancelButton({ style: CancelButtonStyle.INPUT })
          .enterKeyType(EnterKeyType.Search)
          .enableKeyboardOnFocus(true)
          .onChange((query: string) => {
            this.onQuery(query);
            this.scrollToTop();
          })
          .onSubmit(() => this.searchController.stopEditing())
          .onAreaChange(() => {
            if (this.focusSearchOnLayout && focusControl.requestFocus(SEARCH_ID)) {
              this.focusSearchOnLayout = false;
            }
          })
      } else {
        Text(uiText(this.language, '设置', 'Settings'))
          .fontSize(21)
          .fontWeight(FontWeight.Medium)
          .fontColor(workspaceForegroundColor(this.dark))
          .layoutWeight(1)
          .margin({ left: 12 })
        this.SearchButton('workspace-settings-open-search', $r('sys.symbol.magnifyingglass'), this.searchLabel(), () => {
          this.focusSearchOnLayout = true;
          this.onSearch();
        })
      }
      WorkspaceFilterButton({
        groups: this.filterGroups,
        customized: this.filterActive,
        dark: this.dark,
        language: this.language,
        label: uiText(this.language, '筛选设置中的环境和项目', 'Filter settings environments and projects'),
        onFilter: this.onFilter,
      })
    }
    .width('100%')
    .height(56)
    .padding({ left: 4, right: 4 })
  }

  @Builder
  private EmptyState() {
    Column({ space: 8 }) {
      Text(uiText(this.language, '无结果', 'No results'))
        .fontSize(21)
        .lineHeight('28fp')
        .fontWeight(FontWeight.Bold)
        .fontColor(workspaceForegroundColor(this.dark))
        .textAlign(TextAlign.Center)
      Text(uiText(this.language, `没有与“${this.query.trim()}”匹配的设置。`,
        `No settings match “${this.query.trim()}”.`))
        .fontSize(16)
        .lineHeight('23fp')
        .fontColor(workspaceMutedColor(this.dark))
        .wordBreak(WordBreak.BREAK_WORD)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding(32)
    .accessibilityGroup(true)
  }

  build() {
    Column() {
      this.Header()
      Scroll(this.scroller) {
        Column({ space: 16 }) {
          if (this.sections().some((section) => section.rows.some((entry) => this.matches(entry, section)))) {
            ForEach(this.sections(), (section: SettingsSection) => {
              if (section.rows.some((entry) => this.matches(entry, section))) {
                WorkspaceSettingsRows({
                  title: uiText(this.language, section.zh, section.en),
                  rows: this.rows(section),
                  dark: this.dark,
                  onSelect: (row: SettingsRowContent) => this.select(section, row),
                })
              }
            }, (section: SettingsSection) => section.key)
          } else {
            this.EmptyState()
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 36 })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .initialOffset({ xOffset: 0, yOffset: this.scrollOffset })
      .backgroundColor(workspaceSurfaceColor(this.dark))
      .borderRadius({ topLeft: 28, topRight: 28 })
      .clip(true)
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor(workspaceHeaderColor(this.dark))
  }
}
