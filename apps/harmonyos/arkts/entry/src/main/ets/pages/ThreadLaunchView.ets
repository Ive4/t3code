import {
  resolveThreadLaunchLocalWorkspace, ThreadLaunchLocalWorkspace, ThreadLaunchModel, ThreadLaunchOptions, ThreadLaunchProject, ThreadLaunchProvider,
  ThreadLaunchReadRefs, ThreadLaunchRuntimeMode, ThreadLaunchScratch, ThreadLaunchSelection, ThreadLaunchSwitchRef,
  ThreadLaunchWorkspaceStrategy, threadLaunchRuntimeModes, threadLaunchWorktree,
} from '../client/ThreadLaunchProtocol';
import { changeThreadModelOption, threadModelOptionDescriptors, threadModelSelectionForTarget,
  withThreadModelOptionDefaults } from '../client/ThreadModelOptionProtocol';
import type { ThreadModelOptionDescriptor, ThreadModelOptionSelection } from '../client/ThreadModelOptionProtocol';
import { modelCatalogVisibleModels } from '../client/ModelCatalogPreferences';
import type { PickedThreadAttachment } from '../client/ThreadAttachmentProtocol';
import type { NativeThreadGitRef } from '../client/ThreadGitProtocol';
import type { EnvironmentSummary } from '../client/EnvironmentStore';
import type { NativeThreadFile, NativeThreadFileDirectory, NativeThreadFileEntry } from '../client/ThreadFilesProtocol';
import { COMPOSER_COMMAND_CONTEXT_MAX_RECORDS, referencedComposerCommandContext } from '../client/ComposerCommandProtocol';
import type { ComposerCommandContextRecord, ComposerCommandTrigger } from '../client/ComposerCommandProtocol';
import type { NativeComposerScope } from '../client/ComposerCatalogProtocol';
import type { ThreadComposerSuggestion } from './ThreadComposerSuggestions';
import { ThreadDetailComposer } from './ThreadDetailComposer';
import { ThreadDetailFiles } from './ThreadDetailFiles';
import { ThreadModelParameterChoices, ThreadModelParameterRows } from './ThreadModelParameters';
import { ThreadLaunchEnvironmentPicker, ThreadLaunchProjectPicker, ThreadLaunchRepositoryPicker } from './ThreadLaunchPickers';
import { UiLanguage, uiText } from './UiLanguage';
import { workspaceForegroundColor, workspaceGroupedCardColor, workspaceHeaderColor, workspaceMutedColor, workspaceSurfaceColor } from './WorkspaceChrome';

type ThreadLaunchPane = 'projects' | 'draft' | 'environment' | 'branches' | 'repositories' | 'settings' | 'files';
const SHORT_DRAFT_VIEWPORT_HEIGHT = 380;

@Component
export struct ThreadLaunchView {
  @Prop language: UiLanguage = 'zh';
  @Prop dark: boolean = false;
  @Prop @Watch('resetOptions') options: ThreadLaunchOptions | undefined = undefined;
  @Prop loading: boolean = false;
  @Prop launching: boolean = false;
  @Prop error: string = '';
  @Prop attachments: PickedThreadAttachment[] = [];
  @Prop pickingAttachments: boolean = false;
  @Prop canWriteGit: boolean = false;
  @Prop canOpenScratch: boolean = false;
  @Prop canReadFiles: boolean = false;
  @Prop environments: EnvironmentSummary[] = [];
  @Prop activeEnvironmentKey: string = '';
  @Prop @Watch('navigateBack') backRequest: number = 0;
  @Prop @Watch('resetOptions') addedProjectId: string = '';
  onBack: () => void = () => {};
  onAddProject: () => void = () => {};
  onRetry: () => void = () => {};
  onPickAttachment: (photos: boolean) => void = () => {};
  onRemoveAttachment: (uri: string) => void = () => {};
  onRecallModelOptions: (selection: ThreadLaunchSelection) => ThreadModelOptionSelection[] | undefined = () => undefined;
  onRememberModelOptions: (selection: ThreadLaunchSelection) => void = () => {};
  onLaunch: (project: ThreadLaunchProject, model: ThreadLaunchSelection, text: string,
    mode: ThreadLaunchRuntimeMode, workspace: ThreadLaunchWorkspaceStrategy,
    records: ComposerCommandContextRecord[]) => void = () => {};
  onReadSuggestions?: (scope: NativeComposerScope, instanceId: string, trigger: ComposerCommandTrigger) =>
    Promise<ThreadComposerSuggestion[]>;
  onLoadRefs?: ThreadLaunchReadRefs;
  onSwitchRef?: ThreadLaunchSwitchRef;
  onOpenScratch?: (workspaceRoot: string) => Promise<ThreadLaunchScratch>;
  onLoadWorkspaceProviders?: (projectId: string, cwd: string) => Promise<ThreadLaunchProvider[]>;
  onListFiles?: (cwd: string, path: string) => Promise<NativeThreadFileDirectory>;
  onReadFile?: (cwd: string, path: string) => Promise<NativeThreadFile>;
  onSearchFiles?: (cwd: string, query: string) => Promise<NativeThreadFileDirectory>;
  @State private pane: ThreadLaunchPane = 'projects';
  @State private projectQuery: string = '';
  @State private projectSearchOpen: boolean = false;
  @State private selectedProjectId: string = '';
  @State private scratchSelected: boolean = false;
  @State private providerId: string = '';
  @State private modelSlug: string = '';
  @State private modelOptionSelections?: ThreadModelOptionSelection[] = undefined;
  @State private modelParameterId: string = '';
  @State private compactDraft: boolean = false;
  @State private text: string = '';
  @State private runtimeMode: ThreadLaunchRuntimeMode | undefined = undefined;
  @State private scratch: ThreadLaunchScratch | undefined = undefined;
  @State private workspaceProviders: ThreadLaunchProvider[] | undefined = undefined;
  @State private workspaceChanging: boolean = false;
  @State private workspaceError: string = '';
  @State private gitRepo: boolean = false;
  @State private newWorktree: boolean = false;
  @State private localWorkspace: ThreadLaunchLocalWorkspace = { type: 'root' };
  @State private baseRef: string | undefined = undefined;
  @State private startFromOrigin: boolean = true;
  @State private defaultRefs: NativeThreadGitRef[] = [];
  @State private branchRefs: NativeThreadGitRef[] = [];
  @State private nextBranchCursor: number | null = null;
  @State private branchQuery: string = '';
  @State private refsLoading: boolean = false;
  @State private refsError: string = '';
  @State private fileDirectory: NativeThreadFileDirectory | undefined = undefined;
  @State private directoryPath: string = '';
  @State private filePreview: NativeThreadFile | undefined = undefined;
  @State private fileTarget: string = '';
  @State private fileSearchOpen: boolean = false;
  @State private fileLoading: boolean = false;
  @State private fileError: string = '';
  private fileGeneration: number = 0;
  private projectGeneration: number = 0;
  private refsGeneration: number = 0;
  private appliedBranchQuery: string = '';
  private selectedWorkspaceRoot: string = '';
  private cachedScratchRoot: string = '';
  private appliedAddedProjectId: string = '';
  private projectPickerFromDraft: boolean = false;
  private leaving: boolean = false;
  private commandContexts: ComposerCommandContextRecord[] = [];

