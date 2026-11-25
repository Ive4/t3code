import { UiLanguage, uiText } from './UiLanguage';
import { threadRuntimeModeChoices } from '../client/ThreadLaunchProtocol';
import type {
  ThreadLaunchModel, ThreadLaunchProvider, ThreadLaunchRuntimeMode, ThreadLaunchSelection, ThreadRuntimeModeChoice,
} from '../client/ThreadLaunchProtocol';
import type { ThreadModelOptionDescriptor } from '../client/ThreadModelOptionProtocol';
import { ThreadModelParameterChoices, ThreadModelParameterRows } from './ThreadModelParameters';
import { modelCatalogIsFavorite, modelCatalogIsHidden, modelCatalogVisibleModels } from '../client/ModelCatalogPreferences';
import type { ModelCatalogPreferenceKind, NativeModelCatalogPreferences } from '../client/ModelCatalogPreferences';

const MODE_LABELS: Record<ThreadLaunchRuntimeMode, string> = {
  'approval-required': '需要审批', 'auto-accept-edits': '自动接受编辑', 'auto': '自动', 'full-access': '完全访问',
};

const MODE_DESCRIPTIONS: Record<ThreadLaunchRuntimeMode, string> = {
  'approval-required': '执行命令和修改文件前请求审批。',
  'auto-accept-edits': '自动接受文件修改，其他操作仍需审批。',
  'auto': '受支持的提供商自动审批常规操作。',
  'full-access': '允许直接执行命令和修改文件。',
};

const MODE_LABELS_EN: Record<ThreadLaunchRuntimeMode, string> = {
  'approval-required': 'Approval required', 'auto-accept-edits': 'Auto-accept edits', 'auto': 'Auto',
  'full-access': 'Full access',
};

const MODE_DESCRIPTIONS_EN: Record<ThreadLaunchRuntimeMode, string> = {
  'approval-required': 'Ask before running commands or editing files.',
  'auto-accept-edits': 'Accept file edits automatically and ask before other actions.',
  'auto': 'Supported providers approve routine actions automatically.',
  'full-access': 'Run commands and edit files directly.',
};

@Component
export struct ThreadModelPicker {
  @Prop language: UiLanguage = 'zh';
  @Prop providers: ThreadLaunchProvider[] = [];
  @Prop selection: ThreadLaunchSelection | undefined = undefined;
  @Prop currentProviderInstanceId: string = '';
  @Prop loading: boolean = false;
  @Prop applying: boolean = false;
  @Prop error: string = '';
  @Prop canSwitchProvider: boolean = false;
  @Prop showRuntime: boolean = false;
  @Prop runtimeMode: ThreadLaunchRuntimeMode | undefined = undefined;
  @Prop maxRuntimeMode: ThreadLaunchRuntimeMode | undefined = undefined;
  @Prop parameters: ThreadModelOptionDescriptor[] = [];
  @Prop parameterId: string = '';
  @Prop pendingModel: boolean = false;
  @Prop modelCatalog?: NativeModelCatalogPreferences = undefined;
  @Prop canWriteCatalog: boolean = false;
  onChoose: (selection: ThreadLaunchSelection) => void = () => {};
  onSaveModel: () => void = () => {};
  onOpenParameter: (id: string) => void = () => {};
  onBackParameter: () => void = () => {};
  onChangeParameter: (id: string, value: string | boolean) => void = () => {};
  onChangeCatalog: (provider: string, model: string, kind: ModelCatalogPreferenceKind, enabled: boolean) => void = () => {};
  onOpenRuntime: () => void = () => {};
  onBackRuntime: () => void = () => {};
  onChooseRuntime: (mode: ThreadLaunchRuntimeMode) => void = () => {};
  onRetry: () => void = () => {};
  onClose: () => void = () => {};
  @State private manageHidden: boolean = false;
  @State private favoritesOnly: boolean = false;

  private copy(chinese: string, english: string): string {
    return uiText(this.language, chinese, english);
  }

