import { UiLanguage, uiText } from './UiLanguage';
import { workspaceForegroundColor, workspaceHeaderColor, workspaceMutedColor, workspaceNavigationBarColor } from './UiTheme';
import type { WorkspaceThreadRowStatus, WorkspaceThreadSection } from './WorkspaceThreadListModel';
export { workspaceForegroundColor, workspaceGroupedCardColor, workspaceHeaderColor, workspaceMutedColor,
  workspaceSurfaceColor } from './UiTheme';

const SEARCH_FIELD_ID = 'workspace-search-query';
const WORDMARK = 'M33.4509 93V47.56H15.5309V37H64.3309V47.56H46.4109V93H33.4509Z' +
  'M86.7253 93.96C82.832 93.96 78.9653 93.4533 75.1253 92.44C71.2853 91.3733 68.032 89.88 65.3653 87.96' +
  'L70.4053 78.04C72.5386 79.5867 75.0186 80.8133 77.8453 81.72C80.672 82.6267 83.5253 83.08 86.4053 83.08' +
  'C89.6586 83.08 92.2186 82.44 94.0853 81.16C95.952 79.88 96.8853 78.12 96.8853 75.88' +
  'C96.8853 73.7467 96.0586 72.0667 94.4053 70.84C92.752 69.6133 90.0853 69 86.4053 69H80.4853V60.44' +
  'L96.0853 42.76L97.5253 47.4H68.1653V37H107.365V45.4L91.8453 63.08L85.2853 59.32H89.0453' +
  'C95.9253 59.32 101.125 60.8667 104.645 63.96C108.165 67.0533 109.925 71.0267 109.925 75.88' +
  'C109.925 79.0267 109.099 81.9867 107.445 84.76C105.792 87.48 103.259 89.6933 99.8453 91.4' +
  'C96.432 93.1067 92.0586 93.96 86.7253 93.96Z';
const FILTER_OUTLINE = 'M4 4h16v2.172a2 2 0 0 1 -.586 1.414L15 12v7l-6 2v-8.5L4.52 7.57A2 2 0 0 1 4 6.227Z';
const FILTER_FILLED = 'M20 3h-16a1 1 0 0 0 -1 1v2.227l.008 .223a3 3 0 0 0 .772 1.795l4.22 4.641v8.114' +
  'a1 1 0 0 0 1.316 .949l6 -2l.108 -.043a1 1 0 0 0 .576 -.906v-6.586l4.121 -4.12' +
  'a3 3 0 0 0 .879 -2.123v-2.171a1 1 0 0 0 -1 -1z';

export type WorkspaceSharedTab = 'pullRequests' | 'issues';
export type WorkspaceTab = 'threads' | WorkspaceSharedTab | 'usage' | 'settings';

export interface WorkspaceFilterOption {
  key: string;
  label: string;
  selected: boolean;
  enabled?: boolean;
}

export interface WorkspaceFilterGroup {
  label: string;
  options: WorkspaceFilterOption[];
}

function workspaceAccentColor(dark: boolean): string {
  return dark ? '#346bf1' : '#1b4ed8';
}

function threadSectionLabel(section: WorkspaceThreadSection, language: UiLanguage): string {
  switch (section) {
    case 'pinned': return uiText(language, '置顶', 'Pinned');
    case 'attention': return uiText(language, '需要处理', 'Needs attention');
    case 'working': return uiText(language, '进行中', 'Working');
    case 'unread': return uiText(language, '未读结果', 'Unread results');
    case 'recent': return uiText(language, '最近会话', 'Recent chats');
    case 'snoozed': return uiText(language, '稍后处理', 'Snoozed');
    case 'settled': return uiText(language, '已完成', 'Settled');
  }
}

@Component
export struct WorkspaceFilterButton {
  @Prop groups: WorkspaceFilterGroup[] = [];
  @Prop customized: boolean = false;
  @Prop dark: boolean = false;
  @Prop language: UiLanguage = 'zh';
  @Prop label: string = '';
  onFilter: (key: string) => void = () => {};

