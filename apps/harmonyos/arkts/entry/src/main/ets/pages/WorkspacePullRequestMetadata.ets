import type {
  NativePullRequestMetadataCandidate, NativePullRequestMetadataKind, NativePullRequestMetadataPage,
} from '../client/PullRequestMetadataProtocol';

@Component
export struct WorkspacePullRequestMetadata {
  @Prop @Watch('resetCandidates') mode: NativePullRequestMetadataKind = 'labels';
  @Prop subtitle: string = '';
  @Prop @Watch('resetCandidates') listAvailable: boolean = true;
  @Prop @Watch('scheduleHostSearch') searchOnHost: boolean = false;
  onRead?: (query?: string) => Promise<NativePullRequestMetadataPage>;
  onBack: () => void = () => {};

  @State private query: string = '';
  @State private loaded?: NativePullRequestMetadataPage = undefined;
  @State private searched?: NativePullRequestMetadataPage = undefined;
  @State private changedKeys: string[] = [];
  @State private loading: boolean = true;
  @State private searching: boolean = false;
  @State private loadError: string = '';
  @State private searchError: string = '';
  private loadRequest: number = 0;
  private searchRequest: number = 0;
  private queryTimer: number = -1;
  private searchController: TextInputController = new TextInputController();

  aboutToAppear(): void {
    void this.load();
  }

  aboutToDisappear(): void {
    this.loadRequest++;
    this.searchRequest++;
    clearTimeout(this.queryTimer);
  }

  private resetCandidates(): void {
    this.query = '';
    this.changedKeys = [];
    void this.load();
  }

  private async load(): Promise<void> {
    const request = ++this.loadRequest;
    this.loaded = undefined;
    this.loadError = '';
    this.scheduleHostSearch();
    this.loading = this.listAvailable;
    if (!this.listAvailable) return;
    if (!this.onRead) {
      this.loadError = '当前环境无法读取候选。';
      this.loading = false;
      return;
    }
    try {
      const result = await this.onRead();
      if (request !== this.loadRequest) return;
      this.loaded = result;
      this.scheduleHostSearch();
    } catch (error) {
      if (request === this.loadRequest) this.loadError = (error as Error).message || '无法读取候选。';
    } finally {
      if (request === this.loadRequest) this.loading = false;
    }
  }

  private scheduleHostSearch(): void {
    const request = ++this.searchRequest;
    const query = this.query.trim();
    clearTimeout(this.queryTimer);
    this.searched = undefined;
    this.searchError = '';
    this.searching = this.mode === 'reviewers' && this.searchOnHost && this.loaded?.truncated === true &&
      query.length > 0 && this.onRead !== undefined;
    if (this.searching) {
      this.queryTimer = setTimeout(() => { void this.search(request, query); }, 250);
    }
  }

  private async search(request: number, query: string): Promise<void> {
    if (request !== this.searchRequest || !this.onRead) return;
    try {
      const result = await this.onRead(query);
      if (request === this.searchRequest) this.searched = result;
    } catch (error) {
      if (request === this.searchRequest) this.searchError = (error as Error).message || '无法搜索评审人。';
    } finally {
      if (request === this.searchRequest) this.searching = false;
    }
  }

  private visibleRows(): NativePullRequestMetadataCandidate[] {
    const query = this.query.trim().toLowerCase();
    const loaded = this.loaded?.candidates ?? [];
    const searched = this.searched?.candidates ?? [];
    const fetched = new Set<string>(searched.map((row: NativePullRequestMetadataCandidate) => row.key));
    const rows = loaded.filter((row: NativePullRequestMetadataCandidate) =>
      fetched.has(row.key) || row.title.toLowerCase().includes(query) || row.subtitle.toLowerCase().includes(query));
    if (this.mode === 'reviewers') {
      const known = new Set<string>(loaded.map((row: NativePullRequestMetadataCandidate) => row.key));
      rows.push(...searched.filter((row: NativePullRequestMetadataCandidate) => !known.has(row.key)));
      rows.sort((left: NativePullRequestMetadataCandidate, right: NativePullRequestMetadataCandidate) =>
        Number(right.selected) - Number(left.selected) ||
        (left.subtitle || left.title).localeCompare(right.subtitle || right.title));
    }
    return rows;
  }

  private isSelected(row: NativePullRequestMetadataCandidate): boolean {
    return row.selected !== this.changedKeys.includes(row.key);
  }

  private toggle(row: NativePullRequestMetadataCandidate): void {
    this.changedKeys = this.changedKeys.includes(row.key)
      ? this.changedKeys.filter((key: string) => key !== row.key)
      : [...this.changedKeys, row.key];
  }

  private emptyMessage(): string {
    if (this.mode === 'labels') return this.query.trim() ? '没有匹配的标签。' : '此仓库没有标签。';
    return this.query.trim() ? '没有匹配的评审人。' : '没有可选评审人。';
  }

  private truncationMessage(): string {
    if (this.mode === 'labels') return this.loaded?.truncated ? '此仓库还有未列出的标签。' : '';
    if (!this.loaded?.truncated) return '';
    if (!this.searchOnHost) return '提供商仅返回部分评审人。';
    if (!this.query.trim()) return '请输入姓名或账号，搜索其余评审人。';
    return this.searched?.truncated ? '结果过多，请缩小搜索范围。' : '';
  }

