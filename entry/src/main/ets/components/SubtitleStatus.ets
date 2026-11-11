// Shared stream count subtitle: "N 条 · 今天收下 N 条" in the home header
// trailing slot (<1000vp), the docked hamburger row (>=1000vp) and the
// freeform title strip. Values come from the stream loader (StreamHome).
@ComponentV2
export struct SubtitleStatus {
  @Param loading: boolean = false;
  @Param total: number = 0;
  @Param todayCount: number = 0;

  private text(): string {
    if (this.loading) {
      return '正在翻开…';
    }
    return `${this.total} 条 · 今天收下 ${this.todayCount} 条`;
  }

  build() {
    Text(this.text())
      .fontSize(12)
      .fontColor($r('app.color.ink_tertiary'))
  }
}
