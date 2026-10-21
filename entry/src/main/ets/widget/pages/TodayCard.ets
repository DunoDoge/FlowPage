@Entry
@Component
struct TodayCard {
  @LocalStorageProp('today_title') cardTitle: string = '纸还空着';
  @LocalStorageProp('today_domain') cardDomain: string = '';
  @LocalStorageProp('today_id') cardId: string = '';

  build() {
    Column() {
      Row({ space: 6 }) {
        Row()
          .width(2)
          .height(12)
          .backgroundColor($r('app.color.ink'))
          .borderRadius(1)
        Text('今日笺')
          .fontSize(10)
          .fontColor($r('app.color.ink_secondary'))
          .letterSpacing(1)
      }
      .width('100%')

      Text(this.cardTitle)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink'))
        .lineHeight(22)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 10 })

      Blank()

      Text(this.cardDomain.length > 0 ? this.cardDomain : '去收第一笺')
        .fontSize(10)
        .fontColor($r('app.color.ink_tertiary'))
        .maxLines(1)
        .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(14)
    .backgroundColor($r('app.color.paper'))
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      if (this.cardId.length > 0) {
        postCardAction(this, {
          action: 'router',
          abilityName: 'EntryAbility',
          params: {
            bookmarkId: this.cardId
          }
        });
      }
    })
  }
}
