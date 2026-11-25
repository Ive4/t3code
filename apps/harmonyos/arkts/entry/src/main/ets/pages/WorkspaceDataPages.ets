import type { WorkspaceSharedTab } from './WorkspaceChrome';
import { WorkspacePullRequests } from './WorkspacePullRequests';
import { WorkspaceIssues } from './WorkspaceIssues';
import { WorkspaceUsage } from './WorkspaceUsage';
import type { NativePullRequestPage, NativePullRequestQuery, NativePullRequestRow } from '../client/PullRequestProtocol';
import type { NativePullRequestFilterMode, NativePullRequestFilterCandidatePage } from '../client/PullRequestFilterOptionsProtocol';
import type {
  NativeIssueCandidates, NativeIssueEntry, NativeIssueFilters, NativeIssuePage, NativeIssueScope,
} from '../client/IssueProtocol';
import type { NativeUsageAccount, NativeUsageLimitWindow, NativeUsageSummary, WorkspaceUsageView }
  from '../client/WorkspaceUsageProtocol';

export type WorkspaceDataTab = WorkspaceSharedTab | 'usage';

const SEARCH_FIELD_ID = 'workspace-data-search-query';

@Component
export struct WorkspaceDataPages {
  @Prop tab: WorkspaceDataTab = 'pullRequests';
  @Prop connected: boolean = false;
  @Prop environmentKey: string = '';
  @Prop environmentId: string = '';
  @Prop environmentLabel: string = '';
  @Prop viewOwner: string = '';
  @Prop query: string = '';
  @Prop searchOpen: boolean = false;
  onSelectSharedTab: (tab: WorkspaceSharedTab) => void = () => {};
  onSearch: () => void = () => {};
  onCloseSearch: () => void = () => {};
  onQuery: (query: string) => void = () => {};
  onApplyQuery: (key: string, tab: WorkspaceSharedTab, query: string) => void = () => {};
  onOpenEnvironments: () => void = () => {};
  onLoadPullRequests?: (key: string, input: NativePullRequestQuery) => Promise<NativePullRequestPage>;
  onLoadPullRequestFilters?: (key: string, mode: NativePullRequestFilterMode, projectId?: string,
    query?: string) => Promise<NativePullRequestFilterCandidatePage>;
  onOpenPullRequest: (key: string, row: NativePullRequestRow) => void = () => {};
  onLoadIssues?: (key: string, filters: NativeIssueFilters, cursors?: Record<string, string>,
    refresh?: boolean) => Promise<NativeIssuePage>;
  onLoadIssueCandidates?: (key: string, scope: NativeIssueScope) => Promise<NativeIssueCandidates>;
  onOpenIssue: (key: string, entry: NativeIssueEntry) => void = () => {};
  onLoadUsage?: (key: string, days: number) => Promise<NativeUsageSummary>;
  onLoadUsageLimits?: (key: string) => Promise<NativeUsageAccount[]>;
  onOpenUsageAccount: (key: string, account: NativeUsageAccount, window: NativeUsageLimitWindow) => void = () => {};

  @StorageLink('t3.arkts.workspaceUsageView') private usageView: WorkspaceUsageView = 'limits';
  @StorageLink('t3.arkts.workspaceUsageDays') private usageDays: number = 30;
  private searchController: TextInputController = new TextInputController();
  private focusSearchOnLayout: boolean = false;

  private sharedTitle(): string {
    return this.tab === 'issues' ? '工单' : '拉取请求';
  }

