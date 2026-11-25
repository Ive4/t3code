import {
  canPullThreadGit, canPushThreadGit, normalizeThreadGitNewRef, threadGitCommitFilePaths, threadGitRefOccupied,
} from '../client/ThreadGitProtocol';
import type {
  NativeThreadGitCommitResult, NativeThreadGitFile, NativeThreadGitPullResult, NativeThreadGitPushResult,
  NativeThreadGitRef, NativeThreadGitRefs, NativeThreadGitStatus,
} from '../client/ThreadGitProtocol';

class GitFileDataSource implements IDataSource {
  private files: NativeThreadGitFile[] = [];
  private listeners: Set<DataChangeListener> = new Set<DataChangeListener>();

  totalCount(): number {
    return this.files.length;
  }

  getData(index: number): NativeThreadGitFile {
    return this.files[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.add(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners.delete(listener);
  }

  replace(files: NativeThreadGitFile[]): void {
    this.files = files;
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded());
  }
}

@Component
export struct ThreadGitStatus {
  @Link @Watch('updatePane') pane: string;
  @Prop @Watch('updateFiles') status: NativeThreadGitStatus | undefined = undefined;
  @Prop @Watch('updateDirectory') cwd: string = '';
  @Prop loading: boolean = false;
  @Prop error: string = '';
  @Prop canWrite: boolean = false;
  @Prop canChangeBranch: boolean = false;
  onBack: () => void = () => {};
  onRefresh: () => void = () => {};
  onListRefs?: (query: string, cursor: number | null) => Promise<NativeThreadGitRefs>;
  onChangeBranch?: (refName: string, create: boolean) => Promise<void>;
  onCommit?: (message: string, filePaths?: string[]) => Promise<NativeThreadGitCommitResult>;
  onPull?: () => Promise<NativeThreadGitPullResult>;
  onPush?: (refName: string, confirmedDefaultRef: boolean) => Promise<NativeThreadGitPushResult>;
  onReview?: () => void;
  @State private refs: NativeThreadGitRef[] = [];
  @State private refsQuery: string = '';
  @State private refsLoading: boolean = false;
  @State private refsError: string = '';
  @State private refsRepo: boolean = true;
  @State private nextRefsCursor: number | null = null;
  @State private newBranch: string = '';
  @State private actionLabel: string = '';
  @State private actionError: string = '';
  @State private actionFeedback: string = '';
  @State private commitMessage: string = '';
  @State private excludedFiles: Set<string> = new Set<string>();
  @State private pushConfirmRef: string = '';
  private changes = new GitFileDataSource();
  private refsRequest: number = 0;
  private searchTimer: number = -1;
  private gitContext: number = 0;

  aboutToAppear(): void {
    this.updateFiles();
    this.updatePane();
  }

  aboutToDisappear(): void {
    this.stopRefs();
    this.gitContext++;
  }

  private updateFiles(): void {
    this.changes.replace(this.status?.files ?? []);
  }

  private updateDirectory(): void {
    this.gitContext++;
    this.pane = 'status';
    this.actionLabel = '';
    this.actionError = '';
    this.actionFeedback = '';
  }

  private updatePane(): void {
    this.stopRefs();
    this.actionError = '';
    if (this.pane === 'status') return;
    this.actionFeedback = '';
    if (this.pane === 'branches') {
      this.refsQuery = '';
      this.newBranch = '';
      this.refreshRefs();
    } else if (this.pane === 'commit') {
      this.commitMessage = '';
      this.excludedFiles = new Set<string>();
    }
  }

  private stopRefs(): void {
    clearTimeout(this.searchTimer);
    this.refsRequest++;
  }

  private refreshRefs(debounce: boolean = false): void {
    this.stopRefs();
    this.refs = [];
    this.refsRepo = true;
    this.refsError = '';
    this.nextRefsCursor = null;
    this.refsLoading = true;
    if (debounce) this.searchTimer = setTimeout(() => { void this.loadRefs(null); }, 250);
    else void this.loadRefs(null);
  }

  private async loadRefs(cursor: number | null): Promise<void> {
    const list = this.onListRefs;
    if (this.pane !== 'branches' || !list) return;
    const request = ++this.refsRequest;
    this.refsLoading = true;
    this.refsError = '';
    try {
      const page = await list(this.refsQuery, cursor);
      if (request !== this.refsRequest) return;
      if (page.nextCursor !== null && cursor !== null && page.nextCursor <= cursor) {
        throw new Error('环境未返回下一页 Git 分支。');
      }
      const refs = new Map<string, NativeThreadGitRef>();
      if (cursor !== null) this.refs.forEach((ref: NativeThreadGitRef) => refs.set(ref.name, ref));
      page.refs.forEach((ref: NativeThreadGitRef) => refs.set(ref.name, ref));
      this.refs = Array.from(refs.values());
      this.refsRepo = page.isRepo;
      this.nextRefsCursor = page.nextCursor;
    } catch (error) {
      if (request === this.refsRequest) this.refsError = (error as Error).message || '无法读取 Git 分支。';
    } finally {
      if (request === this.refsRequest) this.refsLoading = false;
    }
  }

