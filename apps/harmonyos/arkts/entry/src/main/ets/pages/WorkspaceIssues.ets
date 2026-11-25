import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import {
  ISSUE_FILTER_LABEL_LIMIT, issueCanShowEditor, issueCandidateScopes, issueListEmptyMessage, issueRefKey,
  issueSearchEntries, mergeIssueEntries,
} from '../client/IssueProtocol';
import type {
  NativeIssueActor, NativeIssueAssigneeFilter, NativeIssueCandidates, NativeIssueDetail, NativeIssueEditor,
  NativeIssueEntry, NativeIssueError, NativeIssueFacet, NativeIssueFilters, NativeIssueInvolvement, NativeIssueLabel,
  NativeIssueLinkedPullRequest, NativeIssuePage, NativeIssueRef, NativeIssueScope, NativeIssueSort, NativeIssueState,
  NativeIssueStateFilter, NativeIssueTracker,
} from '../client/IssueProtocol';
import {
  ISSUE_VIEW_NAME_LIMIT, issueSavedViewMatches, readIssueSavedViews, writeIssueSavedView,
} from '../client/IssueSavedViews';
import type { NativeIssueSavedView, NativeIssueViewScope } from '../client/IssueSavedViews';
import { WorkspaceIssueFilterSheet } from './WorkspaceIssueFilterSheet';

interface IssueFacetSelection {
  labels: string[];
  assignee: NativeIssueAssigneeFilter | null;
}

const issueFacetSelections = new Map<string, IssueFacetSelection>();

const actorName = (actor: NativeIssueActor | null): string => actor?.name || actor?.login || '未知用户';

function formatIssueDate(value: string): string {
  return new Date(value).toLocaleDateString();
}

function issueDisplayKey(issue: NativeIssueEntry): string {
  return issue.displayKey.startsWith(`${issue.scope}-`) ? issue.displayKey : `${issue.scope} ${issue.displayKey}`;
}

function issueError(error: Error, fallback: string): string {
  return error?.message || fallback;
}

interface IssueActivity {
  key: string;
  actor: string;
  body: string;
  time: string;
  event: boolean;
}

function issueActivity(detail: NativeIssueDetail): IssueActivity[] {
  const eventLabels: Record<string, string> = {
    'closed': '关闭了工单',
    'reopened': '重新打开了工单',
    'labeled': '添加了标签',
    'unlabeled': '移除了标签',
    'assigned': '添加了经办人',
    'unassigned': '移除了经办人',
    'renamed': '重命名了工单',
    'referenced': '引用了工单',
    'state-changed': '更新了状态',
  };
  const entries: IssueActivity[] = detail.comments.map((comment): IssueActivity => ({
    key: `comment-${comment.id}`, actor: actorName(comment.author), body: comment.body,
    time: comment.createdAt, event: false,
  }));
  detail.events.forEach((event) => {
    const label = eventLabels[event.kind] ?? '更新了工单';
    entries.push({
      key: `event-${event.id}`, actor: actorName(event.actor),
      body: event.detail ? `${label} · ${event.detail}` : label, time: event.createdAt, event: true,
    });
  });
  return entries.sort((left, right) => Date.parse(left.time) - Date.parse(right.time));
}

@Builder
function IssueStateLabel(state: NativeIssueState) {
  Text(state.name)
    .fontSize(12)
    .fontWeight(FontWeight.Medium)
    .fontColor(state.category === 'open' ? $r('sys.color.font_emphasize') : $r('sys.color.font_secondary'))
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .borderRadius(10)
    .maxLines(1)
    .textOverflow({ overflow: TextOverflow.Ellipsis })
}

@Builder
function IssueLabels(labels: NativeIssueLabel[], maxLabels: number) {
  Flex({ wrap: FlexWrap.Wrap }) {
    ForEach(labels.slice(0, maxLabels), (label: NativeIssueLabel) => {
      Text(label.name)
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .margin({ right: 6, bottom: 4 })
        .borderRadius(10)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }, (label: NativeIssueLabel) => label.name)
    if (labels.length > maxLabels) {
      Text(`+${labels.length - maxLabels}`)
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .padding(4)
    }
  }
  .width('100%')
}

@Component
export struct WorkspaceIssues {
  @Prop @Watch('environmentChanged') environmentKey: string = '';
  @Prop @Watch('ownerChanged') viewOwner: string = '';
  @Prop @Watch('scheduleSearch') query: string = '';
  onLoad?: (filters: NativeIssueFilters, cursors?: Record<string, string>, refresh?: boolean) => Promise<NativeIssuePage>;
  onLoadCandidates?: (key: string, scope: NativeIssueScope) => Promise<NativeIssueCandidates>;
  onOpen: (entry: NativeIssueEntry) => void = () => {};
  onApplyQuery: (query: string) => void = () => {};