  @Builder
  private FilterMenu() {
    Menu() {
      ForEach(this.groups, (group: WorkspaceFilterGroup) => {
        MenuItemGroup({ header: group.label }) {
          ForEach(group.options, (option: WorkspaceFilterOption) => {
            MenuItem({ content: option.label })
              .selected(option.selected)
              .selectIcon(true)
              .enabled(option.enabled !== false)
              .onChange(() => this.onFilter(option.key))
          }, (option: WorkspaceFilterOption) => option.key)
        }
      }, (group: WorkspaceFilterGroup) => group.label)
    }
    .width(248)
    .backgroundColor(workspaceHeaderColor(this.dark))
    .borderRadius(12)
  }

  build() {
    Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Shape() {
        Path({ commands: this.customized ? FILTER_FILLED : FILTER_OUTLINE })
          .width('100%')
          .height('100%')
          .fill(this.customized ? workspaceForegroundColor(this.dark) : Color.Transparent)
          .stroke(this.customized ? Color.Transparent : workspaceForegroundColor(this.dark))
          .strokeWidth(2)
          .strokeLineJoin(LineJoinStyle.Round)
      }
      .viewPort({ x: 0, y: 0, width: 24, height: 24 })
      .width(24)
      .height(24)
    }
    .id('workspace-filter')
    .width(48)
    .height(48)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .accessibilityText(this.label || uiText(this.language, '筛选环境和项目', 'Filter environments and projects'))
    .accessibilityStateDescription(this.customized ? uiText(this.language, '已应用筛选', 'Filters applied') : '')
    .bindMenu(this.FilterMenu)
  }
}

@Component
export struct WorkspaceHeader {
  @Prop title: string = '';
  @Prop status: string = '';
  @Prop statusProgress: boolean = false;
  @Prop query: string = '';
  @Prop searchOpen: boolean = false;
  @Prop filterGroups: WorkspaceFilterGroup[] = [];
  @Prop filterCustomized: boolean = false;
  @Prop language: UiLanguage = 'zh';
  @Prop dark: boolean = false;
  onQuery: (query: string) => void = () => {};
  onSearch: () => void = () => {};
  onCloseSearch: () => void = () => {};
  onEnvironment: () => void = () => {};
  onFilter: (key: string) => void = () => {};
  private searchController: TextInputController = new TextInputController();
  private focusSearchOnLayout: boolean = false;

  @Builder
  private IconButton(id: string, icon: Resource, label: string, action: () => void) {
    Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      SymbolGlyph(icon).fontSize(24).fontColor([workspaceForegroundColor(this.dark)])
    }
    .id(id)
    .width(48)
    .height(48)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .accessibilityText(label)
    .onClick(action)
  }

  @Builder
  private Wordmark() {
    Shape() {
      Path({ commands: WORDMARK })
        .width('100%')
        .height('100%')
        .fill(workspaceForegroundColor(this.dark))
    }
    .viewPort({ x: 15.53, y: 37, width: 94.4, height: 56.96 })
    .width(25)
    .height(15)
  }

  build() {
    Row() {
      if (this.searchOpen || this.query.length > 0) {
        this.IconButton('workspace-search-close', $r('sys.symbol.arrow_left'),
          uiText(this.language, '关闭搜索', 'Close search'), () => {
            this.searchController.stopEditing();
            this.onCloseSearch();
          })
        TextInput({
          text: this.query, placeholder: uiText(this.language, '搜索会话', 'Search chats'),
          controller: this.searchController,
        })
          .id(SEARCH_FIELD_ID)
          .height(44)
          .layoutWeight(1)
          .padding({ left: 12, right: 12 })
          .margin({ right: 4 })
          .borderRadius(22)
          .backgroundColor(this.dark ? '#292929' : '#eaeaeb')
          .fontColor(workspaceForegroundColor(this.dark))
          .placeholderColor(workspaceMutedColor(this.dark))
          .fontSize(16)
          .enterKeyType(EnterKeyType.Search)
          .enableKeyboardOnFocus(true)
          .accessibilityText(uiText(this.language, '搜索会话', 'Search chats'))
          .onChange((query: string) => this.onQuery(query))
          .onAreaChange(() => {
            if (this.focusSearchOnLayout && focusControl.requestFocus(SEARCH_FIELD_ID)) {
              this.focusSearchOnLayout = false;
            }
          })
      } else {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 6 }) {
            this.Wordmark()
            Text('Code')
              .fontSize(21)
              .fontWeight(FontWeight.Medium)
              .fontColor(workspaceMutedColor(this.dark))
              .letterSpacing(-0.5)
              .maxLines(1)
            if (this.status) {
              if (this.statusProgress) {
                LoadingProgress().width(16).height(16).color(workspaceMutedColor(this.dark))
              }
              Text(this.status)
                .fontSize(13)
                .fontColor(workspaceMutedColor(this.dark))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .flexShrink(1)
            }
          }
          .width('100%')
        }
        .id('workspace-environment')
        .height(48)
        .layoutWeight(1)
        .padding({ left: 12, right: 4 })
        .backgroundColor(Color.Transparent)
        .accessibilityGroup(true)
        .accessibilityText(['T3 Code', this.status || this.title].filter(Boolean).join(', '))
        .accessibilityDescription(uiText(this.language, '打开环境设置', 'Opens environment settings'))
        .onClick(() => this.onEnvironment())
        this.IconButton('workspace-search', $r('sys.symbol.magnifyingglass'),
          uiText(this.language, '搜索会话', 'Search chats'), () => {
            this.focusSearchOnLayout = true;
            this.onSearch();
          })
      }
      if (this.filterGroups.length > 0) {
        WorkspaceFilterButton({
          groups: this.filterGroups, customized: this.filterCustomized, dark: this.dark, language: this.language,
          onFilter: (key: string) => this.onFilter(key),
        })
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 4, right: 4 })
    .backgroundColor(workspaceHeaderColor(this.dark))
  }
}

