import { workspaceForegroundColor, workspaceGroupedCardColor, workspaceMutedColor } from './WorkspaceChrome';

export interface SettingsRowContent {
  id: string;
  label: string;
  detail?: string;
  value?: string;
  icon?: Resource;
  kind?: 'link' | 'choice' | 'switch';
  disabled?: boolean;
  selected?: boolean;
}

function rowKey(item: SettingsRowContent): string {
  // A retained ArkUI ForEach child keeps the original plain object.
  const content = [item.id, item.label, item.detail ?? '', item.value ?? '', item.kind ?? '',
    String(item.disabled ?? false), item.selected === undefined ? '' : String(item.selected)];
  return JSON.stringify(content);
}

@Component
struct SettingsRow {
  @Prop item: SettingsRowContent = { id: '', label: '' };
  @Prop dark: boolean | undefined = undefined;
  onSelect: (item: SettingsRowContent) => void = () => {};

  private foreground(): ResourceColor {
    return this.dark === undefined ? $r('sys.color.font_primary') : workspaceForegroundColor(this.dark);
  }

  private muted(): ResourceColor {
    return this.dark === undefined ? $r('sys.color.font_secondary') : workspaceMutedColor(this.dark);
  }

  private accessibilityLabel(): string {
    return [this.item.label, this.item.detail ?? '', this.item.value ?? ''].filter((value) => !!value).join(', ');
  }

  @Builder
  private ChoiceIndicator() {
    Stack() {
      if (this.item.selected) {
        Circle().width(10).height(10).fill(this.foreground())
      }
    }
    .width(20)
    .height(20)
    .border({ width: 2, color: this.item.selected ? this.foreground() : this.muted() })
    .borderRadius(10)
  }

  build() {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 12 }) {
        if (this.item.icon) {
          SymbolGlyph(this.item.icon)
            .fontSize(this.dark === undefined ? 22 : 24)
            .fontColor([this.dark === undefined ? $r('sys.color.icon_primary') : this.foreground()])
        }
        Column({ space: 4 }) {
          Text(this.item.label)
            .fontSize(16)
            .lineHeight('23fp')
            .fontColor(this.foreground())
          if (this.item.detail) {
            Text(this.item.detail)
              .fontSize(13)
              .lineHeight('17fp')
              .fontColor(this.muted())
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        if (this.item.value) {
          Text(this.item.value).fontSize(this.dark === undefined ? 13 : 14).fontColor(this.muted())
            .constraintSize({ maxWidth: this.dark === undefined ? '45%' : '40%' })
            .maxLines(this.dark === undefined ? 2 : 1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (this.item.kind === 'link') {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(this.dark === undefined ? 14 : 16)
            .fontColor([this.dark === undefined ? $r('sys.color.icon_secondary') : this.muted()])
        } else if (this.item.kind === 'choice') {
          this.ChoiceIndicator()
        } else if (this.item.kind === 'switch') {
          Toggle({ type: ToggleType.Switch }).enabled(false)
        }
      }
      .width('100%')
      .constraintSize({ minHeight: this.dark !== undefined && this.item.detail ? 72 : 56 })
      .padding({ left: 16, right: 16, top: this.dark === undefined ? 12 : 8, bottom: this.dark === undefined ? 12 : 8 })
      .opacity(this.item.disabled && this.dark !== undefined ? 0.45 : 1)
    }
    .id(this.item.id)
    .width('100%')
    .height('auto')
    .borderRadius(0)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .accessibilityGroup(true)
    .accessibilityText(this.accessibilityLabel())
    .accessibilitySelected(this.item.selected ?? false)
    .enabled(!this.item.disabled && (this.item.kind === 'link' ||
      (this.item.kind === 'choice' && this.item.selected !== undefined)))
    .onClick(() => this.onSelect(this.item))
  }
}

@Component
export struct WorkspaceSettingsRows {
  @Prop title: string = '';
  @Prop rows: SettingsRowContent[] = [];
  @Prop dark: boolean | undefined = undefined;
  onSelect: (item: SettingsRowContent) => void = () => {};

  build() {
    if (this.rows.length > 0) {
      Column({ space: 8 }) {
        if (this.title) {
          Text(this.title).fontSize(13).lineHeight('17fp').fontWeight(FontWeight.Medium)
            .fontColor(this.dark === undefined ? $r('sys.color.font_secondary') : workspaceMutedColor(this.dark))
            .margin({ left: 16 })
        }
        Column() {
          ForEach(this.rows, (item: SettingsRowContent, index: number) => {
            if (this.dark === undefined && index > 0) {
              Divider().color($r('sys.color.comp_divider')).margin({ left: 16, right: 16 })
            }
            SettingsRow({ item, dark: this.dark, onSelect: this.onSelect })
          }, (item: SettingsRowContent) => rowKey(item))
        }
        .width('100%')
        .backgroundColor(this.dark === undefined ? $r('sys.color.comp_background_tertiary') : workspaceGroupedCardColor(this.dark))
        .borderRadius(this.dark === undefined ? 26 : 28)
        .clip(true)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }
}
