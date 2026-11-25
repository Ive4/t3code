import { availableProjectActions, projectsOnShelf } from '../client/ProjectManagementProtocol';
import type {
  NativeManagedProject, ProjectManagementAction, ProjectManagementChange, ProjectManagementSnapshot,
} from '../client/ProjectManagementProtocol';

@Component
export struct ProjectManagementView {
  @Prop @Watch('resetEnvironment') environmentKey: string = '';
  @Prop environmentLabel: string = '';
  @Prop @Watch('back') backRequest: number = 0;
  @Prop @Watch('reloadAddedProject') addedProjectId: string = '';
  onBack: () => void = () => {};
  onAddProject: () => void = () => {};
  onLoad?: () => Promise<ProjectManagementSnapshot>;
  onChange?: (change: ProjectManagementChange) => Promise<NativeManagedProject>;
  onChanged: () => void = () => {};
  @State private snapshot: ProjectManagementSnapshot | undefined = undefined;
  @State private selectedId: string = '';
  @State private nameDraft: string = '';
  @State private loading: boolean = false;
  @State private saving: boolean = false;
  @State private error: string = '';
  private generation: number = 0;
  private pendingAddedProjectId: string = '';

  aboutToAppear(): void {
    this.resetEnvironment();
  }

  aboutToDisappear(): void {
    this.generation++;
  }

  private resetEnvironment(): void {
    this.generation++;
    this.snapshot = undefined;
    this.selectedId = '';
    this.nameDraft = '';
    this.pendingAddedProjectId = '';
    this.loading = false;
    this.saving = false;
    this.error = '';
    void this.load();
  }

  private reloadAddedProject(): void {
    if (!this.addedProjectId) return;
    this.pendingAddedProjectId = this.addedProjectId;
    void this.load();
  }

  private async load(): Promise<void> {
    const load = this.onLoad;
    if (!this.environmentKey || !load || this.loading || this.saving) return;
    const generation = this.generation;
    this.loading = true;
    this.error = '';
    try {
      const snapshot = await load();
      if (generation === this.generation) {
        this.snapshot = snapshot;
        const added = snapshot.projects.find((project) => project.id === this.pendingAddedProjectId);
        if (added) {
          this.pendingAddedProjectId = '';
          this.openProject(added);
        }
      }
    } catch (error) {
      if (generation === this.generation) this.error = (error as Error).message || '无法读取项目。';
    } finally {
      if (generation === this.generation) this.loading = false;
    }
  }

  private openProject(project: NativeManagedProject): void {
    this.selectedId = project.id;
    this.nameDraft = project.title;
    this.error = '';
  }

  private back(): void {
    if (this.saving) return;
    if (this.selectedId) {
      this.selectedId = '';
      this.error = '';
    } else {
      this.onBack();
    }
  }

  private selectedProject(): NativeManagedProject | undefined {
    return this.snapshot?.projects.find((project: NativeManagedProject) => project.id === this.selectedId);
  }

  private available(project: NativeManagedProject, action: ProjectManagementAction): boolean {
    return availableProjectActions(project, this.snapshot?.canOperate === true, this.snapshot?.canOrganize === true)
      .includes(action);
  }

  private async change(action: ProjectManagementAction, value?: string): Promise<void> {
    const snapshot = this.snapshot;
    const change = this.onChange;
    if (!snapshot?.canOperate || !change || this.loading || this.saving || action === 'add') return;
    const selected = this.selectedProject();
    if (!selected || !this.available(selected, action)) return;
    if (action === 'rename' && (!value?.trim() || value.trim() === selected.title)) return;
    const generation = this.generation;
    this.saving = true;
    this.error = '';
    try {
      const project = await change({ action, projectId: selected.id, value });
      if (generation !== this.generation) return;
      const projects = snapshot.projects.map((entry: NativeManagedProject) => entry.id === project.id ? project : entry);
      if (!projects.some((entry: NativeManagedProject) => entry.id === project.id)) projects.push(project);
      this.snapshot = { projects, canOperate: snapshot.canOperate, canOrganize: snapshot.canOrganize };
      if (action === 'rename') {
        this.nameDraft = project.title;
      }
      this.onChanged();
    } catch (error) {
      if (generation === this.generation) this.error = (error as Error).message || '无法更新项目。';
    } finally {
      if (generation === this.generation) this.saving = false;
    }
  }

