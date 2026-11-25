import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import {
  canEditPullRequestComment, filterPullRequestRows, groupPullRequestFiles, mergePullRequestRows, nextPullRequestQuery,
  pullRequestDiffLines, pullRequestPreferencesKey, pullRequestRowKey,
  pullRequestViewMatches, readPullRequestPreferences, savePullRequestView,
  sortPullRequestRows,
} from '../client/PullRequestProtocol';
import type {
  NativePullRequestComment, NativePullRequestDetail, NativePullRequestDiff, NativePullRequestDiffLine,
  NativePullRequestDiscussion, NativePullRequestFilters, NativePullRequestDraftFilter,
  NativePullRequestReviewFilter, NativePullRequestChecksFilter,
  NativePullRequestFile, NativePullRequestFileGroup, NativePullRequestInvolvement, NativePullRequestPage, NativePullRequestQuery,
  NativePullRequestPreferences, NativePullRequestRef, NativePullRequestRow, NativePullRequestSavedView,
  NativePullRequestSort, NativePullRequestState, NativePullRequestViewScope,
} from '../client/PullRequestProtocol';
import { pullRequestReviewDraftKey } from '../client/PullRequestReviewDraft';
import type { NativePullRequestInlineTarget, NativePullRequestLineDraft } from '../client/PullRequestReviewDraft';
import type { NativePullRequestMetadataKind, NativePullRequestMetadataPage } from '../client/PullRequestMetadataProtocol';
import type { NativePullRequestFilterMode, NativePullRequestFilterCandidatePage } from '../client/PullRequestFilterOptionsProtocol';
import { pullRequestGuideExcerpt, pullRequestGuideIsStale } from '../client/PullRequestGuideProtocol';
import type { NativePullRequestGuideResult, NativePullRequestGuideTarget } from '../client/PullRequestGuideProtocol';
import type { NativePullRequestCompletionOptions, NativePullRequestComposerTrigger } from '../client/PullRequestReferenceProtocol';
import { WorkspacePullRequestEdit } from './WorkspacePullRequestEdit';
import type { NativePullRequestEditField } from './WorkspacePullRequestEdit';
import { WorkspacePullRequestReview } from './WorkspacePullRequestReview';
import { WorkspacePullRequestMetadata } from './WorkspacePullRequestMetadata';
import { WorkspacePullRequestGuide } from './WorkspacePullRequestGuide';
import { WorkspacePullRequestFilterPicker } from './WorkspacePullRequestFilterPicker';

type StatusFilter = NativePullRequestState | 'all';
type DetailPane = 'overview' | 'activity' | 'guide' | 'changes';
type FilePatchStatus = 'idle' | 'loading' | 'error' | 'empty';
const VIEWS_STORE = 'arkts-pull-request-views';
const FILE_PATCH_PREVIEW_LIMIT = 40000;
let preferenceWrites: Promise<void> = Promise.resolve();

function stateLabel(state: StatusFilter): string {
  switch (state) {
    case 'open': return '开放';
    case 'merged': return '已合并';
    case 'closed': return '已关闭';
    default: return '全部状态';
  }
}

function involvementLabel(involvement: NativePullRequestInvolvement): string {
  switch (involvement) {
    case 'reviewing': return '我参与评审的';
    case 'authored': return '我创建的';
    default: return '所有参与方式';
  }
}

function statusColor(state: NativePullRequestState, draft: boolean): ResourceColor {
  if (draft) return $r('sys.color.icon_secondary');
  if (state === 'merged') return '#9D66D8';
  if (state === 'closed') return '#DE5D5F';
  return '#33A267';
}

function updatedLabel(value: string): string {
  if (!value) return '';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString();
}

function sortLabel(sort: NativePullRequestSort): string {
  if (sort === 'created') return '最新创建';
  if (sort === 'oldest') return '最早更新';
  return '最近更新';
}

@Component
struct PullRequestStatusMark {
  @Prop state: NativePullRequestState = 'open';
  @Prop draft: boolean = false;

  build() {
    SymbolGlyph($r('sys.symbol.arrow_triangle_merge'))
      .fontSize(19)
      .fontColor([statusColor(this.state, this.draft)])
      .accessibilityText(this.draft ? '草稿' : stateLabel(this.state))
  }
}

@Component
struct PullRequestFeedback {
  @Prop text: string = '';
  @Prop loading: boolean = false;
  onRetry?: () => void;

  build() {
    Column({ space: 8 }) {
      if (this.loading) {
        LoadingProgress().width(28).height(28).color($r('sys.color.icon_secondary'))
      }
      Text(this.text)
        .fontSize(14)
        .textAlign(TextAlign.Center)
        .fontColor($r('sys.color.font_secondary'))
      if (this.onRetry) {
        Button('重试', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(40)
          .onClick(() => { this.onRetry?.(); })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 24, bottom: 24 })
  }
}

@Component
export struct WorkspacePullRequests {
  @Prop @Watch('sourceChanged') sourceKey: string = '';
  @Prop @Watch('queryChanged') query: string = '';
  @Prop @Watch('sourceChanged') viewOwner: string = '';
  @Prop @Watch('sourceChanged') preferenceScope: string = '';
  onLoad?: (input: NativePullRequestQuery) => Promise<NativePullRequestPage>;
  onOpen: (row: NativePullRequestRow) => void = () => {};
  onApplyQuery?: (query: string) => void;
  onLoadFilters?: (mode: NativePullRequestFilterMode, projectId?: string, query?: string) =>
    Promise<NativePullRequestFilterCandidatePage>;

  @State private state: StatusFilter = 'open';
  @State private involvement: NativePullRequestInvolvement = 'all';
  @State private sort: NativePullRequestSort = 'updated';
  @State private statusFilters: NativePullRequestFilters = {};
  @State private statusFiltersOpen: boolean = false;
  @State private scopeFilterMode: NativePullRequestFilterMode = 'projects';
  @State private scopeFilterOpen: boolean = false;
  @State private projectId?: string = undefined;
  @State private rows: NativePullRequestRow[] = [];
  @State private messages: string[] = [];
  @State private loading: boolean = false;
  @State private error: string = '';
  @State private next?: NativePullRequestQuery = undefined;
  @State private truncated: boolean = false;
  @State private views: NativePullRequestSavedView[] = [];
  @State private selectedViewId: string = '';
  @State private preferencesLoading: boolean = false;
  @State private preferencesError: string = '';
  @State private viewBusy: boolean = false;
  @State private viewEditorOpen: boolean = false;
  @State private viewEditorId: string = '';
  @State private viewEditorName: string = '';
  @State private viewEditorError: string = '';
  private generation: number = 0;
  private queryTimer?: number = undefined;
  private failedPage?: NativePullRequestQuery = undefined;
  private viewGeneration: number = 0;
  private viewKey: string = '';
  private previousQuery: string = '';

  aboutToAppear(): void {
    this.sourceChanged();
  }

  aboutToDisappear(): void {
    this.cancelLoad();
    this.viewGeneration++;
    this.viewKey = '';
  }

  private cancelLoad(): void {
    this.generation++;
    if (this.queryTimer !== undefined) clearTimeout(this.queryTimer);
    this.queryTimer = undefined;
  }

  private reset(): void {
    this.cancelLoad();
    this.rows = [];
    this.messages = [];
    this.error = '';
    this.loading = this.sourceKey.length > 0 && this.onLoad !== undefined;
    this.next = undefined;
    this.failedPage = undefined;
    this.truncated = false;
  }

  private sourceChanged(): void {
    const key = pullRequestPreferencesKey(this.viewOwner, this.preferenceScope || this.sourceKey);
    if (key === this.viewKey) {
      if (!this.preferencesLoading) this.reloadList();
      return;
    }
    this.viewKey = key;
    this.state = 'open';
    this.involvement = 'all';
    this.sort = 'updated';
    this.statusFilters = {};
    this.statusFiltersOpen = false;
    this.scopeFilterOpen = false;
    this.projectId = undefined;
    this.views = [];
    this.selectedViewId = '';
    this.previousQuery = this.query;
    this.viewEditorOpen = false;
    this.viewBusy = false;
    this.reset();
    void this.restoreViews();
  }

  private reloadList(): void {
    this.reset();
    void this.loadFirst();
  }

  private queryChanged(): void {
    if (!this.selectedViewId) {
      const previous = this.currentScope();
      previous.query = this.previousQuery;
      this.selectedViewId = this.views.find((view: NativePullRequestSavedView) =>
        pullRequestViewMatches(view, previous))?.id ?? '';
    }
    this.previousQuery = this.query;
    if (this.preferencesLoading) return;
    this.reset();
    this.queryTimer = setTimeout(() => {
      this.queryTimer = undefined;
      void this.loadFirst();
    }, 180);
  }

  private currentScope(): NativePullRequestViewScope {
    return { state: this.state, involvement: this.involvement, query: this.query, sort: this.sort,
      filters: this.statusFilters, projectId: this.projectId };
  }

  private selectedView(): NativePullRequestSavedView | undefined {
    const scope = this.currentScope();
    return this.views.find((view: NativePullRequestSavedView) => view.id === this.selectedViewId) ??
      this.views.find((view: NativePullRequestSavedView) => pullRequestViewMatches(view, scope));
  }

  private viewModified(): boolean {
    const selected = this.selectedView();
    return selected !== undefined && !pullRequestViewMatches(selected, this.currentScope());
  }

  private viewLabel(): string {
    const selected = this.selectedView();
    return selected ? `${selected.name}${this.viewModified() ? ' *' : ''}` : '视图';
  }

  private async viewsStore(): Promise<preferences.Preferences> {
    const context = this.getUIContext().getHostContext();
    if (!context) throw new Error('无法访问本地存储。');
    return preferences.getPreferences(context, { name: VIEWS_STORE });
  }

