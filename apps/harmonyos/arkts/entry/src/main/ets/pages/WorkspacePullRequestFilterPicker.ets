import type {
  NativePullRequestFilterCandidate, NativePullRequestFilterCandidatePage, NativePullRequestFilterMode,
} from '../client/PullRequestFilterOptionsProtocol';

@Component
export struct WorkspacePullRequestFilterPicker {
  @Prop @Watch('resetCandidates') mode: NativePullRequestFilterMode = 'projects';
  @Prop selected: string[] = [];
  onRead?: (query?: string) => Promise<NativePullRequestFilterCandidatePage>;
  onToggle: (key: string) => void = () => {};
  onClear: () => void = () => {};
  onClose: () => void = () => {};

  @State private query: string = '';
  @State private initial?: NativePullRequestFilterCandidatePage = undefined;
  @State private searched?: NativePullRequestFilterCandidatePage = undefined;
  @State private loading: boolean = false;
  @State private error: string = '';
  private request: number = 0;
  private queryTimer: number = -1;
  private searchController: TextInputController = new TextInputController();

  aboutToAppear(): void {
    void this.load('', ++this.request);
  }

  aboutToDisappear(): void {
    this.request++;
    clearTimeout(this.queryTimer);
  }

  private resetCandidates(): void {
    clearTimeout(this.queryTimer);
    this.query = '';
    this.initial = undefined;
    this.searched = undefined;
    void this.load('', ++this.request);
  }

  private async load(query: string, request: number): Promise<void> {
    if (request !== this.request) return;
    this.loading = true;
    this.error = '';
    try {
      if (!this.onRead) throw new Error('当前环境无法读取筛选候选。');
      const page = await this.onRead(query || undefined);
      if (request !== this.request) return;
      if (query) this.searched = page;
      else this.initial = page;
    } catch (error) {
      if (request === this.request) this.error = (error as Error).message || '无法读取筛选候选。';
    } finally {
      if (request === this.request) this.loading = false;
    }
  }

  private setQuery(value: string): void {
    this.query = value;
    if (this.mode === 'projects') return;
    clearTimeout(this.queryTimer);
    const request = ++this.request;
    const query = value.trim();
    this.searched = undefined;
    this.error = '';
    this.loading = !!query || !this.initial;
    if (this.loading) {
      this.queryTimer = setTimeout(() => { void this.load(query, request); }, 250);
    }
  }

  private normalizeKey(value: string): string {
    return this.mode === 'projects' ? value : value.toLowerCase();
  }

  private isSelected(key: string): boolean {
    const normalized = this.normalizeKey(key);
    return this.selected.some((value: string) => this.normalizeKey(value) === normalized);
  }

  private modeLabel(): string {
    if (this.mode === 'projects') return '项目';
    if (this.mode === 'authors') return '作者';
    if (this.mode === 'excluded-labels') return '排除标签';
    return '标签';
  }

  private isLabel(): boolean {
    return this.mode === 'labels' || this.mode === 'excluded-labels';
  }

  private rows(): NativePullRequestFilterCandidate[] {
    const needle = this.query.trim().toLowerCase();
    const known = new Map<string, NativePullRequestFilterCandidate>();
    const hosted = new Set<string>();
    for (const candidate of this.initial?.candidates ?? []) known.set(this.normalizeKey(candidate.key), candidate);
    for (const candidate of this.searched?.candidates ?? []) {
      const key = this.normalizeKey(candidate.key);
      known.set(key, candidate);
      hosted.add(key);
    }
    if (this.mode === 'authors') {
      const viewer: NativePullRequestFilterCandidate = { key: 'me', title: '我创建的' };
      known.set(viewer.key, viewer);
    }
    for (const value of this.selected) {
      const key = this.normalizeKey(value);
      if (!known.has(key)) known.set(key, { key: value, title: value });
    }
    return Array.from(known.values())
      .filter((candidate: NativePullRequestFilterCandidate) => this.isSelected(candidate.key) ||
        hosted.has(this.normalizeKey(candidate.key)) || candidate.key.toLowerCase().includes(needle) ||
        candidate.title.toLowerCase().includes(needle))
      .sort((left: NativePullRequestFilterCandidate, right: NativePullRequestFilterCandidate) =>
        Number(this.isSelected(right.key)) - Number(this.isSelected(left.key)) ||
        left.title.localeCompare(right.title));
  }

