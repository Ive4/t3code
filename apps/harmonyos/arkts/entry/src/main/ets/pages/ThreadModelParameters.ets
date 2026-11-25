import { UiLanguage, uiText } from './UiLanguage';
import type { ThreadModelOptionChoice, ThreadModelOptionDescriptor } from '../client/ThreadModelOptionProtocol';

@Component
export struct ThreadModelParameterRows {
  @Prop descriptors: ThreadModelOptionDescriptor[] = [];
  @Prop language: UiLanguage = 'zh';
  @Prop idPrefix: string = 'thread-model-parameter';
  @Prop editable: boolean = true;
  onOpen: (id: string) => void = () => {};
  onChange: (id: string, value: boolean) => void = () => {};

  private valueLabel(descriptor: ThreadModelOptionDescriptor): string {
    if (descriptor.promptControlled) return 'Ultrathink';
    return descriptor.options.find((choice: ThreadModelOptionChoice) => choice.id === descriptor.currentValue)?.label ?? uiText(this.language, '默认', 'Default');
  }

  @Builder
  private ParameterLabel(descriptor: ThreadModelOptionDescriptor) {
    Column({ space: 4 }) {
      Text(descriptor.label).fontSize(15).fontColor($r('sys.color.font_primary'))
      if (descriptor.description) {
        Text(descriptor.description).fontSize(12).fontColor($r('sys.color.font_secondary'))
          .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }

  @Builder
  private Parameter(descriptor: ThreadModelOptionDescriptor) {
    if (descriptor.type === 'boolean') {
      Row({ space: 8 }) {
        this.ParameterLabel(descriptor)
        Toggle({ type: ToggleType.Switch, isOn: descriptor.currentValue === true })
          .id(`${this.idPrefix}-${descriptor.id}`).accessibilityText(descriptor.label)
          .enabled(this.editable).onChange((value: boolean) => this.onChange(descriptor.id, value))
      }.width('100%').constraintSize({ minHeight: 52 }).padding({ left: 12, right: 12, top: 6, bottom: 6 })
    } else {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        Row({ space: 8 }) {
          this.ParameterLabel(descriptor)
          Text(this.valueLabel(descriptor)).fontSize(14).fontColor($r('sys.color.font_secondary'))
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 136 })
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([$r('sys.color.icon_secondary')])
        }.width('100%').padding({ top: 6, bottom: 6 })
      }.id(`${this.idPrefix}-${descriptor.id}`).width('100%').constraintSize({ minHeight: 52 })
        .accessibilityText(`${descriptor.label}，${this.valueLabel(descriptor)}`)
        .enabled(this.editable && descriptor.options.length > 0).onClick(() => this.onOpen(descriptor.id))
    }
  }

  build() {
    if (this.descriptors.length) {
      Column() {
        ForEach(this.descriptors, (descriptor: ThreadModelOptionDescriptor) => {
          this.Parameter(descriptor)
        }, (descriptor: ThreadModelOptionDescriptor) => `${descriptor.id}:${descriptor.currentValue}:${descriptor.promptControlled}`)
      }.width('100%').borderRadius(14).backgroundColor($r('sys.color.comp_background_secondary'))
    }
  }
}

@Component
export struct ThreadModelParameterChoices {
  @Prop descriptor?: ThreadModelOptionDescriptor = undefined;
  @Prop language: UiLanguage = 'zh';
  @Prop idPrefix: string = 'thread-model-parameter';
  @Prop editable: boolean = true;
  onChoose: (value: string) => void = () => {};

  @Builder
  private Choice(choice: ThreadModelOptionChoice) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Text(choice.label).fontSize(16).fontColor($r('sys.color.font_primary'))
          if (choice.description) Text(choice.description).fontSize(12).fontColor($r('sys.color.font_secondary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (!this.descriptor?.promptControlled && choice.id === this.descriptor?.currentValue) {
          SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16).fontColor([$r('sys.color.icon_emphasize')])
        }
      }.width('100%').padding({ top: 8, bottom: 8 })
    }.id(`${this.idPrefix}-${this.descriptor?.id ?? ''}-${choice.id}`).width('100%').constraintSize({ minHeight: 50 })
      .enabled(this.editable && !this.descriptor?.promptLocked)
      .accessibilitySelected(!this.descriptor?.promptControlled && choice.id === this.descriptor?.currentValue)
      .onClick(() => this.onChoose(choice.id))
  }

  build() {
    Scroll() {
      Column({ space: 4 }) {
        if (this.descriptor?.promptLocked) {
          Text(uiText(this.language, '消息正文中的 Ultrathink 指令控制此参数。',
            'The Ultrathink instruction in the message controls this option.')).fontSize(13).fontColor($r('sys.color.font_secondary'))
            .padding({ left: 12, right: 12, bottom: 8 })
        }
        ForEach(this.descriptor?.options ?? [], (choice: ThreadModelOptionChoice) => {
          this.Choice(choice)
        }, (choice: ThreadModelOptionChoice) => choice.id)
      }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 12, right: 12, bottom: 12 })
    }.width('100%').align(Alignment.Top).scrollBar(BarState.Off)
  }
}