  @Builder
  private IconButton(id: string, icon: Resource, label: string, action: () => void) {
    Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([$r('sys.color.icon_primary')])
    }
    .id(id)
    .width(48)
    .height(48)
    .padding(0)
    .accessibilityText(label)
    .onClick(action)
  }

  @Builder
  private SharedTabMenu() {
    Menu() {
      MenuItem({ content: '拉取请求' })
        .selected(this.tab === 'pullRequests')
        .selectIcon(true)
        .onChange(() => this.onSelectSharedTab('pullRequests'))
      MenuItem({ content: '工单' })
        .selected(this.tab === 'issues')
        .selectIcon(true)
        .onChange(() => this.onSelectSharedTab('issues'))
    }
  }

  @Builder
  private Header() {
    Row({ space: 4 }) {
      if (this.tab === 'usage') {
        Text('用量')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
          .margin({ left: 8 })
      } else if (this.searchOpen || this.query.length > 0) {
        this.IconButton('workspace-data-search-close', $r('sys.symbol.arrow_left'), '关闭搜索', () => {
          this.searchController.stopEditing();
          this.onCloseSearch();
        })
        TextInput({ text: this.query, placeholder: `搜索${this.sharedTitle()}`, controller: this.searchController })
          .id(SEARCH_FIELD_ID)
          .height(44)
          .fontSize(16)
          .layoutWeight(1)
          .enterKeyType(EnterKeyType.Search)
          .enableKeyboardOnFocus(true)
          .accessibilityText(`搜索${this.sharedTitle()}`)
          .onChange((query: string) => this.onQuery(query))
          .onAreaChange(() => {
            if (this.focusSearchOnLayout && focusControl.requestFocus(SEARCH_FIELD_ID)) {
              this.focusSearchOnLayout = false;
            }
          })
      } else {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 6 }) {
            Text(this.sharedTitle())
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.font_primary'))
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(12)
              .fontColor([$r('sys.color.icon_secondary')])
          }
        }
        .id('workspace-shared-tab-menu')
        .height(48)
        .padding({ left: 8, right: 8 })
        .accessibilityText(`${this.sharedTitle()}，切换列表`)
        .bindMenu(this.SharedTabMenu)
        Blank()
        this.IconButton('workspace-data-search', $r('sys.symbol.magnifyingglass'), `搜索${this.sharedTitle()}`, () => {
          this.focusSearchOnLayout = true;
          this.onSearch();
        })
      }
    }
    .width('100%')
    .height(60)
    .padding({ left: 12, right: 12 })
    .backgroundColor($r('sys.color.comp_background_primary'))
  }

  @Builder
  private UsageOption(view: WorkspaceUsageView, label: string) {
    Button(label, { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
      .id(`workspace-usage-mode-${view}`)
      .height(40)
      .layoutWeight(1)
      .fontSize(14)
      .fontWeight(this.usageView === view ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.usageView === view ? $r('sys.color.font_primary') : $r('sys.color.font_secondary'))
      .backgroundColor(this.usageView === view ? $r('sys.color.comp_background_primary') : Color.Transparent)
      .accessibilitySelected(this.usageView === view)
      .onClick(() => { this.usageView = view; })
  }

  @Builder
  private UsageWindow(days: number, label: string) {
    Button(label, { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
      .id(`workspace-usage-window-${days}`)
      .height(40)
      .layoutWeight(1)
      .fontSize(13)
      .fontWeight(this.usageDays === days ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.usageDays === days ? $r('sys.color.font_primary') : $r('sys.color.font_secondary'))
      .backgroundColor(this.usageDays === days ? $r('sys.color.comp_background_primary') : Color.Transparent)
      .accessibilityText(`过去${label}`)
      .accessibilitySelected(this.usageDays === days)
      .onClick(() => { this.usageDays = days; })
  }

  @Builder
  private UsageControls() {
    Row({ space: 2 }) {
      this.UsageOption('cost', '费用')
      this.UsageOption('tokens', 'Token')
      this.UsageOption('limits', '限额')
    }
    .width('100%')
    .padding(4)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .borderRadius(24)
    if (this.usageView !== 'limits') {
      Row({ space: 2 }) {
        this.UsageWindow(1, '24 小时')
        this.UsageWindow(7, '7 天')
        this.UsageWindow(30, '30 天')
        this.UsageWindow(90, '90 天')
      }
      .width('100%')
      .padding(4)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .borderRadius(24)
    }
  }

  @Builder
  private EmptyState() {
    Column({ space: 10 }) {
      Text('连接环境')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .textAlign(TextAlign.Center)
      Text(this.tab === 'usage' ? '连接环境后可查看用量。' : `连接环境后可查看项目的${this.sharedTitle()}。`)
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
      Button('添加环境', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
        .id('workspace-data-connect')
        .constraintSize({ minHeight: 44 })
        .onClick(() => this.onOpenEnvironments())
    }
    .width('100%')
    .padding({ top: 36, bottom: 36, left: 12, right: 12 })
  }

  build() {
    Column() {
      this.Header()
      Scroll() {
        Column({ space: 12 }) {
          if (this.tab === 'usage') {
            this.UsageControls()
          }
          if (!this.connected || !this.environmentKey) {
            this.EmptyState()
          } else if (this.tab === 'pullRequests') {
            WorkspacePullRequests({
              sourceKey: this.environmentKey,
              preferenceScope: this.environmentId,
              viewOwner: this.viewOwner,
              query: this.query,
              onApplyQuery: (query: string) => this.onApplyQuery(this.environmentKey, 'pullRequests', query),
              onLoad: this.onLoadPullRequests
                ? (input: NativePullRequestQuery) => this.onLoadPullRequests!(this.environmentKey, input) : undefined,
              onLoadFilters: this.onLoadPullRequestFilters
                ? (mode: NativePullRequestFilterMode, projectId?: string, query?: string) =>
                  this.onLoadPullRequestFilters!(this.environmentKey, mode, projectId, query) : undefined,
              onOpen: (row: NativePullRequestRow) => this.onOpenPullRequest(this.environmentKey, row),
            })
          } else if (this.tab === 'issues') {
            WorkspaceIssues({
              environmentKey: this.environmentKey,
              viewOwner: this.viewOwner,
              query: this.query,
              onApplyQuery: (query: string) => this.onApplyQuery(this.environmentKey, 'issues', query),
              onLoad: this.onLoadIssues
                ? (filters: NativeIssueFilters, cursors?: Record<string, string>, refresh?: boolean) =>
                  this.onLoadIssues!(this.environmentKey, filters, cursors, refresh) : undefined,
              onLoadCandidates: this.onLoadIssueCandidates,
              onOpen: (entry: NativeIssueEntry) => this.onOpenIssue(this.environmentKey, entry),
            })
          } else {
            WorkspaceUsage({
              view: this.usageView,
              days: this.usageDays,
              environmentKey: this.environmentKey,
              environmentLabel: this.environmentLabel,
              onLoadSummary: this.onLoadUsage ? (days: number) => this.onLoadUsage!(this.environmentKey, days) : undefined,
              onLoadLimits: this.onLoadUsageLimits ? () => this.onLoadUsageLimits!(this.environmentKey) : undefined,
              onOpenAccount: (account: NativeUsageAccount, window: NativeUsageLimitWindow) =>
                this.onOpenUsageAccount(this.environmentKey, account, window),
            })
          }
        }
        .width('100%')
        .constraintSize({ maxWidth: 560 })
        .padding({ left: 20, right: 20, top: 16, bottom: 16 })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .layoutWeight(1)
  }
}