@Component
export struct WorkspaceDock {
  @Prop selection: WorkspaceTab = 'threads';
  @Prop sharedTab: WorkspaceSharedTab = 'pullRequests';
  @Prop language: UiLanguage = 'zh';
  @Prop dark: boolean = false;
  onSelect: (selection: WorkspaceTab) => void = () => {};

  @Builder
  private Destination(tab: WorkspaceTab, label: string, icon: Resource) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Column({ space: 4 }) {
        Row() {
          SymbolGlyph(icon).fontSize(24).fontColor([workspaceForegroundColor(this.dark)])
        }
        .justifyContent(FlexAlign.Center)
        .width('88%')
        .constraintSize({ maxWidth: 64 })
        .height(32)
        .borderRadius(16)
        .backgroundColor(this.selection === tab ? (this.dark ? '#474747' : '#c0c0c0') : Color.Transparent)
        Text(label)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(workspaceForegroundColor(this.dark))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 2, right: 2 })
      }
      .width('100%')
    }
    .id(`workspace-tab-${tab}`)
    .layoutWeight(1)
    .height(80)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .accessibilityGroup(true)
    .accessibilityText(label)
    .accessibilitySelected(this.selection === tab)
    .onClick(() => this.onSelect(tab))
  }

  build() {
    Row() {
      this.Destination('threads', uiText(this.language, '会话', 'Chats'), $r('sys.symbol.message_on_message'))
      if (this.sharedTab === 'issues') {
        this.Destination('issues', uiText(this.language, '工单', 'Issues'), $r('sys.symbol.exclamationmark_circle'))
      } else {
        this.Destination('pullRequests', uiText(this.language, '拉取请求', 'Pulls'),
          $r('sys.symbol.point_bottomleft_forward_to_point_topright_scurvepath'))
      }
      this.Destination('usage', uiText(this.language, '用量', 'Usage'), $r('sys.symbol.histogram'))
      this.Destination('settings', uiText(this.language, '设置', 'Settings'), $r('sys.symbol.gearshape'))
    }
    .width('100%')
    .height(80)
    .backgroundColor(workspaceNavigationBarColor(this.dark))
    .accessibilityRole(AccessibilityRoleType.TAB_BAR)
  }
}

@Component
export struct WorkspaceComposeButton {
  @Prop expanded: boolean = true;
  @Prop dark: boolean = false;
  @Prop language: UiLanguage = 'zh';
  onCreate: () => void = () => {};

