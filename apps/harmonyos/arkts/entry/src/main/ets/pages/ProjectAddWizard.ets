import type { UiLanguage } from './UiLanguage';
import { uiText } from './UiLanguage';
import { workspaceForegroundColor, workspaceHeaderColor, workspaceMutedColor, workspaceSurfaceColor } from './WorkspaceChrome';
import { WorkspaceSettingsRows } from './WorkspaceSettingsRows';
import type { SettingsRowContent } from './WorkspaceSettingsRows';
import type { NativeProjectFolder, NativeProjectFolderListing } from '../client/ProjectManagementProtocol';

type ProjectAddPage = 'source' | 'new' | 'local' | 'repository' | 'destination';

interface BrowseAttempt {
  path: string;
  select: boolean;
}

type ProjectAddPageTitle = [string, string];

const PAGE_TITLES: Record<ProjectAddPage, ProjectAddPageTitle> = {
  'source': ['添加项目', 'Add project'],
  'new': ['新建项目', 'New project'],
  'local': ['本地目录', 'Local folder'],
  'repository': ['Git URL', 'Git URL'],
  'destination': ['克隆目标目录', 'Clone destination'],
};

@Component
export struct ProjectAddWizard {
  @Prop language: UiLanguage = 'zh';
  @Prop dark: boolean = false;
  @Prop environmentLabel: string = '';
  @Prop canAddFolder: boolean = false;
  @Prop busy: boolean = false;
  @Prop error: string = '';
  @Prop @Watch('handleBackRequest') backRequest: number = 0;
  onBack: () => void = () => {};
  onAddFolder: (folder: string) => void = () => {};
  onBrowseFolders?: (path: string) => Promise<NativeProjectFolderListing>;

  @State private page: ProjectAddPage = 'source';
  @State private name: string = '';
  @State private folder: string = '';
  @State private repository: string = '';
  @State private destination: string = '';
  @State private submittedFolder: string = '';
  @State private browseListing: NativeProjectFolderListing | undefined = undefined;
  @State private browseLoading: boolean = false;
  @State private browseError: string = '';
  private browseGeneration: number = 0;
  private failedBrowse: BrowseAttempt | undefined = undefined;

  private copy(zh: string, en: string): string {
    return uiText(this.language, zh, en);
  }

  aboutToDisappear(): void {
    this.browseGeneration++;
  }

  private handleBackRequest(): void {
    this.back();
  }

  private back(): void {
    if (this.busy) return;
    this.resetBrowse();
    if (this.page === 'source') this.onBack();
    else this.page = this.page === 'destination' ? 'repository' : 'source';
  }

  private canSubmitFolder(): boolean {
    return this.canAddFolder && !this.busy && !this.browseLoading && this.folder.trim().length > 0;
  }

  private submitFolder(): void {
    if (!this.canSubmitFolder()) return;
    this.submittedFolder = this.folder.trim();
    this.onAddFolder(this.submittedFolder);
  }

  private canContinueToDestination(): boolean {
    return this.repository.trim().length > 0 && !this.busy;
  }

  private continueToDestination(): void {
    if (!this.canContinueToDestination()) return;
    this.page = 'destination';
    void this.browse(this.destination.trim() || '~', false);
  }

  private resetBrowse(): void {
    this.browseGeneration++;
    this.browseListing = undefined;
    this.browseLoading = false;
    this.browseError = '';
    this.failedBrowse = undefined;
  }

  private currentPath(): string {
    return this.page === 'destination' ? this.destination : this.folder;
  }

  private changePath(path: string): void {
    if (path === this.currentPath()) return;
    this.resetBrowse();
    if (this.page === 'destination') this.destination = path;
    else this.folder = path;
  }

  private directoryQuery(path: string): string {
    if (path === '~' || /[/\\]$/.test(path)) return path;
    return path + (/^[a-z]:|^[\\/]{2}/i.test(path) ? '\\' : '/');
  }

