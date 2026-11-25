import { linkedEnvironmentHealth } from '../client/LinkedEnvironmentProtocol';
import type { LinkedEnvironmentBatchResult, LinkedEnvironmentCandidate, LinkedEnvironmentHealth, NativeLinkedEnvironment,
  NativePeerLinkAccess } from '../client/LinkedEnvironmentProtocol';

interface LinkedEnvironmentAccessOption {
  access: NativePeerLinkAccess;
  label: string;
  description: string;
}

const LINK_ACCESS_OPTIONS: LinkedEnvironmentAccessOption[] = [
  { access: 'read-only', label: '只读', description: '可以读取项目和会话。' },
  { access: 'approval-required', label: '需审批', description: '运行命令和修改文件前需审批。' },
  { access: 'auto-accept-edits', label: '自动接受编辑', description: '自动接受文件编辑，其他操作需审批。' },
  { access: 'auto', label: '自动', description: '支持自动模式的提供方会自动批准常规操作。' },
  { access: 'full-access', label: '完全访问', description: '运行命令和修改文件无需审批。' },
];

@Component
export struct LinkedEnvironmentsView {
  @Prop environmentLabel: string = '';
  @Prop @Watch('syncClock') links: NativeLinkedEnvironment[] = [];
  @Prop canUnlink: boolean = false;
  @Prop candidates: LinkedEnvironmentCandidate[] = [];
  @Prop busy: boolean = false;
  @Prop batchOnly: boolean = false;
  @Prop batchAvailable: boolean | undefined = undefined;
  @Prop batchLoading: boolean = false;
  @Prop batchLoadError: string = '';
  @Prop @Watch('syncBatchResults') linkBatchResults: LinkedEnvironmentBatchResult[] = [];
  onLink: (candidate: LinkedEnvironmentCandidate, access: NativePeerLinkAccess) => void = () => {};
  onLinkBatch: (keys: string[], access: NativePeerLinkAccess) => void = () => {};
  onRefreshBatch: () => void = () => {};
  onUnlink: (link: NativeLinkedEnvironment) => void = () => {};
  @StorageLink('t3.arkts.foreground') @Watch('syncClock') private appInForeground: boolean = false;
  @State private nowMs: number = Date.now();
  @State private selecting: boolean = false;
  @State private candidateKey: string = '';
  @State private accessIndex: number = 1;
  @State private showBatch: boolean = false;
  @State private batchCandidates: LinkedEnvironmentCandidate[] = [];
  @State private batchHistory: LinkedEnvironmentBatchResult[] = [];
  @State private selectedBatchKeys: string[] = [];
  @State private batchAccessIndex: number = 1;
  private clock: number = -1;
  private visible: boolean = false;
  private confirming: boolean = false;
  private submittedBatchKeys: string[] = [];

  aboutToAppear(): void {
    this.visible = true;
    this.syncClock();
  }

  aboutToDisappear(): void {
    this.visible = false;
    this.stopClock();
  }

  private syncClock(): void {
    if (!this.appInForeground || this.links.length === 0) {
      this.stopClock();
      return;
    }
    this.nowMs = Date.now();
    if (this.clock !== -1) return;
    this.clock = setInterval(() => { this.nowMs = Date.now(); }, 60_000);
  }

  private stopClock(): void {
    clearInterval(this.clock);
    this.clock = -1;
  }

  private statusText(health: LinkedEnvironmentHealth): string {
    switch (health.kind) {
      case 'expired':
        return '已过期。请使用新的配对码重新关联。';
      case 'unreachable':
        return health.detail ?? '暂时没有响应。';
      case 'failing':
        return health.detail ?? '连接出现问题。';
      case 'reachable':
        return health.expiresInDays === undefined ? '可访问' : `${health.expiresInDays} 天后过期`;
    }
  }

  private statusColor(health: LinkedEnvironmentHealth): ResourceColor {
    return health.kind === 'reachable' && health.expiresInDays === undefined
      ? $r('sys.color.font_secondary') : '#c8353c';
  }

  private candidateIndex(): number {
    return this.candidates.findIndex((candidate) => candidate.key === this.candidateKey);
  }

  private submitLink(): void {
    const candidate = this.candidates[this.candidateIndex()];
    if (!this.busy && candidate !== undefined) this.onLink(candidate, LINK_ACCESS_OPTIONS[this.accessIndex].access);
  }

  private openBatch(): void {
    this.batchCandidates = this.candidates.slice();
    this.batchHistory = [];
    this.selectedBatchKeys = [];
    this.submittedBatchKeys = [];
    this.batchAccessIndex = 1;
    this.showBatch = true;
  }

  private syncBatchResults(): void {
    if (!this.showBatch || this.submittedBatchKeys.length === 0) return;
    const submitted = this.linkBatchResults.filter((result) => this.submittedBatchKeys.includes(result.key));
    const current = new Map<string, LinkedEnvironmentBatchResult>();
    for (const result of this.batchHistory) current.set(result.key, result);
    for (const result of submitted) current.set(result.key, result);
    this.batchHistory = Array.from(current.values());
    if (submitted.length === this.submittedBatchKeys.length &&
      submitted.every((result) => result.status === 'failed' || result.status === 'linked')) {
      this.selectedBatchKeys = submitted.filter((result) => result.status === 'failed').map((result) => result.key);
      this.submittedBatchKeys = [];
    }
  }

