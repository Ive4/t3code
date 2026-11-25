export interface ThreadSideChatItem {
  threadId: string;
  title: string;
  needs?: 'approval' | 'input';
}

@Component
export struct ThreadSideChatsRow {
  @Prop chats: ThreadSideChatItem[] = [];
  @Prop openingThreadId: string = '';
  onOpen: (threadId: string) => void = () => {};

  private chipDescription(chat: ThreadSideChatItem): string {
    if (this.openingThreadId === chat.threadId) return '正在打开旁支会话 ' + chat.title;
    const status = chat.needs === 'approval' ? '，等待审批' : chat.needs === 'input' ? '，等待输入' : '';
    return '打开旁支会话 ' + chat.title + status;
  }

  @Builder
  private ChatChip(chat: ThreadSideChatItem) {
    Button({ type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 6 }) {
        if (this.openingThreadId === chat.threadId) {
          LoadingProgress().width(12).height(12).color($r('sys.color.icon_secondary'))
        } else if (chat.needs) {
          Circle().width(6).height(6).fill(chat.needs === 'approval' ? '#BA6B00' : $r('sys.color.icon_emphasize'))
        }
        Text(chat.title)
          .fontSize(12)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1)
      }
    }
    .id('thread-side-chat-' + chat.threadId)
    .height(24)
    .constraintSize({ maxWidth: 192 })
    .padding({ left: 10, right: 10 })
    .backgroundColor($r('sys.color.comp_background_secondary'))
    .accessibilityText(this.chipDescription(chat))
    .enabled(!this.openingThreadId)
    .onClick(() => this.onOpen(chat.threadId))
  }

  build() {
    if (this.chats.length > 0) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.message_on_message'))
          .fontSize(12)
          .fontColor([$r('sys.color.icon_secondary')])
        Text('旁支会话').fontSize(12).fontColor($r('sys.color.font_secondary'))
        Scroll() {
          Row({ space: 4 }) {
            ForEach(this.chats, (chat: ThreadSideChatItem) => this.ChatChip(chat),
              (chat: ThreadSideChatItem) => `${chat.threadId}\n${chat.title}\n${chat.needs ?? ''}`)
          }.padding({ right: 16 })
        }
        .layoutWeight(1)
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .align(Alignment.Start)
      }
      .id('thread-side-chats')
      .width('100%')
      .padding({ left: 16, top: 8, bottom: 8 })
    }
  }
}