  private async browse(path: string, select: boolean): Promise<void> {
    const load = this.onBrowseFolders;
    if (!load || this.busy) return;
    const page = this.page;
    this.resetBrowse();
    const generation = this.browseGeneration;
    this.browseLoading = true;
    try {
      const listing = await load(this.directoryQuery(path));
      if (generation !== this.browseGeneration || page !== this.page) return;
      this.browseListing = listing;
      if (select) {
        if (page === 'destination') this.destination = listing.parentPath;
        else this.folder = listing.parentPath;
      }
    } catch (error) {
      if (generation === this.browseGeneration && page === this.page) {
        this.browseError = (error as Error).message || this.copy('无法读取目录。', 'Could not read the folder.');
        this.failedBrowse = { path, select };
      }
    } finally {
      if (generation === this.browseGeneration) this.browseLoading = false;
    }
  }

  private browseCurrent(): void {
    const failed = this.failedBrowse;
    if (failed) {
      void this.browse(failed.path, failed.select);
      return;
    }
    const path = this.currentPath().trim();
    void this.browse(path || '~', !!path);
  }

  private selectFolder(path: string): void {
    void this.browse(path, true);
  }

  private folderRows(listing: NativeProjectFolderListing): SettingsRowContent[] {
    const rows: SettingsRowContent[] = [];
    if (!/^(?:[/\\]|[a-z]:[/\\]|[/\\]{2}[^/\\]+[/\\][^/\\]+[/\\]?)$/i.test(listing.parentPath)) {
      rows.push({ id: 'project-add-folder-parent', label: this.copy('上一级', 'Parent folder'),
        icon: $r('sys.symbol.arrow_up'), kind: 'link', disabled: this.busy });
    }
    for (const entry of listing.entries) {
      if (entry.name.startsWith('.')) continue;
      rows.push({ id: 'project-add-folder-entry:' + entry.fullPath, label: entry.name,
        icon: $r('sys.symbol.folder'), kind: 'link', disabled: this.busy });
    }
    return rows;
  }

  private selectFolderRow(row: SettingsRowContent): void {
    const listing = this.browseListing;
    if (!listing || this.busy) return;
    if (row.id === 'project-add-folder-parent') {
      const path = this.directoryQuery(listing.parentPath);
      this.selectFolder(path + '..' + path[path.length - 1]);
      return;
    }
    const folder = listing.entries.find((entry: NativeProjectFolder) =>
      row.id === 'project-add-folder-entry:' + entry.fullPath);
    if (folder) this.selectFolder(folder.fullPath);
  }

  private sources(): SettingsRowContent[] {
    return [
      { id: 'project-add-source-new', label: this.copy('新建项目', 'New project'),
        detail: this.copy('按名称创建 Git 仓库', 'Start a new Git repository from a name'),
        icon: $r('sys.symbol.plus'), kind: 'link', disabled: this.busy },
      { id: 'project-add-source-local', label: this.copy('本地目录', 'Local folder'),
        detail: this.canAddFolder ? this.copy('浏览磁盘上的目录', 'Browse a folder on disk')
          : this.copy('此连接没有添加项目的权限。', 'This connection cannot add projects.'),
        icon: $r('sys.symbol.folder_badge_plus'), kind: 'link', disabled: !this.canAddFolder || this.busy },
      { id: 'project-add-source-clone', label: 'Git URL',
        detail: this.copy('从远程 URL 克隆', 'Clone from a remote URL'),
        icon: $r('sys.symbol.link'), kind: 'link', disabled: this.busy },
    ];
  }

  private selectSource(id: string): void {
    if (this.busy) return;
    if (id === 'project-add-source-new') this.page = 'new';
    else if (id === 'project-add-source-local' && this.canAddFolder) {
      this.page = 'local';
      void this.browse(this.folder.trim() || '~', false);
    }
    else if (id === 'project-add-source-clone') this.page = 'repository';
  }