  build() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.square_and_pencil')).fontSize(24).fontColor([Color.White])
        if (this.expanded) {
          Text(uiText(this.language, '新建会话', 'New thread'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1)
        }
      }
      .justifyContent(FlexAlign.Center)
    }
    .id('workspace-new-thread')
    .width(this.expanded ? (this.language === 'zh' ? 122 : 142) : 56)
    .height(56)
    .padding({ left: 14, right: 14 })
    .borderRadius(16)
    .backgroundColor(workspaceAccentColor(this.dark))
    .shadow(ShadowStyle.OUTER_DEFAULT_SM)
    .animation({ duration: 160, curve: Curve.EaseOut })
    .accessibilityText(uiText(this.language, '新建会话', 'New thread'))
    .onClick(() => this.onCreate())
  }
}

@Component
export struct WorkspaceThreadSectionTitle {
  @Prop section: WorkspaceThreadSection = 'recent';
  @Prop dark: boolean = false;
  @Prop language: UiLanguage = 'zh';

  build() {
    Text(threadSectionLabel(this.section, this.language))
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 6 })
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(workspaceMutedColor(this.dark))
  }
}

@Component
export struct WorkspaceThreadShelf {
  @Prop section: WorkspaceThreadSection = 'working';
  @Prop count: number = 0;
  @Prop expanded: boolean = false;
  @Prop dark: boolean = false;
  @Prop language: UiLanguage = 'zh';
  onToggle: () => void = () => {};

  build() {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 8 }) {
        SymbolGlyph(this.expanded ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([workspaceMutedColor(this.dark)])
        Text(threadSectionLabel(this.section, this.language))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(workspaceForegroundColor(this.dark))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1)
        Text(this.count.toString())
          .fontSize(12)
          .fontColor(workspaceMutedColor(this.dark))
      }
      .width('100%')
    }
    .id(`workspace-thread-shelf-${this.section}`)
    .width('100%')
    .constraintSize({ minHeight: 44 })
    .padding({ left: 12, right: 12 })
    .borderRadius(12)
    .backgroundColor(workspaceHeaderColor(this.dark))
    .accessibilityGroup(true)
    .accessibilityText(`${threadSectionLabel(this.section, this.language)}, ${this.count}`)
    .accessibilityStateDescription(this.expanded ? uiText(this.language, '已展开', 'Expanded') :
      uiText(this.language, '已收起', 'Collapsed'))
    .onClick(() => this.onToggle())
  }
}

@Component
export struct WorkspaceThreadSwipeAction {
  @Prop label: string = '';
  @Prop icon: Resource = $r('sys.symbol.checkmark');
  @Prop dark: boolean = false;
  onAction: () => void = () => {};

  build() {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Column({ space: 3 }) {
        SymbolGlyph(this.icon).fontSize(20).fontColor([workspaceForegroundColor(this.dark)])
        Text(this.label)
          .fontSize(12)
          .fontColor(workspaceForegroundColor(this.dark))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width(68)
    .height('100%')
    .padding({ left: 6, right: 6 })
    .borderRadius(12)
    .backgroundColor(workspaceHeaderColor(this.dark))
    .accessibilityText(this.label)
    .onClick(() => this.onAction())
  }
}

@Component
export struct WorkspaceChatRow {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop snippet: string = '';
  @Prop timeLabel: string = '';
  @Prop status: WorkspaceThreadRowStatus = 'ready';
  @Prop unread: boolean = false;
  @Prop pinned: boolean = false;
  @Prop showProjectIcon: boolean = true;
  @Prop showActions: boolean = false;
  @Prop showActionButton: boolean = false;
  @Prop dark: boolean = false;
  @Prop language: UiLanguage = 'zh';
  onOpen: () => void = () => {};
  onActions: () => void = () => {};