  private async restoreViews(): Promise<void> {
    const generation = ++this.viewGeneration;
    const key = this.viewKey;
    this.preferencesLoading = true;
    this.preferencesError = '';
    try {
      const store = await this.viewsStore();
      await preferenceWrites;
      const raw = await store.get(key, '');
      if (generation !== this.viewGeneration) return;
      const saved = readPullRequestPreferences(typeof raw === 'string' ? raw : '', key);
      this.state = saved.state;
      this.involvement = saved.involvement;
      this.sort = saved.sort ?? 'updated';
      this.statusFilters = saved.filters ?? {};
      this.projectId = saved.projectId;
      this.views = saved.views;
      this.selectedViewId = this.selectedView()?.id ?? '';
    } catch (_) {
      if (generation === this.viewGeneration) this.preferencesError = '无法读取本机的拉取请求视图。';
    } finally {
      if (generation === this.viewGeneration) {
        this.preferencesLoading = false;
        this.reloadList();
      }
    }
  }

  private async persistViews(views: NativePullRequestSavedView[], scope: NativePullRequestViewScope): Promise<boolean> {
    if (this.preferencesLoading || this.preferencesError || this.viewBusy) return false;
    const generation = this.viewGeneration;
    const key = this.viewKey;
    const snapshot: NativePullRequestPreferences = {
      key, state: scope.state, involvement: scope.involvement, sort: scope.sort, filters: scope.filters,
      projectId: scope.projectId, views,
    };
    this.viewBusy = true;
    const openStore = this.viewsStore();
    const write = preferenceWrites.then(async () => {
      const store = await openStore;
      const previous = await store.get(key, '');
      await store.put(key, JSON.stringify(snapshot));
      try {
        await store.flush();
      } catch (error) {
        await store.put(key, previous);
        throw new Error((error as Error).message);
      }
    });
    preferenceWrites = write.catch(() => {});
    try {
      await write;
      if (generation !== this.viewGeneration) return false;
      this.views = views;
      return true;
    } catch (_) {
      if (generation === this.viewGeneration) {
        this.getUIContext().getPromptAction().showToast({ message: '无法保存拉取请求视图。' });
      }
      return false;
    } finally {
      if (generation === this.viewGeneration) this.viewBusy = false;
    }
  }

  private async applyView(view: NativePullRequestSavedView): Promise<void> {
    if (!(await this.persistViews(this.views, view))) return;
    this.state = view.state;
    this.involvement = view.involvement;
    this.sort = view.sort ?? 'updated';
    this.statusFilters = view.filters ?? {};
    this.projectId = view.projectId;
    this.selectedViewId = view.id;
    this.query = view.query;
    this.onApplyQuery?.(view.query);
    this.reloadList();
  }

  private editViewName(view?: NativePullRequestSavedView): void {
    this.viewEditorId = view?.id ?? '';
    this.viewEditorName = view?.name ?? (this.involvement === 'reviewing' ? '待我评审的拉取请求' : '');
    this.viewEditorError = '';
    this.viewEditorOpen = true;
  }

  private async submitViewName(): Promise<void> {
    if (this.viewBusy) return;
    const current = this.views.find((view: NativePullRequestSavedView) => view.id === this.viewEditorId);
    const scope = this.currentScope();
    const id = current?.id ?? util.generateRandomUUID();
    try {
      const updated = savePullRequestView(this.views, id, this.viewEditorName, current ?? scope);
      if (await this.persistViews(updated, scope)) {
        this.selectedViewId = id;
        this.viewEditorOpen = false;
      }
    } catch (error) {
      this.viewEditorError = (error as Error).message;
    }
  }

  private updateView(): void {
    const view = this.selectedView();
    if (!view) return;
    const scope = this.currentScope();
    void this.persistViews(savePullRequestView(this.views, view.id, view.name, scope), scope);
  }

  private async deleteView(): Promise<void> {
    const selected = this.selectedView();
    if (!selected) return;
    const views = this.views.filter((view: NativePullRequestSavedView) => selected.id !== view.id);
    if (await this.persistViews(views, this.currentScope())) this.selectedViewId = '';
  }

  private loadFirst(): Promise<void> {
    return this.load({ state: this.state, involvement: this.involvement, query: this.query, sort: this.sort,
      filters: this.statusFilters, projectId: this.projectId }, false);
  }

  private async load(input: NativePullRequestQuery, append: boolean): Promise<void> {
    const load = this.onLoad;
    if (!this.sourceKey || !load) return;
    const generation = ++this.generation;
    this.loading = true;
    this.error = '';
    this.failedPage = undefined;
    try {
      const page = await load(input);
      if (generation !== this.generation) return;
      this.rows = sortPullRequestRows(append ? mergePullRequestRows(this.rows, page.rows) : page.rows, this.sort);
      this.messages = Array.from(new Set(append ? this.messages.concat(page.messages) : page.messages));
      this.next = nextPullRequestQuery(input, page);
      this.truncated = page.truncated;
    } catch (error) {
      if (generation !== this.generation) return;
      this.error = (error as Error).message || '无法读取拉取请求。';
      if (append) this.failedPage = input;
    } finally {
      if (generation === this.generation) this.loading = false;
    }
  }

  private retry(): void {
    const failedPage = this.failedPage;
    if (failedPage) void this.load(failedPage, true);
    else void this.loadFirst();
  }

  private selectState(state: StatusFilter): void {
    if (this.state === state) return;
    this.selectedViewId = this.selectedView()?.id ?? '';
    this.state = state;
    this.reloadList();
    void this.persistViews(this.views, this.currentScope());
  }

  private selectInvolvement(involvement: NativePullRequestInvolvement): void {
    if (this.involvement === involvement) return;
    this.selectedViewId = this.selectedView()?.id ?? '';
    this.involvement = involvement;
    this.reloadList();
    void this.persistViews(this.views, this.currentScope());
  }

  private selectSort(sort: NativePullRequestSort): void {
    if (this.sort === sort) return;
    this.selectedViewId = this.selectedView()?.id ?? '';
    this.sort = sort;
    this.rows = sortPullRequestRows(this.rows, sort);
    void this.persistViews(this.views, this.currentScope());
  }

  private statusFilterCount(): number {
    return Number(!!this.statusFilters.draft) + Number(!!this.statusFilters.review) + Number(!!this.statusFilters.checks);
  }

  private selectStatusFilters(filters: NativePullRequestFilters): void {
    this.changeListScope(this.projectId, {
      draft: filters.draft, review: filters.review, checks: filters.checks,
      author: this.statusFilters.author, labels: this.statusFilters.labels,
      excludedLabels: this.statusFilters.excludedLabels,
    });
  }

  private changeListScope(projectId: string | undefined, filters: NativePullRequestFilters): void {
    if (this.viewBusy || this.preferencesLoading) return;
    const current = this.currentScope();
    const next: NativePullRequestViewScope = { state: current.state, involvement: current.involvement,
      query: current.query, sort: current.sort, projectId, filters };
    if (pullRequestViewMatches(current, next)) return;
    this.selectedViewId = this.selectedView()?.id ?? '';
    this.statusFilters = filters;
    this.projectId = projectId;
    this.reloadList();
    void this.persistViews(this.views, next);
  }

  private filterSelection(): string[] {
    switch (this.scopeFilterMode) {
      case 'projects': return this.projectId ? [this.projectId] : [];
      case 'authors': return this.statusFilters.author ? [this.statusFilters.author] : [];
      case 'labels': return this.statusFilters.labels?.flat() ?? [];
      case 'excluded-labels': return this.statusFilters.excludedLabels ?? [];
      default: return [];
    }
  }

  private applyScopeChoice(key?: string): void {
    if (!this.scopeFilterOpen || this.viewBusy) return;
    if (this.scopeFilterMode === 'projects') {
      this.changeListScope(key, this.statusFilters);
      this.scopeFilterOpen = false;
      return;
    }
    const filters = this.statusFilters;
    const next: NativePullRequestFilters = {
      draft: filters.draft, review: filters.review, checks: filters.checks, author: filters.author,
      labels: filters.labels, excludedLabels: filters.excludedLabels,
    };
    if (this.scopeFilterMode === 'authors') {
      next.author = key;
      this.scopeFilterOpen = false;
    } else {
      const selected = this.filterSelection();
      const normalized = key?.toLowerCase();
      const alreadySelected = selected.some((value: string) => value.toLowerCase() === normalized);
      if (key && !alreadySelected && selected.length >= 10) {
        this.getUIContext().getPromptAction().showToast({ message: '最多可选 10 个标签。' });
        return;
      }
      const values = !key ? [] : alreadySelected
        ? selected.filter((value: string) => value.toLowerCase() !== normalized) : selected.concat(key);
      if (this.scopeFilterMode === 'labels') next.labels = values.map((value: string) => [value]);
      else next.excludedLabels = values;
    }
    this.changeListScope(this.projectId, next);
  }

  private clearStatusFilters(): void {
    this.selectStatusFilters({});
  }

  private selectDraftFilter(draft?: NativePullRequestDraftFilter): void {
    this.selectStatusFilters({ draft, review: this.statusFilters.review, checks: this.statusFilters.checks });
  }

  private selectReviewFilter(review?: NativePullRequestReviewFilter): void {
    this.selectStatusFilters({ draft: this.statusFilters.draft, review, checks: this.statusFilters.checks });
  }

  private selectChecksFilter(checks?: NativePullRequestChecksFilter): void {
    this.selectStatusFilters({ draft: this.statusFilters.draft, review: this.statusFilters.review, checks });
  }

  @Builder
  private StatusChoice(id: string, label: string, selected: boolean, action: () => void) {
    Button(label, { type: ButtonType.Capsule,
      buttonStyle: selected ? ButtonStyleMode.NORMAL : ButtonStyleMode.TEXTUAL })
      .id(`workspace-pr-status-${id}`).height(44).margin({ right: 6, bottom: 4 })
      .accessibilitySelected(selected).enabled(!this.viewBusy).onClick(action)
  }

