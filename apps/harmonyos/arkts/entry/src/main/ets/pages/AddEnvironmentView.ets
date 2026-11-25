@Component
export struct AddEnvironmentView {
  @StorageLink('t3.arkts.keyboardVisible') private keyboardVisible: boolean = false;
  @Prop @Watch('showIncomingLink') link: string = '';
  @Prop pairing: boolean = false;
  @Prop scanning: boolean = false;
  @Prop error: string = '';
  @Prop initialAddress: string = '';
  onLink: (link: string) => void = () => {};
  onScan: () => void = () => {};
  onSubmit: (address: string, code: string) => void = () => {};
  @State private address: string = '';
  @State private code: string = '';
  @State private linkMode: boolean = false;

  aboutToAppear(): void {
    this.address = this.initialAddress;
    this.showIncomingLink();
  }

  private showIncomingLink(): void {
    if (this.link.trim()) this.linkMode = true;
  }

  private canSubmit(): boolean {
    return !this.pairing && !this.scanning && (this.linkMode ? !!this.link.trim() :
      !!this.address.trim() && !!this.code.trim());
  }

  @Builder
  private ScannerCard() {
    Column({ space: 12 }) {
      Text('扫描配对码')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
      Text('在电脑的 T3 Code 环境设置中打开配对二维码。')
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
      Button('打开扫码')
        .height(44)
        .enabled(!this.pairing && !this.scanning)
        .onClick(() => this.onScan())
    }.width('100%').alignItems(HorizontalAlign.Start).padding(16).borderRadius(22)
      .backgroundColor($r('sys.color.comp_background_secondary'))
  }

  @Builder
  private PairingFields() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(this.linkMode ? '配对链接' : '手动输入')
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .layoutWeight(1)
        Button(this.linkMode ? '输入地址和配对码' : '使用配对链接', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(44)
          .enabled(!this.pairing && !this.scanning)
          .onClick(() => { this.linkMode = !this.linkMode; })
      }.width('100%')
      if (this.linkMode) {
        TextInput({ text: this.link, placeholder: '配对链接' })
          .id('environment-pair-link')
          .type(InputType.URL)
          .height(48)
          .enabled(!this.pairing)
          .onChange((value: string) => this.onLink(value))
      } else {
        TextInput({ text: this.address, placeholder: '服务器地址' })
          .id('environment-address')
          .type(InputType.URL)
          .height(48)
          .enabled(!this.pairing)
          .onChange((value: string) => { this.address = value; })
        TextInput({ text: this.code, placeholder: '配对码' })
          .id('environment-code')
          .type(InputType.Password)
          .height(48)
          .enabled(!this.pairing)
          .onChange((value: string) => { this.code = value; })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 16 }) {
          if (!this.keyboardVisible) {
            this.ScannerCard()
          }
          this.PairingFields()
        }.width('100%').alignItems(HorizontalAlign.Start).padding(20)
      }.width('100%').layoutWeight(1).align(Alignment.Top)
      Column({ space: 8 }) {
        if (this.error) {
          Text(this.error).fontSize(14).fontColor($r('sys.color.font_primary'))
        }
        Button(this.pairing ? '正在连接…' : '配对环境')
          .width('100%')
          .height(46)
          .enabled(this.canSubmit())
          .onClick(() => {
            if (this.linkMode) this.onSubmit('', '');
            else this.onSubmit(this.address, this.code);
          })
      }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 20, right: 20, top: 8, bottom: 12 })
    }.width('100%').layoutWeight(1)
  }
}