  private inputBackground(): string {
    return this.dark ? '#111111' : '#FFFFFF';
  }

  private inputBorder(): string {
    return this.dark ? '#1E1E1E' : '#D4D4D8';
  }

  private actionBackground(enabled: boolean): string {
    return enabled ? (this.dark ? '#346BF1' : '#1B4ED8') : (this.dark ? '#141414' : '#FAFAFA');
  }

  private actionText(enabled: boolean): string {
    return enabled ? '#FFFFFF' : workspaceMutedColor(this.dark);
  }

  @Builder
  private Header() {
    Row() {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        SymbolGlyph($r('sys.symbol.arrow_left')).fontSize(24).fontColor([workspaceForegroundColor(this.dark)])
      }
      .id('project-add-back')
      .width(48).height(48).padding(0)
      .backgroundColor(Color.Transparent)
      .accessibilityText(this.copy('返回', 'Back'))
      .enabled(!this.busy)
      .onClick(() => this.back())
      Column({ space: 2 }) {
        Text(this.copy(PAGE_TITLES[this.page][0], PAGE_TITLES[this.page][1]))
          .id('project-add-title')
          .fontSize(21).fontWeight(FontWeight.Medium).fontColor(workspaceForegroundColor(this.dark))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.environmentLabel) {
          Text(this.environmentLabel).fontSize(13).fontColor(workspaceMutedColor(this.dark))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').height(56).padding({ left: 4, right: 16 })
  }

  @Builder
  private NoEnvironment() {
    Column({ space: 12 }) {
      Text(this.copy('环境不可用', 'Environment unavailable'))
        .fontSize(18).fontWeight(FontWeight.Bold).fontColor(workspaceForegroundColor(this.dark))
        .textAlign(TextAlign.Center)
      Text(this.copy('启动或重新连接环境后即可添加项目。', 'Start or reconnect an environment before adding a project.'))
        .fontSize(14).lineHeight('19fp').fontColor(workspaceMutedColor(this.dark))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 32, bottom: 32 })
    .borderRadius(16)
    .backgroundColor(workspaceHeaderColor(this.dark))
  }

  @Builder
  private TextHint(value: string) {
    Text(value).fontSize(14).lineHeight('19fp').fontColor(workspaceMutedColor(this.dark)).width('100%')
  }

  @Builder
  private ErrorBanner(value: string) {
    Text(value)
      .fontSize(14).lineHeight('19fp').fontWeight(FontWeight.Medium)
      .fontColor(this.dark ? '#FF6467' : '#C10007')
      .backgroundColor(this.dark ? '#301214' : '#FCEBEC')
      .border({ width: 1, color: this.dark ? '#52FB414A' : '#52FB2C36', radius: 16 })
      .padding({ left: 14, right: 14, top: 12, bottom: 12 })
      .wordBreak(WordBreak.BREAK_WORD)
      .width('100%')
  }