  @Builder
  private Candidate(row: NativePullRequestFilterCandidate) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 12 }) {
        if (this.isLabel()) {
          Circle().width(10).height(10)
            .fill(row.color && /^#?[0-9a-f]{6}$/i.test(row.color)
              ? (row.color.startsWith('#') ? row.color : '#' + row.color) : $r('sys.color.icon_secondary'))
        }
        Text(row.title).fontSize(15).fontColor($r('sys.color.font_primary')).layoutWeight(1)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.isSelected(row.key)) {
          SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([$r('sys.color.icon_emphasize')])
        }
      }.width('100%')
    }.id(`workspace-pr-filter-picker-option-${row.key}`).width('100%')
      .constraintSize({ minHeight: 48 }).padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .accessibilitySelected(this.isSelected(row.key))
      .enabled(!this.isLabel() || this.isSelected(row.key) || this.selected.length < 10)
      .onClick(() => {
        if (!this.isLabel()) this.searchController.stopEditing();
        this.onToggle(row.key);
      })
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(`按${this.modeLabel()}筛选`).fontSize(20).fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary')).layoutWeight(1)
        Button('完成', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
          .id('workspace-pr-filter-picker-close').height(44).onClick(() => {
            this.searchController.stopEditing();
            this.onClose();
          })
      }.width('100%')
      TextInput({ text: this.query, placeholder: `搜索${this.modeLabel()}`, controller: this.searchController })
        .id('workspace-pr-filter-picker-query').width('100%').height(44).fontSize(16)
        .maxLength(100).enterKeyType(EnterKeyType.Search).cancelButton({ style: CancelButtonStyle.INPUT })
        .accessibilityText(`搜索${this.modeLabel()}`)
        .onChange((query: string) => this.setQuery(query))
        .onSubmit(() => this.searchController.stopEditing())
      if (this.selected.length > 0) {
        Button('清除所选', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
          .id('workspace-pr-filter-picker-clear').height(44).alignSelf(ItemAlign.Start)
          .onClick(() => this.onClear())
      }
      Scroll() {
        Column({ space: 4 }) {
          if (this.loading) {
            LoadingProgress().id('workspace-pr-filter-picker-loading').width(28).height(28)
              .accessibilityText('正在读取候选')
          }
          if (this.error) {
            Text(this.error).id('workspace-pr-filter-picker-error').fontSize(14)
              .fontColor($r('sys.color.font_secondary')).width('100%')
            Button('重试', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
              .id('workspace-pr-filter-picker-retry').height(44)
              .onClick(() => { void this.load(this.mode === 'projects' ? '' : this.query.trim(), ++this.request); })
          } else if (!this.loading && this.rows().length === 0) {
            Text(this.query.trim() ? '没有匹配的候选。' : `没有可选${this.modeLabel()}。`)
              .id('workspace-pr-filter-picker-empty').fontSize(14)
              .fontColor($r('sys.color.font_secondary')).width('100%').padding({ top: 12, bottom: 12 })
          }
          ForEach(this.rows(), (row: NativePullRequestFilterCandidate) => this.Candidate(row),
            (row: NativePullRequestFilterCandidate) => JSON.stringify([row.key, row.title, row.color]))
          if ((this.searched ?? this.initial)?.truncated) {
            Text('候选仅显示部分结果，请缩小搜索范围。').id('workspace-pr-filter-picker-truncated')
              .fontSize(13).fontColor($r('sys.color.font_secondary')).width('100%').padding(8)
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)
    }.id('workspace-pr-filter-picker').width('100%').height('100%').padding(20)
      .backgroundColor($r('sys.color.comp_background_primary'))
  }
}
