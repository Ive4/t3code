import type { EnvironmentSummary } from '../client/EnvironmentStore';
import type { ThreadLaunchProject } from '../client/ThreadLaunchProtocol';
import { UiLanguage, uiText } from './UiLanguage';
import { workspaceForegroundColor, workspaceGroupedCardColor, workspaceHeaderColor, workspaceMutedColor, workspaceSurfaceColor } from './WorkspaceChrome';

const PROJECT_SEARCH_ID = 'thread-launch-project-search';

interface PickerRowContent {
  id: string;
  title: string;
  detail?: string;
  icon: Resource;
  selected?: boolean;
  chevron?: boolean;
  disabled?: boolean;
  selectionRole?: AccessibilityRoleType;
  shortRow?: boolean;
}

@Component
struct PickerIconButton {
  @Prop buttonId: string = '';
  @Prop icon: Resource = $r('sys.symbol.arrow_left');
  @Prop label: string = '';
  @Prop isEnabled: boolean = true;
  @Prop dark: boolean = false;
  onPress: () => void = () => {};

  build() {
    Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      SymbolGlyph(this.icon).fontSize(24).fontColor([workspaceForegroundColor(this.dark)])
    }
    .id(this.buttonId)
    .width(48)
    .height(48)
    .padding(0)
    .enabled(this.isEnabled)
    .accessibilityText(this.label)
    .onClick(this.onPress)
  }
}

@Component
struct PickerRow {
  @Prop item: PickerRowContent = { id: '', title: '', icon: $r('sys.symbol.folder') };
  @Prop language: UiLanguage = 'zh';
  @Prop dark: boolean = false;
  onPress: () => void = () => {};

  build() {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 16 }) {
        SymbolGlyph(this.item.icon).fontSize(24).fontColor([workspaceMutedColor(this.dark)])
        Column({ space: 4 }) {
          Text(this.item.title)
            .fontSize(16).fontColor(workspaceForegroundColor(this.dark))
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.item.detail) {
            Text(this.item.detail)
              .fontSize(13).fontColor(workspaceMutedColor(this.dark))
              .maxLines(1).ellipsisMode(EllipsisMode.CENTER).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (this.item.selected) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(20).fontColor([this.dark ? '#729af8' : '#1b4ed8'])
        } else if (this.item.chevron && !this.item.disabled) {
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([workspaceMutedColor(this.dark)])
        }
      }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
    }
    .id(this.item.id)
    .width('100%')
    .height('auto')
    .constraintSize({ minHeight: this.item.shortRow ? 64 : this.item.detail ? 72 : 56 })
    .padding(0)
    .borderRadius(0)
    .enabled(!this.item.disabled)
    .accessibilityGroup(true)
    .accessibilityRole(this.item.selectionRole ?? AccessibilityRoleType.BUTTON)
    .accessibilityText(this.item.title + (this.item.detail ? ', ' + this.item.detail : ''))
    .accessibilitySelected(this.item.selected === true)
    .accessibilityStateDescription(this.item.selected ? uiText(this.language, '已选择', 'Selected') : '')
    .onClick(this.onPress)
  }
}

@Component
struct PickerHeader {
  @Prop title: string = '';
  @Prop backId: string = '';
  @Prop language: UiLanguage = 'zh';
  @Prop dark: boolean = false;
  onBack: () => void = () => {};

  build() {
    Row({ space: 4 }) {
      PickerIconButton({
        buttonId: this.backId, label: uiText(this.language, '返回', 'Back'), dark: this.dark, onPress: this.onBack,
      })
      Text(this.title).fontSize(21).fontWeight(FontWeight.Medium)
        .fontColor(workspaceForegroundColor(this.dark)).layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }.height(56).width('100%').padding({ left: 4, right: 4 })
  }
}

@Component
struct PickerSurface {
  @Prop dark: boolean = false;
  @BuilderParam content: () => void;

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor(workspaceSurfaceColor(this.dark))
    .borderRadius({ topLeft: 28, topRight: 28 })
    .clip(true)
  }
}

@Component
export struct ThreadLaunchProjectPicker {
  @Prop projects: ThreadLaunchProject[] = [];
  @Prop selectedProjectId: string = '';
  @Prop offersScratch: boolean = false;
  @Prop loading: boolean = false;
  @Prop error: string = '';
  @Prop disabled: boolean = false;
  @Prop query: string = '';
  @Prop searchOpen: boolean = false;
  @Prop language: UiLanguage = 'zh';
  @Prop dark: boolean = false;
  onBack: () => void = () => {};
  onRetry: () => void = () => {};
  onSelectProject: (index: number) => void = () => {};
  onAddProject: () => void = () => {};
  onQuery: (query: string) => void = () => {};
  onOpenSearch: () => void = () => {};
  onCloseSearch: () => void = () => {};
  private searchController: TextInputController = new TextInputController();
  private focusSearchOnLayout: boolean = false;