  private copy(chinese: string, english: string): string {
    return uiText(this.language, chinese, english);
  }

  private changeDraft(text: string): void {
    this.text = text;
    this.commandContexts = referencedComposerCommandContext(text, this.commandContexts);
  }

  private addCommandContext(record: ComposerCommandContextRecord): boolean {
    if (!this.composerScope()) return false;
    if (this.commandContexts.some((item: ComposerCommandContextRecord) => item.contextId === record.contextId)) return true;
    if (this.commandContexts.length >= COMPOSER_COMMAND_CONTEXT_MAX_RECORDS) {
      this.workspaceError = this.copy('上下文已满，请移除一些引用后重试。', 'Remove some context references and try again.');
      return false;
    }
    this.commandContexts.push(record);
    return true;
  }

  private composerScope(): NativeComposerScope | undefined {
    const project = this.project();
    if (!project || !this.controlsEnabled() || this.pane !== 'draft' || !this.activeEnvironmentKey) return undefined;
    return { environmentKey: this.activeEnvironmentKey, cwd: this.fileWorkspaceRoot(), projectId: project.id };
  }

  aboutToAppear(): void {
    this.resetOptions();
  }

  aboutToDisappear(): void {
    this.projectGeneration++;
    this.refsGeneration++;
    this.fileGeneration++;
  }

  private resetOptions(): void {
    if (!this.options) return;
    if (this.cachedScratchRoot !== this.options.scratchWorkspaceRoot) {
      this.scratch = undefined;
      this.cachedScratchRoot = '';
    }
    if (this.selectAddedProject()) return;
    if ((this.scratchSelected && this.selectedWorkspaceRoot !== this.options.scratchWorkspaceRoot) ||
      (this.selectedProjectId && !this.project())) {
      this.projectGeneration++;
      this.refsGeneration++;
      this.fileGeneration++;
      this.selectedProjectId = '';
      this.scratchSelected = false;
      this.workspaceChanging = false;
      this.pane = 'projects';
    } else if (this.selectedProjectId && this.project()?.workspaceRoot !== this.selectedWorkspaceRoot) {
      const index = this.options.projects.findIndex((project: ThreadLaunchProject) => project.id === this.selectedProjectId);
      if (index >= 0) this.beginProject(index);
    }
  }

  private selectAddedProject(): boolean {
    if (!this.addedProjectId || this.appliedAddedProjectId === this.addedProjectId) return false;
    const index = this.options?.projects.findIndex((project: ThreadLaunchProject) => project.id === this.addedProjectId) ?? -1;
    if (index < 0) return false;
    this.appliedAddedProjectId = this.addedProjectId;
    this.clearProjectSearch();
    this.beginProject(index);
    return true;
  }

  private offersScratch(): boolean {
    return this.canOpenScratch && !!this.options?.scratchWorkspaceRoot && this.onOpenScratch !== undefined;
  }

  private isScratchSelected(): boolean {
    return this.scratchSelected;
  }

  private project(): ThreadLaunchProject | undefined {
    if (this.scratchSelected) return this.scratch?.project;
    return this.options?.projects.find((project: ThreadLaunchProject) => project.id === this.selectedProjectId);
  }

  private providers(): ThreadLaunchProvider[] {
    const projectId = this.project()?.id;
    const providers = this.isScratchSelected() ? this.scratch?.providers : this.workspaceProviders ??
      (projectId ? this.options?.providers.filter((provider: ThreadLaunchProvider) => provider.projectIds.includes(projectId)) : []);
    return (providers ?? []).filter((provider: ThreadLaunchProvider) => this.launchModels(provider).length > 0);
  }

  private launchModels(provider: ThreadLaunchProvider): ThreadLaunchModel[] {
    return modelCatalogVisibleModels(provider.models, this.options?.modelCatalog, provider.instanceId, false, false,
      provider.instanceId === this.providerId ? this.modelSlug : '');
  }

  private provider(): ThreadLaunchProvider | undefined {
    const providers = this.providers();
    return providers.find((provider: ThreadLaunchProvider) => provider.instanceId === this.providerId) ?? providers[0];
  }

  private model(): ThreadLaunchModel | undefined {
    const provider = this.provider();
    if (!provider) return undefined;
    const models = this.launchModels(provider);
    return (provider.instanceId === this.providerId
      ? models.find((model: ThreadLaunchModel) => model.slug === this.modelSlug) : undefined) ??
      models.find((model: ThreadLaunchModel) => model.isDefault === true) ?? models[0];
  }

  private providerOptions(): SelectOption[] {
    return this.providers().map((provider: ThreadLaunchProvider): SelectOption => ({ value: provider.displayName }));
  }

  private modelOptions(): SelectOption[] {
    const provider = this.provider();
    return provider ? this.launchModels(provider).map((model: ThreadLaunchModel): SelectOption => ({ value: model.name })) : [];
  }

  private runtimeModes(): ThreadLaunchRuntimeMode[] {
    return threadLaunchRuntimeModes(this.model(), this.options?.maxRuntimeMode);
  }

  private selectedRuntimeMode(): ThreadLaunchRuntimeMode | undefined {
    const available = this.runtimeModes();
    const preferred = this.runtimeMode ?? this.options?.defaultRuntimeMode;
    return preferred && available.includes(preferred) ? preferred : available[0];
  }