  private canSelectBatchCandidate(key: string): boolean {
    return this.candidates.some((candidate) => candidate.key === key) &&
      !this.batchHistory.some((result) => result.key === key && result.status === 'linked');
  }

  private batchSelection(): string[] {
    return this.selectedBatchKeys.filter((key) => this.canSelectBatchCandidate(key));
  }

  private allBatchSelected(): boolean {
    const selectable = this.batchCandidates.filter((candidate) => this.canSelectBatchCandidate(candidate.key)).length;
    return selectable > 0 && this.batchSelection().length === selectable;
  }

  private toggleAllBatchCandidates(): void {
    this.selectedBatchKeys = this.allBatchSelected() ? [] : this.batchCandidates
      .filter((candidate) => this.canSelectBatchCandidate(candidate.key)).map((candidate) => candidate.key);
  }

  private toggleBatchCandidate(key: string, checked: boolean): void {
    if (this.busy || !this.canSelectBatchCandidate(key)) return;
    if (checked && !this.selectedBatchKeys.includes(key)) this.selectedBatchKeys = this.selectedBatchKeys.concat([key]);
    if (!checked) this.selectedBatchKeys = this.selectedBatchKeys.filter((selected) => selected !== key);
  }

  private submitBatch(): void {
    const selection = this.batchSelection();
    if (!this.busy && selection.length > 0) {
      this.submittedBatchKeys = selection;
      this.onLinkBatch(selection, LINK_ACCESS_OPTIONS[this.batchAccessIndex].access);
    }
  }

  private batchStatus(key: string): string {
    const result = this.batchHistory.find((entry) => entry.key === key);
    switch (result?.status) {
      case 'pending': return '等待关联';
      case 'linking': return '正在关联…';
      case 'linked': return '已关联';
      case 'failed': return result.message ?? '关联失败';
      default: return this.canSelectBatchCandidate(key) ? '' : '暂不可关联';
    }
  }

