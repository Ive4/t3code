import { DeviceApprovalRequest } from '../client/RelayProtocol';

@Component
export struct DeviceApprovalPendingView {
  @Prop environmentId: string = '';
  @Prop environmentLabel: string = '';
  @Prop verificationCode: string = '';
  @Prop busy: boolean = false;
  @Prop error: string = '';
  onRetry: () => void = () => {};
  onCancel: () => void = () => {};

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text('设备审批')
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
        Text(this.environmentLabel)
          .fontSize(17)
          .fontColor($r('sys.color.font_primary'))
        Text('环境 ID ' + this.environmentId)
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .wordBreak(WordBreak.BREAK_ALL)
        Text('在已连接此环境的设备上核对以下验证码，批准后再重试。')
          .fontSize(15)
          .fontColor($r('sys.color.font_secondary'))
        Text(this.verificationCode)
          .fontSize(32)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
        if (this.error) {
          Text(this.error)
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
        }
        Button(this.busy ? '正在连接…' : '重试')
          .width('100%')
          .height(44)
          .enabled(!this.busy)
          .onClick(() => this.onRetry())
        Button('返回', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .width('100%')
          .height(44)
          .enabled(!this.busy)
          .onClick(() => this.onCancel())
      }
      .width('100%')
      .constraintSize({ maxWidth: 480 })
      .alignItems(HorizontalAlign.Start)
      .padding(20)
    }
    .layoutWeight(1)
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }
}

@Component
export struct DeviceApprovalView {
  @Prop environmentId: string = '';
  @Prop environmentLabel: string = '';
  @Prop requests: DeviceApprovalRequest[] = [];
  @Prop busy: boolean = false;
  @Prop error: string = '';
  @Prop notice: string = '';
  onRefresh: () => void = () => {};
  onApprove: (pairingLinkId: string) => void = () => {};
  onDeny: (pairingLinkId: string) => void = () => {};
  onBack: () => void = () => {};

  build() {
    Column() {
      Row({ space: 8 }) {
        Button('返回', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(44)
          .enabled(!this.busy)
          .onClick(() => this.onBack())
        Text('设备审批')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        Button('刷新', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(44)
          .enabled(!this.busy)
          .onClick(() => this.onRefresh())
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 12 })

      Scroll() {
        Column({ space: 12 }) {
          Text(this.environmentLabel)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
          Text('环境 ID ' + this.environmentId)
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
            .wordBreak(WordBreak.BREAK_ALL)
          if (this.error || this.notice) {
            Text(this.error || this.notice)
              .fontSize(15)
              .fontColor($r('sys.color.font_primary'))
          }
          if (this.busy) {
            Row({ space: 8 }) {
              LoadingProgress().width(20).height(20)
              Text('正在处理…')
                .fontSize(14)
                .fontColor($r('sys.color.font_secondary'))
            }
          } else if (this.requests.length === 0 && !this.error) {
            Text('暂无待审批的设备。')
              .fontSize(15)
              .fontColor($r('sys.color.font_secondary'))
          }
          if (this.requests.length > 0) {
            Text('请仅批准验证码一致的设备。')
              .fontSize(15)
              .fontColor($r('sys.color.font_secondary'))
          }
          ForEach(this.requests, (request: DeviceApprovalRequest) => {
            Divider()
            Text(request.deviceLabel)
              .fontSize(16)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(request.verificationCode)
              .fontSize(23)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
            Row({ space: 8 }) {
              Button('拒绝', { buttonStyle: ButtonStyleMode.NORMAL })
                .height(44)
                .layoutWeight(1)
                .enabled(!this.busy)
                .onClick(() => this.onDeny(request.pairingLinkId))
              Button('批准')
                .height(44)
                .layoutWeight(1)
                .enabled(!this.busy)
                .onClick(() => this.onApprove(request.pairingLinkId))
            }
            .width('100%')
          }, (request: DeviceApprovalRequest) => request.pairingLinkId)
        }
        .width('100%')
        .constraintSize({ maxWidth: 480 })
        .alignItems(HorizontalAlign.Start)
        .padding(20)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .layoutWeight(1)
    .width('100%')
  }
}
