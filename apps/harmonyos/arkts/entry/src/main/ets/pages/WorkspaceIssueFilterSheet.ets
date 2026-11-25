import type {
  NativeIssueAssigneeFilter, NativeIssueCandidates, NativeIssueFacet, NativeIssueScope,
} from '../client/IssueProtocol';
import { ISSUE_FILTER_LABEL_LIMIT } from '../client/IssueProtocol';

interface IssueCandidateRow {
  key: string;
  detail: string;
  color?: string;
}

interface IssueCandidateRead {
  candidates?: NativeIssueCandidates;
  error?: string;
}

@Component
export struct WorkspaceIssueFilterSheet {
  @Prop environmentKey: string = '';
  @Prop facet: NativeIssueFacet = 'labels';
  @Prop scopes: NativeIssueScope[] = [];
  @Prop labels: string[] = [];
  @Prop assignee: NativeIssueAssigneeFilter | null = null;
  onRead?: (key: string, scope: NativeIssueScope) => Promise<NativeIssueCandidates>;
  onLabel: (label: string) => void = () => {};
  onAssignee: (assignee: NativeIssueAssigneeFilter | null) => void = () => {};
  onClose: () => void = () => {};

  @State private query: string = '';
  @State private rows: IssueCandidateRow[] = [];
  @State private loading: boolean = true;
  @State private errors: string[] = [];
  @State private truncated: boolean = false;
  private request: number = 0;

  aboutToAppear(): void {
    void this.load();
  }

  aboutToDisappear(): void {
    ++this.request;
  }

  private async readScope(key: string, scope: NativeIssueScope): Promise<IssueCandidateRead> {
    try {
      if (!this.onRead) return { error: '当前环境无法读取筛选候选。' };
      return { candidates: await this.onRead(key, scope) };
    } catch (error) {
      return { error: `${scope.scope} · ${(error as Error).message || '无法读取候选。'}` };
    }
  }

  private async load(): Promise<void> {
    const request = ++this.request;
    const key = this.environmentKey;
    const scopes = this.scopes;
    const scopeBatchSize = 4;
    this.loading = scopes.length > 0;
    this.rows = [];
    this.errors = [];
    this.truncated = false;
    const rows = new Map<string, IssueCandidateRow>();
    for (let start = 0; start < scopes.length; start += scopeBatchSize) {
      if (request !== this.request || key !== this.environmentKey) return;
      const results = await Promise.all(scopes.slice(start, start + scopeBatchSize)
        .map((scope: NativeIssueScope) => this.readScope(key, scope)));
      if (request !== this.request || key !== this.environmentKey) return;
      results.forEach((result: IssueCandidateRead) => {
        if (result.candidates) {
          this.collectRows(rows, result.candidates);
          this.truncated = this.truncated || result.candidates.truncated;
        } else if (result.error) {
          this.errors = [...this.errors, result.error];
        }
      });
      this.rows = Array.from(rows.values()).sort((left, right) => left.key.localeCompare(right.key));
    }
    if (request === this.request) this.loading = false;
  }

  private collectRows(rows: Map<string, IssueCandidateRow>, candidates: NativeIssueCandidates): void {
    if (this.facet === 'labels') {
      candidates.labels.forEach((label) => {
        if (label.name.length > 200 || rows.has(label.name)) return;
        rows.set(label.name, { key: label.name, detail: label.description ?? '', color: label.color ?? undefined });
      });
    } else {
      candidates.assignees.forEach((actor) => {
        if (actor.login.length > 320 || rows.has(actor.login)) return;
        rows.set(actor.login, { key: actor.login, detail: actor.name ?? '' });
      });
    }
  }

  private visibleRows(): IssueCandidateRow[] {
    const unoffered: IssueCandidateRow[] = [];
    if (this.facet === 'labels') {
      this.labels.forEach((label: string) => {
        if (!this.rows.some((candidate) => candidate.key === label)) unoffered.push({ key: label, detail: '' });
      });
    } else {
      const assignee = this.assignee;
      if (assignee && !this.rows.some((candidate) => candidate.key === assignee.login)) {
        unoffered.push({ key: assignee.login, detail: assignee.name ?? '' });
      }
    }
    const needle = this.query.trim().toLowerCase();
    return [...unoffered, ...this.rows].filter((row) =>
      row.key.toLowerCase().includes(needle) || row.detail.toLowerCase().includes(needle));
  }