  private modeLabel(mode: ThreadLaunchRuntimeMode): string {
    return this.copy(MODE_LABELS[mode], MODE_LABELS_EN[mode]);
  }

  private modeDescription(mode: ThreadLaunchRuntimeMode): string {
    return this.copy(MODE_DESCRIPTIONS[mode], MODE_DESCRIPTIONS_EN[mode]);
  }

  private availableProviders(): ThreadLaunchProvider[] {
    const current = this.currentProviderInstanceId || this.selection?.instanceId;
    return this.canSwitchProvider ? this.providers :
      this.providers.filter((provider: ThreadLaunchProvider) => provider.instanceId === current);
  }

  private isSelected(provider: ThreadLaunchProvider, model: ThreadLaunchModel): boolean {
    return this.selection?.instanceId === provider.instanceId && this.selection?.model === model.slug;
  }

  private visibleModels(provider: ThreadLaunchProvider): ThreadLaunchModel[] {
    return modelCatalogVisibleModels(provider.models, this.modelCatalog, provider.instanceId,
      this.manageHidden, this.favoritesOnly, this.selection?.instanceId === provider.instanceId ? this.selection?.model : '');
  }

  private parameter(): ThreadModelOptionDescriptor | undefined {
    return this.parameters.find((item: ThreadModelOptionDescriptor) => item.id === this.parameterId);
  }

  private headerBack(): void {
    if (this.parameterId) this.onBackParameter();
    else if (this.showRuntime) this.onBackRuntime();
    else this.onClose();
  }

  private runtimeOptions(): ThreadRuntimeModeChoice[] {
    const selection = this.selection;
    const provider = this.providers.find((item: ThreadLaunchProvider) => item.instanceId === selection?.instanceId);
    const model = provider?.models.find((item: ThreadLaunchModel) => item.slug === selection?.model);
    return threadRuntimeModeChoices(model, this.maxRuntimeMode);
  }

