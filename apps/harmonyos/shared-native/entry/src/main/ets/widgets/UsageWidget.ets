interface UsageWidgetRow {
  label: string;
  remaining: number;
}

const storage = new LocalStorage();

@Entry(storage)
@Component
struct UsageWidget {
  @LocalStorageProp('title') title: string = '';
  @LocalStorageProp('message') message: string = '';
  @LocalStorageProp('asOf') asOf: string = '';
  @LocalStorageProp('rows') rows: UsageWidgetRow[] = [];

  build() {
    Column({ space: 3 }) {
      Text(this.title || $r('app.string.usage_widget_title'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.rows.length === 0) {
        Text(this.message || $r('app.string.usage_widget_refresh'))
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
      } else {
        ForEach(this.rows, (row: UsageWidgetRow) => {
          Row({ space: 10 }) {
            Text(row.label)
              .layoutWeight(1)
              .fontSize(13)
              .fontColor($r('sys.color.font'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Progress({ value: row.remaining, total: 100, type: ProgressType.Linear })
              .width('25%')
          }.width('100%')
        })
        if (this.asOf) {
          Text(this.asOf)
            .fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
        }
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { t3Widget: 'usage' },
      });
    })
  }
}