  private copy(zh: string, en: string): string {
    return uiText(this.language, zh, en);
  }

  private visibleProjects(): ThreadLaunchProject[] {
    const query = this.query.trim().toLowerCase();
    if (!query) return this.projects;
    return this.projects.filter((project) =>
      project.title.toLowerCase().includes(query) || project.workspaceRoot.toLowerCase().includes(query));
  }

  private chooseProject(project: ThreadLaunchProject): void {
    const index = this.projects.findIndex((entry) => entry.id === project.id);
    if (index >= 0) this.onSelectProject(index);
  }

  @Builder
  private Header() {
    Row({ space: 4 }) {
      if (this.searchOpen || this.query.length > 0) {
        PickerIconButton({
          buttonId: 'thread-launch-project-search-close',
          label: this.copy('关闭搜索', 'Close search'),
          dark: this.dark,
          onPress: () => {
            this.searchController.stopEditing();
            this.onCloseSearch();
          },
        })
        TextInput({ text: this.query, placeholder: this.copy('搜索项目', 'Search projects'), controller: this.searchController })
          .id(PROJECT_SEARCH_ID)
          .accessibilityText(this.copy('搜索项目', 'Search projects'))
          .height(44)
          .layoutWeight(1)
          .borderRadius(22)
          .padding({ left: 12, right: 12 })
          .backgroundColor(this.dark ? '#292929' : '#eaeaeb')
          .fontSize(16)
          .fontColor(workspaceForegroundColor(this.dark))
          .placeholderColor(workspaceMutedColor(this.dark))
          .enterKeyType(EnterKeyType.Search)
          .onChange((query: string) => this.onQuery(query))
          .onAreaChange(() => {
            if (this.focusSearchOnLayout && focusControl.requestFocus(PROJECT_SEARCH_ID)) {
              this.focusSearchOnLayout = false;
            }
          })
      } else {
        PickerIconButton({
          buttonId: 'thread-launch-project-back', label: this.copy('返回', 'Back'), dark: this.dark, onPress: this.onBack,
        })
        Text(this.copy('选择项目', 'Choose project')).fontSize(21).fontWeight(FontWeight.Medium)
          .fontColor(workspaceForegroundColor(this.dark)).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        PickerIconButton({
          buttonId: 'thread-launch-project-search-open',
          icon: $r('sys.symbol.magnifyingglass'),
          label: this.copy('搜索项目', 'Search projects'),
          dark: this.dark,
          onPress: () => {
            this.focusSearchOnLayout = true;
            this.onOpenSearch();
          },
        })
        if (!this.loading && this.projects.length > 0) {
          PickerIconButton({
            buttonId: 'thread-launch-add-project',
            icon: $r('sys.symbol.plus'),
            label: this.copy('添加项目', 'Add project'),
            dark: this.dark,
            isEnabled: !this.disabled,
            onPress: this.onAddProject,
          })
        }
      }
    }.width('100%').height(56).padding({ left: 4, right: 4 })
  }

  @Builder
  private EmptyState(title: string, detail: string = '') {
    Column({ space: 8 }) {
      Text(title).fontSize(18).fontWeight(FontWeight.Bold)
        .fontColor(workspaceForegroundColor(this.dark)).textAlign(TextAlign.Center)
      if (detail) {
        Text(detail).fontSize(14).fontColor(workspaceMutedColor(this.dark)).textAlign(TextAlign.Center)
      }
    }.width('100%').alignItems(HorizontalAlign.Center)
  }

  @Builder
  private ScratchRow() {
    PickerRow({
      item: {
        id: 'thread-launch-no-project',
        title: this.copy('无项目', 'No project'),
        detail: this.copy('开始不关联项目的会话', 'Start a task without a project'),
        icon: $r('sys.symbol.message_on_message'),
        chevron: true,
        disabled: this.disabled,
      },
      language: this.language,
      dark: this.dark,
      onPress: () => this.onSelectProject(-1),
    })
  }