  @Builder
  private RuntimeOption(choice: ThreadRuntimeModeChoice) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 10 }) {
        Column({ space: 4 }) {
          Text(this.modeLabel(choice.mode)).fontSize(16).fontColor($r('sys.color.font_primary'))
          Text(choice.allowed ? this.modeDescription(choice.mode) : this.copy('受环境管理策略限制', 'Restricted by the environment policy'))
            .fontSize(13).fontColor($r('sys.color.font_secondary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (this.runtimeMode === choice.mode) Text('✓').fontSize(18).fontColor($r('sys.color.icon_emphasize'))
      }.width('100%').padding({ top: 8, bottom: 8 })
    }.id(`thread-runtime-${choice.mode}`).width('100%').constraintSize({ minHeight: 52 })
      .accessibilityText(this.modeLabel(choice.mode)).accessibilitySelected(this.runtimeMode === choice.mode)
      .enabled(choice.allowed && !this.loading && !this.applying).onClick(() => this.onChooseRuntime(choice.mode))
  }

  @Builder
  private RuntimeSettings() {
    List({ space: 1 }) {
      ForEach(this.runtimeOptions(), (choice: ThreadRuntimeModeChoice) => {
        ListItem() { this.RuntimeOption(choice) }
      }, (choice: ThreadRuntimeModeChoice) => choice.mode)
    }.width('100%').layoutWeight(1).padding({ left: 12, right: 12, bottom: 12 })
  }

  @Builder
  private ModelRow(provider: ThreadLaunchProvider, model: ThreadLaunchModel) {
    Row({ space: 2 }) {
      this.ModelPick(provider, model)
      if (this.modelCatalog) {
        Button(modelCatalogIsFavorite(this.modelCatalog, provider.instanceId, model.slug) ? '★' : '☆',
          { type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL })
          .id(`thread-model-favorite-${provider.instanceId}-${model.slug}`).width(44).height(44).padding(0)
          .fontSize(20).accessibilityText(modelCatalogIsFavorite(this.modelCatalog, provider.instanceId, model.slug)
            ? this.copy(`取消收藏 ${model.name}`, `Remove from favorites ${model.name}`) : this.copy(`收藏 ${model.name}`, `Favorite ${model.name}`))
          .enabled(this.canWriteCatalog && !this.loading && !this.applying)
          .onClick(() => this.onChangeCatalog(provider.instanceId, model.slug, 'favorite',
            !modelCatalogIsFavorite(this.modelCatalog, provider.instanceId, model.slug)))
        if (this.manageHidden && !model.isCustom) {
          Button(modelCatalogIsHidden(this.modelCatalog, provider.instanceId, model.slug) ? this.copy('恢复', 'Restore') : this.copy('隐藏', 'Hide'),
            { buttonStyle: ButtonStyleMode.TEXTUAL })
            .id(`thread-model-hidden-${provider.instanceId}-${model.slug}`).height(44)
            .accessibilityText(modelCatalogIsHidden(this.modelCatalog, provider.instanceId, model.slug)
              ? this.copy(`恢复 ${model.name}`, `Restore ${model.name}`) : this.copy(`隐藏 ${model.name}`, `Hide ${model.name}`))
            .enabled(this.canWriteCatalog && !this.loading && !this.applying)
            .onClick(() => this.onChangeCatalog(provider.instanceId, model.slug, 'hidden',
              !modelCatalogIsHidden(this.modelCatalog, provider.instanceId, model.slug)))
        }
      }
    }.width('100%')
  }

  @Builder
  private ModelPick(provider: ThreadLaunchProvider, model: ThreadLaunchModel) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        Text(model.name)
          .layoutWeight(1)
          .fontSize(16)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.isSelected(provider, model)) {
          Text('✓').fontSize(18).fontColor($r('sys.color.icon_emphasize'))
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12 })
    }
    .id(`thread-model-${provider.instanceId}-${model.slug}`)
    .layoutWeight(1)
    .constraintSize({ minHeight: 48 })
    .borderRadius(12)
    .backgroundColor(this.isSelected(provider, model) ? $r('sys.color.comp_background_secondary') : Color.Transparent)
    .accessibilityText(model.name)
    .accessibilityStateDescription(this.isSelected(provider, model) ? this.copy('已选中', 'Selected') : '')
    .enabled(!this.loading && !this.applying)
    .onClick(() => this.onChoose({ instanceId: provider.instanceId, model: model.slug }))
  }

  @Builder
  private CatalogControls() {
    Row({ space: 8 }) {
      Text(this.copy('管理隐藏模型', 'Manage hidden models')).fontSize(14).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.manageHidden }).id('thread-model-manage-hidden')
        .accessibilityText(this.copy('管理隐藏模型', 'Manage hidden models')).enabled(!this.applying)
        .onChange((enabled: boolean) => { this.manageHidden = enabled; })
      Button(this.copy('仅收藏', 'Favorites only'), { type: ButtonType.Capsule,
        buttonStyle: this.favoritesOnly ? ButtonStyleMode.NORMAL : ButtonStyleMode.TEXTUAL })
        .id('thread-model-favorites-only').height(44).accessibilitySelected(this.favoritesOnly)
        .enabled(!this.applying).onClick(() => { this.favoritesOnly = !this.favoritesOnly; })
    }.width('100%').padding({ left: 12, right: 4, top: 8 })
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 12 }) {
        Text(this.parameterId ? this.parameter()?.label ?? this.copy('模型参数', 'Model options') : this.showRuntime ? this.copy('运行模式', 'Runtime mode') : this.copy('会话设置', 'Chat settings'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Button(this.showRuntime || this.parameterId ? this.copy('返回', 'Back') : this.pendingModel ? this.copy('取消', 'Cancel') : this.copy('关闭', 'Close'),
          { buttonStyle: ButtonStyleMode.TEXTUAL })
          .id(this.parameterId ? 'thread-model-parameter-back' : this.showRuntime ? 'thread-runtime-back' : 'thread-model-close')
          .height(44)
          .enabled(!this.applying)
          .onClick(() => this.headerBack())
        if (this.pendingModel && !this.showRuntime && !this.parameterId) {
          Button(this.copy('保存', 'Save'), { type: ButtonType.Capsule }).id('thread-model-save').height(44)
            .enabled(!this.loading && !this.applying).onClick(() => this.onSaveModel())
        }
      }
      .width('100%')
      .padding({ left: 16, right: 12 })

      if (this.loading || this.applying) {
        Row({ space: 8 }) {
          LoadingProgress().width(20).height(20)
          Text(this.loading ? this.copy('正在加载模型…', 'Loading models…') : this.copy('正在保存…', 'Saving…')).fontSize(15)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      }
      if (this.error) {
        Row({ space: 8 }) {
          Text(this.error).fontSize(15).layoutWeight(1)
          Button(this.copy('重试', 'Retry'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .id('thread-model-retry')
            .height(44)
            .enabled(!this.loading && !this.applying)
            .onClick(() => this.onRetry())
        }
        .width('100%')
        .padding({ left: 16, right: 12 })
      }
      if (this.parameterId) {
        ThreadModelParameterChoices({ language: this.language, descriptor: this.parameter(), editable: !this.loading && !this.applying,
          onChoose: (value: string) => this.onChangeParameter(this.parameterId, value),
        }).layoutWeight(1)
      } else if (this.showRuntime) {
        this.RuntimeSettings()
      } else if (this.availableProviders().length > 0) {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 8 }) {
            Text(this.copy('运行模式', 'Runtime mode')).fontSize(15).fontColor($r('sys.color.font_primary')).layoutWeight(1)
            Text(this.runtimeMode ? this.modeLabel(this.runtimeMode) : this.copy('由环境决定', 'Environment default'))
              .fontSize(14).fontColor($r('sys.color.font_secondary'))
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([$r('sys.color.icon_secondary')])
          }.width('100%')
        }.id('thread-model-runtime').width('92%').height(48).borderRadius(12)
          .backgroundColor($r('sys.color.comp_background_secondary'))
          .enabled(this.selection !== undefined && !this.loading && !this.applying)
          .onClick(() => this.onOpenRuntime())
        List({ space: 4 }) {
          if (this.parameters.length > 0) {
            ListItem() {
              ThreadModelParameterRows({ language: this.language, descriptors: this.parameters, editable: !this.loading && !this.applying,
                onOpen: (id: string) => this.onOpenParameter(id),
                onChange: (id: string, value: boolean) => this.onChangeParameter(id, value),
              })
            }
          }
          if (this.modelCatalog) {
            ListItem() { this.CatalogControls() }
          }
          ForEach(this.availableProviders(), (provider: ThreadLaunchProvider) => {
            if (this.visibleModels(provider).length > 0) {
              ListItem() {
                Text(provider.displayName)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('sys.color.font_secondary'))
                  .padding({ left: 12, right: 12, top: 12, bottom: 4 })
              }
              ForEach(this.visibleModels(provider), (model: ThreadLaunchModel) => {
                ListItem() { this.ModelRow(provider, model) }
              }, (model: ThreadLaunchModel): string => model.slug)
            }
          }, (provider: ThreadLaunchProvider): string => provider.instanceId)
          if (!this.availableProviders().some((provider: ThreadLaunchProvider) => this.visibleModels(provider).length > 0)) {
            ListItem() { Text(this.favoritesOnly ? this.copy('没有收藏的模型。', 'No favorite models.') : this.copy('没有可见模型。', 'No visible models.')).padding(12) }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 12, right: 12, bottom: 12 })
      } else if (!this.loading && !this.error) {
        Text(this.copy('没有可用模型。', 'No models available.'))
          .fontSize(15)
          .width('100%')
          .padding(16)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: 8 })
    .backgroundColor($r('sys.color.comp_background_primary'))
  }
}
