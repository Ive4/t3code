import type { EnvironmentMaintenanceProvider, EnvironmentMaintenanceSnapshot }
  from '../client/EnvironmentMaintenanceProtocol';

@Component
export struct EnvironmentMaintenanceView {
  @Prop snapshot: EnvironmentMaintenanceSnapshot | undefined = undefined;
  @Prop loading: boolean = false;
  @Prop busy: boolean = false;
  @Prop error: string = '';
  @Prop notice: string = '';
  @Prop latestVersion: string | null | undefined = undefined;
  onCheck: () => void = () => {};
  onRefreshProviders: () => void = () => {};
  onUpdateProvider: (provider: EnvironmentMaintenanceProvider) => void = () => {};

  private providerStatus(status?: string): string {
    switch (status) {
      case 'queued': return '等待更新';
      case 'running': return '正在更新';
      case 'succeeded': return '更新完成';
      case 'failed': return '更新失败';
      case 'unchanged': return '版本未变更';
      default: return '';
    }
  }

  @Builder
  private ProviderRow(provider: EnvironmentMaintenanceProvider) {
    Column({ space: 5 }) {
      Text(provider.label).fontSize(16).fontWeight(FontWeight.Medium)
      Text(provider.latestVersion ? provider.version + ' · 最新 ' + provider.latestVersion : provider.version)
        .fontSize(13).fontColor($r('sys.color.font_secondary'))
      if (this.providerStatus(provider.status)) {
        Text(this.providerStatus(provider.status)).fontSize(13).fontColor($r('sys.color.font_secondary'))
      }
      if (provider.detail) Text(provider.detail).fontSize(13).fontColor($r('sys.color.font_secondary'))
      if (provider.canUpdate) {
        Button('更新 ' + provider.label, { buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(44)
          .enabled(!this.busy && !this.loading && !this.snapshot?.providers.some((entry) =>
            entry.status === 'running' || entry.status === 'queued'))
          .onClick(() => this.onUpdateProvider(provider))
      }
    }.alignItems(HorizontalAlign.Start).width('100%').padding({ top: 6, bottom: 6 })
  }

  build() {
    Column({ space: 10 }) {
      Text('T3 Code').fontSize(14).fontColor($r('sys.color.font_secondary'))
      if (this.loading || this.busy) {
        LoadingProgress().width(22).height(22).accessibilityText('正在处理环境维护')
      }
      if (this.error) Text(this.error).fontSize(14).fontColor($r('sys.color.font_secondary'))
      if (this.notice) Text(this.notice).fontSize(14).fontColor($r('sys.color.font_secondary'))
      if (this.snapshot) {
        Text('版本 ' + this.snapshot.version).fontSize(16)
        if (this.snapshot.organization) {
          Text('由 ' + this.snapshot.organization + ' 管理')
            .fontSize(13).fontColor($r('sys.color.font_secondary'))
        }
        if (this.snapshot.updateDenial) {
          Text(this.snapshot.updateDenial).fontSize(13).fontColor($r('sys.color.font_secondary'))
        } else if (this.snapshot.canCheck) {
          Button('检查更新', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .height(44).enabled(!this.busy && !this.loading)
            .onClick(this.onCheck)
          if (this.latestVersion) {
            Text('版本 ' + this.latestVersion + ' 可用')
              .fontSize(14).fontColor($r('sys.color.font_secondary'))
            Text(this.snapshot.serverUpdateCapability === 'desktop-managed'
              ? '请在主机上更新 T3 Code 桌面应用。' : '请在主机上更新 T3 Code。')
              .fontSize(13).fontColor($r('sys.color.font_secondary'))
          } else if (this.latestVersion === null) {
            Text('当前已是最新版本。').fontSize(14).fontColor($r('sys.color.font_secondary'))
          }
        }

        if (this.snapshot.providers.length > 0 || this.snapshot.canRefresh) {
          Text('提供商').fontSize(14).fontColor($r('sys.color.font_secondary'))
          if (this.snapshot.canRefresh) {
            Button('刷新提供商', { buttonStyle: ButtonStyleMode.TEXTUAL })
              .height(44).enabled(!this.busy && !this.loading)
              .onClick(this.onRefreshProviders)
          }
          ForEach(this.snapshot.providers, (provider: EnvironmentMaintenanceProvider) => {
            this.ProviderRow(provider)
          }, (provider: EnvironmentMaintenanceProvider) => JSON.stringify([
            provider.instanceId, provider.label, provider.version, provider.latestVersion,
            provider.canUpdate, provider.status, provider.detail,
          ]))
        }
      }
    }.alignItems(HorizontalAlign.Start).width('100%')
  }
}