  private async confirmUnlink(link: NativeLinkedEnvironment): Promise<void> {
    if (this.busy || this.confirming || !this.canUnlink) return;
    this.confirming = true;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '解除关联？',
        message: `${this.environmentLabel} 上的代理将失去对 ${link.label} 的访问。如果目标环境可访问，也会结束关联使用的会话。`,
        buttons: [
          { text: '取消', color: $r('sys.color.font_secondary') },
          { text: '解除关联', color: '#c8353c' },
        ],
      });
      if (result.index === 1 && this.visible && !this.busy && this.canUnlink &&
        this.links.some((current) => current.environmentId === link.environmentId)) this.onUnlink(link);
    } catch (_) {
    } finally {
      this.confirming = false;
    }
  }

  @Builder
  private AccessPicker(batch: boolean) {
    Column({ space: 8 }) {
      Text('代理访问权限').fontSize(14)
      Select(LINK_ACCESS_OPTIONS.map((option): SelectOption => ({ value: option.label })))
        .width('100%')
        .selected(batch ? this.batchAccessIndex : this.accessIndex)
        .value(LINK_ACCESS_OPTIONS[batch ? this.batchAccessIndex : this.accessIndex].label)
        .accessibilityText('代理访问权限')
        .enabled(!this.busy)
        .onSelect((index: number) => {
          if (!LINK_ACCESS_OPTIONS[index]) return;
          if (batch) this.batchAccessIndex = index;
          else this.accessIndex = index;
        })
      Text(LINK_ACCESS_OPTIONS[batch ? this.batchAccessIndex : this.accessIndex].description)
        .fontSize(13)
        .fontColor($r('sys.color.font_secondary'))
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private LinkPicker() {
    Column({ space: 10 }) {
      Text(`${this.environmentLabel} 上的代理可按所选权限访问目标环境。你可以在目标环境的「共享与访问」中撤销授权。`)
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
      Select(this.candidates.map((candidate): SelectOption => ({ value: candidate.label })))
        .width('100%')
        .selected(this.candidateIndex())
        .value(this.candidates[this.candidateIndex()]?.label ?? '选择目标环境')
        .accessibilityText('目标环境')
        .enabled(!this.busy)
        .onSelect((index: number) => { this.candidateKey = this.candidates[index]?.key ?? ''; })
      this.AccessPicker(false)
      Row({ space: 8 }) {
        Button('取消', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy)
          .onClick(() => { this.selecting = false; })
        Button('关联环境').enabled(!this.busy && this.candidateIndex() !== -1)
          .onClick(() => this.submitLink())
      }.width('100%').justifyContent(FlexAlign.End)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private BatchSheet() {
    Scroll() {
      Column({ space: 12 }) {
        Text('批量关联环境').fontSize(20).fontWeight(FontWeight.Medium)
        Text(`${this.environmentLabel} 上的代理可按所选权限访问这些环境。你可以在目标环境的「共享与访问」中撤销授权。`)
          .fontSize(14).fontColor($r('sys.color.font_secondary'))
        if (this.batchLoadError) {
          Text(this.batchLoadError).fontSize(14).fontColor($r('sys.color.font_secondary'))
          Button('重新读取关联环境', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .enabled(!this.busy && !this.batchLoading).onClick(this.onRefreshBatch)
        }
        if (this.batchCandidates.length === 0) {
          Text('当前没有可关联的环境。').fontSize(14).fontColor($r('sys.color.font_secondary'))
        } else {
          ForEach(this.batchCandidates, (candidate: LinkedEnvironmentCandidate) => {
            Row({ space: 12 }) {
              Checkbox({ name: candidate.key })
                .select(this.canSelectBatchCandidate(candidate.key) && this.selectedBatchKeys.includes(candidate.key))
                .enabled(!this.busy && this.canSelectBatchCandidate(candidate.key))
                .accessibilityText(candidate.label)
                .accessibilityDescription(this.batchStatus(candidate.key))
                .onChange((checked: boolean) => this.toggleBatchCandidate(candidate.key, checked))
              Column({ space: 3 }) {
                Text(candidate.label).fontSize(16).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.batchStatus(candidate.key)) {
                  Text(this.batchStatus(candidate.key))
                    .fontSize(13)
                    .fontColor(this.batchHistory.some((result) => result.key === candidate.key && result.status === 'failed')
                      ? '#c8353c' : $r('sys.color.font_secondary'))
                }
              }
              .layoutWeight(1)
              .constraintSize({ minHeight: 44 })
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Start)
              .onClick(() => this.toggleBatchCandidate(candidate.key, !this.selectedBatchKeys.includes(candidate.key)))
            }.width('100%').constraintSize({ minHeight: 44 })
          }, (candidate: LinkedEnvironmentCandidate) => candidate.key)
          Button(this.allBatchSelected() ? '取消全选' : '全选', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .enabled(!this.busy && this.batchCandidates.some((candidate) => this.canSelectBatchCandidate(candidate.key)))
            .onClick(() => this.toggleAllBatchCandidates())
        }
        this.AccessPicker(true)
        if (this.busy) {
          LoadingProgress().width(24).height(24).accessibilityText('正在批量关联环境')
        } else if (this.batchLoading) {
          LoadingProgress().width(24).height(24).accessibilityText('正在读取关联环境')
        } else if (this.batchHistory.length > 0) {
          Text(`已关联 ${this.batchHistory.filter((result) => result.status === 'linked').length} / ${this.batchHistory.length} 个环境`)
            .fontSize(14).fontColor($r('sys.color.font_secondary'))
        }
        Button(this.busy ? '正在关联…' : `关联 ${this.batchSelection().length} 个环境`)
          .width('100%').enabled(!this.busy && this.batchSelection().length > 0)
          .onClick(() => this.submitBatch())
        Button(this.batchHistory.length > 0 ? '完成' : '取消', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .width('100%').enabled(!this.busy).onClick(() => { this.showBatch = false; })
      }.width('100%').padding(20).alignItems(HorizontalAlign.Start)
    }.width('100%').align(Alignment.Top)
  }

  build() {
    Column({ space: 12 }) {
      if (this.links.length > 0 || (!this.batchOnly && this.candidates.length > 0)) {
        Text(`关联自 ${this.environmentLabel}`)
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
        ForEach(this.links, (link: NativeLinkedEnvironment) => {
          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Text(link.label)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_primary'))
              Text(this.statusText(linkedEnvironmentHealth(link, this.nowMs)))
                .fontSize(13)
                .fontColor(this.statusColor(linkedEnvironmentHealth(link, this.nowMs)))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            if (this.canUnlink && !this.batchOnly) {
              Button('解除关联', { buttonStyle: ButtonStyleMode.TEXTUAL, role: ButtonRole.ERROR })
                .accessibilityText(`解除与 ${link.label} 的关联`)
                .enabled(!this.busy)
                .onClick(() => { void this.confirmUnlink(link); })
            }
          }
          .width('100%')
        }, (link: NativeLinkedEnvironment) => JSON.stringify(link))
        if (!this.batchOnly && this.candidates.length > 0) {
          if (this.selecting) {
            this.LinkPicker()
          } else {
            Button('关联其他环境', { buttonStyle: ButtonStyleMode.TEXTUAL })
              .enabled(!this.busy)
              .onClick(() => {
                this.candidateKey = '';
                this.accessIndex = 1;
                this.selecting = true;
              })
          }
        }
      }
      if (this.batchAvailable ?? (this.candidates.length >= 2)) {
        Button(this.batchOnly ? `批量关联到 ${this.environmentLabel}` : '批量关联环境', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .id('linked-environments-batch-open')
          .enabled(!this.busy)
          .onClick(() => this.openBatch())
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .bindSheet(this.showBatch, this.BatchSheet(), {
      height: SheetSize.LARGE,
      showClose: false,
      onWillDismiss: (dismiss: DismissSheetAction) => { if (!this.busy) dismiss.dismiss(); },
      onDisappear: () => { this.showBatch = false; },
    })
  }
}