  private back(): void {
    if (this.pane === 'status') this.onBack();
    else this.pane = 'status';
  }

  private refDescription(ref: NativeThreadGitRef): string {
    if (ref.current) return '当前分支';
    if (threadGitRefOccupied(ref, this.cwd)) return '已在其他工作树检出';
    return ref.isDefault ? '默认分支' : '本地分支';
  }

  private canSwitch(ref: NativeThreadGitRef): boolean {
    return this.canChangeBranch && !this.actionLabel && !this.refsLoading &&
      !ref.current && !threadGitRefOccupied(ref, this.cwd);
  }

  private handleBranch(refName: string, create: boolean): void {
    const change = this.onChangeBranch;
    if (!this.canChangeBranch || !change) return;
    void this.runWrite(create ? '正在创建并切换分支…' : '正在切换分支…', async () => {
      await change(refName, create);
      return `已切换到 ${refName}`;
    });
  }

  private selectedCount(): number {
    return this.status?.files.filter((file: NativeThreadGitFile) => !this.excludedFiles.has(file.path)).length ?? 0;
  }

  private toggleFile(path: string, checked: boolean): void {
    const next = new Set<string>(this.excludedFiles);
    if (checked) next.delete(path);
    else next.add(path);
    this.excludedFiles = next;
  }

  private toggleAllFiles(): void {
    const files = this.status?.files ?? [];
    this.excludedFiles = this.selectedCount() === files.length ?
      new Set<string>(files.map((file: NativeThreadGitFile) => file.path)) : new Set<string>();
  }

  private canCommit(): boolean {
    return this.canWrite && !this.actionLabel && !this.loading && !this.error &&
      this.status?.hasWorkingTreeChanges === true && this.selectedCount() > 0 && this.commitMessage.trim().length > 0;
  }

  private handleCommit(): void {
    const commit = this.onCommit;
    if (!this.canCommit() || !commit) return;
    void this.runWrite('正在提交改动…', async () => {
      const filePaths = threadGitCommitFilePaths(this.status?.files ?? [], this.excludedFiles);
      const result = await commit(this.commitMessage, filePaths);
      if (result.status === 'skipped_no_changes') return '所选文件已没有可提交的改动。';
      return `已提交 ${result.commitSha?.slice(0, 8) ?? ''}${result.subject ? ` · ${result.subject}` : ''}`;
    });
  }

  private canRunRemote(): boolean {
    return this.canWrite && !this.actionLabel && !this.loading && !this.error;
  }

  private handlePull(): void {
    const pull = this.onPull;
    if (!pull || !this.canRunRemote() || !canPullThreadGit(this.status)) return;
    void this.runWrite('正在拉取最新更改…', async () => {
      const result = await pull();
      return result.status === 'skipped_up_to_date' ? '当前分支已是最新。' : `已拉取 ${result.refName} 的最新更改`;
    });
  }

  private requestPush(): void {
    const refName = this.status?.refName;
    if (!refName || !this.canRunRemote() || !canPushThreadGit(this.status)) return;
    if (this.status?.isDefaultRef) {
      this.pushConfirmRef = refName;
      this.pane = 'push-confirm';
    } else {
      this.handlePush(refName, false);
    }
  }

  private canPush(refName: string, confirmedDefaultRef: boolean): boolean {
    return this.canRunRemote() && canPushThreadGit(this.status) && this.status?.refName === refName &&
      (!this.status?.isDefaultRef || confirmedDefaultRef);
  }

  private handlePush(refName: string, confirmedDefaultRef: boolean): void {
    const push = this.onPush;
    if (!push || !this.canPush(refName, confirmedDefaultRef) ||
      (confirmedDefaultRef && (this.pane !== 'push-confirm' || this.pushConfirmRef !== refName))) return;
    void this.runWrite('正在推送分支…', async () => {
      const result = await push(refName, confirmedDefaultRef);
      if (result.status === 'skipped_up_to_date') return '远端分支已包含本地提交。';
      if (result.setUpstream && result.upstreamBranch) return `已推送并跟踪 ${result.upstreamBranch}`;
      return `已推送 ${result.upstreamBranch ?? result.branch ?? refName}`;
    });
  }

