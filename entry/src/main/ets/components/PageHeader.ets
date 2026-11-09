// Shared page header for tab-hosted sub pages: a caller-supplied trailing
// status slot only. Back and sidebar menu moved out with the floating tab
// bar: destinations are tabs below 1000vp and the rail above, so these
// pages never need a back control or a drawer entry of their own.
@ComponentV2
export struct PageHeader {
  @Builder
  NoopTrailing() {
  }

  @BuilderParam trailing: () => void = this.NoopTrailing;

  build() {
    Row() {
      Blank()

      this.trailing()
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12 })
  }
}
