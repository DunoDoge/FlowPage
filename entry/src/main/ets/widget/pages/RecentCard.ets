class RecentItem {
  title: string = '';
  domain: string = '';
  id: string = '';
}

@Entry
@Component
struct RecentCard {
  @LocalStorageProp('recent_lines') @Watch('onLinesChanged') recentLines: string = '';
  @State items: RecentItem[] = [];

  aboutToAppear(): void {
    this.onLinesChanged();
  }

  onLinesChanged(): void {
    const next: RecentItem[] = [];
    if (this.recentLines.length > 0) {
      const lines = this.recentLines.split('\n');
      for (let i = 0; i < lines.length; i++) {
        const parts = lines[i].split('|');
        if (parts.length >= 3) {
          const item = new RecentItem();
          item.title = parts[0];
          item.domain = parts[1];
          item.id = parts[2];
          next.push(item);
        }
      }
    }
    this.items = next;
  }

  private open(id: string): void {
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
      Row() {
        Text('最近')
          .fontSize(10)
          .fontColor($r('app.color.ink_secondary'))
          .letterSpacing(1)
        Blank()
        Text('流笺')
          .fontSize(9)
          .fontColor($r('app.color.ink_tertiary'))
      }
      .width('100%')
      .margin({ bottom: 6 })

      if (this.items.length === 0) {
        Column({ space: 4 }) {
          Text('纸还空着')
            .fontSize(14)
            .fontColor($r('app.color.ink'))
          Text('去收第一笺')
            .fontSize(10)
            .fontColor($r('app.color.ink_tertiary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        ForEach(this.items, (item: RecentItem) => {
          Column() {
            Text(item.title)
              .fontSize(13)
              .fontColor($r('app.color.ink'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(item.domain)
              .fontSize(9)
              .fontColor($r('app.color.ink_tertiary'))
              .maxLines(1)
              .width('100%')
              .margin({ top: 2 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Start)
          .onClick(() => this.open(item.id))
        }, (item: RecentItem) => item.id)
      }
    }
    .width('100%')
    .height('100%')
    .padding(14)
    .backgroundColor($r('app.color.paper'))
    .alignItems(HorizontalAlign.Start)
  }
}