  @Builder
  private StatusFiltersSheet() {
    Column({ space: 10 }) {
      Text('状态筛选').fontSize(20).fontWeight(FontWeight.Medium)
      Text('草稿').fontSize(14).fontColor($r('sys.color.font_secondary'))
      Flex({ wrap: FlexWrap.Wrap }) {
        this.StatusChoice('draft-all', '全部', !this.statusFilters.draft, () =>
          this.selectDraftFilter(undefined))
        this.StatusChoice('draft-only', '仅草稿', this.statusFilters.draft === 'only', () =>
          this.selectDraftFilter('only'))
        this.StatusChoice('draft-hide', '隐藏草稿', this.statusFilters.draft === 'hide', () =>
          this.selectDraftFilter('hide'))
      }.width('100%')
      Text('审查').fontSize(14).fontColor($r('sys.color.font_secondary'))
      Flex({ wrap: FlexWrap.Wrap }) {
        this.StatusChoice('review-all', '全部', !this.statusFilters.review, () =>
          this.selectReviewFilter(undefined))
        this.StatusChoice('review-approved', '已批准', this.statusFilters.review === 'approved', () =>
          this.selectReviewFilter('approved'))
        this.StatusChoice('review-changes', '请求修改', this.statusFilters.review === 'changes-requested', () =>
          this.selectReviewFilter('changes-requested'))
        this.StatusChoice('review-required', '需要审查', this.statusFilters.review === 'review-required', () =>
          this.selectReviewFilter('review-required'))
        this.StatusChoice('review-none', '无审查', this.statusFilters.review === 'none', () =>
          this.selectReviewFilter('none'))
      }.width('100%')
      Text('检查').fontSize(14).fontColor($r('sys.color.font_secondary'))
      Flex({ wrap: FlexWrap.Wrap }) {
        this.StatusChoice('checks-all', '全部', !this.statusFilters.checks, () =>
          this.selectChecksFilter(undefined))
        this.StatusChoice('checks-passing', '已通过', this.statusFilters.checks === 'passing', () =>
          this.selectChecksFilter('passing'))
        this.StatusChoice('checks-failing', '未通过', this.statusFilters.checks === 'failing', () =>
          this.selectChecksFilter('failing'))
      }.width('100%')
      Row({ space: 8 }) {
        Button('清除状态筛选', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
          .id('workspace-pr-status-clear').height(44)
          .enabled(!this.viewBusy && this.statusFilterCount() > 0).onClick(() => this.clearStatusFilters())
        Blank()
        Button('完成', { type: ButtonType.Capsule }).id('workspace-pr-status-done').height(44)
          .onClick(() => { this.statusFiltersOpen = false; })
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start).padding(20)
  }

  @Builder
  private ScopeFilterChip(mode: NativePullRequestFilterMode) {
    Button(this.scopeFilterLabel(mode), { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
      .id(`workspace-pr-filter-${mode}`).height(40)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .enabled(!this.preferencesLoading && !this.viewBusy)
      .onClick(() => {
        this.scopeFilterMode = mode;
        this.scopeFilterOpen = true;
      })
  }

  private scopeFilterLabel(mode: NativePullRequestFilterMode): string {
    if (mode === 'projects') {
      if (!this.projectId) return '项目';
      return this.rows.find((row: NativePullRequestRow) => row.projectId === this.projectId)?.projectTitle ?? '已选项目';
    }
    if (mode === 'authors') return this.statusFilters.author === 'me' ? '我创建的' : this.statusFilters.author ?? '作者';
    if (mode === 'labels') return this.statusFilters.labels?.length
      ? `标签 ${this.statusFilters.labels.length}` : '标签';
    return this.statusFilters.excludedLabels?.length
      ? `排除标签 ${this.statusFilters.excludedLabels.length}` : '排除标签';
  }

  @Builder
  private ScopeFilterSheet() {
    WorkspacePullRequestFilterPicker({
        mode: this.scopeFilterMode, selected: this.filterSelection(),
        onRead: async (query?: string) => {
          if (!this.scopeFilterOpen || !this.onLoadFilters) throw new Error('当前环境无法读取筛选选项。');
          return this.onLoadFilters(this.scopeFilterMode, this.projectId, query);
        },
        onToggle: (key: string) => this.applyScopeChoice(key),
        onClear: () => this.applyScopeChoice(),
        onClose: () => { this.scopeFilterOpen = false; },
    })
  }

  @Builder
  private SortMenu() {
    Menu() {
      MenuItem({ content: sortLabel('updated') }).id('workspace-pr-sort-updated')
        .selected(this.sort === 'updated').selectIcon(true).onChange(() => this.selectSort('updated'))
      MenuItem({ content: sortLabel('created') }).id('workspace-pr-sort-created')
        .selected(this.sort === 'created').selectIcon(true).onChange(() => this.selectSort('created'))
      MenuItem({ content: sortLabel('oldest') }).id('workspace-pr-sort-oldest')
        .selected(this.sort === 'oldest').selectIcon(true).onChange(() => this.selectSort('oldest'))
    }
  }

  @Builder
  private StatusMenu() {
    Menu() {
      MenuItem({ content: '开放' }).selected(this.state === 'open').selectIcon(true)
        .onChange(() => this.selectState('open'))
      MenuItem({ content: '已合并' }).selected(this.state === 'merged').selectIcon(true)
        .onChange(() => this.selectState('merged'))
      MenuItem({ content: '已关闭' }).selected(this.state === 'closed').selectIcon(true)
        .onChange(() => this.selectState('closed'))
      MenuItem({ content: '全部状态' }).selected(this.state === 'all').selectIcon(true)
        .onChange(() => this.selectState('all'))
    }
  }

  @Builder
  private InvolvementMenu() {
    Menu() {
      MenuItem({ content: '所有参与方式' }).selected(this.involvement === 'all').selectIcon(true)
        .onChange(() => this.selectInvolvement('all'))
      MenuItem({ content: '我参与评审的' }).selected(this.involvement === 'reviewing').selectIcon(true)
        .onChange(() => this.selectInvolvement('reviewing'))
      MenuItem({ content: '我创建的' }).selected(this.involvement === 'authored').selectIcon(true)
        .onChange(() => this.selectInvolvement('authored'))
    }
  }

  @Builder
  private SavedViewsMenu() {
    Menu() {
      ForEach(this.views, (view: NativePullRequestSavedView) => {
        MenuItem({ content: view.name })
          .id(`workspace-pr-view-${view.id}`)
          .selected(this.selectedView()?.id === view.id && !this.viewModified())
          .selectIcon(true)
          .onChange(() => { void this.applyView(view); })
      }, (view: NativePullRequestSavedView) => `${view.id}:${view.name}`)
      MenuItem({ content: '保存当前视图…' })
        .id('workspace-pr-save-view')
        .onChange(() => this.editViewName())
      if (this.selectedView()) {
        if (this.viewModified()) {
          MenuItem({ content: '更新已保存视图' })
            .id('workspace-pr-update-view')
            .onChange(() => this.updateView())
        }
        MenuItem({ content: '重命名视图…' })
          .id('workspace-pr-rename-view')
          .onChange(() => this.editViewName(this.selectedView()))
        MenuItem({ content: '删除视图' })
          .id('workspace-pr-delete-view')
          .onChange(() => { void this.deleteView(); })
      }
    }
  }

  @Builder
  private ViewNameSheet() {
    Column({ space: 12 }) {
      Text(this.viewEditorId ? '重命名拉取请求视图' : '保存拉取请求视图')
        .fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary')).width('100%')
      TextInput({ text: this.viewEditorName, placeholder: '视图名称' })
        .id('workspace-pr-view-name')
        .height(48)
        .width('100%')
        .maxLength(80)
        .enabled(!this.viewBusy)
        .enterKeyType(EnterKeyType.Done)
        .onChange((name: string) => { this.viewEditorName = name; this.viewEditorError = ''; })
        .onSubmit(() => { void this.submitViewName(); })
      if (this.viewEditorError) Text(this.viewEditorError).fontSize(13).fontColor($r('sys.color.font_secondary'))
      Row({ space: 12 }) {
        Button('取消', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(44).layoutWeight(1).enabled(!this.viewBusy)
          .onClick(() => { this.viewEditorOpen = false; })
        Button('保存')
          .id('workspace-pr-view-name-save')
          .height(44).layoutWeight(1).enabled(!this.viewBusy)
          .onClick(() => { void this.submitViewName(); })
      }.width('100%')
    }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 24 })
  }

  @Builder
  private Filters() {
    Scroll() {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 6 }) {
            Text(this.viewLabel()).fontSize(13).fontColor($r('sys.color.font_primary'))
              .constraintSize({ maxWidth: 130 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(10).fontColor([$r('sys.color.icon_secondary')])
          }
        }
        .id('workspace-pr-saved-views')
        .height(40)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .accessibilityText(`已保存的拉取请求视图，${this.viewLabel()}`)
        .enabled(!this.preferencesLoading && !this.preferencesError && !this.viewBusy)
        .bindMenu(this.SavedViewsMenu)
        Button(this.statusFilterCount() ? `状态筛选 ${this.statusFilterCount()}` : '状态筛选',
          { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
          .id('workspace-pr-filter-status').height(40)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .enabled(!this.preferencesLoading && !this.viewBusy)
          .onClick(() => { this.statusFiltersOpen = true; })
          .bindSheet(this.statusFiltersOpen, this.StatusFiltersSheet(), {
            height: SheetSize.FIT_CONTENT, showClose: false,
            onDisappear: () => { this.statusFiltersOpen = false; },
          })
        Button({ type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 6 }) {
            Text(stateLabel(this.state)).fontSize(13).fontColor($r('sys.color.font_primary'))
            SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(10).fontColor([$r('sys.color.icon_secondary')])
          }
        }
        .id('workspace-pr-filter-state')
        .height(40)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .enabled(!this.preferencesLoading && !this.viewBusy)
        .bindMenu(this.StatusMenu)
        Button({ type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 6 }) {
            Text(involvementLabel(this.involvement)).fontSize(13).fontColor($r('sys.color.font_primary'))
            SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(10).fontColor([$r('sys.color.icon_secondary')])
          }
        }
        .id('workspace-pr-filter-involvement')
        .height(40)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .enabled(!this.preferencesLoading && !this.viewBusy)
        .bindMenu(this.InvolvementMenu)
        Button({ type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 6 }) {
            Text(sortLabel(this.sort)).fontSize(13).fontColor($r('sys.color.font_primary'))
            SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(10).fontColor([$r('sys.color.icon_secondary')])
          }
        }
        .id('workspace-pr-filter-sort')
        .height(40)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .enabled(!this.preferencesLoading && !this.viewBusy)
        .bindMenu(this.SortMenu)
        if (this.onLoadFilters) {
          this.ScopeFilterChip('projects')
          this.ScopeFilterChip('authors')
          this.ScopeFilterChip('labels')
          this.ScopeFilterChip('excluded-labels')
        }
      }
    }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).align(Alignment.Start)
  }