  @Builder
  private FolderBrowser() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(this.copy('浏览目录', 'Browse folders')).fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor(this.dark ? '#4B7CF3' : '#1B4ED8').layoutWeight(1)
        if (this.onBrowseFolders) {
          Button(this.browseError ? this.copy('重试', 'Retry') : this.copy('浏览', 'Browse'),
            { buttonStyle: ButtonStyleMode.TEXTUAL })
            .id('project-add-browse').height(40).enabled(!this.browseLoading && !this.busy)
            .fontColor(this.dark ? '#4B7CF3' : '#1B4ED8')
            .backgroundColor(Color.Transparent)
            .onClick(() => this.browseCurrent())
        }
      }.width('100%').padding({ left: 16, right: 4 })
      if (!this.onBrowseFolders) {
        this.TextHint(this.copy('目录浏览暂不可用。请直接输入环境机器上的目录路径。',
          'Folder browsing is unavailable. Enter the path on the environment machine.'))
      } else if (this.browseLoading) {
        Row() {
          LoadingProgress().width(22).height(22).color(workspaceMutedColor(this.dark))
            .accessibilityText(this.copy('正在读取目录', 'Reading folders'))
        }
        .width('100%').height(56).justifyContent(FlexAlign.Center)
        .borderRadius(28).backgroundColor(workspaceHeaderColor(this.dark))
      } else if (this.browseError) {
        this.ErrorBanner(this.browseError)
      } else if (this.browseListing) {
        Text(this.browseListing.parentPath).fontSize(13).fontColor(workspaceMutedColor(this.dark))
          .padding({ left: 16, right: 16 }).width('100%')
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.browseListing.entries.every((entry: NativeProjectFolder) => entry.name.startsWith('.'))) {
          this.TextHint(this.copy('此处没有可浏览的目录。', 'There are no folders to browse here.'))
        }
        WorkspaceSettingsRows({ rows: this.folderRows(this.browseListing), dark: this.dark,
          onSelect: (row: SettingsRowContent) => this.selectFolderRow(row) })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private LocalFolder() {
    if (this.error && this.submittedFolder === this.folder.trim()) {
      this.ErrorBanner(this.error)
    }
    if (!this.canAddFolder) {
      this.ErrorBanner(this.copy('此连接没有添加项目的权限。', 'This connection cannot add projects.'))
    }
    TextInput({ text: this.folder, placeholder: '~/projects/my-app' })
      .id('project-add-folder')
      .width('100%').height(48).padding({ left: 16, right: 16 })
      .backgroundColor(this.inputBackground()).border({ width: 1, color: this.inputBorder(), radius: 24 })
      .fontSize(16).fontColor(workspaceForegroundColor(this.dark)).placeholderColor(workspaceMutedColor(this.dark))
      .accessibilityText(this.copy('目录路径', 'Folder path'))
      .enterKeyType(EnterKeyType.Done)
      .enabled(!this.busy && this.canAddFolder)
      .onChange((value: string) => this.changePath(value))
      .onSubmit(() => this.submitFolder())
    Button({ type: ButtonType.Capsule }) {
      Row({ space: 8 }) {
        if (this.busy) {
          LoadingProgress().width(18).height(18).color(workspaceMutedColor(this.dark))
        }
        Text(this.busy ? this.copy('正在添加…', 'Adding…') : this.copy('添加项目', 'Add project'))
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.actionText(this.canSubmitFolder()))
      }
    }
    .id('project-add-folder-submit')
    .width('100%').height(48).enabled(this.canSubmitFolder())
    .backgroundColor(this.actionBackground(this.canSubmitFolder()))
    .accessibilityText(this.busy ? this.copy('正在添加项目', 'Adding project') : this.copy('添加项目', 'Add project'))
    .onClick(() => this.submitFolder())
    this.FolderBrowser()
  }

  @Builder
  private NewProject() {
    TextInput({ text: this.name, placeholder: this.copy('项目名称', 'Project name') })
      .id('project-add-name')
      .width('100%').height(48).padding({ left: 16, right: 16 })
      .backgroundColor(this.inputBackground()).border({ width: 1, color: this.inputBorder(), radius: 24 })
      .fontSize(16).fontColor(workspaceForegroundColor(this.dark)).placeholderColor(workspaceMutedColor(this.dark))
      .accessibilityText(this.copy('项目名称', 'Project name'))
      .enterKeyType(EnterKeyType.Done)
      .enabled(!this.busy)
      .onChange((value: string) => { this.name = value; })
    Button(this.copy('创建项目', 'Create project'), { type: ButtonType.Capsule })
      .id('project-add-new-submit').width('100%').height(48).enabled(false)
      .fontSize(16).fontWeight(FontWeight.Medium)
      .backgroundColor(this.actionBackground(false)).fontColor(this.actionText(false))
    this.TextHint(this.copy('项目创建暂不可用。', 'Creating a project is unavailable.'))
    WorkspaceSettingsRows({
      rows: [{ id: 'project-add-existing', label: this.copy('添加已有项目', 'Add existing project'),
        detail: this.copy('打开目录或克隆仓库', 'Open a folder or clone a repository'),
        icon: $r('sys.symbol.folder_badge_plus'), kind: 'link', disabled: this.busy }],
      dark: this.dark,
      onSelect: () => this.back(),
    })
  }

  @Builder
  private Repository() {
    TextInput({ text: this.repository, placeholder: 'https://example.com/org/repo.git' })
      .id('project-add-repository')
      .width('100%').height(48).padding({ left: 16, right: 16 })
      .backgroundColor(this.inputBackground()).border({ width: 1, color: this.inputBorder(), radius: 24 })
      .fontSize(16).fontColor(workspaceForegroundColor(this.dark)).placeholderColor(workspaceMutedColor(this.dark))
      .type(InputType.URL).enterKeyType(EnterKeyType.Next)
      .accessibilityText('Git URL')
      .enabled(!this.busy)
      .onChange((value: string) => { this.repository = value; })
      .onSubmit(() => this.continueToDestination())
    Button(this.copy('继续', 'Continue'), { type: ButtonType.Capsule })
      .id('project-add-clone-continue').width('100%').height(48)
      .enabled(this.canContinueToDestination())
      .fontSize(16).fontWeight(FontWeight.Medium)
      .backgroundColor(this.actionBackground(this.canContinueToDestination()))
      .fontColor(this.actionText(this.canContinueToDestination()))
      .onClick(() => this.continueToDestination())
  }

  @Builder
  private Destination() {
    Text(this.repository.trim())
      .id('project-add-clone-url')
      .width('100%').fontSize(16).fontWeight(FontWeight.Bold).fontColor(workspaceForegroundColor(this.dark))
      .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .borderRadius(24).backgroundColor(workspaceHeaderColor(this.dark))
    TextInput({ text: this.destination, placeholder: '~/projects/my-app' })
      .id('project-add-destination')
      .width('100%').height(48).padding({ left: 16, right: 16 })
      .backgroundColor(this.inputBackground()).border({ width: 1, color: this.inputBorder(), radius: 24 })
      .fontSize(16).fontColor(workspaceForegroundColor(this.dark)).placeholderColor(workspaceMutedColor(this.dark))
      .accessibilityText(this.copy('目标目录路径', 'Destination folder path'))
      .enterKeyType(EnterKeyType.Done)
      .enabled(!this.busy)
      .onChange((value: string) => this.changePath(value))
    Button(this.copy('克隆项目', 'Clone project'), { type: ButtonType.Capsule })
      .id('project-add-clone-submit').width('100%').height(48).enabled(false)
      .fontSize(16).fontWeight(FontWeight.Medium)
      .backgroundColor(this.actionBackground(false)).fontColor(this.actionText(false))
    this.TextHint(this.copy('项目克隆暂不可用。', 'Cloning a project is unavailable.'))
    this.FolderBrowser()
  }

  build() {
    Column() {
      this.Header()
      Scroll() {
        Column({ space: 16 }) {
          if (this.page === 'source') {
            if (this.environmentLabel) {
              WorkspaceSettingsRows({ rows: this.sources(), dark: this.dark,
                onSelect: (item: SettingsRowContent) => this.selectSource(item.id) })
            } else {
              this.NoEnvironment()
            }
          } else if (this.page === 'local') {
            this.LocalFolder()
          } else if (this.page === 'new') {
            this.NewProject()
          } else if (this.page === 'repository') {
            this.Repository()
          } else if (this.page === 'destination') {
            this.Destination()
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
          .padding({ left: 16, right: 16, top: 16, bottom: 36 })
      }
      .width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)
      .backgroundColor(workspaceSurfaceColor(this.dark)).borderRadius({ topLeft: 28, topRight: 28 }).clip(true)
    }.width('100%').layoutWeight(1).backgroundColor(workspaceHeaderColor(this.dark))
  }
}