  private beginProject(index: number): void {
    const project = index >= 0 ? this.options?.projects[index] : undefined;
    const scratch = index === -1 && this.offersScratch();
    if (!project && !scratch) return;
    this.pane = 'draft';
    this.projectPickerFromDraft = false;
    if (scratch ? this.scratchSelected && !!this.scratch : !this.scratchSelected &&
      project?.id === this.selectedProjectId && project?.workspaceRoot === this.selectedWorkspaceRoot) return;
    void this.selectProject(project, scratch);
  }

  private async selectProject(project: ThreadLaunchProject | undefined, scratch: boolean): Promise<void> {
    const generation = ++this.projectGeneration;
    this.refsGeneration++;
    this.fileGeneration++;
    this.selectedProjectId = project?.id ?? '';
    this.selectedWorkspaceRoot = scratch ? this.options?.scratchWorkspaceRoot ?? '' : project?.workspaceRoot ?? '';
    this.scratchSelected = scratch;
    this.workspaceChanging = false;
    this.workspaceError = '';
    this.workspaceProviders = undefined;
    this.providerId = '';
    this.modelSlug = '';
    this.modelOptionSelections = undefined;
    this.modelParameterId = '';
    this.localWorkspace = { type: 'root' };
    this.newWorktree = false;
    this.baseRef = undefined;
    this.startFromOrigin = this.project()?.startFromOrigin ?? true;
    this.gitRepo = false;
    this.defaultRefs = [];
    this.branchRefs = [];
    this.branchQuery = '';
    this.appliedBranchQuery = '';
    this.nextBranchCursor = null;
    this.refsLoading = false;
    this.refsError = '';
    const openScratch = this.onOpenScratch;
    const scratchRoot = this.options?.scratchWorkspaceRoot;
    if (this.isScratchSelected() && !this.scratch && openScratch && scratchRoot) {
      this.workspaceChanging = true;
      try {
        const scratch = await openScratch(scratchRoot);
        if (generation !== this.projectGeneration) return;
        this.scratch = scratch;
        this.cachedScratchRoot = scratchRoot;
      } catch (error) {
        if (generation === this.projectGeneration) this.workspaceError = (error as Error).message ||
          this.copy('无法打开无项目会话。', 'Could not open a thread without a project.');
      } finally {
        if (generation === this.projectGeneration) this.workspaceChanging = false;
      }
    }
    if (generation !== this.projectGeneration) return;
    this.selectModel(this.project()?.defaultModelSelection);
    if (!this.isScratchSelected()) void this.loadRefs('', null);
  }

  private selectModel(model?: ThreadLaunchSelection): void {
    const providers = this.providers();
    const provider = providers.find((item: ThreadLaunchProvider) => item.instanceId === model?.instanceId) ?? providers[0];
    if (!provider) return;
    const models = this.launchModels(provider);
    const selected = models.find((item: ThreadLaunchModel) => item.slug === model?.model) ??
      models.find((item: ThreadLaunchModel) => item.isDefault === true) ?? models[0];
    if (selected) this.selectLaunchModel(provider, selected, model);
  }

  private selectProvider(index: number): void {
    const provider = this.providers()[index];
    if (!provider) return;
    const models = this.launchModels(provider);
    const model = models.find((item: ThreadLaunchModel) => item.isDefault === true) ?? models[0];
    if (model) this.selectLaunchModel(provider, model, this.modelSelection());
  }

  private chooseModel(index: number): void {
    const provider = this.provider();
    const model = provider ? this.launchModels(provider)[index] : undefined;
    if (!provider || !model) return;
    this.selectLaunchModel(provider, model, this.modelSelection());
  }

  private selectLaunchModel(provider: ThreadLaunchProvider, model: ThreadLaunchModel, previous?: ThreadLaunchSelection): void {
    const target: ThreadLaunchSelection = { instanceId: provider.instanceId, model: model.slug };
    this.setModelOptionSelection(threadModelSelectionForTarget(provider.instanceId, model, previous,
      this.onRecallModelOptions(target)));
  }

  private setModelOptionSelection(selection: ThreadLaunchSelection): void {
    this.providerId = selection.instanceId;
    this.modelSlug = selection.model;
    this.modelOptionSelections = selection.options;
    this.modelParameterId = '';
  }

  private modelParameters(): ThreadModelOptionDescriptor[] {
    return threadModelOptionDescriptors(this.model(), this.modelSelection(), this.text);
  }

  private updateModelParameter(id: string, value: string | boolean): void {
    const selection = this.modelSelection();
    if (!selection || !this.controlsEnabled()) return;
    const change = changeThreadModelOption(this.model(), selection, id, value, this.text);
    if (!change) return;
    this.changeDraft(change.prompt);
    this.setModelOptionSelection(change.selection);
    this.onRememberModelOptions(change.selection);
  }

  private async loadRefs(query: string, cursor: number | null): Promise<void> {
    const project = this.project();
    const listRefs = this.onLoadRefs;
    if (!project || !listRefs) return;
    const generation = ++this.refsGeneration;
    this.refsLoading = true;
    this.refsError = '';
    try {
      const page = await listRefs(project.workspaceRoot, query, cursor, 'all', !query && cursor === null);
      if (generation !== this.refsGeneration) return;
      if (page.nextCursor !== null && cursor !== null && page.nextCursor <= cursor) {
        throw new Error(this.copy('环境未返回下一页 Git 分支。', 'The environment did not return the next page of Git branches.'));
      }
      this.gitRepo = page.isRepo;
      this.nextBranchCursor = page.nextCursor;
      const refs = new Map<string, NativeThreadGitRef>();
      if (cursor !== null) {
        for (const ref of this.branchRefs) refs.set(this.branchKey(ref), ref);
      }
      for (const ref of page.refs) refs.set(this.branchKey(ref), ref);
      this.branchRefs = Array.from(refs.values());
      if (!query && cursor === null) this.defaultRefs = page.refs;
    } catch (error) {
      if (generation === this.refsGeneration) this.refsError = (error as Error).message ||
        this.copy('无法读取 Git 分支。', 'Could not load Git branches.');
    } finally {
      if (generation === this.refsGeneration) this.refsLoading = false;
    }
  }