  @Builder
  private RetryButton(textual: boolean) {
    Button(this.copy('重试', 'Try again'), {
      buttonStyle: textual ? ButtonStyleMode.TEXTUAL : ButtonStyleMode.NORMAL,
    })
      .id('thread-launch-project-retry')
      .enabled(!this.disabled)
      .onClick(this.onRetry)
  }

  @Builder
  private Content() {
    if (this.loading) {
      Column({ space: 12 }) {
        LoadingProgress().width(26).height(26).accessibilityLevel('no')
        Text(this.copy('正在加载项目…', 'Loading projects…')).fontSize(15).fontColor(workspaceMutedColor(this.dark))
      }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
    } else if (this.error && this.projects.length === 0) {
      Column({ space: 12 }) {
        this.EmptyState(this.copy('无法加载项目', 'Could not load projects'), this.error)
        this.RetryButton(false)
      }.width('100%').layoutWeight(1).padding(24).justifyContent(FlexAlign.Center)
    } else if (this.projects.length === 0) {
      Column({ space: 12 }) {
        this.EmptyState(this.copy('没有找到项目', 'No projects found'),
          this.copy('当前环境还没有项目。', 'The connected environment did not report any projects.'))
        Button(this.copy('添加新项目', 'Add new project'))
          .id('thread-launch-add-project').enabled(!this.disabled).onClick(this.onAddProject)
        if (this.offersScratch) {
          Button(this.copy('无项目开始', 'Start without a project'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .id('thread-launch-no-project').enabled(!this.disabled).onClick(() => this.onSelectProject(-1))
        }
      }.width('100%').layoutWeight(1).padding(24).justifyContent(FlexAlign.Center)
    } else {
      Scroll() {
        Column({ space: 8 }) {
          if (this.error) {
            Text(this.error).fontSize(14).fontColor(workspaceMutedColor(this.dark)).width('100%')
            this.RetryButton(true)
          }
          if (this.offersScratch) {
            Column() { this.ScratchRow() }
              .width('100%').backgroundColor(workspaceGroupedCardColor(this.dark)).borderRadius(28).clip(true)
          }
          if (this.visibleProjects().length === 0) {
            Column() {
              this.EmptyState(this.copy('没有匹配的项目', 'No matching projects'),
                this.copy('试试其他项目名称或工作区路径。', 'Try a different project name or workspace path.'))
            }.width('100%').padding({ left: 24, right: 24, top: 32, bottom: 32 })
          } else {
            Column() {
              ForEach(this.visibleProjects(), (project: ThreadLaunchProject) => {
                PickerRow({
                  item: {
                    id: 'thread-launch-project-' + project.id,
                    title: project.title,
                    detail: project.workspaceRoot,
                    icon: $r('sys.symbol.folder'),
                    selected: project.id === this.selectedProjectId,
                    chevron: true,
                    disabled: this.disabled,
                  },
                  language: this.language,
                  dark: this.dark,
                  onPress: () => this.chooseProject(project),
                })
              }, (project: ThreadLaunchProject) => project.id)
            }.width('100%').backgroundColor(workspaceGroupedCardColor(this.dark)).borderRadius(28).clip(true)
          }
        }.width('100%').padding({ left: 16, right: 16, top: 16, bottom: 32 })
      }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)
    }
  }

  build() {
    Column() {
      this.Header()
      PickerSurface({ dark: this.dark, content: () => { this.Content() } })
    }.width('100%').layoutWeight(1).backgroundColor(workspaceHeaderColor(this.dark))
  }
}

@Component
export struct ThreadLaunchEnvironmentPicker {
  @Prop environments: EnvironmentSummary[] = [];
  @Prop activeEnvironmentKey: string = '';
  @Prop language: UiLanguage = 'zh';
  @Prop dark: boolean = false;
  onBack: () => void = () => {};

  private visibleEnvironments(): EnvironmentSummary[] {
    const environments = new Map<string, EnvironmentSummary>();
    for (const environment of this.environments) {
      const previous = environments.get(environment.environmentId);
      if (!previous || environment.key === this.activeEnvironmentKey ||
        (previous.key !== this.activeEnvironmentKey && !previous.enabled && environment.enabled)) {
        environments.set(environment.environmentId, environment);
      }
    }
    return Array.from(environments.values());
  }

  private environmentDescription(environment: EnvironmentSummary): string {
    if (!environment.enabled) return uiText(this.language, '已停用', 'Disabled');
    return environment.managed ? 'T3 Connect' : uiText(this.language, '直连', 'Direct connection');
  }