  @StorageLink('t3.arkts.workspaceIssueState') private stateFilter: NativeIssueStateFilter = 'open';
  @StorageLink('t3.arkts.workspaceIssueSort') private sort: NativeIssueSort = 'updated';
  @StorageLink('t3.arkts.workspaceIssueInvolvement') private involvement: NativeIssueInvolvement = 'all';
  @State private page?: NativeIssuePage = undefined;
  @State private loading: boolean = true;
  @State private loadingMore: boolean = false;
  @State private error: string = '';
  @State private emptyText: string = '';
  @State private nextPageFailed: boolean = false;
  @State private issueLabels: string[] = [];
  @State private issueAssignee: NativeIssueAssigneeFilter | null = null;
  @State private showIssueFilter: boolean = false;
  @State private filterFacet: NativeIssueFacet = 'labels';
  @State private filterScopes: NativeIssueScope[] = [];
  @State private filterEnvironmentKey: string = '';
  @State private savedViews: NativeIssueSavedView[] = [];
  @State private selectedViewId: string = '';
  @State private viewsReady: boolean = false;
  @State private savingView: boolean = false;
  @State private viewError: string = '';
  @State private showViewName: boolean = false;
  @State private viewName: string = '';
  @State private editingView: NativeIssueSavedView | undefined = undefined;
  private viewsRequest: number = 0;
  private request: number = 0;
  private searchTimer: number = -1;
  private candidatePage?: NativeIssuePage;
  private filterOwner: string = '';

  aboutToAppear(): void {
    this.ownerChanged();
  }

  aboutToDisappear(): void {
    this.cancelPending();
    ++this.viewsRequest;
  }

  private viewScope(): NativeIssueViewScope {
    return {
      query: this.query, state: this.stateFilter, involvement: this.involvement, sort: this.sort,
      labels: this.issueLabels, assignee: this.issueAssignee,
    };
  }

  private selectedView(): NativeIssueSavedView | undefined {
    return this.savedViews.find((view) => view.id === this.selectedViewId) ??
      this.savedViews.find((view) => issueSavedViewMatches(view, this.viewScope()));
  }

  private modifiedView(): boolean {
    const selection = this.selectedView();
    return !!selection && !issueSavedViewMatches(selection, this.viewScope());
  }

  private viewLabel(): string {
    const selection = this.selectedView();
    return selection ? selection.name + (this.modifiedView() ? ' *' : '') : '视图';
  }

  private viewPreferenceKey(): string {
    return this.viewOwner ? 'account:' + this.viewOwner : 'local';
  }

  private async viewPreferences(): Promise<preferences.Preferences> {
    const context = this.getUIContext().getHostContext();
    if (!context) throw new Error('无法读取本机偏好。');
    return preferences.getPreferences(context, { name: 'arkts-issue-views' });
  }

  private async loadSavedViews(): Promise<void> {
    const request = ++this.viewsRequest;
    const preference = this.viewPreferenceKey();
    this.viewsReady = false;
    this.savingView = false;
    this.savedViews = [];
    this.selectedViewId = '';
    this.viewError = '';
    this.showViewName = false;
    this.editingView = undefined;
    try {
      const store = await this.viewPreferences();
      const raw = await store.get(preference, '[]');
      if (request !== this.viewsRequest || preference !== this.viewPreferenceKey()) return;
      this.savedViews = readIssueSavedViews(typeof raw === 'string' ? raw : '');
      this.rememberMatchingView();
      this.viewsReady = true;
    } catch (_) {
      if (request === this.viewsRequest && preference === this.viewPreferenceKey()) {
        this.viewError = '无法读取本机保存的视图。';
      }
    }
  }

  private async persistViews(update: (current: NativeIssueSavedView[]) => NativeIssueSavedView[],
    selectedId: string): Promise<void> {
    if (!this.viewsReady || this.savingView) return;
    const request = this.viewsRequest;
    const preference = this.viewPreferenceKey();
    this.savingView = true;
    this.viewError = '';
    try {
      const store = await this.viewPreferences();
      const raw = await store.get(preference, '[]');
      if (request !== this.viewsRequest || preference !== this.viewPreferenceKey()) return;
      const next = update(readIssueSavedViews(typeof raw === 'string' ? raw : ''));
      await store.put(preference, JSON.stringify(next));
      await store.flush();
      if (request !== this.viewsRequest || preference !== this.viewPreferenceKey()) return;
      this.savedViews = next;
      this.selectedViewId = selectedId;
      this.showViewName = false;
    } catch (error) {
      if (request === this.viewsRequest && preference === this.viewPreferenceKey()) {
        this.viewError = issueError(error as Error, '无法保存工单视图。');
      }
    } finally {
      if (request === this.viewsRequest && preference === this.viewPreferenceKey()) this.savingView = false;
    }
  }

