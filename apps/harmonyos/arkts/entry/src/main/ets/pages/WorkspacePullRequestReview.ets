import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import {
  emptyPullRequestReviewDraft, pullRequestReviewDraftProblem, readPullRequestReviewDrafts, withPullRequestLineDraft,
} from '../client/PullRequestReviewDraft';
import type {
  NativePullRequestInlineTarget, NativePullRequestLineDraft, NativePullRequestReviewDraft,
  NativePullRequestReviewDraftDocument, NativePullRequestReviewMode, NativePullRequestReviewVerdict,
} from '../client/PullRequestReviewDraft';
import type {
  NativePullRequestCompletionOptions, NativePullRequestCompletionSupport, NativePullRequestComposerTrigger,
} from '../client/PullRequestReferenceProtocol';
import { WorkspacePullRequestComposer } from './WorkspacePullRequestComposer';

const DRAFTS_FILE = '/pull-request-drafts.json';
const VERDICTS: NativePullRequestReviewVerdict[] = ['comment', 'approve', 'request-changes'];
let diskWrites: Promise<void> = Promise.resolve();

async function readDrafts(path: string): Promise<Record<string, NativePullRequestReviewDraft>> {
  let raw: string;
  try {
    raw = await fileIo.readText(path);
  } catch (error) {
    if ((error as BusinessError).code === 13900002) return {};
    throw new Error('无法读取拉取请求草稿。');
  }
  return readPullRequestReviewDrafts(raw);
}

function writeDraft(path: string, key: string, draft: NativePullRequestReviewDraft): Promise<void> {
  const write = diskWrites.then(async () => {
    const previous = await readDrafts(path);
    const drafts: Record<string, NativePullRequestReviewDraft> = {};
    for (const id of Object.keys(previous)) {
      if (id !== key) drafts[id] = previous[id];
    }
    if (draft.summary || draft.comment || draft.comments.length) drafts[key] = draft;
    const document: NativePullRequestReviewDraftDocument = { version: 1, drafts };
    const bytes = new util.TextEncoder().encodeInto(JSON.stringify(document));
    const temporary = `${path}.tmp`;
    const file = await fileIo.open(temporary, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      if (await fileIo.write(file.fd, bytes.buffer) !== bytes.byteLength) throw new Error('草稿写入不完整。');
      await fileIo.fsync(file.fd);
    } finally {
      await fileIo.close(file);
    }
    await fileIo.rename(temporary, path);
  });
  diskWrites = write.catch(() => {});
  return write;
}

function verdictLabel(verdict: NativePullRequestReviewVerdict): string {
  if (verdict === 'approve') return '批准';
  if (verdict === 'request-changes') return '请求修改';
  return '评论';
}

function lineLabel(line: NativePullRequestInlineTarget): string {
  return `${line.side === 'LEFT' ? '旧' : '新'}行 ${line.line}`;
}

@Component
export struct WorkspacePullRequestReview {
  @Prop @Watch('loadDraft') draftKey: string = '';
  @Prop @Watch('resetInline') mode: NativePullRequestReviewMode = 'review';
  @Prop subtitle: string = '';
  @Prop headSha: string = '';
  @Prop verdicts: NativePullRequestReviewVerdict[] = [];
  @Prop canComment: boolean = false;
  @Prop canInlineComment: boolean = false;
  @Prop requiresChangeSummary: boolean = false;
  @Prop completionSupport?: NativePullRequestCompletionSupport = undefined;
  @Prop @Watch('resetInline') inline?: NativePullRequestInlineTarget = undefined;
  @Prop @Watch('finishBack') backRequest: number = 0;
  @StorageProp('t3.arkts.foreground') @Watch('foregroundChanged') private appInForeground: boolean = true;
  onBack: () => void = () => {};
  onRelocate?: (draft: NativePullRequestLineDraft) => void;
  onReadCompletions?: (trigger: NativePullRequestComposerTrigger) => Promise<NativePullRequestCompletionOptions>;