  @Builder
  private ProjectRow(project: NativeManagedProject) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text(project.title)
            .fontSize(16)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(project.workspaceRoot)
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        if (project.pinned) {
          Text('已置顶').fontSize(13).fontColor($r('sys.color.font_secondary'))
        }
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('sys.color.icon_secondary')])
      }
      .width('100%')
      .padding(12)
    }
    .width('100%')
    .height('auto')
    .constraintSize({ minHeight: 56 })
    .borderRadius(16)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .enabled(!this.loading)
    .accessibilityText(project.title + '，' + project.workspaceRoot + (project.pinned ? '，已置顶' : ''))
    .onClick(() => this.openProject(project))
  }

  @Builder
  private ProjectShelf(title: string, projects: NativeManagedProject[]) {
    if (projects.length > 0) {
      Column({ space: 8 }) {
        Text(title).fontSize(14).fontColor($r('sys.color.font_secondary'))
        ForEach(projects, (project: NativeManagedProject) => {
          this.ProjectRow(project)
        }, (project: NativeManagedProject) => JSON.stringify(project))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  private ProjectList(snapshot: ProjectManagementSnapshot) {
    if (snapshot.canOperate) {
      Button('添加项目', { buttonStyle: ButtonStyleMode.TEXTUAL })
        .id('project-management-add-project')
        .height(44)
        .enabled(!this.loading)
        .onClick(this.onAddProject)
    } else {
      Text('此连接只有项目读取权限。').fontSize(14).fontColor($r('sys.color.font_secondary'))
    }
    if (snapshot.projects.length === 0) {
      Text('此环境还没有项目。').fontSize(14).fontColor($r('sys.color.font_secondary'))
    }
    this.ProjectShelf('未归档', projectsOnShelf(snapshot.projects, false))
    this.ProjectShelf('已归档', projectsOnShelf(snapshot.projects, true))
  }

  @Builder
  private ProjectDetails(project?: NativeManagedProject) {
    if (project) {
      Text(project.title).fontSize(22).fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
      Text(project.workspaceRoot).fontSize(14).fontColor($r('sys.color.font_secondary'))
        .copyOption(CopyOptions.LocalDevice)
      if (this.available(project, 'rename')) {
        Row({ space: 8 }) {
          TextInput({ text: this.nameDraft, placeholder: '项目名称' })
            .height(44)
            .layoutWeight(1)
            .accessibilityText('项目名称')
            .enabled(!this.saving)
            .onChange((value: string) => { this.nameDraft = value; })
            .onSubmit(() => { void this.change('rename', this.nameDraft); })
          Button('保存')
            .height(44)
            .enabled(!this.saving && !!this.nameDraft.trim() && this.nameDraft.trim() !== project.title)
            .onClick(() => { void this.change('rename', this.nameDraft); })
        }
        .width('100%')
      }
      if (this.available(project, 'pin') || this.available(project, 'unpin')) {
        Button(project.pinned ? '取消置顶' : '置顶项目', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(44)
          .enabled(!this.saving)
          .onClick(() => { void this.change(project.pinned ? 'unpin' : 'pin'); })
      }
      if (this.available(project, 'archive') || this.available(project, 'restore')) {
        Button(project.archived ? '取消归档' : '归档项目', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(44)
          .enabled(!this.saving)
          .onClick(() => { void this.change(project.archived ? 'restore' : 'archive'); })
        Text('归档会从项目选择器隐藏项目，并保留会话与文件。')
          .fontSize(14).fontColor($r('sys.color.font_secondary'))
      }
    }
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button('返回', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(44)
          .enabled(!this.saving)
          .onClick(() => this.back())
        Column({ space: 2 }) {
          Text(this.selectedId ? '项目详情' : '项目')
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
          if (this.environmentLabel) {
            Text(this.environmentLabel)
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        if (this.environmentKey && !this.selectedId) {
          Button('刷新', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .height(44)
            .enabled(!this.loading)
            .onClick(() => { void this.load(); })
        }
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 12 })

      Scroll() {
        Column({ space: 14 }) {
          if (!this.environmentKey) {
            Text('连接环境后即可管理项目。').fontSize(14).fontColor($r('sys.color.font_secondary'))
          } else if (this.selectedId) {
            this.ProjectDetails(this.selectedProject())
          } else if (this.snapshot) {
            this.ProjectList(this.snapshot)
          }
          if (this.loading || this.saving) {
            LoadingProgress().width(22).height(22)
              .accessibilityText(this.saving ? '正在更新项目' : '正在加载项目')
          }
          if (this.error) {
            Text(this.error).fontSize(14).fontColor($r('sys.color.font_primary'))
          }
        }
        .width('100%')
        .padding(20)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
    }
    .width('100%')
    .layoutWeight(1)
  }
}