  private applySavedView(view: NativeIssueSavedView): void {
    this.selectedViewId = view.id;
    this.viewError = '';
    this.stateFilter = view.state;
    this.involvement = view.involvement;
    this.sort = view.sort;
    this.issueLabels = view.labels ?? [];
    this.issueAssignee = view.assignee ?? null;
    this.rememberIssueFacets();
    const queryChanged = view.query !== this.query;
    this.onApplyQuery(view.query);
    if (!queryChanged) this.reload();
  }

  private openViewName(view?: NativeIssueSavedView): void {
    this.editingView = view;
    this.viewName = view?.name ?? (this.involvement === 'assigned' ? '指派给我的工单' : '');
    this.viewError = '';
    this.showViewName = true;
  }

  private saveNamedView(): void {
    const editing = this.editingView;
    const scope = editing ?? this.viewScope();
    const next: NativeIssueSavedView = {
      id: editing?.id ?? util.generateRandomUUID(), name: this.viewName, query: scope.query,
      state: scope.state, involvement: scope.involvement, sort: scope.sort, labels: scope.labels,
      assignee: scope.assignee,
    };
    void this.persistViews((stored) => writeIssueSavedView(stored, next), next.id);
  }

  private updateSavedView(view: NativeIssueSavedView): void {
    const scope = this.viewScope();
    const next: NativeIssueSavedView = {
      id: view.id, name: view.name, query: scope.query, state: scope.state,
      involvement: scope.involvement, sort: scope.sort, labels: scope.labels, assignee: scope.assignee,
    };
    void this.persistViews((stored) => writeIssueSavedView(stored, next), next.id);
  }

  private cancelPending(): void {
    ++this.request;
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
  }

  private environmentChanged(): void {
    this.showIssueFilter = false;
    this.candidatePage = undefined;
    const filters = issueFacetSelections.get(this.issueFacetKey());
    this.issueLabels = filters?.labels ?? [];
    this.issueAssignee = filters?.assignee ?? null;
    this.reload();
  }

  private ownerChanged(): void {
    this.selectedViewId = '';
    this.environmentChanged();
    void this.loadSavedViews();
  }

  private issueFacetKey(): string {
    return JSON.stringify([this.viewOwner, this.environmentKey]);
  }

  private rememberIssueFacets(): void {
    issueFacetSelections.set(this.issueFacetKey(), { labels: this.issueLabels, assignee: this.issueAssignee });
  }

  private openIssueFilter(facet: NativeIssueFacet): void {
    const page = this.candidatePage;
    this.filterFacet = facet;
    this.filterScopes = page ? issueCandidateScopes(page, facet) : [];
    this.filterEnvironmentKey = this.environmentKey;
    this.filterOwner = this.viewOwner;
    this.showIssueFilter = true;
  }

  private toggleIssueLabel(label: string): void {
    if (this.filterEnvironmentKey !== this.environmentKey || this.filterOwner !== this.viewOwner) return;
    if (this.issueLabels.includes(label)) {
      this.issueLabels = this.issueLabels.filter((name: string) => name !== label);
    } else if (this.issueLabels.length < ISSUE_FILTER_LABEL_LIMIT) {
      this.issueLabels = [...this.issueLabels, label];
    } else {
      return;
    }
    this.rememberIssueFacets();
    this.scheduleSearch();
  }

  private selectIssueAssignee(assignee: NativeIssueAssigneeFilter | null): void {
    if (this.filterEnvironmentKey !== this.environmentKey || this.filterOwner !== this.viewOwner) return;
    this.issueAssignee = assignee;
    this.rememberIssueFacets();
    this.reload();
  }

  private scheduleSearch(): void {
    this.rememberMatchingView();
    this.prepareReload();
    this.searchTimer = setTimeout(() => {
      this.searchTimer = -1;
      void this.load(false, false);
    }, 300);
  }

  private prepareReload(): void {
    this.cancelPending();
    this.page = undefined;
    this.error = '';
    this.emptyText = '';
    this.nextPageFailed = false;
    this.loadingMore = false;
    this.loading = true;
  }

  private reload(): void {
    this.rememberMatchingView();
    this.prepareReload();
    void this.load(false, false);
  }

  private rememberMatchingView(): void {
    if (!this.selectedViewId) this.selectedViewId = this.selectedView()?.id ?? '';
  }

