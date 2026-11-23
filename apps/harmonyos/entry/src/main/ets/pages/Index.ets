@Entry
@Component
struct Index {
  build() {
    Column() {
      Text($r('app.string.app_name'))
        .fontSize(26)
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