  private searchBranches(): void {
    this.appliedBranchQuery = this.branchQuery.trim();
    this.branchRefs = [];
    this.nextBranchCursor = null;
    void this.loadRefs(this.appliedBranchQuery, null);
  }

  private selectWorkspace(newWorktree: boolean): void {
    if (newWorktree === this.newWorktree) return;
    if (newWorktree && this.localWorkspace.branch) this.baseRef = this.localWorkspace.branch;
    const model = this.modelSelection();
    this.newWorktree = newWorktree;
    this.localWorkspace = { type: 'root' };
    this.workspaceProviders = undefined;
    this.workspaceError = '';
    this.selectModel(model);
  }

  private async selectBranch(ref: NativeThreadGitRef): Promise<void> {
    if (this.newWorktree) {
      this.baseRef = ref.name;
      this.pane = 'draft';
      return;
    }
    const project = this.project();
    const listRefs = this.onLoadRefs;
    const switchRef = this.onSwitchRef;
    if (!project || !listRefs || !switchRef || this.workspaceChanging) return;
    const generation = this.projectGeneration;
    this.workspaceChanging = true;
    this.workspaceError = '';
    try {
      const workspace = await resolveThreadLaunchLocalWorkspace(project.workspaceRoot, ref, listRefs, switchRef);
      if (generation !== this.projectGeneration) return;
      let providers: ThreadLaunchProvider[] | undefined;
      if (workspace.type === 'existing_worktree' && this.onLoadWorkspaceProviders) {
        providers = await this.onLoadWorkspaceProviders(project.id, workspace.worktreePath);
        if (generation !== this.projectGeneration) return;
      }
      const model = this.modelSelection();
      this.localWorkspace = workspace;
      this.workspaceProviders = providers;
      this.selectModel(model);
      this.pane = 'draft';
      this.branchQuery = '';
      this.appliedBranchQuery = '';
      void this.loadRefs('', null);
    } catch (error) {
      if (generation === this.projectGeneration) this.workspaceError = (error as Error).message ||
        this.copy('无法切换分支。', 'Could not switch branches.');
    } finally {
      if (generation === this.projectGeneration) this.workspaceChanging = false;
    }
  }

  private workspace(): ThreadLaunchWorkspaceStrategy | undefined {
    return this.newWorktree ? threadLaunchWorktree(this.defaultRefs, this.baseRef, this.startFromOrigin) : this.localWorkspace;
  }

  private modelSelection(): ThreadLaunchSelection | undefined {
    const provider = this.provider();
    const model = this.model();
    if (!provider || !model) return undefined;
    const selection: ThreadLaunchSelection = { instanceId: provider.instanceId, model: model.slug,
      options: provider.instanceId === this.providerId && model.slug === this.modelSlug ? this.modelOptionSelections : undefined };
    return withThreadModelOptionDefaults(model, selection);
  }

  private branchLabel(): string {
    const workspace = this.workspace();
    if (workspace?.type === 'worktree') return workspace.baseRef;
    if (!workspace) return this.copy('选择起始分支', 'Choose a base branch');
    return workspace.branch ?? this.defaultRefs.find((ref: NativeThreadGitRef) => ref.current)?.name ??
      this.copy('当前检出', 'Current checkout');
  }

  private runtimeLabel(mode: ThreadLaunchRuntimeMode): string {
    switch (mode) {
      case 'approval-required': return this.copy('需要审批', 'Approval required');
      case 'auto-accept-edits': return this.copy('自动接受编辑', 'Auto-accept edits');
      case 'full-access': return this.copy('完全访问', 'Full access');
      case 'auto': return this.copy('自动', 'Auto');
    }
  }

  private controlsEnabled(): boolean {
    return !this.launching && !this.workspaceChanging && !this.pickingAttachments;
  }

  private branchKey(ref: NativeThreadGitRef): string {
    return `${ref.isRemote ? 'remote' : 'local'}:${ref.name}`;
  }

  private branchBadge(ref: NativeThreadGitRef): string {
    if (ref.current) return this.copy('当前分支', 'Current branch');
    if (ref.worktreePath) return this.copy('现有工作树', 'Existing worktree');
    if (ref.isDefault) return this.copy('默认分支', 'Default branch');
    return '';
  }

  private clearProjectSearch(): void {
    this.projectSearchOpen = false;
    this.projectQuery = '';
  }

  private showProjects(): void {
    this.projectPickerFromDraft = true;
    this.pane = 'projects';
  }

  private navigateBack(): void {
    if (!this.controlsEnabled() || this.leaving) return;
    switch (this.pane) {
      case 'projects':
        if (this.projectSearchOpen) this.clearProjectSearch();
        else if (this.projectPickerFromDraft) {
          this.projectPickerFromDraft = false;
          this.pane = 'draft';
        } else void this.exitFlow();
        break;
      case 'draft':
        this.pane = 'projects';
        break;
      case 'files':
        this.backFromFiles();
        break;
      case 'settings':
        if (this.modelParameterId) this.modelParameterId = '';
        else this.pane = 'draft';
        break;
      default:
        this.pane = 'draft';
    }
  }

