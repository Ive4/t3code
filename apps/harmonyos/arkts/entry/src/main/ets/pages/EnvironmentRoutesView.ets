import type { EnvironmentSummary } from '../client/EnvironmentStore';

@Component
export struct EnvironmentRoutesView {
  @Prop label: string = '';
  @Prop routes: EnvironmentSummary[] = [];
  @Prop activeKey: string = '';
  @Prop busy: boolean = false;
  @Prop error: string = '';
  @Prop notice: string = '';
  @State private editing: boolean = false;
  onBack: () => void = () => {};
  onAddRoute: () => void = () => {};
  onMoveRoute: (key: string, delta: number) => void = () => {};
  onRemoveRoute: (key: string) => void = () => {};
  onUseRoute: (key: string) => void = () => {};

  private async confirmRemove(route: EnvironmentSummary): Promise<void> {
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '移除这条线路？',
        message: route.origin,
        buttons: [
          { text: '取消', color: $r('sys.color.font_secondary') },
          { text: '移除', color: $r('sys.color.font_primary') },
        ],
      });
      if (result.index === 1 && !this.busy && this.routes.length > 1 &&
        this.routes.some((entry) => entry.key === route.key)) {
        this.onRemoveRoute(route.key);
      }
    } catch (_) {}
  }

  @Builder
  private routeRow(route: EnvironmentSummary, index: number) {
    Column() {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Row({ space: 8 }) {
            Text(route.managed ? 'T3 Connect' : '直连')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
            if (route.key === this.activeKey || !route.enabled) {
              Text(route.key === this.activeKey ? '使用中' : '已停用')
                .fontSize(13)
                .fontColor($r('sys.color.font_secondary'))
            }
          }.width('100%')
          Text(route.origin)
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (!this.editing && route.enabled && route.key !== this.activeKey) {
          Button('使用', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .height(44)
            .accessibilityText('使用线路 ' + route.origin)
            .enabled(!this.busy)
            .onClick(() => this.onUseRoute(route.key))
        }
      }.width('100%')
      if (this.editing && this.routes.length > 1) {
        Row({ space: 8 }) {
          Button('上移', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .height(44)
            .accessibilityText('上移线路 ' + route.origin)
            .enabled(!this.busy && index > 0)
            .onClick(() => this.onMoveRoute(route.key, -1))
          Button('下移', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .height(44)
            .accessibilityText('下移线路 ' + route.origin)
            .enabled(!this.busy && index < this.routes.length - 1)
            .onClick(() => this.onMoveRoute(route.key, 1))
          Blank()
          Button('移除', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .height(44)
            .accessibilityText('移除线路 ' + route.origin)
            .enabled(!this.busy)
            .onClick(() => { void this.confirmRemove(route); })
        }.width('100%')
      }
    }.width('100%').padding(12).alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Button('返回', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(44)
          .enabled(!this.busy)
          .onClick(this.onBack)
        Text('连接线路').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
        if (this.routes.length > 1) {
          Button(this.editing ? '完成' : '编辑', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .height(44)
            .enabled(!this.busy)
            .onClick(() => { this.editing = !this.editing; })
        }
      }.width('100%').height(56).padding({ left: 12, right: 16 })

      Scroll() {
        Column({ space: 12 }) {
          Text(this.label).fontSize(16).fontColor($r('sys.color.font_secondary'))
          Column() {
            ForEach(this.routes, (route: EnvironmentSummary, index: number) => {
              this.routeRow(route, index)
            }, (route: EnvironmentSummary, index: number) => JSON.stringify([
              route.key, route.origin, route.enabled, index,
            ]))
          }.width('100%').borderRadius(16).backgroundColor($r('sys.color.comp_background_secondary'))
          if (this.busy) LoadingProgress().width(22).height(22).accessibilityText('正在更新线路')
          if (this.error) Text(this.error).fontSize(14).fontColor($r('sys.color.font_secondary'))
          if (this.notice) Text(this.notice).fontSize(14).fontColor($r('sys.color.font_secondary'))
          Button('添加直连线路', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .height(44)
            .enabled(!this.busy)
            .onClick(this.onAddRoute)
        }.width('100%').padding(20).alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).align(Alignment.Top)
    }.width('100%').layoutWeight(1)
  }
}