  @State private draft: NativePullRequestReviewDraft = emptyPullRequestReviewDraft();
  @State private ready: boolean = false;
  @State private loadError: boolean = false;
  @State private writeError: boolean = false;
  @State private busy: boolean = false;
  @State private requestedVerdict: NativePullRequestReviewVerdict = 'comment';
  @State private activeLine?: NativePullRequestInlineTarget = undefined;
  @State private inlineBody: string = '';
  private activeInlineId: string = '';
  private path: string = '';
  private activeKey: string = '';
  private generation: number = 0;
  private revision: number = 0;
  private savedRevision: number = 0;
  private savingRevision: number = -1;
  private pendingWrite?: Promise<boolean> = undefined;
  private timer: number = -1;

  aboutToAppear(): void {
    void this.loadDraft();
  }

  aboutToDisappear(): void {
    void this.flushDraft();
    this.generation++;
  }

  private foregroundChanged(): void {
    if (!this.appInForeground) void this.flushDraft();
  }

  private resetInline(): void {
    this.activeLine = this.mode === 'inline' ? this.inline : undefined;
    this.activeInlineId = this.activeLine?.draftId ?? '';
    this.inlineBody = this.draft.comments.find((entry: NativePullRequestLineDraft) =>
      entry.id === this.activeInlineId)?.body ?? '';
  }

  private async loadDraft(): Promise<void> {
    if (this.ready) void this.flushDraft();
    const generation = ++this.generation;
    this.activeKey = this.draftKey;
    this.path = (this.getUIContext().getHostContext()?.filesDir ?? '') + DRAFTS_FILE;
    this.ready = false;
    this.loadError = false;
    this.writeError = false;
    this.busy = false;
    this.draft = emptyPullRequestReviewDraft();
    this.revision = 0;
    this.savedRevision = 0;
    this.savingRevision = -1;
    this.pendingWrite = undefined;
    this.requestedVerdict = 'comment';
    this.resetInline();
    if (!this.activeKey || this.path === DRAFTS_FILE) {
      this.loadError = true;
      return;
    }
    try {
      await diskWrites;
      const drafts = await readDrafts(this.path);
      if (this.generation !== generation) return;
      this.draft = drafts[this.activeKey] ?? emptyPullRequestReviewDraft();
      this.resetInline();
      this.ready = true;
    } catch (_) {
      if (this.generation === generation) this.loadError = true;
    }
  }

  private changeDraft(draft: NativePullRequestReviewDraft): void {
    this.draft = draft;
    this.revision++;
    clearTimeout(this.timer);
    this.timer = setTimeout(() => { void this.flushDraft(); }, 200);
  }

  private flushDraft(): Promise<boolean> {
    clearTimeout(this.timer);
    if (!this.ready || this.revision === this.savedRevision) return Promise.resolve(true);
    if (this.pendingWrite && this.savingRevision === this.revision) return this.pendingWrite;
    const generation = this.generation;
    const revision = this.revision;
    const write = writeDraft(this.path, this.activeKey, this.draft);
    this.savingRevision = revision;
    this.pendingWrite = this.finishWrite(write, generation, revision);
    return this.pendingWrite;
  }

  private async finishWrite(write: Promise<void>, generation: number, revision: number): Promise<boolean> {
    try {
      await write;
      if (this.generation === generation) {
        this.savedRevision = revision;
        this.writeError = false;
      }
      return true;
    } catch (_) {
      if (this.generation === generation) this.writeError = true;
      return false;
    } finally {
      if (this.generation === generation && this.savingRevision === revision) this.pendingWrite = undefined;
    }
  }

  private shownMode(): NativePullRequestReviewMode {
    return this.activeLine ? 'inline' : this.mode;
  }

  private async finishBack(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    const generation = this.generation;
    const saved = await this.flushDraft();
    if (generation !== this.generation) return;
    this.busy = false;
    if (saved) this.leaveEditor();
  }