  @Builder
  private RequestRow(row: NativePullRequestRow) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 12 }) {
        PullRequestStatusMark({ state: row.state, draft: row.isDraft }).margin({ top: 3 })
        Column({ space: 4 }) {
          Text(row.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`#${row.number} · ${row.repository}${row.author ? ` · ${row.author}` : ''}`)
            .fontSize(12).fontColor($r('sys.color.font_secondary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (row.labels.length > 0) {
            Text(row.labels.join(' · ')).fontSize(12).fontColor($r('sys.color.font_secondary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([$r('sys.color.icon_secondary')])
      }.width('100%').alignItems(VerticalAlign.Top).padding({ top: 10, bottom: 10 })
    }
    .id(`workspace-pr-row-${row.number}`)
    .width('100%')
    .padding({ left: 0, right: 0 })
    .constraintSize({ minHeight: 56 })
    .accessibilityText(`#${row.number} ${row.title}，${row.repository}，${row.isDraft ? '草稿' : stateLabel(row.state)}`)
    .onClick(() => this.onOpen(row))
    Divider().color($r('sys.color.comp_divider')).margin({ left: 31 })
  }

  build() {
    Column({ space: 8 }) {
      Column() { this.Filters() }.width('100%').bindSheet(this.scopeFilterOpen, this.ScopeFilterSheet(), {
        height: SheetSize.LARGE, showClose: false,
        onDisappear: () => { this.scopeFilterOpen = false; },
      })
      if (this.preferencesError) {
        PullRequestFeedback({ text: this.preferencesError, onRetry: () => { void this.restoreViews(); } })
          .id('workspace-pr-views-error')
      }
      if (this.onLoad === undefined) {
        PullRequestFeedback({ text: '当前环境无法读取拉取请求。' })
      } else {
        ForEach(this.messages, (message: string) => {
          Text(message).fontSize(13).fontColor($r('sys.color.font_secondary')).width('100%').padding(6)
        }, (message: string) => message)
        ForEach(filterPullRequestRows(this.rows, this.statusFilters, this.projectId), (row: NativePullRequestRow) => {
          this.RequestRow(row)
        }, (row: NativePullRequestRow) => `${pullRequestRowKey(row)}:${row.updatedAt}:${row.title}`)
        if (this.loading) {
          PullRequestFeedback({ text: '正在加载拉取请求…', loading: true }).id('workspace-pr-loading')
        } else if (this.error) {
          PullRequestFeedback({ text: this.error, onRetry: () => this.retry() }).id('workspace-pr-error')
        } else if (this.next) {
          Button('加载更多', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
            .id('workspace-pr-more')
            .onClick(() => { if (this.next && !this.loading) void this.load(this.next, true); })
        } else if (filterPullRequestRows(this.rows, this.statusFilters, this.projectId).length === 0) {
          PullRequestFeedback({ text: '没有匹配的拉取请求。' }).id('workspace-pr-empty')
        } else if (this.truncated) {
          PullRequestFeedback({ text: '环境只返回了部分拉取请求。' })
        }
      }
    }.width('100%').bindSheet(this.viewEditorOpen, this.ViewNameSheet(), {
      height: SheetSize.FIT_CONTENT, showClose: false,
      onWillDismiss: (dismiss: DismissSheetAction) => { if (!this.viewBusy) dismiss.dismiss(); },
      onDisappear: () => { this.viewEditorOpen = false; },
    })
  }
}

@Component
export struct WorkspacePullRequestDetail {
  @Prop @Watch('reset') row?: NativePullRequestRow = undefined;
  @Prop @Watch('back') backRequest: number = 0;
  @Prop canWrite: boolean = false;
  @Prop environmentId: string = '';
  @Prop viewOwner: string = '';
  @StorageProp('t3.arkts.foreground') @Watch('guideForegroundChanged') private appInForeground: boolean = true;
  onBack: () => void = () => {};
  onLoadDetail?: (ref: NativePullRequestRef, allowStale?: boolean) => Promise<NativePullRequestDetail>;
  onLoadDiscussion?: (ref: NativePullRequestRef) => Promise<NativePullRequestDiscussion>;
  onLoadDiff?: (ref: NativePullRequestRef, cursor?: string) => Promise<NativePullRequestDiff>;
  onLoadFilePatch?: (ref: NativePullRequestRef, path: string) => Promise<NativePullRequestFile | undefined>;
  onLoadMetadata?: (ref: NativePullRequestRef, kind: NativePullRequestMetadataKind,
    query?: string) => Promise<NativePullRequestMetadataPage>;
  onGuideEnabled?: () => Promise<boolean>;
  onLoadGuide?: (ref: NativePullRequestRef) => Promise<NativePullRequestGuideResult>;
  onGuideCanGenerate?: () => Promise<boolean>;
  onGenerateGuide?: (ref: NativePullRequestRef) => Promise<NativePullRequestGuideResult>;
  onLoadCompletions?: (ref: NativePullRequestRef, trigger: NativePullRequestComposerTrigger) =>
    Promise<NativePullRequestCompletionOptions>;

  @State private detail?: NativePullRequestDetail = undefined;
  @State private discussion?: NativePullRequestDiscussion = undefined;
  @State private files: NativePullRequestFile[] = [];
  @State private fileGroups: NativePullRequestFileGroup[] = [];
  @State private file?: NativePullRequestFile = undefined;
  @State private filesPickerOpen: boolean = false;
  @State private collapsedDirectories: string[] = [];
  @State private pane: DetailPane = 'overview';
  @State private loadingDetail: boolean = false;
  @State private loadingDiscussion: boolean = false;
  @State private loadingDiff: boolean = false;
  @State private loadedDiff: boolean = false;
  @State private detailError: string = '';
  @State private discussionError: string = '';
  @State private diffError: string = '';
  @State private diffTruncated: boolean = false;
  @State private diffCursor?: string = undefined;
  @State private diffHeadSha: string = '';
  @State private withheldFilesReadable: boolean = false;
  @State private filePatchStatus: FilePatchStatus = 'idle';
  @State private guidesEnabled: boolean = false;
  @State private guideResult?: NativePullRequestGuideResult = undefined;
  @State private guidePosition: number = -1;
  @State private loadingGuide: boolean = false;
  @State private guideError: string = '';
  @State private guideCanGenerate: boolean = false;
  @State private guideStarting: boolean = false;
  @State private guideStartError: string = '';
  @State private guideJumpLoading: boolean = false;
  @State private guideJumpError: string = '';
  @State private guideFileFocus: string = '';
  @State private editField?: NativePullRequestEditField = undefined;
  @State private editOriginal: string = '';
  @State private metadataMode?: NativePullRequestMetadataKind = undefined;
  @State private reviewMode?: 'review' | 'comment' | 'inline' = undefined;
  @State private reviewBackRequest: number = 0;
  @State private inlineTarget?: NativePullRequestInlineTarget = undefined;
  @State private linePickerOpen: boolean = false;
  @State private diffLines: NativePullRequestDiffLine[] = [];
  @State private visibleDiffLines: number = 100;
  @State private draftToRelocate?: NativePullRequestLineDraft = undefined;
  private generation: number = 0;
  private guideTimer: number = -1;
  private guidePermissionRequest: number = 0;
  private guideFileRequest: number = 0;
  private filePatchRequest: number = 0;
  private filesWithoutText: Set<string> = new Set<string>();
  private guideFileTarget?: NativePullRequestGuideTarget = undefined;
  private diffRead?: Promise<void> = undefined;
  private jumpedFromGuide: boolean = false;
  private previousPane: DetailPane = 'overview';
  private detailScroller: Scroller = new Scroller();
  private fileScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.reset();
  }

  aboutToDisappear(): void {
    this.generation++;
    this.guideFileRequest++;
    clearTimeout(this.guideTimer);
  }

  private reset(): void {
    this.generation++;
    this.detail = undefined;
    this.discussion = undefined;
    this.files = [];
    this.fileGroups = [];
    this.file = undefined;
    this.filesPickerOpen = false;
    this.collapsedDirectories = [];
    this.pane = 'overview';
    this.previousPane = 'overview';
    this.loadingDetail = false;
    this.loadingDiscussion = false;
    this.loadingDiff = false;
    this.loadedDiff = false;
    this.detailError = '';
    this.discussionError = '';
    this.diffError = '';
    this.diffTruncated = false;
    this.diffCursor = undefined;
    this.diffHeadSha = '';
    this.diffRead = undefined;
    this.withheldFilesReadable = false;
    this.filesWithoutText.clear();
    this.cancelFilePatch();
    this.guidesEnabled = false;
    this.guideResult = undefined;
    this.guidePosition = -1;
    this.loadingGuide = false;
    this.guideError = '';
    this.guideCanGenerate = false;
    this.guideStarting = false;
    this.guideStartError = '';
    this.guideFileFocus = '';
    this.jumpedFromGuide = false;
    this.cancelGuideJump();
    clearTimeout(this.guideTimer);
    this.editField = undefined;
    this.editOriginal = '';
    this.metadataMode = undefined;
    this.closeReview();
    this.linePickerOpen = false;
    this.diffLines = [];
    this.draftToRelocate = undefined;
    void this.loadDetail();
    void this.loadGuideAvailability();
  }

  private back(): void {
    if (this.editField) this.closeEdit();
    else if (this.metadataMode) this.metadataMode = undefined;
    else if (this.reviewMode) this.reviewBackRequest++;
    else if (this.linePickerOpen) this.linePickerOpen = false;
    else if (this.filesPickerOpen) this.filesPickerOpen = false;
    else if (this.file) {
      this.file = undefined;
      this.guideFileFocus = '';
      this.guideFileTarget = undefined;
      this.cancelFilePatch();
      if (this.jumpedFromGuide) {
        this.jumpedFromGuide = false;
        this.selectPane('guide');
      }
    }
    else if (this.pane === 'changes') {
      this.draftToRelocate = undefined;
      this.selectPane(this.previousPane);
    }
    else if (this.pane === 'guide' && this.guidePosition >= 0) this.selectGuideStop(-1);
    else this.onBack();
  }

  private selectPane(pane: DetailPane): void {
    if (pane === 'changes' && this.pane !== 'changes') this.previousPane = this.pane;
    if (this.pane === 'guide' && pane !== 'guide') this.cancelGuideJump();
    clearTimeout(this.guideTimer);
    this.pane = pane;
    if (pane === 'activity' && !this.discussion && !this.discussionError) void this.loadDiscussion();
    if (pane === 'changes' && !this.diffError && (!this.loadedDiff ||
      (this.detail?.headSha && this.detail.headSha !== this.diffHeadSha))) void this.loadDiff();
    if (pane === 'guide') {
      void this.refreshGuidePermission();
      void this.loadGuide();
    }
  }

  private async loadDetail(): Promise<void> {
    if (!this.row || this.loadingDetail || !this.onLoadDetail) return;
    const generation = this.generation;
    this.loadingDetail = true;
    this.detailError = '';
    try {
      const detail = await this.onLoadDetail(this.row);
      if (this.generation === generation) this.detail = detail;
    } catch (error) {
      if (this.generation === generation) this.detailError = (error as Error).message || '无法读取拉取请求详情。';
    } finally {
      if (this.generation === generation) this.loadingDetail = false;
    }
  }

  private async loadDiscussion(): Promise<void> {
    if (!this.row || this.loadingDiscussion || !this.onLoadDiscussion) return;
    const generation = this.generation;
    this.loadingDiscussion = true;
    this.discussionError = '';
    try {
      const discussion = await this.onLoadDiscussion(this.row);
      if (this.generation === generation) this.discussion = discussion;
    } catch (error) {
      if (this.generation === generation) this.discussionError = (error as Error).message || '无法读取拉取请求动态。';
    } finally {
      if (this.generation === generation) this.loadingDiscussion = false;
    }
  }

  private loadDiff(cursor?: string, headSha: string = this.detail?.headSha ?? ''): Promise<void> {
    if (this.diffRead) return this.diffRead;
    const pending = this.fetchDiff(cursor, headSha).finally(() => {
      if (this.diffRead === pending) this.diffRead = undefined;
    });
    this.diffRead = pending;
    return pending;
  }

  private async fetchDiff(cursor: string | undefined, headSha: string): Promise<void> {
    if (!this.row || this.loadingDiff || !this.onLoadDiff) return;
    const generation = this.generation;
    this.loadingDiff = true;
    this.diffError = '';
    if (!cursor) {
      this.files = [];
      this.fileGroups = [];
      this.diffCursor = undefined;
      this.diffHeadSha = '';
      this.diffTruncated = false;
      this.loadedDiff = false;
      this.withheldFilesReadable = false;
      this.filesWithoutText.clear();
      this.cancelFilePatch();
    }
    try {
      const diff = await this.onLoadDiff(this.row, cursor);
      if (this.generation !== generation) return;
      if (!cursor) {
        this.diffHeadSha = headSha;
        this.withheldFilesReadable = diff.withheldFilesReadable === true;
      }
      else if (this.diffHeadSha !== headSha) this.diffHeadSha = '';
      this.files = cursor ? this.files.concat(diff.files) : diff.files;
      this.fileGroups = groupPullRequestFiles(this.files);
      this.diffCursor = cursor === diff.nextCursor ? undefined : diff.nextCursor;
      this.diffTruncated = diff.truncated || (cursor !== undefined && this.diffTruncated);
      this.loadedDiff = true;
      if (this.draftToRelocate && !this.file) {
        const match = this.files.find((entry: NativePullRequestFile) => this.matchesRelocatingDraft(entry));
        if (match) this.showFile(match);
      }
    } catch (error) {
      if (this.generation === generation) this.diffError = (error as Error).message || '无法读取文件变更。';
    } finally {
      if (this.generation === generation) this.loadingDiff = false;
    }
  }

  private async loadGuideAvailability(): Promise<void> {
    if (!this.row || !this.onGuideEnabled || !this.onLoadGuide) return;
    const generation = this.generation;
    try {
      const enabled = await this.onGuideEnabled();
      if (generation === this.generation) this.guidesEnabled = enabled;
    } catch (_) {
      if (generation === this.generation) this.guidesEnabled = false;
    }
  }

  private async refreshGuidePermission(): Promise<void> {
    if (!this.guidesEnabled || !this.onGuideCanGenerate || !this.onGenerateGuide) return;
    const generation = this.generation;
    const request = ++this.guidePermissionRequest;
    try {
      const allowed = await this.onGuideCanGenerate();
      if (this.generation === generation && this.guidePermissionRequest === request) this.guideCanGenerate = allowed;
    } catch (_) {
      if (this.generation === generation && this.guidePermissionRequest === request) this.guideCanGenerate = false;
    }
  }

  private guideVisible(): boolean {
    return this.appInForeground && this.pane === 'guide' && !this.editField && !this.reviewMode && !this.metadataMode;
  }

  private guideForegroundChanged(): void {
    if (this.guideVisible()) {
      void this.refreshGuidePermission();
      void this.loadGuide();
    }
    else {
      clearTimeout(this.guideTimer);
      this.cancelGuideJump();
    }
  }

  private acceptGuideResult(result: NativePullRequestGuideResult): void {
    const previous = this.guideResult;
    this.guideResult = result;
    if (previous?.currentHeadSha !== undefined && previous.currentHeadSha !== result.currentHeadSha) {
      this.cancelGuideJump();
    }
    if (previous?.guide && (previous.guide.headSha !== result.guide?.headSha ||
      previous.guide.generatedAt !== result.guide?.generatedAt)) {
      this.selectGuideStop(-1);
    }
  }

  private scheduleGuideRefresh(): void {
    clearTimeout(this.guideTimer);
    if (this.guideVisible() && this.guideResult?.run?._tag === 'Running') {
      this.guideTimer = setTimeout(() => { void this.loadGuide(); }, 5000);
    }
  }

  private async loadGuide(): Promise<void> {
    if (!this.guidesEnabled || !this.guideVisible() || !this.row || !this.onLoadGuide ||
      this.loadingGuide || this.guideStarting) return;
    clearTimeout(this.guideTimer);
    const generation = this.generation;
    this.loadingGuide = true;
    this.guideError = '';
    try {
      const result = await this.onLoadGuide(this.row);
      if (generation === this.generation) this.acceptGuideResult(result);
    } catch (error) {
      if (generation === this.generation) this.guideError = (error as Error).message || '无法刷新审查指南。';
    } finally {
      if (generation === this.generation) {
        this.loadingGuide = false;
        this.scheduleGuideRefresh();
      }
    }
  }

  private async startGuide(): Promise<void> {
    if (!this.guidesEnabled || !this.guideVisible() || !this.guideCanGenerate || !this.row ||
      !this.onGenerateGuide || !this.guideResult || this.loadingGuide ||
      this.guideStarting || this.guideResult.run?._tag === 'Running') return;
    const generation = this.generation;
    clearTimeout(this.guideTimer);
    this.guideStarting = true;
    this.guideStartError = '';
    this.guideError = '';
    try {
      const result = await this.onGenerateGuide(this.row);
      if (generation === this.generation) this.acceptGuideResult(result);
    } catch (error) {
      if (generation === this.generation) {
        this.guideStartError = (error as Error).message || '无法启动审查指南生成。';
        void this.refreshGuidePermission();
      }
    } finally {
      if (generation === this.generation) {
        this.guideStarting = false;
        this.scheduleGuideRefresh();
      }
    }
  }

  private cancelGuideJump(): void {
    this.guideFileRequest++;
    this.guideJumpLoading = false;
    this.guideJumpError = '';
  }

  private guideRequestCurrent(request: number): boolean {
    return request === this.guideFileRequest && this.guideVisible();
  }

  private guideFile(path: string): NativePullRequestFile | undefined {
    return this.files.find((file: NativePullRequestFile) => file.path === path) ??
      this.files.find((file: NativePullRequestFile) => file.previousPath === path);
  }

  private async loadGuideFiles(paths: string[], request: number): Promise<void> {
    if (!this.onLoadDiff || this.detail?.diffAvailable === false) return;
    const headSha = this.guideResult?.currentHeadSha ?? this.detail?.headSha ?? '';
    if (this.diffRead) await this.diffRead;
    if (!this.guideRequestCurrent(request)) return;
    if (!this.loadedDiff || this.diffHeadSha !== headSha || this.diffError) await this.loadDiff(undefined, headSha);
    const seen = new Set<string>();
    while (this.guideRequestCurrent(request) && !this.diffError && this.diffCursor &&
      !seen.has(this.diffCursor) && paths.some((path: string) => this.guideFile(path) === undefined)) {
      const cursor = this.diffCursor;
      seen.add(cursor);
      await this.loadDiff(cursor, headSha);
    }
  }

  private selectGuideStop(position: number): void {
    const stop = this.guideResult?.guide?.stops[position];
    if (position >= 0 && !stop) return;
    this.cancelGuideJump();
    this.guidePosition = position;
    this.detailScroller.scrollEdge(Edge.Top);
    if (stop && this.guideResult && !pullRequestGuideIsStale(this.guideResult)) {
      const paths = stop.excerpts.map((excerpt: NativePullRequestGuideTarget) => excerpt.path);
      if (paths.length > 0) void this.loadGuideFiles(paths, this.guideFileRequest);
    }
  }

  private async openGuideFile(target: NativePullRequestGuideTarget): Promise<void> {
    if (!this.guideVisible() || this.guidePosition < 0 || this.guideJumpLoading) return;
    if (!this.onLoadDiff || this.detail?.diffAvailable === false) {
      this.guideJumpError = '当前环境无法读取此拉取请求的变更。';
      return;
    }
    const request = ++this.guideFileRequest;
    this.guideJumpLoading = true;
    this.guideJumpError = '';
    await this.loadGuideFiles([target.path], request);
    if (!this.guideRequestCurrent(request)) return;
    this.guideJumpLoading = false;
    const file = this.guideFile(target.path);
    if (this.diffError || !file) {
      this.guideJumpError = this.diffError || '此文件未出现在当前拉取请求的变更中。';
      return;
    }
    clearTimeout(this.guideTimer);
    this.previousPane = 'guide';
    this.pane = 'changes';
    this.jumpedFromGuide = true;
    this.showFile(file);
    this.guideFileTarget = target;
    this.guideFileFocus = this.guideResult && !pullRequestGuideIsStale(this.guideResult)
      ? pullRequestGuideExcerpt(file.patch.slice(0, FILE_PATCH_PREVIEW_LIMIT), target) : '';
  }

  private canReview(): boolean {
    return this.canWrite && (this.detail?.actions.verdicts.length ?? 0) > 0;
  }

  private canAddComment(): boolean {
    return this.canWrite && this.detail?.actions.comment === true;
  }

  private canEditRequest(): boolean {
    return this.canWrite && this.detail?.actions.editChangeRequest === true;
  }

  private canOpenMetadata(kind: NativePullRequestMetadataKind): boolean {
    if (!this.canWrite || !this.detail || !this.onLoadMetadata) return false;
    return kind === 'labels' ? this.detail.actions.editLabels : this.detail.actions.requestReviewers;
  }

  private async loadMetadata(query?: string): Promise<NativePullRequestMetadataPage> {
    if (!this.row || !this.metadataMode || !this.onLoadMetadata || !this.canOpenMetadata(this.metadataMode)) {
      throw new Error('当前连接无法读取此选项。');
    }
    return this.onLoadMetadata(this.row, this.metadataMode, query);
  }

  private async loadCompletions(trigger: NativePullRequestComposerTrigger): Promise<NativePullRequestCompletionOptions> {
    if (!this.row || !this.onLoadCompletions) throw new Error('当前环境无法读取引用候选。');
    return this.onLoadCompletions(this.row, trigger);
  }

  private openEdit(field: NativePullRequestEditField, comment?: NativePullRequestComment): void {
    if (!this.detail || !this.canWrite) return;
    if (field === 'comment') {
      if (!comment || !canEditPullRequestComment(this.detail, comment)) return;
      this.editOriginal = comment.body;
    } else {
      if (!this.canEditRequest()) return;
      this.editOriginal = field === 'title' ? this.detail.title : this.detail.body;
    }
    this.editField = field;
    if (this.pane === 'guide') this.cancelGuideJump();
  }

  private closeEdit(): void {
    this.editField = undefined;
    void this.loadGuide();
  }

  private openReview(mode: 'review' | 'comment'): void {
    if (mode === 'review' ? !this.canReview() : !this.canAddComment()) return;
    this.reviewMode = mode;
    if (this.pane === 'guide') this.cancelGuideJump();
    void this.loadDetail();
  }

  private closeReview(): void {
    this.reviewMode = undefined;
    this.inlineTarget = undefined;
    void this.loadGuide();
  }

  private reviewDraftKey(): string {
    const row = this.row;
    return row ? pullRequestReviewDraftKey(this.viewOwner, this.environmentId, {
      projectId: row.projectId, host: row.host, repository: row.repository, number: row.number,
    }) : '';
  }

  private canPickInlineLine(): boolean {
    return this.canWrite && this.detail?.actions.inlineComment === true && this.diffHeadSha.length > 0 &&
      this.detail.headSha === this.diffHeadSha && !!this.file && !this.file.withheld;
  }

  private matchesRelocatingDraft(file: NativePullRequestFile): boolean {
    const path = this.draftToRelocate?.path;
    return !!path && (file.path === path || file.previousPath === path);
  }

  private relocateInlineDraft(draft: NativePullRequestLineDraft): void {
    if (!this.canWrite || !this.detail?.actions.inlineComment || !this.detail.headSha) return;
    this.closeReview();
    this.file = undefined;
    this.draftToRelocate = draft;
    this.selectPane('changes');
    if (this.detail.headSha === this.diffHeadSha && this.loadedDiff && !this.loadingDiff) {
      const match = this.files.find((entry: NativePullRequestFile) => this.matchesRelocatingDraft(entry));
      if (match) this.showFile(match);
    }
  }

  private openInlineLines(): void {
    if (!this.file || !this.canPickInlineLine()) return;
    this.diffLines = pullRequestDiffLines(this.file.patch.slice(0, FILE_PATCH_PREVIEW_LIMIT));
    this.visibleDiffLines = 100;
    this.linePickerOpen = true;
  }

  private openInlineComment(line: NativePullRequestDiffLine): void {
    if (!this.file || !this.canPickInlineLine()) return;
    this.inlineTarget = { path: this.file.path, oldPath: this.file.previousPath ?? undefined,
      side: line.side, line: line.line, code: line.code, headSha: this.diffHeadSha,
      draftId: this.matchesRelocatingDraft(this.file) ? this.draftToRelocate?.id : undefined };
    if (this.inlineTarget.draftId) this.draftToRelocate = undefined;
    this.linePickerOpen = false;
    this.reviewMode = 'inline';
    void this.loadDetail();
  }

  private showFile(file: NativePullRequestFile): void {
    this.filesPickerOpen = false;
    if (this.file && this.file !== file) this.fileScroller.scrollEdge(Edge.Top);
    if (this.file?.path !== file.path) {
      this.guideFileFocus = '';
      this.guideFileTarget = undefined;
      this.cancelFilePatch();
      if (this.filesWithoutText.has(file.path)) this.filePatchStatus = 'empty';
    }
    this.file = file;
  }

  private cancelFilePatch(): void {
    this.filePatchRequest++;
    this.filePatchStatus = 'idle';
  }

  private async loadFilePatch(): Promise<void> {
    const file = this.file;
    const row = this.row;
    const readPatch = this.onLoadFilePatch;
    const readDetail = this.onLoadDetail;
    if (!file?.withheld || !row || !readPatch || !readDetail || !this.withheldFilesReadable ||
      this.filePatchStatus === 'loading' || this.filePatchStatus === 'empty') return;
    const request = ++this.filePatchRequest;
    const generation = this.generation;
    const headSha = this.diffHeadSha;
    const environmentId = this.environmentId;
    const current = (): boolean => this.filePatchRequest === request && this.generation === generation &&
      this.environmentId === environmentId && this.file?.path === file.path;
    this.filePatchStatus = 'loading';
    try {
      const patch = await readPatch(row, file.path);
      if (!current()) return;
      const latest = await readDetail(row, false);
      if (!current()) return;
      if (!headSha || latest.headSha !== headSha || this.diffHeadSha !== headSha) {
        if (this.diffRead) await this.diffRead;
        if (!current()) return;
        this.detail = latest;
        this.file = undefined;
        this.guideFileFocus = '';
        this.guideFileTarget = undefined;
        this.jumpedFromGuide = false;
        this.getUIContext().getPromptAction().showToast({ message: headSha
          ? '分支已更新，请从变更列表重新选择文件。' : '已确认分支版本，请从变更列表重新选择文件。' });
        await this.loadDiff(undefined, latest.headSha);
        return;
      }
      if (!patch) {
        this.filesWithoutText.add(file.path);
        this.filePatchStatus = 'empty';
        return;
      }
      const loaded: NativePullRequestFile = { path: patch.path, previousPath: patch.previousPath,
        additions: file.additions ?? patch.additions, deletions: file.deletions ?? patch.deletions,
        patch: patch.patch, withheld: false };
      this.files = this.files.map((entry: NativePullRequestFile) => entry.path === file.path ? loaded : entry);
      this.fileGroups = groupPullRequestFiles(this.files);
      this.file = loaded;
      this.filePatchStatus = 'idle';
      const target = this.guideFileTarget;
      if (target && this.guideResult && !pullRequestGuideIsStale(this.guideResult) &&
        this.guideResult.currentHeadSha === headSha) {
        this.guideFileFocus = pullRequestGuideExcerpt(loaded.patch.slice(0, FILE_PATCH_PREVIEW_LIMIT), target);
      }
    } catch (_) {
      if (current()) this.filePatchStatus = 'error';
    }
  }

  private toggleDirectory(directory: string): void {
    this.collapsedDirectories = this.collapsedDirectories.includes(directory)
      ? this.collapsedDirectories.filter((value: string) => value !== directory)
      : this.collapsedDirectories.concat(directory);
  }

  @Builder
  private ActionsMenu() {
    Menu() {
      if (this.canReview()) {
        MenuItem({ content: '提交审查' }).id('workspace-pr-action-review')
          .onChange(() => this.openReview('review'))
      }
      if (this.canAddComment()) {
        MenuItem({ content: '添加评论' }).id('workspace-pr-action-comment')
          .onChange(() => this.openReview('comment'))
      }
      if (this.pane !== 'changes' && this.canEditRequest()) {
        MenuItem({ content: '编辑标题' }).id('workspace-pr-action-edit-title')
          .onChange(() => this.openEdit('title'))
        MenuItem({ content: '编辑描述' }).id('workspace-pr-action-edit-body')
          .onChange(() => this.openEdit('body'))
      }
      if (this.canPickInlineLine()) {
        MenuItem({ content: '添加行评论' }).id('workspace-pr-action-inline')
          .onChange(() => this.openInlineLines())
      }
    }
  }

  @Builder
  private Header() {
    Row({ space: 12 }) {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        SymbolGlyph($r('sys.symbol.arrow_left')).fontSize(22).fontColor([$r('sys.color.icon_primary')])
      }
      .id('workspace-pr-detail-back')
      .width(48)
      .height(48)
      .padding(0)
      .accessibilityText('返回')
      .onClick(() => this.back())
      Column({ space: 3 }) {
        Text(this.pane === 'changes' ? this.file ? '变更' : '变更文件' :
          this.pane === 'guide' && this.guidePosition >= 0
            ? `步骤 ${this.guidePosition + 1} / ${this.guideResult?.guide?.stops.length ?? 0}`
            : `#${this.row?.number ?? ''}`)
          .fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
        Text(this.pane === 'changes' ? `#${this.row?.number ?? ''} · ${this.row?.repository ?? ''}` :
          this.row?.repository ?? '').fontSize(12).fontColor($r('sys.color.font_secondary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      if (this.file) {
        Button('变更文件', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
          .id('workspace-pr-files-picker').height(44)
          .onClick(() => { this.filesPickerOpen = true; })
      }
      if (this.canReview() || this.canAddComment() || (this.pane !== 'changes' && this.canEditRequest())) {
        Button('···', { type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL })
          .id('workspace-pr-actions').width(44).height(44).padding(0).fontSize(22)
          .accessibilityText('拉取请求操作').bindMenu(this.ActionsMenu)
      }
    }
    .width('100%')
    .height(60)
    .padding({ left: 8, right: 16 })
    .backgroundColor($r('sys.color.comp_background_primary'))
  }

  @Builder
  private PaneButton(pane: DetailPane, title: string) {
    Button(title, { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
      .id(pane === 'guide' ? 'workspace-pr-guide' : pane === 'activity' ? 'workspace-pr-discussion' : 'workspace-pr-overview')
      .height(36)
      .layoutWeight(1)
      .fontSize(14)
      .fontColor(this.pane === pane ? $r('sys.color.font_primary') : $r('sys.color.font_secondary'))
      .backgroundColor(this.pane === pane ? $r('sys.color.comp_background_primary') : Color.Transparent)
      .accessibilitySelected(this.pane === pane)
      .onClick(() => this.selectPane(pane))
  }

  @Builder
  private Identity(row: NativePullRequestRow) {
    Text(row.title).fontSize(22).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
    Row({ space: 8 }) {
      PullRequestStatusMark({ state: row.state, draft: row.isDraft })
      Text(row.isDraft ? '草稿' : stateLabel(row.state)).fontSize(13).fontColor(statusColor(row.state, row.isDraft))
      if (row.author) Text(row.author).fontSize(13).fontColor($r('sys.color.font_secondary'))
    }.width('100%')
    Text(`${row.baseBranch} ← ${row.headBranch}`).fontSize(13).fontColor($r('sys.color.font_secondary'))
    Row({ space: 2 }) {
      this.PaneButton('overview', '概览')
      this.PaneButton('activity', '动态')
      if (this.guidesEnabled) this.PaneButton('guide', '指南')
    }
    .width('100%')
    .padding(4)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .borderRadius(24)
  }

  @Builder
  private Overview() {
    if (this.loadingDetail) {
      PullRequestFeedback({ text: '正在加载拉取请求详情…', loading: true }).id('workspace-pr-detail-loading')
    } else if (this.detailError) {
      PullRequestFeedback({ text: this.detailError, onRetry: () => { void this.loadDetail(); } })
    } else if (this.detail) {
      Text('描述').fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
      Text(this.detail.body || '此拉取请求没有描述。').fontSize(15).fontColor($r('sys.color.font_secondary'))
        .copyOption(CopyOptions.LocalDevice)
      if (this.detail.labels.length > 0 || this.canOpenMetadata('labels')) {
        Row({ space: 8 }) {
          Text(this.detail.labels.length ? `标签  ${this.detail.labels.join(' · ')}` : '标签')
            .fontSize(14).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
          if (this.canOpenMetadata('labels')) {
            Button(this.detail.labels.length ? '编辑标签' : '添加标签',
              { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
              .id('workspace-pr-labels').height(44).onClick(() => { this.metadataMode = 'labels'; })
          }
        }.width('100%')
      }
      if (this.detail.reviewers.length > 0 || this.canOpenMetadata('reviewers')) {
        Row({ space: 8 }) {
          Text(this.detail.reviewers.length ? `评审人  ${this.detail.reviewers.join(' · ')}` : '评审人')
            .fontSize(14).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
          if (this.canOpenMetadata('reviewers')) {
            Button('请求评审', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
              .id('workspace-pr-reviewers').height(44).onClick(() => { this.metadataMode = 'reviewers'; })
          }
        }.width('100%')
      }
      if (this.detail.changedFiles !== null) {
        Text(`已更改 ${this.detail.changedFiles} 个文件`).fontSize(14).fontColor($r('sys.color.font_secondary'))
      }
    } else {
      PullRequestFeedback({ text: '当前环境无法读取拉取请求详情。' })
    }
  }

  @Builder
  private DiscussionComment(comment: NativePullRequestComment) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(comment.author || '未知作者').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
        Text(updatedLabel(comment.createdAt)).fontSize(12).fontColor($r('sys.color.font_secondary'))
        if (this.canWrite && this.detail && canEditPullRequestComment(this.detail, comment)) {
          Button('编辑', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
            .id('workspace-pr-edit-comment-' + comment.key).height(40)
            .onClick(() => this.openEdit('comment', comment))
        }
      }.width('100%')
      if (comment.location) {
        Text(comment.location).fontFamily('monospace').fontSize(12).fontColor($r('sys.color.font_secondary'))
      }
      Text(comment.body).fontSize(14).fontColor($r('sys.color.font_primary')).copyOption(CopyOptions.LocalDevice)
    }.width('100%').alignItems(HorizontalAlign.Start).padding(12).borderRadius(12)
      .backgroundColor($r('sys.color.comp_background_secondary'))
  }

  @Builder
  private Activity() {
    if (this.loadingDiscussion) {
      PullRequestFeedback({ text: '正在加载动态…', loading: true }).id('workspace-pr-activity-loading')
    } else if (this.discussionError) {
      PullRequestFeedback({ text: this.discussionError, onRetry: () => { void this.loadDiscussion(); } })
    } else if (this.discussion) {
      ForEach(this.discussion.comments, (comment: NativePullRequestComment) => {
        this.DiscussionComment(comment)
      }, (comment: NativePullRequestComment) => comment.key)
      if (this.discussion.comments.length === 0) PullRequestFeedback({ text: '还没有讨论。' })
      if (this.discussion.truncated) PullRequestFeedback({ text: '环境只返回了部分讨论。' })
    } else {
      PullRequestFeedback({ text: '当前环境无法读取拉取请求动态。' })
    }
  }

  @Builder
  private FileStats(file: NativePullRequestFile) {
    if (file.additions !== null && file.deletions !== null) {
      Row({ space: 5 }) {
        Text(`+${file.additions}`).fontSize(12).fontColor('#33A267')
        Text(`−${file.deletions}`).fontSize(12).fontColor('#DE5D5F')
      }.accessibilityText(`新增 ${file.additions} 行，删除 ${file.deletions} 行`)
    }
  }

  @Builder
  private FileRow(file: NativePullRequestFile, inPicker: boolean) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.doc_plaintext')).fontSize(18).fontColor([$r('sys.color.icon_secondary')])
        Column({ space: 4 }) {
          Text(file.path.slice(file.path.lastIndexOf('/') + 1))
            .fontSize(14).fontColor($r('sys.color.font_primary')).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (!inPicker && file.path.includes('/')) {
            Text(file.path.slice(0, file.path.lastIndexOf('/'))).fontSize(12)
              .fontColor($r('sys.color.font_secondary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        this.FileStats(file)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([$r('sys.color.icon_secondary')])
      }.width('100%').padding({ top: 9, bottom: 9 })
    }
    .id(`${inPicker ? 'workspace-pr-picker-file' : 'workspace-pr-file'}-${file.path}`)
    .width('100%').constraintSize({ minHeight: 52 }).padding({ left: 0, right: 0 })
    .accessibilityText(file.path)
    .onClick(() => this.showFile(file))
    Divider().color($r('sys.color.comp_divider')).margin({ left: 28 })
  }

  @Builder
  private ChangesFooter(inPicker: boolean) {
    if (this.loadingDiff) {
      PullRequestFeedback({ text: '正在加载变更…', loading: true })
        .id(inPicker ? 'workspace-pr-picker-loading' : 'workspace-pr-changes-loading')
    } else if (this.diffError) {
      PullRequestFeedback({ text: this.diffError, onRetry: () => { void this.loadDiff(this.diffCursor); } })
    } else if (this.diffCursor) {
      Button('加载更多文件', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
        .id(inPicker ? 'workspace-pr-picker-more-files' : 'workspace-pr-more-files')
        .onClick(() => { void this.loadDiff(this.diffCursor); })
    } else if (this.diffTruncated) {
      PullRequestFeedback({ text: '环境只返回了部分变更。' })
    } else if (this.files.length === 0) {
      PullRequestFeedback({ text: '没有可显示的文件变更。' })
    }
  }

  @Builder
  private ChangesList() {
    Scroll() {
      Column() {
        if (this.draftToRelocate) {
          PullRequestFeedback({ text: `为 ${this.draftToRelocate.path} 的草稿重新选择评论行。` })
        }
        if (this.files.length > 0) {
          Text(`已加载 ${this.files.length} 个文件`).fontSize(13).fontColor($r('sys.color.font_secondary'))
            .margin({ bottom: 6 })
        }
        ForEach(this.files, (file: NativePullRequestFile) => {
          this.FileRow(file, false)
        }, (file: NativePullRequestFile, index: number) => `${file.path}:${index}`)
        this.ChangesFooter(false)
      }.width('100%').constraintSize({ maxWidth: 560 }).alignItems(HorizontalAlign.Start)
        .padding({ left: 20, right: 20, top: 12, bottom: 20 })
    }.id('workspace-pr-file-list').width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off)
      .visibility(this.file ? Visibility.Hidden : Visibility.Visible)
  }

  @Builder
  private FileDiff(file: NativePullRequestFile) {
    Scroll(this.fileScroller) {
      Column({ space: 12 }) {
        Column({ space: 8 }) {
          Text(file.path).id('workspace-pr-file-path').fontSize(18).fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary')).copyOption(CopyOptions.LocalDevice)
          if (file.previousPath) {
            Text(`原路径 ${file.previousPath}`).fontSize(13).fontColor($r('sys.color.font_secondary'))
          }
          this.FileStats(file)
        }.width('100%').alignItems(HorizontalAlign.Start)
        if (this.guideFileFocus) {
          Text(this.guideFileFocus).id('workspace-pr-guide-file-focus')
            .fontFamily('monospace').fontSize(13).lineHeight(19).width('100%')
            .fontColor($r('sys.color.font_primary')).copyOption(CopyOptions.LocalDevice)
            .padding(12).borderRadius(8).backgroundColor($r('sys.color.comp_background_secondary'))
        }
        if (file.withheld) {
          this.WithheldFilePatch()
        } else {
          Text(file.patch.slice(0, FILE_PATCH_PREVIEW_LIMIT))
            .id('workspace-pr-file-patch').fontFamily('monospace').fontSize(12).lineHeight(18).width('100%')
            .fontColor($r('sys.color.font_primary')).copyOption(CopyOptions.LocalDevice)
            .padding(12).borderRadius(8).backgroundColor($r('sys.color.comp_background_secondary'))
          if (file.patch.length > FILE_PATCH_PREVIEW_LIMIT) {
            PullRequestFeedback({ text: `此文件较大，已显示前 ${FILE_PATCH_PREVIEW_LIMIT} 个字符。` })
          }
        }
      }.width('100%').constraintSize({ maxWidth: 560 }).alignItems(HorizontalAlign.Start)
        .padding({ left: 20, right: 20, top: 12, bottom: 20 })
    }.id('workspace-pr-file-detail').width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off)
  }

  @Builder
  private WithheldFilePatch() {
    if (this.filePatchStatus === 'loading') {
      PullRequestFeedback({ text: '正在加载补丁…', loading: true }).id('workspace-pr-file-patch-loading')
    } else if (this.filePatchStatus === 'empty') {
      PullRequestFeedback({ text: '此文件没有文本补丁。' }).id('workspace-pr-file-patch-empty')
    } else if (this.withheldFilesReadable && this.onLoadFilePatch && this.onLoadDetail) {
      Column({ space: 8 }) {
        if (this.filePatchStatus === 'error') {
          Text('无法加载此文件的补丁。').fontSize(14).fontColor($r('sys.color.font_secondary'))
            .id('workspace-pr-file-patch-error')
        }
        Button(this.filePatchStatus === 'error' ? '重试' : '补丁过大，点击加载',
          { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
          .id('workspace-pr-file-load-patch').height(44)
          .enabled(!this.loadingDiff).onClick(() => { void this.loadFilePatch(); })
      }.width('100%').alignItems(HorizontalAlign.Start)
    } else {
      PullRequestFeedback({ text: '此文件的补丁未包含在环境返回的变更中。' })
        .id('workspace-pr-file-patch-unavailable')
    }
  }

  @Builder
  private FileDirectory(group: NativePullRequestFileGroup) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 8 }) {
        SymbolGlyph(this.collapsedDirectories.includes(group.directory) ? $r('sys.symbol.chevron_right') :
          $r('sys.symbol.chevron_down')).fontSize(12).fontColor([$r('sys.color.icon_secondary')])
        SymbolGlyph($r('sys.symbol.folder')).fontSize(17).fontColor([$r('sys.color.icon_secondary')])
        Text(group.directory || '仓库根目录').fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary')).layoutWeight(1).maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }.width('100%').height(44).padding({ left: 0, right: 0 })
      .accessibilityDescription(this.collapsedDirectories.includes(group.directory) ? '展开目录' : '折叠目录')
      .onClick(() => this.toggleDirectory(group.directory))
    if (!this.collapsedDirectories.includes(group.directory)) {
      ForEach(group.files, (file: NativePullRequestFile) => {
        this.FileRow(file, true)
      }, (file: NativePullRequestFile, index: number) => `${file.path}:${index}`)
    }
  }

  @Builder
  private FilesPicker() {
    Column() {
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Text('变更文件').fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
          Text(`#${this.row?.number ?? ''} · ${this.row?.repository ?? ''}`)
            .fontSize(12).fontColor($r('sys.color.font_secondary')).maxLines(1)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([$r('sys.color.icon_secondary')])
        }.width(44).height(44).padding(0).accessibilityText('关闭变更文件')
          .onClick(() => { this.filesPickerOpen = false; })
      }.width('100%')
      Scroll() {
        Column() {
          ForEach(this.fileGroups, (group: NativePullRequestFileGroup) => {
            this.FileDirectory(group)
          }, (group: NativePullRequestFileGroup, index: number) => `${group.directory}:${index}:${group.files.length}`)
          this.ChangesFooter(true)
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)
    }.id('workspace-pr-file-picker-sheet').width('100%').height('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 16 })
  }

  @Builder
  private InlineLinePicker() {
    Column({ space: 12 }) {
      Row() {
        Text('选择评论行').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button('关闭', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(44).onClick(() => { this.linePickerOpen = false; })
      }.width('100%')
      List() {
        ForEach(this.diffLines.slice(0, this.visibleDiffLines), (line: NativePullRequestDiffLine) => {
          ListItem() {
            Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
              Row({ space: 8 }) {
                Text(`${line.line}`).width(48).fontSize(13).fontColor($r('sys.color.font_secondary'))
                Text(line.code).fontFamily('monospace').fontSize(13).layoutWeight(1)
              }.width('100%')
            }.width('100%').constraintSize({ minHeight: 44 }).padding(0)
              .id(`workspace-pr-line-${line.side}-${line.line}`)
              .onClick(() => this.openInlineComment(line))
          }
        }, (line: NativePullRequestDiffLine) => `${line.side}:${line.line}`)
        if (this.diffLines.length > this.visibleDiffLines) {
          ListItem() {
            Button('加载更多行', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
              .height(44).onClick(() => { this.visibleDiffLines += 100; })
          }
        }
        if (this.diffLines.length === 0) {
          ListItem() {
            PullRequestFeedback({ text: '此补丁没有可评论的代码行。' })
          }
        }
      }.width('100%').layoutWeight(1)
    }.id('workspace-pr-line-picker').width('100%').height('100%').padding(20)
  }

  @Builder
  private DetailContent() {
    Column() {
      this.Header()
      if (this.pane === 'changes') {
        Stack() {
          this.ChangesList()
          if (this.file) {
            ForEach([this.file], (file: NativePullRequestFile) => this.FileDiff(file),
              (file: NativePullRequestFile) => `${file.path}:${file.withheld}`)
          }
        }.width('100%').layoutWeight(1)
      } else {
        Scroll(this.detailScroller) {
          Column({ space: 14 }) {
            if (this.row && (this.pane !== 'guide' || this.guidePosition < 0)) {
              this.Identity(this.detail ?? this.row)
              if (this.pane === 'overview') this.Overview()
              else if (this.pane === 'activity') this.Activity()
            }
            if (this.pane === 'guide') {
              WorkspacePullRequestGuide({
                result: this.guideResult, stopIndex: this.guidePosition,
                loading: this.loadingGuide, error: this.guideError,
                canGenerate: this.guideCanGenerate, starting: this.guideStarting, startError: this.guideStartError,
                files: this.files, diffLoading: this.loadingDiff, diffError: this.diffError,
                jumpLoading: this.guideJumpLoading, jumpError: this.guideJumpError,
                onSelect: (position: number) => this.selectGuideStop(position),
                onRetry: () => { void this.loadGuide(); },
                onStart: () => { void this.startGuide(); },
                onOpenFile: (target: NativePullRequestGuideTarget) => { void this.openGuideFile(target); },
                onFinishReview: this.canReview() && this.guideResult && !pullRequestGuideIsStale(this.guideResult) &&
                  this.guideResult.guide?.headSha === this.detail?.headSha
                  ? () => this.openReview('review') : undefined,
              })
            }
          }
          .width('100%')
          .constraintSize({ maxWidth: 560 })
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 20, right: 20, top: 12, bottom: 20 })
        }.layoutWeight(1).width('100%').align(Alignment.Top).scrollBar(BarState.Off)
      }
      if (this.pane !== 'changes' && (this.pane !== 'guide' || this.guidePosition < 0) &&
        this.onLoadDiff !== undefined && this.detail?.diffAvailable !== false) {
        Row() {
          Button('查看变更', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
            .id('workspace-pr-changes').height(44).layoutWeight(1)
            .onClick(() => this.selectPane('changes'))
        }.width('100%').padding({ left: 20, right: 20, top: 4, bottom: 8 })
          .backgroundColor($r('sys.color.comp_background_primary'))
      }
    }.width('100%').height('100%').backgroundColor($r('sys.color.comp_background_primary'))
      .bindSheet(this.filesPickerOpen, this.FilesPicker(), {
        height: SheetSize.LARGE, showClose: false,
        onDisappear: () => { this.filesPickerOpen = false; },
      })
  }

  build() {
    Stack() {
      Column() { this.DetailContent() }
        .width('100%').height('100%')
        .bindSheet(this.linePickerOpen, this.InlineLinePicker(), {
          height: SheetSize.LARGE, showClose: false,
          onDisappear: () => { this.linePickerOpen = false; },
        })
        .visibility(this.editField || this.reviewMode || this.metadataMode ? Visibility.Hidden : Visibility.Visible)
      if (this.editField) {
        WorkspacePullRequestEdit({ field: this.editField, original: this.editOriginal,
          subtitle: `#${this.row?.number ?? ''} · ${this.row?.repository ?? ''}`,
          completionSupport: this.detail?.completion,
          onReadCompletions: (trigger: NativePullRequestComposerTrigger) => this.loadCompletions(trigger),
          onBack: () => this.closeEdit() })
      } else if (this.reviewMode && this.row) {
        WorkspacePullRequestReview({ mode: this.reviewMode,
          draftKey: this.reviewDraftKey(),
          subtitle: `#${this.row.number} · ${this.row.repository}`,
          headSha: this.detail?.headSha ?? '',
          verdicts: this.canWrite ? this.detail?.actions.verdicts ?? [] : [],
          canComment: this.canAddComment(), canInlineComment: this.canWrite && this.detail?.actions.inlineComment === true,
          requiresChangeSummary: this.detail?.actions.requiresChangeSummary === true,
          completionSupport: this.detail?.completion,
          onReadCompletions: (trigger: NativePullRequestComposerTrigger) => this.loadCompletions(trigger),
          inline: this.inlineTarget, backRequest: this.reviewBackRequest, onBack: () => this.closeReview(),
          onRelocate: (draft: NativePullRequestLineDraft) => this.relocateInlineDraft(draft) })
      } else if (this.metadataMode && this.row) {
        WorkspacePullRequestMetadata({
          mode: this.metadataMode,
          subtitle: `#${this.row.number} · ${this.row.repository}`,
          listAvailable: this.metadataMode === 'labels' || this.detail?.actions.listReviewers === true,
          searchOnHost: this.metadataMode === 'reviewers' && this.detail?.actions.searchReviewers === true,
          onRead: (query?: string) => this.loadMetadata(query),
          onBack: () => { this.metadataMode = undefined; },
        })
      }
    }.width('100%').height('100%')
  }
}