  private async load(append: boolean, refresh: boolean): Promise<void> {
    if (!this.onLoad || !this.environmentKey) {
      this.emptyText = '当前环境无法读取工单。';
      this.loading = false;
      return;
    }
    const previous = this.page;
    const cursors = append ? previous?.nextCursors : undefined;
    if (append && (!cursors || Object.keys(cursors).length === 0)) return;
    const request = ++this.request;
    const environment = this.environmentKey;
    const filters: NativeIssueFilters = {
      state: this.stateFilter, query: this.query, involvement: this.involvement, sort: this.sort,
      labels: this.issueLabels, assignee: this.issueAssignee?.login,
    };
    this.error = '';
    this.emptyText = '';
    this.nextPageFailed = false;
    this.loadingMore = append;
    this.loading = !append;
    try {
      const page = await this.onLoad(filters, cursors, refresh);
      if (request !== this.request || environment !== this.environmentKey) return;
      const nextPage: NativeIssuePage = {
        entries: mergeIssueEntries(append && previous ? previous.entries : [],
          issueSearchEntries(page, filters.query ?? ''), this.sort),
        trackers: page.trackers,
        errors: page.errors,
        nextCursors: page.nextCursors,
        scopes: page.scopes,
        unavailable: page.unavailable,
      };
      this.candidatePage = page;
      this.page = nextPage;
      this.emptyText = issueListEmptyMessage(nextPage, filters.query ?? '');
    } catch (error) {
      if (request !== this.request || environment !== this.environmentKey) return;
      this.error = issueError(error as Error, '无法加载工单。');
      this.nextPageFailed = append;
    } finally {
      if (request === this.request && environment === this.environmentKey) {
        this.loading = false;
        this.loadingMore = false;
      }
    }
  }

  private hasNextPage(): boolean {
    return !!this.page && Object.keys(this.page.nextCursors).length > 0;
  }