  private leaveEditor(): void {
    if (this.mode === 'review' && this.activeLine) {
      this.activeLine = undefined;
      this.activeInlineId = '';
      this.inlineBody = '';
    } else {
      this.onBack();
    }
  }

  private offeredVerdicts(): NativePullRequestReviewVerdict[] {
    return VERDICTS.filter((verdict: NativePullRequestReviewVerdict) => this.verdicts.includes(verdict));
  }

  private verdict(): NativePullRequestReviewVerdict | undefined {
    const offered = this.offeredVerdicts();
    return offered.includes(this.requestedVerdict) ? this.requestedVerdict : offered[0];
  }

  private inputText(): string {
    const mode = this.shownMode();
    return mode === 'review' ? this.draft.summary : mode === 'comment' ? this.draft.comment : this.inlineBody;
  }

  private setInputText(value: string): void {
    if (!this.ready || this.busy) return;
    const mode = this.shownMode();
    if (mode === 'inline') {
      this.inlineBody = value;
      return;
    }
    this.changeDraft({
      summary: mode === 'review' ? value : this.draft.summary,
      comment: mode === 'comment' ? value : this.draft.comment,
      comments: this.draft.comments,
    });
  }

  private openLine(entry: NativePullRequestLineDraft): void {
    if (entry.headSha !== this.headSha) {
      this.onRelocate?.(entry);
      return;
    }
    this.activeLine = entry;
    this.activeInlineId = entry.id;
    this.inlineBody = entry.body;
  }

  private canSaveInline(): boolean {
    return this.ready && !this.busy && this.canInlineComment && !!this.headSha && !!this.inlineBody.trim() &&
      this.activeLine?.headSha === this.headSha;
  }

  private async saveLine(): Promise<void> {
    const line = this.activeLine;
    if (!line || !this.canSaveInline()) return;
    this.activeInlineId = this.activeInlineId || util.generateRandomUUID();
    this.changeDraft(withPullRequestLineDraft(this.draft, line, this.inlineBody, this.activeInlineId));
    await this.finishBack();
  }