  private async exitFlow(): Promise<void> {
    if (!this.text.trim() && this.attachments.length === 0) {
      this.onBack();
      return;
    }
    this.leaving = true;
    const generation = this.projectGeneration;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: this.copy('丢弃草稿？', 'Discard draft?'),
        message: this.copy('草稿中的文字和附件将被丢弃。', 'Your draft text and attachments will be discarded.'),
        buttons: [
          { text: this.copy('继续编辑', 'Keep editing'), color: $r('sys.color.font_primary') },
          { text: this.copy('丢弃', 'Discard'), color: $r('sys.color.font_emphasize') },
        ],
      });
      if (result.index === 1 && generation === this.projectGeneration) this.onBack();
    } catch (_) {
    } finally {
      this.leaving = false;
    }
  }

  private activeEnvironmentLabel(): string {
    return this.environments.find((environment: EnvironmentSummary) => environment.key === this.activeEnvironmentKey)
      ?.label ?? this.copy('当前环境', 'Current environment');
  }

  private projectLabel(): string {
    return this.isScratchSelected() ? this.copy('无项目', 'No project') :
      this.project()?.title ?? this.copy('选择项目', 'Choose a project');
  }

  private pickBranch(): void {
    this.workspaceError = '';
    this.pane = 'branches';
    if (this.branchRefs.length === 0 && !this.refsLoading) this.searchBranches();
  }

  private fileWorkspaceRoot(): string {
    if (!this.newWorktree && this.localWorkspace.type === 'existing_worktree') return this.localWorkspace.worktreePath;
    return this.project()?.workspaceRoot ?? '';
  }

  private canInspectFiles(): boolean {
    return this.canReadFiles && !!this.fileWorkspaceRoot() && !!this.onListFiles && !!this.onReadFile;
  }

  private openFiles(): void {
    if (!this.canInspectFiles() || !this.controlsEnabled()) return;
    this.fileSearchOpen = false;
    this.pane = 'files';
    void this.loadFileDirectory('');
  }

  private async loadFileDirectory(path: string): Promise<void> {
    const cwd = this.fileWorkspaceRoot();
    const read = this.onListFiles;
    if (!cwd || !read) return;
    const generation = ++this.fileGeneration;
    this.directoryPath = path;
    this.fileDirectory = undefined;
    this.fileTarget = '';
    this.filePreview = undefined;
    this.fileError = '';
    this.fileLoading = true;
    try {
      const result = await read(cwd, path);
      if (generation === this.fileGeneration) this.fileDirectory = result;
    } catch (error) {
      if (generation === this.fileGeneration) this.fileError = (error as Error).message ||
        this.copy('无法读取目录。', 'Could not open the directory.');
    } finally {
      if (generation === this.fileGeneration) this.fileLoading = false;
    }
  }

  private async previewFile(path: string): Promise<void> {
    const cwd = this.fileWorkspaceRoot();
    const read = this.onReadFile;
    if (!cwd || !read) return;
    const generation = ++this.fileGeneration;
    this.fileTarget = path;
    this.filePreview = undefined;
    this.fileError = '';
    this.fileLoading = true;
    try {
      const result = await read(cwd, path);
      if (generation === this.fileGeneration) this.filePreview = result;
    } catch (error) {
      if (generation === this.fileGeneration) this.fileError = (error as Error).message ||
        this.copy('无法读取文件。', 'Could not open the file.');
    } finally {
      if (generation === this.fileGeneration) this.fileLoading = false;
    }
  }

  private async searchFiles(query: string): Promise<NativeThreadFileDirectory> {
    const cwd = this.fileWorkspaceRoot();
    if (!cwd || !this.onSearchFiles) throw new Error(this.copy('当前项目无法搜索文件。', 'File search is unavailable for this project.'));
    return this.onSearchFiles(cwd, query);
  }

  private backFromFiles(): void {
    if (this.fileTarget) {
      this.fileGeneration++;
      this.fileTarget = '';
      this.filePreview = undefined;
      this.fileLoading = false;
      this.fileError = '';
    } else if (this.fileSearchOpen) {
      this.fileSearchOpen = false;
    } else if (this.directoryPath) {
      void this.loadFileDirectory(this.directoryPath.slice(0, Math.max(0, this.directoryPath.lastIndexOf('/'))));
    } else {
      this.fileGeneration++;
      this.fileDirectory = undefined;
      this.pane = 'draft';
    }
  }

  @Builder
  BranchPicker() {
    Row({ space: 8 }) {
      TextInput({ text: this.branchQuery, placeholder: this.copy('查找分支', 'Find a branch') })
        .id('thread-launch-branch-search')
        .layoutWeight(1)
        .height(44)
        .borderRadius(22)
        .fontSize(15)
        .fontColor(workspaceForegroundColor(this.dark))
        .placeholderColor(workspaceMutedColor(this.dark))
        .backgroundColor(workspaceHeaderColor(this.dark))
        .maxLength(256)
        .enabled(this.controlsEnabled())
        .onChange((value: string) => { this.branchQuery = value; })
        .onSubmit(() => this.searchBranches())
      Button(this.copy('查找', 'Search'), { buttonStyle: ButtonStyleMode.TEXTUAL })
        .height(44)
        .enabled(this.controlsEnabled())
        .onClick(() => this.searchBranches())
    }.width('100%')
    if (this.refsLoading) {
      Row({ space: 8 }) {
        LoadingProgress().width(20).height(20)
        Text(this.copy('正在加载分支…', 'Loading branches…')).fontSize(14).fontColor(workspaceMutedColor(this.dark))
      }.width('100%').justifyContent(FlexAlign.Center).height(56)
    } else if (this.branchRefs.length === 0 && !this.refsError) {
      Text(this.appliedBranchQuery ? this.copy('没有匹配的分支', 'No matching branches') :
        this.copy('没有可用分支', 'No branches available'))
        .width('100%').height(56).textAlign(TextAlign.Center).fontSize(14).fontColor(workspaceMutedColor(this.dark))
    }
    if (this.branchRefs.length > 0) {
      Column() {
        ForEach(this.branchRefs, (ref: NativeThreadGitRef, index: number) => {
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.arrow_triangle_merge')).fontSize(24).fontColor([workspaceMutedColor(this.dark)])
              Column({ space: 2 }) {
                Text(ref.name).fontSize(16).fontColor(workspaceForegroundColor(this.dark)).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.branchBadge(ref)) Text(this.branchBadge(ref)).fontSize(12).fontColor(workspaceMutedColor(this.dark))
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              if (ref.name === this.branchLabel()) {
                SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([workspaceForegroundColor(this.dark)])
              }
            }.width('100%')
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .constraintSize({ minHeight: this.branchBadge(ref) ? 64 : 56 })
          .backgroundColor(Color.Transparent)
          .accessibilitySelected(ref.name === this.branchLabel())
          .enabled(this.controlsEnabled() && !this.refsLoading &&
            (this.newWorktree || this.canWriteGit || ref.current || !!ref.worktreePath))
          .onClick(() => { void this.selectBranch(ref); })
          if (index + 1 < this.branchRefs.length) {
            Divider().color(this.dark ? '#303030' : '#E4E4E7').margin({ left: 52, right: 16 })
          }
        }, (ref: NativeThreadGitRef) => this.branchKey(ref))
      }.width('100%').backgroundColor(workspaceGroupedCardColor(this.dark)).borderRadius(28).clip(true)
    }
    if (this.nextBranchCursor !== null) {
      Button(this.copy('加载更多分支', 'Load more branches'), { buttonStyle: ButtonStyleMode.TEXTUAL })
        .enabled(this.controlsEnabled() && !this.refsLoading)
        .onClick(() => { void this.loadRefs(this.appliedBranchQuery, this.nextBranchCursor); })
    }
  }

  @Builder
  private PaneHeader(title: string, backId: string) {
    Row() {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        SymbolGlyph($r('sys.symbol.arrow_left')).fontSize(24).fontColor([workspaceForegroundColor(this.dark)])
      }
      .id(backId)
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .accessibilityText(this.copy('返回', 'Back'))
      .enabled(this.controlsEnabled())
      .onClick(() => this.navigateBack())
      Text(title).fontSize(21).lineHeight(28).fontWeight(FontWeight.Medium).layoutWeight(1)
        .fontColor(workspaceForegroundColor(this.dark)).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.pane === 'draft' && this.canInspectFiles()) {
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.folder')).fontSize(24).fontColor([workspaceForegroundColor(this.dark)])
        }
        .id('thread-launch-files')
        .width(48)
        .height(48)
        .backgroundColor(Color.Transparent)
        .accessibilityText(this.copy('查看文件', 'Open files'))
        .enabled(this.controlsEnabled())
        .onClick(() => this.openFiles())
      }
    }.width('100%').height(56).padding({ left: 2, right: 4 }).backgroundColor(workspaceHeaderColor(this.dark))
  }

  @Builder
  private ContextButton(label: string, id: string, icon: Resource, action: () => void, navigates: boolean = true,
    accessibilityLabel: string = '') {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 5 }) {
        SymbolGlyph(icon).fontSize(16).fontColor([workspaceMutedColor(this.dark)])
        Text(label)
          .fontSize(14)
          .fontColor(workspaceForegroundColor(this.dark))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 154 })
        if (navigates) SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(11).fontColor([workspaceMutedColor(this.dark)])
      }
    }
    .id(id)
    .height(36)
    .padding({ left: 8, right: 8 })
    .backgroundColor(Color.Transparent)
    .accessibilityText(accessibilityLabel || label)
    .enabled(this.controlsEnabled())
    .onClick(action)
  }

  @Builder
  private DraftContext() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: this.compactDraft ? FlexAlign.Start : FlexAlign.Center }) {
      this.ContextButton(this.projectLabel(), 'thread-launch-change-project', $r('sys.symbol.folder'),
        () => this.showProjects())
      this.DraftEnvironment()
    }.width('100%')
  }

  @Builder
  private DraftEnvironment() {
    this.ContextButton(this.activeEnvironmentLabel(), 'thread-launch-environment', $r('sys.symbol.computer'),
      () => { this.pane = 'environment'; }, true,
      this.copy(`选择环境，${this.activeEnvironmentLabel()}`, `Choose environment, ${this.activeEnvironmentLabel()}`))
  }

  @Builder
  private DraftHero() {
    Column({ space: this.isScratchSelected() ? 8 : 16 }) {
      if (this.isScratchSelected()) {
        Text(this.copy('我们来做些什么？', 'What should we work on?'))
          .fontSize(24).lineHeight(32).fontWeight(FontWeight.Medium)
          .fontColor(workspaceForegroundColor(this.dark)).textAlign(TextAlign.Center)
        this.DraftContext()
      } else {
        Column({ space: 4 }) {
          Text(this.copy('要在', 'What should we build'))
            .fontSize(24).lineHeight(32).fontWeight(FontWeight.Medium)
            .fontColor(workspaceForegroundColor(this.dark)).textAlign(TextAlign.Center)
          Flex({ justifyContent: FlexAlign.Center, alignItems: ItemAlign.Center }) {
            if (this.language === 'en') {
              Text('in ').fontSize(24).lineHeight(32).fontWeight(FontWeight.Medium)
                .fontColor(workspaceForegroundColor(this.dark))
            }
            Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
              Text(this.projectLabel())
                .fontSize(24).lineHeight(32).fontWeight(FontWeight.Medium)
                .fontColor(workspaceForegroundColor(this.dark))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .decoration({ type: TextDecorationType.Underline, color: workspaceMutedColor(this.dark) })
            }
            .id('thread-launch-change-project')
            .flexShrink(1)
            .constraintSize({ maxWidth: 250, minHeight: 44 })
            .padding(0)
            .backgroundColor(Color.Transparent)
            .accessibilityText(this.copy(`选择项目，${this.projectLabel()}`, `Choose project, ${this.projectLabel()}`))
            .enabled(this.controlsEnabled())
            .onClick(() => this.showProjects())
            Text(this.copy(' 中构建什么？', '?')).fontSize(24).lineHeight(32).fontWeight(FontWeight.Medium)
              .fontColor(workspaceForegroundColor(this.dark))
          }.width('100%')
        }.width('100%')
        this.DraftEnvironment()
      }
    }.width('100%').padding({ left: 24, right: 24 })
  }

  @Builder
  private DraftWorkspace() {
    if (this.gitRepo) {
      Flex({ wrap: FlexWrap.Wrap }) {
        this.ContextButton(this.newWorktree ? this.copy('新建工作树', 'New worktree') :
          this.localWorkspace.type === 'existing_worktree' ? this.copy('现有工作树', 'Existing worktree') :
            this.copy('当前检出', 'Current checkout'),
          'thread-launch-workspace-mode', $r('sys.symbol.folder'), () => this.selectWorkspace(!this.newWorktree), false)
        if (this.newWorktree) {
          this.ContextButton(this.copy('仓库', 'Repositories'), 'thread-launch-repositories', $r('sys.symbol.folder'),
            () => { this.pane = 'repositories'; })
        }
        this.ContextButton(this.refsLoading && this.defaultRefs.length === 0 ?
          this.copy('正在加载分支…', 'Loading branches…') : this.branchLabel(),
          'thread-launch-branch', $r('sys.symbol.arrow_triangle_merge'), () => this.pickBranch(), true,
          this.newWorktree ? this.copy(`起始分支，${this.branchLabel()}`, `Base branch: ${this.branchLabel()}`) :
            this.copy(`分支，${this.branchLabel()}`, `Branch: ${this.branchLabel()}`))
      }.width('100%')
    } else if (this.refsLoading) {
      Text(this.copy('正在检查项目分支…', 'Loading branches…'))
        .fontSize(14)
        .fontColor(workspaceMutedColor(this.dark))
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    }
    if (this.refsError) {
      Text(this.refsError).width('100%').fontSize(14)
      Button(this.copy('重试分支列表', 'Try again'), { buttonStyle: ButtonStyleMode.TEXTUAL })
        .enabled(this.controlsEnabled() && !this.refsLoading)
        .onClick(() => this.searchBranches())
    }
  }

  @Builder
  private Draft() {
    Column() {
      this.PaneHeader(this.copy('新建会话', 'New thread'), 'thread-launch-draft-back')
      Column() {
        Blank().layoutWeight(1)
        if (!this.compactDraft) this.DraftHero()
        Blank().layoutWeight(2)
        this.DraftControls()
        ThreadDetailComposer({
          draft: this.text,
          language: this.language,
          dark: this.dark,
          placeholder: this.copy('问点什么', 'Ask anything'),
          error: this.error,
          sending: this.launching,
          canSend: this.canLaunch(),
          modelLabel: this.model()?.name ?? '',
          canPickModel: !!this.model() && this.controlsEnabled(),
          suggestionScope: this.composerScope() ? JSON.stringify([this.composerScope(), this.provider()?.instanceId]) : '',
          canAttach: !!this.project() && !this.workspaceChanging,
          pickingFiles: this.pickingAttachments,
          attachments: this.attachments,
          contextRecords: referencedComposerCommandContext(this.text, this.commandContexts),
          onDraft: (text: string) => this.changeDraft(text),
          onReadSuggestions: (trigger: ComposerCommandTrigger): Promise<ThreadComposerSuggestion[]> => {
            const scope = this.composerScope();
            return scope && this.onReadSuggestions ? this.onReadSuggestions(scope, this.provider()?.instanceId ?? '', trigger) :
              Promise.resolve([]);
          },
          onSuggestionContext: (record: ComposerCommandContextRecord) => this.addCommandContext(record),
          onPickModel: () => { this.pane = 'settings'; },
          onPickAttachment: (photos: boolean) => this.onPickAttachment(photos),
          onRemoveAttachment: (uri: string) => this.onRemoveAttachment(uri),
          onAction: () => this.launch(),
        }).enabled(!this.launching && !this.workspaceChanging)
      }
      .width('100%').layoutWeight(1)
      .backgroundColor(workspaceSurfaceColor(this.dark))
      .borderRadius({ topLeft: 28, topRight: 28 }).clip(true)
    }
    .id('thread-launch-draft')
    .width('100%')
    .height('100%')
    .backgroundColor(workspaceHeaderColor(this.dark))
    .onAreaChange((_old: Area, area: Area) => {
      const height = Number.parseFloat(area.height.toString());
      const compact = height > 0 && height < SHORT_DRAFT_VIEWPORT_HEIGHT;
      if (compact !== this.compactDraft) this.compactDraft = compact;
    })
  }

  @Builder
  private DraftControls() {
    Column({ space: 4 }) {
      if (this.workspaceChanging) {
        Row({ space: 8 }) {
          LoadingProgress().width(18).height(18)
          Text(this.copy('正在准备工作目录…', 'Preparing the workspace…'))
            .fontSize(14).fontColor(workspaceMutedColor(this.dark))
        }
      }
      if (this.workspaceError) {
        Text(this.workspaceError).fontSize(14).fontColor(workspaceMutedColor(this.dark))
        if (this.isScratchSelected() && !this.scratch) {
          Button(this.copy('重试无项目会话', 'Try again'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .enabled(this.controlsEnabled())
            .onClick(() => this.beginProject(-1))
        }
      }
      if (this.compactDraft) this.DraftContext()
      this.DraftWorkspace()
      if (this.project() && !this.model() && !this.workspaceChanging) {
        Text(this.copy('这个项目没有可用模型。', 'No models are available for this project.'))
          .width('100%').fontSize(14).fontColor(workspaceMutedColor(this.dark))
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 16, right: 16 })
  }

  @Builder
  private Branches() {
    Column() {
      this.PaneHeader(this.newWorktree ? this.copy('起始分支', 'Base branch') : this.copy('分支', 'Branch'),
        'thread-launch-branch-back')
      Scroll() {
        Column({ space: 10 }) {
          if (this.newWorktree) {
            Row({ space: 12 }) {
              Text(this.copy('从远程分支开始', 'Start from remote')).layoutWeight(1).fontSize(16)
                .fontColor(workspaceForegroundColor(this.dark))
              Toggle({ type: ToggleType.Switch, isOn: this.startFromOrigin })
                .id('thread-launch-start-from-origin')
                .accessibilityText(this.copy('从远程分支开始', 'Start from remote'))
                .enabled(this.controlsEnabled())
                .onChange((value: boolean) => { this.startFromOrigin = value; })
            }.width('100%').constraintSize({ minHeight: 56 }).padding({ left: 16, right: 16 })
              .backgroundColor(workspaceGroupedCardColor(this.dark)).borderRadius(28)
          }
          this.BranchPicker()
          if (this.workspaceChanging) LoadingProgress().width(20).height(20)
            .accessibilityText(this.copy('正在切换分支…', 'Switching branch…'))
          if (this.workspaceError || this.refsError) {
            Text(this.workspaceError || this.refsError).width('100%').fontSize(14)
              .fontColor(workspaceMutedColor(this.dark))
            if (this.refsError) {
              Button(this.copy('重试', 'Try again'), { buttonStyle: ButtonStyleMode.TEXTUAL })
                .enabled(this.controlsEnabled() && !this.refsLoading)
                .onClick(() => this.searchBranches())
            }
          }
        }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 16 }).alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).align(Alignment.Top)
        .backgroundColor(workspaceSurfaceColor(this.dark))
        .borderRadius({ topLeft: 28, topRight: 28 }).clip(true)
    }.width('100%').height('100%').backgroundColor(workspaceHeaderColor(this.dark))
  }

  @Builder
  private Settings() {
    Column() {
      this.PaneHeader(this.modelParameterId ? this.modelParameters().find((item: ThreadModelOptionDescriptor) =>
        item.id === this.modelParameterId)?.label ?? this.copy('模型参数', 'Model options') :
        this.copy('会话设置', 'Thread settings'), 'thread-launch-settings-back')
      Column() {
        if (this.modelParameterId) {
          ThreadModelParameterChoices({ idPrefix: 'thread-launch-parameter', editable: this.controlsEnabled(),
            language: this.language,
            descriptor: this.modelParameters().find((item: ThreadModelOptionDescriptor) => item.id === this.modelParameterId),
            onChoose: (value: string) => this.updateModelParameter(this.modelParameterId, value),
          }).layoutWeight(1)
        } else {
          Scroll() {
            Column({ space: 12 }) {
              Text(this.copy('提供商', 'Provider')).fontSize(14).fontColor(workspaceMutedColor(this.dark))
              Select(this.providerOptions())
                .id('thread-launch-provider')
                .width('100%')
                .value(this.provider()?.displayName ?? '')
                .enabled(this.controlsEnabled())
                .onSelect((index: number) => this.selectProvider(index))
              Text(this.copy('模型', 'Model')).fontSize(14).fontColor(workspaceMutedColor(this.dark))
              Select(this.modelOptions())
                .id('thread-launch-model')
                .width('100%')
                .value(this.model()?.name ?? '')
                .enabled(this.controlsEnabled())
                .onSelect((index: number) => this.chooseModel(index))
              ThreadModelParameterRows({ descriptors: this.modelParameters(), idPrefix: 'thread-launch-parameter',
                language: this.language,
                editable: this.controlsEnabled(), onOpen: (id: string) => { this.modelParameterId = id; },
                onChange: (id: string, value: boolean) => this.updateModelParameter(id, value),
              })
              Text(this.copy('运行权限', 'Runtime mode')).fontSize(14).fontColor(workspaceMutedColor(this.dark))
              if (this.selectedRuntimeMode() !== undefined) {
                Select(this.runtimeModes().map((mode: ThreadLaunchRuntimeMode): SelectOption => ({ value: this.runtimeLabel(mode) })))
                  .id('thread-launch-runtime')
                  .width('100%')
                  .value(this.runtimeLabel(this.selectedRuntimeMode() ?? 'approval-required'))
                  .enabled(this.controlsEnabled())
                  .onSelect((index: number) => { this.runtimeMode = this.runtimeModes()[index]; })
              } else {
                Text(this.copy('这个模型的运行权限不符合环境策略。', 'The environment does not allow a runtime mode for this model.'))
                  .width('100%').fontSize(14).fontColor(workspaceMutedColor(this.dark))
              }
            }.alignItems(HorizontalAlign.Start).width('100%').padding({ left: 20, right: 20, top: 16, bottom: 16 })
          }.layoutWeight(1).width('100%').align(Alignment.Top)
          Button(this.copy('完成', 'Done'))
            .id('thread-launch-settings-done')
            .margin({ left: 20, right: 20, bottom: 16 })
            .onClick(() => this.navigateBack())
        }
      }
      .width('100%').layoutWeight(1)
      .backgroundColor(workspaceSurfaceColor(this.dark))
      .borderRadius({ topLeft: 28, topRight: 28 }).clip(true)
    }.width('100%').height('100%').backgroundColor(workspaceHeaderColor(this.dark))
  }

  private canLaunch(): boolean {
    return (!!this.text.trim() || this.attachments.length > 0) && !!this.project() && !!this.workspace() &&
      !!this.modelSelection() && !!this.selectedRuntimeMode() && this.controlsEnabled();
  }

  private launch(): void {
    if (!this.canLaunch()) return;
    const project = this.project();
    const model = this.modelSelection();
    const mode = this.selectedRuntimeMode();
    const workspace = this.workspace();
    if (project && model && mode && workspace) {
      this.onLaunch(project, model, this.text, mode, workspace,
        referencedComposerCommandContext(this.text, this.commandContexts));
    }
  }

  build() {
    if (this.pane === 'projects') {
      ThreadLaunchProjectPicker({
        language: this.language,
        dark: this.dark,
        projects: this.options?.projects ?? [],
        selectedProjectId: this.selectedProjectId,
        offersScratch: this.offersScratch(),
        loading: this.loading,
        error: this.error,
        disabled: !this.controlsEnabled(),
        query: this.projectQuery,
        searchOpen: this.projectSearchOpen,
        onOpenSearch: () => { this.projectSearchOpen = true; },
        onCloseSearch: () => this.clearProjectSearch(),
        onQuery: (query: string) => { this.projectQuery = query; },
        onBack: () => this.navigateBack(),
        onRetry: () => this.onRetry(),
        onSelectProject: (index: number) => this.beginProject(index),
        onAddProject: () => this.onAddProject(),
      })
    } else if (this.pane === 'environment') {
      ThreadLaunchEnvironmentPicker({
        language: this.language,
        dark: this.dark,
        environments: this.environments,
        activeEnvironmentKey: this.activeEnvironmentKey,
        onBack: () => this.navigateBack(),
      })
    } else if (this.pane === 'repositories') {
      ThreadLaunchRepositoryPicker({
        language: this.language,
        dark: this.dark,
        project: this.project(),
        projectHasGit: this.gitRepo,
        onBack: () => this.navigateBack(),
      })
    } else if (this.pane === 'branches') {
      this.Branches()
    } else if (this.pane === 'settings') {
      this.Settings()
    } else if (this.pane === 'files') {
      ThreadDetailFiles({
        projectTitle: this.projectLabel(),
        directory: this.directoryPath,
        entries: this.fileDirectory?.entries ?? [],
        fileTarget: this.fileTarget,
        preview: this.filePreview,
        loading: this.fileLoading,
        error: this.fileError,
        truncated: this.fileDirectory?.truncated ?? false,
        searchOpen: this.fileSearchOpen,
        searchContext: this.fileWorkspaceRoot(),
        onBack: () => this.navigateBack(),
        onRefresh: () => {
          if (this.fileTarget) void this.previewFile(this.fileTarget);
          else void this.loadFileDirectory(this.directoryPath);
        },
        onOpen: (entry: NativeThreadFileEntry) => {
          if (entry.kind === 'directory') void this.loadFileDirectory(entry.path);
          else void this.previewFile(entry.path);
        },
        onSearch: this.onSearchFiles ? (query: string) => this.searchFiles(query) : undefined,
        onSearchOpenChange: (open: boolean) => { this.fileSearchOpen = open; },
      })
    } else {
      this.Draft()
    }
  }
}