  private selected(row: IssueCandidateRow): boolean {
    return this.facet === 'labels' ? this.labels.includes(row.key) : this.assignee?.login === row.key;
  }

  private toggle(row: IssueCandidateRow): void {
    if (this.facet === 'labels') {
      this.onLabel(row.key);
    } else {
      const assignee: NativeIssueAssigneeFilter = { login: row.key, name: row.detail || null };
      this.onAssignee(this.selected(row) ? null : assignee);
      this.onClose();
    }
  }

  @Builder
  private Candidate(row: IssueCandidateRow) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 10 }) {
        if (this.facet === 'labels') {
          Circle()
            .width(10)
            .height(10)
            .fill(row.color && /^#?[0-9a-f]{6}$/i.test(row.color) ?
              (row.color.startsWith('#') ? row.color : '#' + row.color) : $r('sys.color.icon_secondary'))
        } else {
          SymbolGlyph($r('sys.symbol.person_head_on_circle'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
        }
        Column({ space: 3 }) {
          Text(row.key)
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (row.detail) {
            Text(row.detail)
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        if (this.selected(row)) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_emphasize')])
        }
      }.width('100%')
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
    .padding({ left: 8, right: 8, top: 8, bottom: 8 })
    .enabled(this.facet !== 'labels' || this.selected(row) || this.labels.length < ISSUE_FILTER_LABEL_LIMIT)
    .accessibilitySelected(this.selected(row))
    .onClick(() => this.toggle(row))
  }

  @Builder
  private Feedback(message: string) {
    Text(message)
      .width('100%')
      .fontSize(13)
      .fontColor($r('sys.color.font_secondary'))
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(22)
            .fontColor([$r('sys.color.icon_primary')])
        }
        .id('workspace-issue-filter-back')
        .width(44)
        .height(44)
        .padding(0)
        .accessibilityText('返回')
        .onClick(() => this.onClose())
        Text(this.facet === 'labels' ? '按标签筛选' : '按经办人筛选')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
      }.width('100%')
      TextInput({ text: this.query, placeholder: this.facet === 'labels' ? '搜索标签' : '搜索人员' })
        .id('workspace-issue-filter-query')
        .height(44)
        .width('100%')
        .enterKeyType(EnterKeyType.Search)
        .onChange((value: string) => { this.query = value; })
      Scroll() {
        Column({ space: 6 }) {
          if (this.scopes.length === 0) {
            this.Feedback('当前环境未提供此筛选的候选范围。')
          }
          if (this.loading) {
            LoadingProgress().width(28).height(28).accessibilityText('正在加载筛选候选')
          }
          if (this.errors.length > 0) {
            Text(this.errors.join('\n'))
              .id('workspace-issue-filter-error')
              .width('100%')
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
            Button('重试', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
              .height(44)
              .enabled(!this.loading)
              .onClick(() => { void this.load(); })
          }
          if (!this.loading && this.visibleRows().length === 0 && this.errors.length === 0 &&
            (this.scopes.length > 0 || this.query.trim())) {
            Text(this.query.trim() ? '没有匹配的候选。' : this.facet === 'labels' ? '此范围没有标签。' : '此范围没有可指派的人员。')
              .id('workspace-issue-filter-empty')
              .width('100%')
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
          }
          if (this.facet === 'labels' && this.labels.length >= ISSUE_FILTER_LABEL_LIMIT) {
            this.Feedback(`最多可以选择 ${ISSUE_FILTER_LABEL_LIMIT} 个标签。`)
          }
          ForEach(this.visibleRows(), (row: IssueCandidateRow) => this.Candidate(row),
            (row: IssueCandidateRow) => JSON.stringify([row.key, row.detail, row.color]))
          if (this.truncated) {
            this.Feedback('跟踪器还有未列出的候选。')
          }
        }.width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 12 })
  }
}
