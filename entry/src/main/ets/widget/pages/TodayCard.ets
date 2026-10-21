import { CardLine, parseCardLines } from '../../common/CardFormat';

@Entry
@Component
struct TodayCard {
  @LocalStorageProp('today_title') cardTitle: string = '纸还空着';
  @LocalStorageProp('today_domain') cardDomain: string = '';
  @LocalStorageProp('today_id') cardId: string = '';
  @LocalStorageProp('today_candidates') @Watch('onCandidatesChanged') candidatesRaw: string = '';
  @State candidates: CardLine[] = [];
  @State index: number = 0;

  aboutToAppear(): void {
    this.onCandidatesChanged();
  }

  onCandidatesChanged(): void {
    const next = parseCardLines(this.candidatesRaw);
    this.candidates = next;
    if (this.index >= next.length) {
      this.index = 0;
    }
  }

  private currentTitle(): string {
    if (this.candidates.length > 0) {
      return this.candidates[this.index].title;
    }
    return this.cardTitle;
  }

  private currentDomain(): string {
    if (this.candidates.length > 0) {
      return this.candidates[this.index].domain;
    }
    return this.cardDomain;
  }

  private currentId(): string {
    if (this.candidates.length > 0) {
      return this.candidates[this.index].id;
    }
    return this.cardId;
  }

  private shuffle(): void {
    if (this.candidates.length <= 1) {
      return;
    }
    this.index = (this.index + 1) % this.candidates.length;
  }

  private open(): void {
    const id = this.currentId();
    if (id.length === 0) {
      return;
    }
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: {
        bookmarkId: id
      }
    });
  }

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

      Text(this.currentTitle())
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink'))
        .lineHeight(22)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 10 })
        .onClick(() => this.open())

      Blank()

      Row() {
        Text(this.currentDomain().length > 0 ? this.currentDomain() : '去收第一笺')
          .fontSize(10)
          .fontColor($r('app.color.ink_tertiary'))
          .maxLines(1)
          .layoutWeight(1)
          .onClick(() => this.open())
        if (this.candidates.length > 1) {
          Text('换一笺')
            .fontSize(10)
            .fontColor($r('app.color.ink_secondary'))
            .padding({ left: 8, top: 4, bottom: 4 })
            .responseRegion({ x: -12, y: -12, width: 68, height: 44 })
            .accessibilityText('换一笺')
            .onClick(() => this.shuffle())
        }
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(14)
    .backgroundColor($r('app.color.paper'))
    .alignItems(HorizontalAlign.Start)
  }
}
