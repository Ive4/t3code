import type { LinkedEnvironmentCandidate, NativeLinkedEnvironment, NativePeerLinkAccess }
  from '../client/LinkedEnvironmentProtocol';
import { LinkedEnvironmentsView } from './LinkedEnvironmentsView';
import type { EnvironmentMaintenanceProvider, EnvironmentMaintenanceSnapshot }
  from '../client/EnvironmentMaintenanceProtocol';
import { EnvironmentMaintenanceView } from './EnvironmentMaintenanceView';

@Component
export struct EnvironmentDetails {
  @Prop @Watch('resetDraft') label: string = '';
  @Prop @Watch('resetDraft') origin: string = '';
  @Prop managed: boolean = false;
  @Prop connectionEnabled: boolean = true;
  @Prop active: boolean = false;
  @Prop busy: boolean = false;
  @Prop error: string = '';
  @Prop notice: string = '';
  @Prop canRemove: boolean = true;
  @Prop linkedEnvironments: NativeLinkedEnvironment[] = [];
  @Prop linkedCandidates: LinkedEnvironmentCandidate[] = [];
  @Prop linkedCanManage: boolean = false;
  @Prop linkedLoading: boolean = false;
  @Prop linkedError: string = '';
  @Prop linkedNotice: string = '';
  @Prop maintenanceSnapshot: EnvironmentMaintenanceSnapshot | undefined = undefined;
  @Prop maintenanceLoading: boolean = false;
  @Prop maintenanceBusy: boolean = false;
  @Prop maintenanceError: string = '';
  @Prop maintenanceNotice: string = '';
  @Prop maintenanceRelease: string | null | undefined = undefined;
  @State private nameDraft: string = '';
  @State private originDraft: string = '';
  onSave: (label: string, address: string) => void = () => {};
  onChangeEnabled: (enabled: boolean) => void = () => {};
  onReconnect: () => void = () => {};
  onManageRoutes: () => void = () => {};
  onLink: (candidate: LinkedEnvironmentCandidate, access: NativePeerLinkAccess) => void = () => {};
  onUnlink: (link: NativeLinkedEnvironment) => void = () => {};
  onCheckRelease: () => void = () => {};
  onRefreshProviders: () => void = () => {};
  onUpdateProvider: (provider: EnvironmentMaintenanceProvider) => void = () => {};
  onRemove: () => void = () => {};
  onBack: () => void = () => {};

  aboutToAppear(): void {
    this.resetDraft();
  }

  private resetDraft(): void {
    this.nameDraft = this.label;
    this.originDraft = this.origin;
  }

  private async confirmRemove(): Promise<void> {
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '移除环境？',
        message: '此操作移除此设备保存的连接与草稿。',
        buttons: [
          { text: '取消', color: $r('sys.color.font_secondary') },
          { text: '移除', color: $r('sys.color.font_primary') },
        ],
      });
      if (result.index === 1 && !this.busy) this.onRemove();
    } catch (_) {}
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Button('返回', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .enabled(!this.busy)
          .onClick(this.onBack)
        Text(this.label)
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 16 })

      Scroll() {
        Column({ space: 14 }) {
          Text('连接').fontSize(14).fontColor($r('sys.color.font_secondary'))
          Row({ space: 12 }) {
            Column({ space: 6 }) {
              Text(this.managed ? 'T3 Connect' : '直连').fontSize(16)
              Text(!this.connectionEnabled ? '已停用' : this.active ? '当前环境' : '已启用')
                .fontSize(13).fontColor($r('sys.color.font_secondary'))
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.connectionEnabled })
              .accessibilityText('启用环境')
              .enabled(!this.busy)
              .onChange((enabled: boolean) => {
                if (!this.busy && enabled !== this.connectionEnabled) this.onChangeEnabled(enabled);
              })
          }.width('100%')
          TextInput({ text: this.nameDraft, placeholder: '环境名称' })
            .accessibilityText('环境名称')
            .enabled(!this.busy)
            .onChange((value: string) => { this.nameDraft = value; })
          if (!this.managed) {
            TextInput({ text: this.originDraft, placeholder: '服务器地址' })
              .accessibilityText('服务器地址')
              .enabled(!this.busy)
              .onChange((value: string) => { this.originDraft = value; })
          }
          if (this.busy && !this.maintenanceBusy) LoadingProgress().width(22).height(22).accessibilityText('正在更新连接')
          if (this.error) Text(this.error).fontSize(14).fontColor($r('sys.color.font_secondary'))
          if (this.notice) Text(this.notice).fontSize(14).fontColor($r('sys.color.font_secondary'))
          Button('保存')
            .enabled(!this.busy && this.nameDraft.trim().length > 0 &&
              (this.managed || this.originDraft.trim().length > 0) &&
              (this.nameDraft.trim() !== this.label || this.originDraft.trim() !== this.origin))
            .onClick(() => this.onSave(this.nameDraft, this.originDraft))
          Button(this.active ? '重新连接' : '连接', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .enabled(!this.busy && this.connectionEnabled)
            .onClick(this.onReconnect)
          Button('连接线路', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .enabled(!this.busy)
            .onClick(this.onManageRoutes)
          if (this.linkedLoading) {
            LoadingProgress().width(22).height(22).accessibilityText('正在读取关联环境')
          }
          if (this.linkedError) Text(this.linkedError).fontSize(14).fontColor($r('sys.color.font_secondary'))
          if (this.linkedNotice) Text(this.linkedNotice).fontSize(14).fontColor($r('sys.color.font_secondary'))
          if (this.linkedEnvironments.length > 0 || this.linkedCandidates.length > 0) {
            LinkedEnvironmentsView({
              links: this.linkedEnvironments,
              environmentLabel: this.label,
              canUnlink: this.linkedCanManage,
              batchAvailable: false,
              candidates: this.linkedCandidates,
              busy: this.busy,
              onLink: this.onLink,
              onUnlink: this.onUnlink,
            })
          }
          if (this.maintenanceSnapshot || this.maintenanceLoading || this.maintenanceError) {
            EnvironmentMaintenanceView({
              snapshot: this.maintenanceSnapshot,
              loading: this.maintenanceLoading,
              busy: this.maintenanceBusy,
              error: this.maintenanceError,
              notice: this.maintenanceNotice,
              latestVersion: this.maintenanceRelease,
              onCheck: this.onCheckRelease,
              onRefreshProviders: this.onRefreshProviders,
              onUpdateProvider: this.onUpdateProvider,
            })
          }
          if (this.canRemove) {
            Button('移除环境', { buttonStyle: ButtonStyleMode.TEXTUAL })
              .enabled(!this.busy)
              .onClick(() => { void this.confirmRemove(); })
          }
        }
        .width('100%')
        .padding(20)
        .alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1)
    }.width('100%').layoutWeight(1)
  }
}