  private async runWrite(label: string, run: () => Promise<string>): Promise<void> {
    if (this.actionLabel) return;
    const context = this.gitContext;
    this.actionLabel = label;
    this.actionError = '';
    this.actionFeedback = '';
    try {
      const message = await run();
      if (context !== this.gitContext) return;
      this.pane = 'status';
      this.actionFeedback = message;
    } catch (error) {
      if (context === this.gitContext) this.actionError = (error as Error).message || 'Git 操作失败。';
    } finally {
      if (context === this.gitContext) this.actionLabel = '';
    }
  }

  private changeSummary(): string {
    const status = this.status;
    if (!status?.hasWorkingTreeChanges) return '工作区干净';
    if (status.files.length === 0) return '工作区有改动';
    return `${status.files.length} 个文件有改动 · +${status.insertions} −${status.deletions}`;
  }

  private upstreamSummary(): string {
    const status = this.status;
    if (status === undefined) return '';
    if (status.aheadCount > 0 && status.behindCount > 0) {
      return `领先 ${status.aheadCount} 个提交 · 落后 ${status.behindCount} 个提交`;
    }
    if (status.behindCount > 0) return `落后上游 ${status.behindCount} 个提交`;
    if (status.aheadCount > 0) {
      return status.hasUpstream ? `领先上游 ${status.aheadCount} 个提交` : `${status.aheadCount} 个提交待推送`;
    }
    return status.hasUpstream ? '与上游同步' : '';
  }

  private showPush(): boolean {
    const status = this.status;
    return status !== undefined && status.refName !== null && (status.hasPrimaryRemote || status.hasUpstream);
  }

  @Builder
  private Header() {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.arrow_left')).fontSize(22).fontColor([$r('sys.color.icon_primary')])
      }
      .id('thread-git-back')
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .accessibilityText('返回')
      .enabled(!this.actionLabel)
      .onClick(() => this.back())

      Text(this.pane === 'branches' ? '分支' : this.pane === 'commit' ? '提交改动' :
        this.pane === 'push-confirm' ? '确认推送' : 'Git')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)