  private async deleteLine(): Promise<void> {
    const id = this.activeInlineId;
    if (!id || this.busy || !this.ready) return;
    const generation = this.generation;
    this.busy = true;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '删除评论草稿？',
        message: '其他审查草稿会保留。',
        buttons: [
          { text: '取消', color: $r('sys.color.font_primary') },
          { text: '删除', color: $r('sys.color.font_emphasize') },
        ],
      });
      if (generation !== this.generation || result.index !== 1) return;
      this.changeDraft({
        summary: this.draft.summary,
        comment: this.draft.comment,
        comments: this.draft.comments.filter((entry: NativePullRequestLineDraft) => entry.id !== id),
      });
      if (await this.flushDraft() && generation === this.generation) this.leaveEditor();
    } catch (_) {
    } finally {
      if (generation === this.generation) this.busy = false;
    }
  }

  private title(): string {
    const mode = this.shownMode();
    if (mode === 'review') return '提交审查';
    if (mode === 'comment') return '添加评论';
    return this.activeInlineId ? '编辑行评论' : '行评论';
  }

  private placeholder(): string {
    const mode = this.shownMode();
    if (mode === 'inline') return '撰写对这一行的反馈…';
    if (mode === 'comment') return '撰写评论…';
    return this.requiresChangeSummary && this.verdict() === 'request-changes'
      ? '请求修改时须填写摘要…' : '撰写审查摘要…';
  }

  private validationMessage(): string {
    const mode = this.shownMode();
    if (mode === 'inline') {
      if (this.activeLine && this.activeLine.headSha !== this.headSha) return '分支已更新，请在当前变更中重新选择行。';
      return this.canInlineComment ? '' : '当前环境或拉取请求不允许添加行评论。';
    }
    if (mode === 'comment') return this.canComment ? '' : '当前环境或拉取请求不允许发表评论。';
    const problem = pullRequestReviewDraftProblem(this.draft, this.headSha, this.verdict(),
      this.canInlineComment, this.requiresChangeSummary);
    if (problem === 'stale') return '分支已更新，请为行评论重新选择当前行。';
    if (problem === 'inline-unavailable') return '此拉取请求当前无法提交行评论，草稿已保留。';
    if (problem === 'unavailable') return '当前环境或拉取请求不允许提交审查。';
    if (problem === 'summary-required') return '此提供商要求填写请求修改的摘要。';
    return '';
  }

  private submitLabel(): string {
    if (this.shownMode() === 'comment') return '发表评论';
    const verdict = this.verdict();
    return verdict && verdict !== 'comment' ? verdictLabel(verdict) : '提交审查';
  }

  @Builder
  private Header() {
    Row({ space: 10 }) {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        SymbolGlyph($r('sys.symbol.arrow_left')).fontSize(21).fontColor([$r('sys.color.icon_primary')])
      }
      .id('workspace-pr-review-back').width(44).height(44).padding(0)
      .accessibilityText('返回').enabled(!this.busy).onClick(() => { void this.finishBack(); })
      Column({ space: 4 }) {
        Text(this.title()).fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('sys.color.font_primary'))
        Text(this.activeLine ? `${this.subtitle} · ${lineLabel(this.activeLine)}` :
          this.mode === 'review' && this.headSha ? `${this.subtitle} · ${this.headSha.slice(0, 7)}` : this.subtitle)
          .fontSize(12).fontColor($r('sys.color.font_secondary')).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
    }.width('100%').padding({ left: 12, right: 16, top: 6, bottom: 6 })
  }

  @Builder
  private Feedback(message: string) {
    Text(message).fontSize(13).fontColor($r('sys.color.font_secondary')).width('100%')
  }

  @Builder
  private VerdictPicker() {
    if (this.offeredVerdicts().length > 1) {
      Row({ space: 3 }) {
        ForEach(this.offeredVerdicts(), (verdict: NativePullRequestReviewVerdict) => {
          Button(verdictLabel(verdict), { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL })
            .id(`workspace-pr-review-verdict-${verdict}`).layoutWeight(1).height(38)
            .backgroundColor(this.verdict() === verdict ? $r('sys.color.comp_background_primary') : Color.Transparent)
            .fontColor($r('sys.color.font_primary')).accessibilitySelected(this.verdict() === verdict)
            .enabled(!this.busy).onClick(() => { this.requestedVerdict = verdict; })
        }, (verdict: NativePullRequestReviewVerdict) => verdict)
      }.width('100%').padding(4).borderRadius(24).backgroundColor($r('sys.color.comp_background_tertiary'))
    }
  }

  @Builder
  private PendingLine(entry: NativePullRequestLineDraft) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Column({ space: 6 }) {
        Text(`${entry.path} · ${lineLabel(entry)}`).fontSize(12).fontFamily('monospace')
          .fontColor($r('sys.color.font_secondary')).maxLines(2)
        Text(entry.body).fontSize(14).fontColor($r('sys.color.font_primary')).maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(entry.headSha === this.headSha ? '点击编辑' : '分支已更新，请重新定位')
          .fontSize(12).fontColor($r('sys.color.font_secondary'))
      }.width('100%').alignItems(HorizontalAlign.Start).padding(14)
    }.id(`workspace-pr-review-draft-${entry.id}`).width('100%').padding(0).borderRadius(16)
      .backgroundColor($r('sys.color.comp_background_secondary'))
      .enabled(!this.busy && (entry.headSha === this.headSha || this.onRelocate !== undefined))
      .onClick(() => this.openLine(entry))
  }

  @Builder
  private Form() {
    if (this.shownMode() === 'review') {
      this.VerdictPicker()
      this.Feedback('摘要')
    } else if (this.activeLine) {
      Column({ space: 8 }) {
        Text(this.activeLine.path).fontSize(12).fontFamily('monospace').fontColor($r('sys.color.font_secondary'))
        if (this.activeLine.code) {
          Text(this.activeLine.code).fontSize(13).fontFamily('monospace').fontColor($r('sys.color.font_primary'))
            .copyOption(CopyOptions.LocalDevice)
        }
      }.width('100%').alignItems(HorizontalAlign.Start).padding(14).borderRadius(16)
        .backgroundColor($r('sys.color.comp_background_secondary'))
    } else {
      this.Feedback('评论')
    }
    ForEach([this.shownMode()], (mode: NativePullRequestReviewMode) => {
      WorkspacePullRequestComposer({ value: this.inputText(), placeholder: this.placeholder(),
        controlId: `workspace-pr-${mode}-body`, label: this.title(), editable: !this.busy,
        support: this.completionSupport, onRead: this.onReadCompletions,
        onValueChange: (value: string) => this.setInputText(value),
      })
    }, (mode: NativePullRequestReviewMode) => mode)
    if (this.shownMode() === 'review' && this.draft.comments.length > 0) {
      this.Feedback(`${this.draft.comments.length} 条待提交行评论`)
      ForEach(this.draft.comments, (entry: NativePullRequestLineDraft) => this.PendingLine(entry),
        (entry: NativePullRequestLineDraft) => `${entry.id}/${entry.headSha}/${entry.line}/${entry.body}`)
    }
    if (this.activeLine) {
      this.Feedback('行评论草稿仅保存在本机，提交审查后才会发布。')
      if (this.draft.comments.some((entry: NativePullRequestLineDraft) => entry.id === this.activeInlineId)) {
        Button('删除草稿', { buttonStyle: ButtonStyleMode.TEXTUAL }).id('workspace-pr-inline-delete')
          .height(44).enabled(!this.busy).onClick(() => { void this.deleteLine(); })
      }
    }
    if (this.validationMessage()) {
      Text(this.validationMessage()).id('workspace-pr-review-validation')
        .fontSize(13).fontColor($r('sys.color.font_secondary')).width('100%')
    }
    if (this.writeError) {
      this.Feedback('无法保存本机草稿，可重试。')
      Button('重试保存', { buttonStyle: ButtonStyleMode.TEXTUAL }).height(44)
        .enabled(!this.busy).onClick(() => { void this.flushDraft(); })
    }
  }

  @Builder
  private Footer() {
    Column({ space: 6 }) {
      if (this.shownMode() === 'inline') {
        Button('保存草稿', { type: ButtonType.Capsule }).id('workspace-pr-inline-save')
          .width('100%').height(46).enabled(this.canSaveInline()).onClick(() => { void this.saveLine(); })
      } else {
        this.Feedback('草稿自动保存在本机，远程提交暂不可用。')
        Button(this.submitLabel(), { type: ButtonType.Capsule }).id('workspace-pr-review-submit')
          .width('100%').height(46).enabled(false)
      }
    }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 10 })
  }

  build() {
    Column() {
      this.Header()
      Scroll() {
        Column({ space: 12 }) {
          if (this.ready) {
            this.Form()
          } else if (this.loadError) {
            this.Feedback('无法读取本机草稿。')
            Button('重试', { buttonStyle: ButtonStyleMode.TEXTUAL }).height(44)
              .onClick(() => { void this.loadDraft(); })
          } else {
            LoadingProgress().width(30).height(30).accessibilityText('正在读取草稿')
          }
        }.width('100%').constraintSize({ maxWidth: 560 }).alignItems(HorizontalAlign.Start)
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)
      this.Footer()
    }.id('workspace-pr-review-form').width('100%').height('100%')
      .backgroundColor($r('sys.color.comp_background_primary'))
  }
}