  private statusText(): string {
    switch (this.status) {
      case 'approval': return uiText(this.language, '等待审批', 'Approval');
      case 'input': return uiText(this.language, '等待回答', 'Input needed');
      case 'request': return uiText(this.language, '待处理请求', 'Request');
      case 'failed': return uiText(this.language, '失败', 'Failed');
      case 'woke': return uiText(this.language, '稍后处理已到期', 'Woke');
      case 'working': return uiText(this.language, '进行中', 'Working');
      case 'waiting': return uiText(this.language, '等待中', 'Waiting');
      case 'snoozed': return uiText(this.language, '稍后处理', 'Snoozed');
      case 'settled': return uiText(this.language, '已完成', 'Settled');
      case 'archived': return uiText(this.language, '已归档', 'Archived');
      default: return '';
    }
  }

  private needsAttention(): boolean {
    return this.status === 'approval' || this.status === 'input' || this.status === 'request' ||
      this.status === 'failed' || this.status === 'woke';
  }

  private attentionColor(): string {
    return this.status === 'failed' ? (this.dark ? '#ff6467' : '#c10007') :
      (this.dark ? '#ffb900' : '#bb4d00');
  }

  private accessibilityActions(): AccessibilityCustomAction[] {
    return this.showActions ? [{
      name: uiText(this.language, '会话操作', 'Chat actions'),
      onAction: () => this.onActions(),
    }] : [];
  }

  @Builder
  private RowState() {
    Row({ space: 5 }) {
      if (this.pinned) {
        SymbolGlyph($r('sys.symbol.pin'))
          .fontSize(12)
          .fontColor([workspaceMutedColor(this.dark)])
      }
      if (this.needsAttention()) {
        Circle().width(7).height(7).fill(this.attentionColor())
      } else if (this.unread) {
        Circle().width(7).height(7).fill(this.dark ? '#729af8' : workspaceAccentColor(this.dark))
      } else if (this.status === 'working' || this.status === 'waiting' || this.status === 'snoozed') {
        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(13)
          .fontColor([workspaceMutedColor(this.dark)])
      }
      if (this.timeLabel) {
        Text(this.timeLabel)
          .fontSize(12)
          .fontColor(workspaceMutedColor(this.dark))
          .maxLines(1)
      }
    }
    .flexShrink(0)
  }

  build() {
    Row() {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 10 }) {
          if (this.showProjectIcon) {
            SymbolGlyph($r('sys.symbol.folder'))
              .fontSize(20)
              .fontColor([workspaceMutedColor(this.dark)])
          }
          Column({ space: 3 }) {
            Row({ space: 8 }) {
              Text(this.title)
                .layoutWeight(1)
                .fontSize(14)
                .lineHeight(21)
                .fontWeight(this.status === 'settled' ? FontWeight.Regular : FontWeight.Medium)
                .fontColor(this.status === 'settled' ? workspaceMutedColor(this.dark) : workspaceForegroundColor(this.dark))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              this.RowState()
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
            if (this.subtitle) {
              Text(this.subtitle)
                .width('100%')
                .fontSize(12)
                .lineHeight(16)
                .fontColor(workspaceMutedColor(this.dark))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            if (this.snippet) {
              Text(this.snippet)
                .width('100%')
                .fontSize(13)
                .fontColor(workspaceMutedColor(this.dark))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }
      .layoutWeight(1)
      .constraintSize({ minHeight: 57 })
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .borderRadius(13)
      .backgroundColor(Color.Transparent)
      .accessibilityGroup(true)
      .accessibilityText([this.title, this.subtitle, this.snippet, this.timeLabel].filter(Boolean).join(', '))
      .accessibilityStateDescription([
        this.statusText(), this.unread ? uiText(this.language, '未读', 'Unread') : '',
        this.pinned ? uiText(this.language, '已置顶', 'Pinned') : '',
      ].filter(Boolean).join(', '))
      .accessibilityDescription(this.showActions ? uiText(this.language, '长按打开会话操作', 'Touch and hold for chat actions') : '')
      .accessibilityCustomActions(this.accessibilityActions())
      .onClick(() => this.onOpen())
      .gesture(LongPressGesture().onAction(() => {
        if (this.showActions) this.onActions();
      }))
      if (this.showActions && this.showActionButton) {
        Button('⋯', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .width(48)
          .height(48)
          .accessibilityText(uiText(this.language, '会话操作', 'Chat actions'))
          .onClick(() => this.onActions())
      }
    }
    .width('100%')
  }
}