  @Builder
  private Content() {
    if (this.environments.length === 0) {
      Column() {
        Text(uiText(this.language, '暂无可用环境', 'No environments available'))
          .fontSize(14).fontColor(workspaceMutedColor(this.dark)).textAlign(TextAlign.Center)
      }.width('100%').layoutWeight(1).padding(24).justifyContent(FlexAlign.Center)
    } else {
      Scroll() {
        Column({ space: 10 }) {
          Column() {
            ForEach(this.visibleEnvironments(), (environment: EnvironmentSummary, index: number) => {
              if (index > 0) Divider().color(this.dark ? '#303030' : '#e4e4e7')
              PickerRow({
                item: {
                  id: 'thread-launch-environment-' + environment.key,
                  title: environment.label,
                  detail: this.environmentDescription(environment),
                  icon: $r('sys.symbol.computer'),
                  selected: environment.key === this.activeEnvironmentKey,
                  disabled: !environment.enabled || environment.key !== this.activeEnvironmentKey,
                  selectionRole: AccessibilityRoleType.RADIO,
                  shortRow: true,
                },
                language: this.language,
                dark: this.dark,
                onPress: this.onBack,
              })
            }, (environment: EnvironmentSummary) => environment.key)
          }.width('100%').backgroundColor(workspaceGroupedCardColor(this.dark)).borderRadius(28).clip(true)
          if (this.visibleEnvironments().length > 1) {
            Text(uiText(this.language, '要使用其他环境，请在工作区切换后新建会话。',
              'To use another environment, switch to it in the workspace before starting a chat.'))
              .fontSize(13).fontColor(workspaceMutedColor(this.dark)).padding({ left: 8, right: 8 })
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 16, right: 16, top: 16, bottom: 32 })
      }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)
    }
  }

  build() {
    Column() {
      PickerHeader({
        title: uiText(this.language, '环境', 'Environment'), backId: 'thread-launch-environment-back',
        language: this.language, dark: this.dark, onBack: this.onBack,
      })
      PickerSurface({ dark: this.dark, content: () => { this.Content() } })
    }.width('100%').layoutWeight(1).backgroundColor(workspaceHeaderColor(this.dark))
  }
}

@Component
export struct ThreadLaunchRepositoryPicker {
  @Prop project: ThreadLaunchProject | undefined = undefined;
  @Prop projectHasGit: boolean = false;
  @Prop language: UiLanguage = 'zh';
  @Prop dark: boolean = false;
  onBack: () => void = () => {};

  private repositoryName(): string {
    const parts = this.project?.workspaceRoot.split(/[\\/]/).filter((part) => part.length > 0) ?? [];
    return parts[parts.length - 1] ?? this.project?.title ?? '';
  }

  @Builder
  private Content() {
    if (this.project && this.projectHasGit) {
      Column({ space: 10 }) {
        Text(uiText(this.language, '此会话使用当前工作区。', 'This chat uses the current workspace.'))
          .fontSize(14).fontColor(workspaceMutedColor(this.dark)).padding({ left: 8, right: 8 })
        Column() {
          PickerRow({
            item: {
              id: 'thread-launch-repository-current',
              title: this.repositoryName(),
              detail: this.project.workspaceRoot,
              icon: $r('sys.symbol.folder'),
              selected: true,
              disabled: true,
              selectionRole: AccessibilityRoleType.CHECKBOX,
            },
            language: this.language,
            dark: this.dark,
          })
        }.width('100%').backgroundColor(workspaceGroupedCardColor(this.dark)).borderRadius(28).clip(true)
      }.width('100%').layoutWeight(1).alignItems(HorizontalAlign.Start).padding({
        left: 16, right: 16, top: 16, bottom: 32,
      })
    } else {
      Column() {
        Text(uiText(this.language, '此项目没有跟踪任何仓库。', 'This project tracks no repositories'))
          .fontSize(14).fontColor(workspaceMutedColor(this.dark)).textAlign(TextAlign.Center)
      }.width('100%').layoutWeight(1).padding(24).justifyContent(FlexAlign.Center)
    }
  }

  build() {
    Column() {
      PickerHeader({
        title: uiText(this.language, '仓库', 'Repositories'), backId: 'thread-launch-repositories-back',
        language: this.language, dark: this.dark, onBack: this.onBack,
      })
      PickerSurface({ dark: this.dark, content: () => { this.Content() } })
    }.width('100%').layoutWeight(1).backgroundColor(workspaceHeaderColor(this.dark))
  }
}
