import type {
  NativePullRequestCompletionOptions, NativePullRequestCompletionSupport, NativePullRequestComposerTrigger,
} from '../client/PullRequestReferenceProtocol';
import { WorkspacePullRequestComposer } from './WorkspacePullRequestComposer';

export type NativePullRequestEditField = 'title' | 'body' | 'comment';

@Component
export struct WorkspacePullRequestEdit {
  @Prop field: NativePullRequestEditField = 'title';
  @Prop original: string = '';
  @Prop subtitle: string = '';
  @Prop completionSupport?: NativePullRequestCompletionSupport = undefined;
  onBack: () => void = () => {};
  onReadCompletions?: (trigger: NativePullRequestComposerTrigger) => Promise<NativePullRequestCompletionOptions>;

  @State private draft?: string = undefined;

  private title(): string {
    if (this.field === 'title') return '编辑标题';
    return this.field === 'body' ? '编辑描述' : '编辑评论';
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_primary')])
        }
        .id('workspace-pr-edit-back')
        .width(48)
        .height(48)
        .padding(0)
        .accessibilityText('取消编辑')
        .onClick(() => this.onBack())
        Column({ space: 2 }) {
          Text(this.title())
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
          Text(this.subtitle)
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').height(60).padding({ left: 8, right: 16 })

      Scroll() {
        Column({ space: 12 }) {
          if (this.field === 'title') {
            TextInput({ text: this.draft ?? this.original, placeholder: '标题' })
              .id('workspace-pr-edit-input')
              .accessibilityText('拉取请求标题')
              .width('100%')
              .height(48)
              .fontSize(16)
              .maxLength(1024)
              .enterKeyType(EnterKeyType.Done)
              .borderRadius(20)
              .backgroundColor($r('sys.color.comp_background_secondary'))
              .onChange((value: string) => { this.draft = value; })
          } else {
            WorkspacePullRequestComposer({ value: this.draft ?? this.original,
              placeholder: '使用 Markdown 编写…', controlId: 'workspace-pr-edit-multiline-input',
              label: this.field === 'body' ? '拉取请求描述' : '评论', inputHeight: 192, fixedHeight: false,
              support: this.completionSupport, onRead: this.onReadCompletions,
              onValueChange: (value: string) => { this.draft = value; },
            })
          }
          if (this.field === 'title' && !(this.draft ?? this.original).trim()) {
            Text('请输入标题。')
              .id('workspace-pr-edit-validation')
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
          .padding({ left: 16, right: 16, top: 16, bottom: 20 })
      }.width('100%').layoutWeight(1).align(Alignment.Top)

      Column({ space: 8 }) {
        Text('服务端保存功能接入后可提交修改。')
          .id('workspace-pr-edit-status')
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
        Button('保存', { type: ButtonType.Capsule })
          .id('workspace-pr-edit-save')
          .width('100%')
          .height(48)
          .enabled(false)
      }.width('100%').alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 8, bottom: 12 })
    }.width('100%').height('100%').backgroundColor($r('sys.color.comp_background_primary'))
  }
}