  @Builder
  private StateButton(state: NativeIssueStateFilter, label: string) {
    Button(label, { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
      .id(`workspace-issue-state-${state}`)
      .height(40)
      .layoutWeight(1)
      .fontSize(13)
      .fontWeight(this.stateFilter === state ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.stateFilter === state ? $r('sys.color.font_primary') : $r('sys.color.font_secondary'))
      .backgroundColor(this.stateFilter === state ? $r('sys.color.comp_background_primary') : Color.Transparent)
      .accessibilitySelected(this.stateFilter === state)
      .onClick(() => {
        if (this.stateFilter !== state) {
          this.stateFilter = state;
          this.reload();
        }
      })
  }

  @Builder
  private InvolvementOption(involvement: NativeIssueInvolvement, label: string) {
    MenuItem({ content: label })
      .selected(this.involvement === involvement)
      .selectIcon(true)
      .onChange(() => {
        if (this.involvement !== involvement) {
          this.involvement = involvement;
          this.reload();
        }
      })
  }

  @Builder
  private InvolvementMenu() {
    Menu() {
      this.InvolvementOption('all', '全部成员')
      this.InvolvementOption('assigned', '指派给我')
      this.InvolvementOption('authored', '我创建的')
      this.InvolvementOption('mentioned', '提到我的')
    }
  }

  @Builder
  private SortMenu() {
    Menu() {
      MenuItem({ content: '最近更新' })
        .selected(this.sort === 'updated')
        .selectIcon(true)
        .onChange(() => {
          if (this.sort !== 'updated') {
            this.sort = 'updated';
            this.reload();
          }
        })
      MenuItem({ content: '最近创建' })
        .selected(this.sort === 'created')
        .selectIcon(true)
        .onChange(() => {
          if (this.sort !== 'created') {
            this.sort = 'created';
            this.reload();
          }
        })
    }
  }

  @Builder
  private SavedViewActions() {
    Menu() {
      if (!this.viewsReady) {
        MenuItem({ content: this.viewError ? '重试加载视图' : '正在加载视图…' })
          .enabled(!!this.viewError)
          .onChange(() => { void this.loadSavedViews(); })
      } else {
        ForEach(this.savedViews, (view: NativeIssueSavedView) => {
          MenuItem({ content: view.name })
            .selected(this.selectedView()?.id === view.id && !this.modifiedView())
            .selectIcon(true)
            .enabled(!this.savingView)
            .onChange(() => this.applySavedView(view))
        }, (view: NativeIssueSavedView) => view.id)
        MenuItem({ content: '保存当前视图…' })
          .enabled(!this.savingView)
          .onChange(() => this.openViewName())
        if (this.selectedView()) {
          if (this.modifiedView()) {
            MenuItem({ content: '更新保存的视图' })
              .enabled(!this.savingView)
              .onChange(() => {
                const view = this.selectedView();
                if (view) this.updateSavedView(view);
              })
          }
          MenuItem({ content: '重命名视图…' })
            .enabled(!this.savingView)
            .onChange(() => {
              const view = this.selectedView();
              if (view) this.openViewName(view);
            })
          MenuItem({ content: '删除视图' })
            .enabled(!this.savingView)
            .onChange(() => {
              const view = this.selectedView();
              if (view) void this.persistViews((stored) => stored.filter((entry) => entry.id !== view.id), '');
            })
        }
      }
    }
  }

  @Builder
  private ViewNameSheet() {
    Column({ space: 12 }) {
      Text(this.editingView ? '重命名工单视图' : '保存工单视图')
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
      TextInput({ text: this.viewName, placeholder: '视图名称' })
        .id('workspace-issue-view-name')
        .width('100%')
        .height(48)
        .maxLength(ISSUE_VIEW_NAME_LIMIT)
        .accessibilityText('视图名称')
        .enabled(!this.savingView)
        .onChange((value: string) => {
          this.viewName = value;
          this.viewError = '';
        })
      if (this.viewError) {
        Text(this.viewError)
          .width('100%')
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
      }
      Row({ space: 12 }) {
        Blank()
        Button('取消', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(44)
          .enabled(!this.savingView)
          .onClick(() => {
            this.viewError = '';
            this.showViewName = false;
          })
        Button(this.savingView ? '正在保存…' : '保存', { type: ButtonType.Capsule })
          .id('workspace-issue-view-save')
          .height(44)
          .enabled(!this.savingView)
          .onClick(() => this.saveNamedView())
      }.width('100%')
    }.width('100%').padding(20)
  }

  @Builder
  private FacetButton(facet: NativeIssueFacet, label: string, selected: boolean) {
    Button({ type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 6 }) {
        Text(label)
          .fontSize(13)
          .fontColor(selected ? $r('sys.color.font_emphasize') : $r('sys.color.font_primary'))
          .constraintSize({ maxWidth: 112 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(12)
          .fontColor([$r('sys.color.icon_secondary')])
      }
    }
    .id(`workspace-issue-filter-${facet}`)
    .height(44)
    .accessibilityText(facet === 'labels' ? '按标签筛选' : '按经办人筛选')
    .enabled(!this.loading || selected)
    .onClick(() => this.openIssueFilter(facet))
  }

  @Builder
  private IssueFilterSheet() {
    WorkspaceIssueFilterSheet({
      environmentKey: this.filterEnvironmentKey,
      facet: this.filterFacet,
      scopes: this.filterScopes,
      labels: this.issueLabels,
      assignee: this.issueAssignee,
      onRead: this.onLoadCandidates,
      onLabel: (label: string) => this.toggleIssueLabel(label),
      onAssignee: (assignee: NativeIssueAssigneeFilter | null) => this.selectIssueAssignee(assignee),
      onClose: () => { this.showIssueFilter = false; },
    })
  }

  @Builder
  private Filters() {
    Row({ space: 2 }) {
      this.StateButton('open', '开放')
      this.StateButton('closed', '已关闭')
      this.StateButton('all', '全部')
    }
    .width('100%')
    .padding(4)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .borderRadius(24)
    Row({ space: 8 }) {
      Scroll() {
        Row({ space: 6 }) {
          Button({ type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Row({ space: 6 }) {
              Text(this.viewLabel())
                .fontSize(13)
                .fontColor(this.selectedView() ? $r('sys.color.font_emphasize') : $r('sys.color.font_primary'))
                .constraintSize({ maxWidth: 112 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(12)
                .fontColor([$r('sys.color.icon_secondary')])
            }
          }
          .id('workspace-issue-saved-views')
          .height(44)
          .accessibilityText('保存的工单视图')
          .bindMenu(this.SavedViewActions)
          Button(this.involvement === 'assigned' ? '指派给我' :
            this.involvement === 'authored' ? '我创建的' : this.involvement === 'mentioned' ? '提到我的' : '全部成员',
            { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
            .id('workspace-issue-involvement')
            .height(44)
            .fontSize(13)
            .bindMenu(this.InvolvementMenu)
          this.FacetButton('labels', this.issueLabels.length === 0 ? '标签' :
            this.issueLabels.length === 1 ? this.issueLabels[0] : `标签 ${this.issueLabels.length}`, this.issueLabels.length > 0)
          this.FacetButton('assignee', this.issueAssignee?.name || this.issueAssignee?.login || '经办人', this.issueAssignee !== null)
          Button(this.sort === 'created' ? '最近创建' : '最近更新',
            { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
            .id('workspace-issue-sort')
            .height(44)
            .fontSize(13)
            .bindMenu(this.SortMenu)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.Start)
      .layoutWeight(1)
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(20)
          .fontColor([$r('sys.color.icon_primary')])
      }
      .id('workspace-issue-refresh')
      .width(44)
      .height(44)
      .accessibilityText('刷新工单')
      .enabled(!this.loading && !this.loadingMore && this.onLoad !== undefined)
      .onClick(() => { void this.load(false, true); })
    }
    .width('100%')
    .bindSheet(this.showIssueFilter, this.IssueFilterSheet(), {
      height: SheetSize.LARGE,
      showClose: false,
      onDisappear: () => { this.showIssueFilter = false; },
    })
  }

  @Builder
  private RowItem(entry: NativeIssueEntry) {
    Column() {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 12 }) {
          SymbolGlyph(entry.state.category === 'open' ? $r('sys.symbol.exclamationmark_circle') : $r('sys.symbol.checkmark'))
            .fontSize(20)
            .fontColor([entry.state.category === 'open' ? $r('sys.color.font_emphasize') : $r('sys.color.icon_secondary')])
          Column({ space: 5 }) {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.person_head_on_circle'))
                .fontSize(16)
                .fontColor([$r('sys.color.icon_secondary')])
              Text(issueDisplayKey(entry))
                .fontSize(12)
                .fontColor($r('sys.color.font_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Text(formatIssueDate(entry.updatedAt))
                .fontSize(11)
                .fontColor($r('sys.color.font_secondary'))
            }.width('100%')
            Text(entry.title)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (entry.labels.length > 0 || entry.commentCount > 0) {
              Row({ space: 6 }) {
                Row() {
                  IssueLabels(entry.labels, 2)
                }.layoutWeight(1)
                if (entry.commentCount > 0) {
                  SymbolGlyph($r('sys.symbol.message_on_message'))
                    .fontSize(14)
                    .fontColor([$r('sys.color.icon_secondary')])
                  Text(String(entry.commentCount)).fontSize(11).fontColor($r('sys.color.font_secondary'))
                }
              }.width('100%')
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }
      .width('100%')
      .padding({ top: 10, bottom: 10 })
      .accessibilityText(`${entry.displayKey} ${entry.title}，${entry.state.name}，${actorName(entry.author)}`)
      .onClick(() => this.onOpen(entry))
      Divider().margin({ left: 32 })
    }
    .width('100%')
  }

  @Builder
  private CenterMessage(message: string) {
    Text(message)
      .fontSize(14)
      .fontColor($r('sys.color.font_secondary'))
      .textAlign(TextAlign.Center)
      .width('100%')
      .padding({ top: 22, bottom: 22 })
  }

  build() {
    Column({ space: 10 }) {
      this.Filters()
      if (this.viewError && !this.showViewName) {
        Text(this.viewError)
          .width('100%')
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
      }
      if (this.loading) {
        LoadingProgress()
          .id('workspace-issue-loading')
          .width(32)
          .height(32)
          .accessibilityText('正在加载工单')
          .margin(12)
      }
      if (this.error) {
        this.CenterMessage(this.error)
        Button('重试', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
          .id('workspace-issue-retry')
          .height(44)
          .onClick(() => { void this.load(this.nextPageFailed, !this.nextPageFailed); })
      }
      if (this.page) {
        ForEach(this.page.trackers.filter((tracker) => !tracker.configured), (tracker: NativeIssueTracker) => {
          Text(`${tracker.tracker} · ${tracker.host} · ${tracker.detail ?? '工单跟踪器尚未配置'}`)
            .width('100%')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
        }, (tracker: NativeIssueTracker): string => `${tracker.tracker}:${tracker.host}`)
        ForEach(this.page.errors, (error: NativeIssueError) => {
          Text(`${error.projectTitle} · ${error.message}`)
            .width('100%')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
        }, (error: NativeIssueError): string => `${error.projectId}:${error.message}`)
        ForEach(this.page.entries, (entry: NativeIssueEntry) => this.RowItem(entry), issueRefKey)
      }
      if (this.emptyText) {
        Text(this.emptyText)
          .id('workspace-issue-empty')
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding({ top: 22, bottom: 22 })
      }
      if (this.hasNextPage() && !this.nextPageFailed) {
        if (this.loadingMore) {
          LoadingProgress()
            .width(26)
            .height(26)
            .accessibilityText('正在加载更多工单')
        } else {
          Button('加载更多', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
            .id('workspace-issue-load-more')
            .height(44)
            .enabled(!this.loading)
            .onClick(() => { void this.load(true, false); })
        }
      }
    }
    .width('100%')
    .bindSheet(this.showViewName, this.ViewNameSheet(), {
      height: SheetSize.MEDIUM,
      showClose: false,
      onWillDismiss: (dismiss: DismissSheetAction) => { if (!this.savingView) dismiss.dismiss(); },
      onDisappear: () => { this.showViewName = false; },
    })
  }
}

type IssueDetailPane = 'detail' | NativeIssueEditor;

@Component
export struct WorkspaceIssueDetail {
  @Prop @Watch('routeChanged') environmentKey: string = '';
  @Prop @Watch('routeChanged') issue: NativeIssueEntry | undefined = undefined;
  @Prop @Watch('handleBack') backRequest: number = 0;
  @Prop @Watch('permissionsChanged') canWrite: boolean = false;
  onLoad?: (ref: NativeIssueRef) => Promise<NativeIssueDetail>;
  onBack: () => void = () => {};

  @State private detail?: NativeIssueDetail = undefined;
  @State private loading: boolean = true;
  @State private error: string = '';
  @State private activity: IssueActivity[] = [];
  @State private pane: IssueDetailPane = 'detail';
  @State private editTitle: string = '';
  @State private editBody: string = '';
  private request: number = 0;

  aboutToAppear(): void {
    this.routeChanged();
  }

  aboutToDisappear(): void {
    ++this.request;
  }

  private routeChanged(): void {
    this.detail = undefined;
    this.activity = [];
    this.closeEditor();
    void this.load();
  }

  private closeEditor(): void {
    this.pane = 'detail';
    this.editTitle = '';
    this.editBody = '';
  }

  private handleBack(): void {
    if (this.pane !== 'detail') {
      this.closeEditor();
    } else {
      this.onBack();
    }
  }

  private permissionsChanged(): void {
    if (this.pane !== 'detail' && (!this.detail || !issueCanShowEditor(this.detail, this.canWrite, this.pane))) {
      this.closeEditor();
    }
  }

  private async load(): Promise<void> {
    const request = ++this.request;
    const issue = this.issue;
    const environment = this.environmentKey;
    this.error = '';
    if (!issue || !this.onLoad || !environment) {
      this.loading = false;
      this.error = '当前环境无法读取工单详情。';
      return;
    }
    this.loading = true;
    try {
      const detail = await this.onLoad(issue);
      if (request !== this.request || environment !== this.environmentKey) return;
      this.detail = detail;
      this.activity = issueActivity(detail);
    } catch (error) {
      if (request !== this.request || environment !== this.environmentKey) return;
      this.error = issueError(error as Error, '无法读取工单详情。');
    } finally {
      if (request === this.request && environment === this.environmentKey) this.loading = false;
    }
  }

  private showEditor(action: NativeIssueEditor): void {
    if (!this.detail || !issueCanShowEditor(this.detail, this.canWrite, action)) return;
    if (action === 'edit') {
      this.editTitle = this.detail.title;
      this.editBody = this.detail.body;
    }
    this.pane = action;
  }

  private title(): string {
    switch (this.pane) {
      case 'detail': return this.issue?.displayKey ?? '工单';
      case 'edit': return '编辑工单';
      case 'labels': return '工单标签';
      case 'assignees': return '工单经办人';
    }
  }

  @Builder
  private Header() {
    Row({ space: 4 }) {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontSize(22)
          .fontColor([$r('sys.color.icon_primary')])
      }
      .id('workspace-issue-detail-back')
      .width(48)
      .height(48)
      .padding(0)
      .accessibilityText('返回')
      .onClick(() => this.handleBack())
      Column({ space: 2 }) {
        Text(this.title())
          .fontWeight(FontWeight.Bold)
          .fontSize(20)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.pane === 'detail' && this.issue) {
          Text(this.issue.scope)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (this.pane !== 'detail') {
        Button('保存', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
          .id('workspace-issue-save-preview')
          .height(44)
          .enabled(false)
      } else if (this.detail && issueCanShowEditor(this.detail, this.canWrite, 'edit')) {
        Button('编辑', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
          .id('workspace-issue-edit')
          .height(44)
          .onClick(() => this.showEditor('edit'))
      }
    }
    .width('100%')
    .height(60)
    .padding({ left: 12, right: 12 })
    .backgroundColor($r('sys.color.comp_background_primary'))
  }

  @Builder
  private SectionHeading(title: string) {
    Text(title)
      .fontSize(15)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_primary'))
      .width('100%')
  }

  @Builder
  private Secondary(text: string) {
    Text(text)
      .fontColor($r('sys.color.font_secondary'))
      .fontSize(13)
      .width('100%')
  }

  @Builder
  private Summary(entry: NativeIssueEntry) {
    Column({ space: 10 }) {
      IssueStateLabel(entry.state)
      Text(entry.title)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .copyOption(CopyOptions.LocalDevice)
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.person_head_on_circle'))
          .fontSize(20)
          .fontColor([$r('sys.color.icon_secondary')])
        Text(actorName(entry.author))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .maxLines(1)
          .layoutWeight(1)
        Text(entry.closedAt ? `关闭于 ${formatIssueDate(entry.closedAt)}` : `创建于 ${formatIssueDate(entry.createdAt)}`)
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
      }.width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private Labels(detail: NativeIssueDetail) {
    if (detail.labels.length > 0) {
      IssueLabels(detail.labels, detail.labels.length)
    } else {
      this.Secondary('暂无标签')
    }
  }

  @Builder
  private Assignees(detail: NativeIssueDetail) {
    if (detail.assignees.length > 0) {
      ForEach(detail.assignees, (actor: NativeIssueActor) => {
        this.Secondary(actorName(actor))
      }, (actor: NativeIssueActor) => actor.login)
    } else {
      this.Secondary('暂无经办人')
    }
  }

  @Builder
  private Properties(detail: NativeIssueDetail) {
    Column({ space: 8 }) {
      Row() {
        Text('标签')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        if (issueCanShowEditor(detail, this.canWrite, 'labels')) {
          Button('管理标签', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
            .id('workspace-issue-manage-labels')
            .height(44)
            .onClick(() => this.showEditor('labels'))
        }
      }.width('100%')
      this.Labels(detail)
      Divider().margin({ top: 4, bottom: 4 })
      Row() {
        Text('经办人')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        if (issueCanShowEditor(detail, this.canWrite, 'assignees')) {
          Button('管理经办人', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
            .id('workspace-issue-manage-assignees')
            .height(44)
            .onClick(() => this.showEditor('assignees'))
        }
      }.width('100%')
      this.Assignees(detail)
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(14)
  }

  @Builder
  private Details(detail: NativeIssueDetail) {
    this.Properties(detail)
    Column({ space: 8 }) {
      this.SectionHeading('描述')
      if (detail.body.trim()) {
        Text(detail.body)
          .fontSize(15)
          .lineHeight(23)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .copyOption(CopyOptions.LocalDevice)
      } else {
        this.Secondary('暂无描述')
      }
    }.width('100%')
    if (detail.linkedPullRequests.length > 0) {
      Column({ space: 8 }) {
        this.SectionHeading('关联的拉取请求')
        ForEach(detail.linkedPullRequests, (pullRequest: NativeIssueLinkedPullRequest) => {
          this.Secondary(`${pullRequest.repository} #${pullRequest.number} · ${pullRequest.title}`)
        }, (pullRequest: NativeIssueLinkedPullRequest): string => `${pullRequest.repository}:${pullRequest.number}`)
      }.width('100%')
    }
    Column({ space: 10 }) {
      this.SectionHeading(detail.commentCount > 0 ? `动态 · ${detail.commentCount} 条评论` : '动态')
      if (detail.commentsCursor) {
        this.Secondary('跟踪器还有更多历史评论。')
      }
      if (this.activity.length === 0) {
        this.Secondary('暂无动态')
      }
      ForEach(this.activity, (entry: IssueActivity) => {
        Column({ space: 6 }) {
          this.Secondary(`${entry.actor} · ${formatIssueDate(entry.time)}`)
          Text(entry.body)
            .width('100%')
            .fontSize(entry.event ? 13 : 15)
            .fontColor(entry.event ? $r('sys.color.font_secondary') : $r('sys.color.font_primary'))
            .copyOption(CopyOptions.LocalDevice)
        }
        .width('100%')
        .padding(12)
        .backgroundColor($r('sys.color.comp_background_primary'))
        .borderRadius(12)
      }, (entry: IssueActivity) => entry.key)
    }.width('100%')
  }

  @Builder
  private Editor(detail: NativeIssueDetail) {
    this.Secondary('当前版本可预览此界面，保存功能尚未接入。')
    if (this.pane === 'edit') {
      this.SectionHeading('标题')
      TextInput({ text: this.editTitle, placeholder: '工单标题' })
        .id('workspace-issue-edit-title')
        .accessibilityText('工单标题')
        .height(48)
        .maxLength(1024)
        .onChange((value: string) => { this.editTitle = value; })
      this.SectionHeading('描述')
      TextArea({ text: this.editBody, placeholder: '工单描述' })
        .id('workspace-issue-edit-body')
        .accessibilityText('工单描述')
        .constraintSize({ minHeight: 144 })
        .onChange((value: string) => { this.editBody = value; })
    } else if (this.pane === 'labels') {
      this.SectionHeading('当前标签')
      this.Labels(detail)
    } else {
      this.SectionHeading('当前经办人')
      this.Assignees(detail)
    }
  }

  build() {
    Column() {
      this.Header()
      Scroll() {
        Column({ space: 18 }) {
          if (this.pane === 'detail') {
            if (this.detail) {
              this.Summary(this.detail)
            } else if (this.issue) {
              this.Summary(this.issue)
            }
            if (this.loading) {
              LoadingProgress()
                .id('workspace-issue-detail-loading')
                .width(32)
                .height(32)
                .accessibilityText('正在加载工单详情')
            } else if (this.error) {
              this.Secondary(this.error)
              Button('重试', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
                .id('workspace-issue-detail-retry')
                .height(44)
                .onClick(() => { void this.load(); })
            } else if (this.detail) {
              this.Details(this.detail)
            }
          } else if (this.detail) {
            this.Editor(this.detail)
          }
        }
        .width('100%')
        .constraintSize({ maxWidth: 560 })
        .padding({ left: 20, right: 20, top: 16, bottom: 24 })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor($r('sys.color.comp_background_secondary'))
  }
}