      if (this.pane === 'status' || this.pane === 'branches') {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(22).fontColor([$r('sys.color.icon_primary')])
        }
        .id(this.pane === 'branches' ? 'thread-git-refresh-refs' : 'thread-git-refresh')
        .width(48)
        .height(48)
        .backgroundColor(Color.Transparent)
        .accessibilityText(this.pane === 'branches' ? '刷新分支' : '刷新 Git 状态')
        .enabled(!this.actionLabel && (this.pane === 'branches' ? !this.refsLoading : !this.loading))
        .onClick(() => {
          if (this.pane === 'branches') this.refreshRefs();
          else this.onRefresh();
        })
      }
    }
    .width('100%')
    .padding(4)
  }

  @Builder
  private Changes(selectable: boolean) {
    List({ space: 4 }) {
      LazyForEach(this.changes, (file: NativeThreadGitFile) => {
        ListItem() {
          Row({ space: 12 }) {
            if (selectable) {
              Checkbox({ name: file.path })
                .id(`thread-git-select-${file.path}`)
                .select(!this.excludedFiles.has(file.path))
                .enabled(this.canWrite && !this.actionLabel)
                .accessibilityText(file.path)
                .onChange((checked: boolean) => this.toggleFile(file.path, checked))
            }
            Text(file.path)
              .layoutWeight(1)
              .fontSize(14)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (file.insertions > 0 || file.deletions > 0) {
              Text(`+${file.insertions} −${file.deletions}`)
                .fontSize(13)
                .fontColor($r('sys.color.font_secondary'))
            }
          }.width('100%').constraintSize({ minHeight: 44 }).padding({ left: 16, right: 16 })
        }
      }, (file: NativeThreadGitFile) => JSON.stringify([file.path, file.insertions, file.deletions]))
    }
    .id('thread-git-files')
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private Status() {
    if (this.loading) {
      Row({ space: 8 }) {
        LoadingProgress().width(18).height(18)
        Text('正在加载 Git 状态…').fontSize(13).fontColor($r('sys.color.font_secondary'))
      }.width('100%').padding(16)
    }
    if (this.error) {
      Row({ space: 8 }) {
        Text(this.error).fontSize(14).fontColor($r('sys.color.font_primary')).layoutWeight(1)
        Button('重试')
          .id('thread-git-retry')
          .controlSize(ControlSize.SMALL)
          .enabled(!this.loading && !this.actionLabel)
          .onClick(() => this.onRefresh())
      }.width('100%').padding(16)
    }
    if (this.status?.isRepo) {
      Column({ space: 6 }) {
        Text(this.status?.refName ?? '游离 HEAD')
          .id('thread-git-branch')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.changeSummary()).fontSize(13).fontColor($r('sys.color.font_secondary'))
        if (this.status?.refName !== null && this.upstreamSummary()) {
          Text(this.upstreamSummary())
            .id('thread-git-upstream-summary')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
        }
        Row({ space: 8 }) {
          Button('分支', { buttonStyle: ButtonStyleMode.NORMAL })
            .id('thread-git-open-branches')
            .height(44)
            .enabled(!this.actionLabel && !this.loading)
            .onClick(() => { this.pane = 'branches'; })
          if (this.canWrite && this.status?.hasWorkingTreeChanges && (this.status?.files.length ?? 0) > 0) {
            Button('提交改动')
              .id('thread-git-open-commit')
              .height(44)
              .enabled(!this.actionLabel && !this.loading && !this.error)
              .onClick(() => { this.pane = 'commit'; })
          }
          if (this.onReview) {
            Button('审查改动', { buttonStyle: ButtonStyleMode.TEXTUAL })
              .enabled(!this.actionLabel)
              .onClick(() => this.onReview?.())
          }
        }.padding({ top: 6 })
        if (this.canWrite && (this.showPush() || canPullThreadGit(this.status))) {
          Row({ space: 8 }) {
            if (canPullThreadGit(this.status)) {
              Button('拉取最新更改', { buttonStyle: ButtonStyleMode.NORMAL })
                .id('thread-git-pull')
                .height(44)
                .enabled(this.canRunRemote())
                .onClick(() => this.handlePull())
            }
            if (this.showPush()) {
              Button(this.status?.hasUpstream === true ? '推送' : '发布分支', { buttonStyle: ButtonStyleMode.NORMAL })
                .id('thread-git-push')
                .height(44)
                .enabled(this.canRunRemote() && canPushThreadGit(this.status))
                .onClick(() => this.requestPush())
            }
          }
          if (!this.canWrite) {
            Text('此连接没有更改源代码的权限。').fontSize(13).fontColor($r('sys.color.font_secondary'))
          }
        }
      }.width('100%').alignItems(HorizontalAlign.Start).padding(16)
      if ((this.status?.files.length ?? 0) > 0) this.Changes(false)
    } else if (this.status) {
      Text('此工作目录没有 Git 仓库。')
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .padding(16)
    }
  }

  @Builder
  private PushConfirmation() {
    Column({ space: 12 }) {
      Text('推送到默认分支？')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
      Text(`将把 ${this.pushConfirmRef} 的本地提交推送到远端。`)
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
      Button('确认推送')
        .id('thread-git-confirm-push')
        .height(44)
        .enabled(this.canPush(this.pushConfirmRef, true))
        .onClick(() => this.handlePush(this.pushConfirmRef, true))
      if (this.canChangeBranch) {
        Button('先切换分支', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .id('thread-git-push-select-branch')
          .height(44)
          .enabled(!this.actionLabel && !this.loading)
          .onClick(() => { this.pane = 'branches'; })
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(16)
  }

  @Builder
  private RefRow(ref: NativeThreadGitRef) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 4 }) {
        Text(ref.name)
          .fontSize(16)
          .fontWeight(ref.current ? FontWeight.Medium : FontWeight.Normal)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.refDescription(ref)).fontSize(13).fontColor($r('sys.color.font_secondary'))
      }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 8, bottom: 8 })
    }
    .id(`thread-git-ref-${ref.name}`)
    .width('100%')
    .constraintSize({ minHeight: 52 })
    .backgroundColor(ref.current ? $r('sys.color.comp_background_secondary') : Color.Transparent)
    .accessibilityText(`${ref.name}，${this.refDescription(ref)}`)
    .enabled(this.canSwitch(ref))
    .onClick(() => {
      if (this.canSwitch(ref)) this.handleBranch(ref.name, false);
    })
  }

  @Builder
  private Branches() {
    Column({ space: 8 }) {
      if (this.canChangeBranch) {
        Row({ space: 8 }) {
          TextInput({ text: this.newBranch, placeholder: '新分支名称' })
            .id('thread-git-new-ref')
            .accessibilityText('新分支名称')
            .layoutWeight(1)
            .height(44)
            .enabled(!this.actionLabel && this.refsRepo)
            .onChange((name: string) => { this.newBranch = name; })
          Button('创建并切换')
            .id('thread-git-create-ref')
            .height(44)
            .enabled(!this.actionLabel && this.refsRepo && this.newBranch.trim().length > 0)
            .onClick(() => this.handleBranch(normalizeThreadGitNewRef(this.newBranch), true))
        }.width('100%')
        if (this.newBranch.trim() && normalizeThreadGitNewRef(this.newBranch) !== this.newBranch.trim()) {
          Text(`将创建 ${normalizeThreadGitNewRef(this.newBranch)}`)
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
        }
      }
      TextInput({ text: this.refsQuery, placeholder: '搜索本地分支' })
        .id('thread-git-ref-search')
        .accessibilityText('搜索本地分支')
        .height(44)
        .maxLength(256)
        .enabled(!this.actionLabel)
        .onChange((query: string) => {
          this.refsQuery = query;
          this.refreshRefs(true);
        })
        .onSubmit(() => this.refreshRefs())
      if (this.refsError) {
        Row({ space: 8 }) {
          Text(this.refsError).layoutWeight(1).fontSize(14).fontColor($r('sys.color.font_primary'))
          Button('重试', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .id('thread-git-refs-retry')
            .height(44)
            .enabled(!this.actionLabel)
            .onClick(() => { void this.loadRefs(this.nextRefsCursor); })
        }.width('100%')
      } else if (this.refsLoading) {
        Row({ space: 8 }) {
          LoadingProgress().width(18).height(18)
          Text('正在加载分支…').fontSize(13).fontColor($r('sys.color.font_secondary'))
        }.width('100%')
      } else if (this.refs.length === 0) {
        Text(this.refsRepo ? (this.refsQuery.trim() ? '没有匹配的本地分支。' : '没有本地分支。') :
          '此工作目录没有 Git 仓库。')
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
      }
      if (this.refs.length > 0) {
        List() {
          ForEach(this.refs, (ref: NativeThreadGitRef) => {
            ListItem() { this.RefRow(ref) }
          }, (ref: NativeThreadGitRef) => JSON.stringify([ref.name, ref.current, ref.isDefault, ref.worktreePath]))
        }.id('thread-git-refs').width('100%').layoutWeight(1)
        if (this.nextRefsCursor !== null && !this.refsError) {
          Button('加载更多分支', { buttonStyle: ButtonStyleMode.NORMAL })
            .id('thread-git-more-refs')
            .height(44)
            .width('100%')
            .enabled(!this.refsLoading && !this.actionLabel)
            .onClick(() => { void this.loadRefs(this.nextRefsCursor); })
        }
      }
    }.width('100%').layoutWeight(1).alignItems(HorizontalAlign.Start).padding({ left: 16, right: 16, bottom: 12 })
  }

  @Builder
  private Commit() {
    Column({ space: 8 }) {
      Text(this.status?.refName ?? '游离 HEAD')
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      TextArea({ text: this.commitMessage, placeholder: '提交说明' })
        .id('thread-git-commit-message')
        .height(92)
        .maxLength(10_000)
        .enabled(this.canWrite && !this.actionLabel)
        .accessibilityText('提交说明')
        .onChange((message: string) => { this.commitMessage = message; })
      Row({ space: 8 }) {
        Text(`已选择 ${this.selectedCount()} / ${this.status?.files.length ?? 0} 个文件`)
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .layoutWeight(1)
        Button(this.selectedCount() === (this.status?.files.length ?? 0) ? '清除选择' : '全选',
          { buttonStyle: ButtonStyleMode.TEXTUAL })
          .id('thread-git-commit-select-all')
          .height(44)
          .enabled(this.canWrite && !this.actionLabel && (this.status?.files.length ?? 0) > 0)
          .onClick(() => this.toggleAllFiles())
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 16, right: 16 })
    this.Changes(true)
    Row() {
      Button('提交')
        .id('thread-git-commit')
        .height(46)
        .width('100%')
        .enabled(this.canCommit())
        .onClick(() => this.handleCommit())
    }.width('100%').padding({ left: 16, right: 16, bottom: 12 })
  }

  build() {
    Column() {
      this.Header()
      if (this.actionLabel) {
        Row({ space: 8 }) {
          LoadingProgress().width(18).height(18)
          Text(this.actionLabel).fontSize(13).fontColor($r('sys.color.font_secondary'))
        }.width('100%').padding(16)
      }
      if (this.actionError || this.actionFeedback) {
        Text(this.actionError || this.actionFeedback)
          .id('thread-git-action-result')
          .width('100%')
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      }
      if (this.pane === 'branches') {
        this.Branches()
      } else if (this.pane === 'commit') {
        this.Commit()
      } else if (this.pane === 'push-confirm') {
        this.PushConfirmation()
      } else {
        this.Status()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.comp_background_primary'))
  }
}