  private candidateSubtitle(row: NativePullRequestMetadataCandidate): string {
    if (row.kind !== 'team') return row.subtitle;
    return row.subtitle ? `${row.subtitle} · 团队` : '团队';
  }

  @Builder
  private Candidate(row: NativePullRequestMetadataCandidate) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 12 }) {
        if (this.mode === 'labels') {
          Circle().width(10).height(10)
            .fill(row.color && /^#?[0-9a-f]{6}$/i.test(row.color)
              ? (row.color.startsWith('#') ? row.color : '#' + row.color) : $r('sys.color.icon_secondary'))
        } else {
          SymbolGlyph($r('sys.symbol.person_head_on_circle'))
            .fontSize(26)
            .fontColor([$r('sys.color.icon_secondary')])
        }
        Column({ space: 4 }) {
          Text(row.title).fontSize(15).fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.candidateSubtitle(row)) {
            Text(this.candidateSubtitle(row)).fontSize(13).fontColor($r('sys.color.font_secondary'))
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (this.isSelected(row)) {
          if (this.mode === 'reviewers') {
            Text(row.selected ? '已请求' : '已选择').fontSize(12).fontColor($r('sys.color.font_secondary'))
          }
          SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([$r('sys.color.icon_emphasize')])
        }
      }.width('100%')
    }
    .id(`workspace-pr-metadata-candidate-${row.key}`)
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .accessibilitySelected(this.isSelected(row))
    .onClick(() => this.toggle(row))
  }

  @Builder
  private CandidateList() {
    Scroll() {
      Column({ space: 6 }) {
        if (this.loading || this.searching) {
          LoadingProgress().id('workspace-pr-metadata-loading').width(28).height(28)
            .accessibilityText(this.loading ? '正在读取候选' : '正在搜索评审人')
        }
        if (this.loadError || this.searchError) {
          Text(this.loadError || this.searchError)
            .id('workspace-pr-metadata-error').fontSize(14).fontColor($r('sys.color.font_secondary'))
            .width('100%')
          Button('重试', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
            .id('workspace-pr-metadata-retry').height(44)
            .onClick(() => {
              if (this.loadError) void this.load();
              else this.scheduleHostSearch();
            })
        } else if (!this.loading && !this.searching && this.visibleRows().length === 0) {
          Text(this.emptyMessage()).id('workspace-pr-metadata-empty').fontSize(14)
            .fontColor($r('sys.color.font_secondary')).width('100%').padding({ top: 12, bottom: 12 })
        }
        ForEach(this.visibleRows(),
          (row: NativePullRequestMetadataCandidate) => this.Candidate(row),
          (row: NativePullRequestMetadataCandidate) =>
            JSON.stringify([row.key, row.title, row.subtitle, row.selected, row.color, row.kind]))
        if (this.truncationMessage()) {
          Text(this.truncationMessage()).id('workspace-pr-metadata-truncated')
            .fontSize(13).fontColor($r('sys.color.font_secondary')).width('100%')
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 12, bottom: 20 })
    }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(20).fontColor([$r('sys.color.icon_primary')])
        }.id('workspace-pr-metadata-back').width(48).height(48).padding(0)
          .accessibilityText(this.mode === 'labels' ? '关闭标签' : '关闭评审人')
          .onClick(() => {
            this.searchController.stopEditing();
            this.onBack();
          })
        if (this.listAvailable) {
          TextInput({
            text: this.query, placeholder: this.mode === 'labels' ? '搜索标签' : '搜索评审人',
            controller: this.searchController,
          })
            .id('workspace-pr-metadata-query').layoutWeight(1).height(44).fontSize(16)
            .maxLength(100).enterKeyType(EnterKeyType.Search).cancelButton({ style: CancelButtonStyle.INPUT })
            .accessibilityText(this.mode === 'labels' ? '搜索标签' : '搜索评审人')
            .onChange((query: string) => {
              this.query = query;
              this.scheduleHostSearch();
            })
            .onSubmit(() => this.searchController.stopEditing())
        } else {
          Column({ space: 3 }) {
            Text('请求评审').fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
            Text(this.subtitle).fontSize(13).fontColor($r('sys.color.font_secondary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }
      }.width('100%').height(60).padding({ left: 8, right: 16 })
      if (this.listAvailable) {
        this.CandidateList()
      } else {
        Scroll() {
          Column({ space: 12 }) {
            Text('此提供商接受评审人账号或 ID，无法列出候选。')
              .fontSize(14).fontColor($r('sys.color.font_secondary')).width('100%')
            TextInput({ text: this.query, placeholder: '评审人账号或 ID' })
              .id('workspace-pr-metadata-reviewer-id').width('100%').height(48)
              .accessibilityText('评审人 ID').onChange((query: string) => { this.query = query; })
            Button('请求评审', { type: ButtonType.Capsule }).width('100%').height(44).enabled(false)
            Button('移除评审请求', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
              .width('100%').height(44).enabled(false)
          }.width('100%').padding(16)
        }.width('100%').layoutWeight(1).align(Alignment.Top)
      }
      Text('选择可在本页预览，服务端保存待接入。')
        .id('workspace-pr-metadata-status').fontSize(13).fontColor($r('sys.color.font_secondary'))
        .width('100%').padding({ left: 16, right: 16, top: 8, bottom: 12 })
    }.id('workspace-pr-metadata').width('100%').height('100%').backgroundColor($r('sys.color.comp_background_primary'))
  }
}
