import { pasteboard } from '@kit.BasicServicesKit';
import { AppState } from '../common/AppState';
import { BookmarkSource } from '../common/Constants';
import { domainOf, extractAllUrls, extractFirstUrl, isValidHttpUrl } from '../common/UrlUtil';
import { FlowRepository } from '../repository/FlowRepository';

// Motion constants (change inbox-sheet-motion design D3). The sheet stays
// mounted and animates by transform (drawer lesson: conditional mount +
// transition does not animate). The outer travel is driven by the node's
// implicit .animation() -- the only translate mechanism proven in this
// codebase (drawer / PaneEntrance); a body-level animateTo never captured
// the panel translate (three acceptance rounds of instant appearance) and
// its companion spring-scale repaint janked the cascade. Entrances use the
// house curve FastOutSlowIn; exits accelerate away; the launch flavor dips
// before gliding out. Field cascade reuses the D11 pane vocabulary.
const INBOX_ENTER_DURATION: number = 400;
const INBOX_SCRIM_IN: number = 240;
const INBOX_SCRIM_OUT: number = 160;
// Launch flavor lets the scrim linger slightly so the rise reads against
// a still-dimming backdrop instead of a bare screen.
const INBOX_SCRIM_LAUNCH_OUT: number = 200;
const INBOX_EXIT_DURATION: number = 300;
// Launch dip: the bottom-docked phone sheet must detach from its edge
// before flying up (a shallow dip leaves the edge tearing -- the "rupture"
// feedback), hence a deep 32vp sink; the anchorless centered card keeps a
// subtle 6vp anticipation. FastOutSlowIn reads as compress-and-hold.
const INBOX_LAUNCH_DIP: number = 100;
const PHONE_LAUNCH_DIP_Y: number = 32;
const WIDE_LAUNCH_DIP_Y: number = 6;
// Phone floating-card inset (see panelMargin).
const PHONE_CARD_MARGIN: number = 12;
// Launch rise matches the entrance (same travel, same curve, same
// duration) so saving away reads as fast as opening, just upward.
const INBOX_LAUNCH_RISE: number = INBOX_ENTER_DURATION;
const WIDE_CARD_MAX_W_MID: number = 600;
const WIDE_CARD_MAX_W_LARGE: number = 720;
// Numeric travel keeps every interpolation number-to-number (the drawer's
// proven pattern). Phone hides bottom-docked at 900vp (covers the tallest
// form incl. the batch block); a centered card needs more because its own
// height does not lift it past the window edge, hence 2000vp.
const INBOX_TRAVEL_PHONE: number = 900;
const WIDE_TRAVEL_VP: number = 2000;
// First-field delay scales with the slower entrance (device feedback:
// fields arriving too early read as racing the panel).
const CASCADE_DELAY: number = 120;
const CASCADE_STEP: number = 30;
const CASCADE_FIELD: number = 180;
const CASCADE_RISE: number = 12;
const BTN_PULSE_MS: number = 90;
const DENY_NUDGE_MS: number = 80;
const HINT_MOTION: number = 150;
const HINT_MAX_H: number = 18;
const BATCH_REVEAL: number = 180;
const BATCH_MAX_H: number = 320;
const BATCH_STEP: number = 30;
const BATCH_CASCADE_CAP: number = 6;
const ROW_COLLAPSE: number = 160;
const ROW_MAX_H: number = 60;
// 60ms grace past ROW_COLLAPSE so the dying row's collapse tail fully
// settles before the data commit removes it.
const ROW_CLEAR: number = 220;
const DENY_NUDGE_X: number = 4;
const PHONE_CARD_MAX_W: number = 560;

// Persistent-mount phase machine. AppState.showInbox stays the single
// intent source; the exit flavor differs only in panel trajectory.
// ENTERING and OPEN are behaviorally equivalent today (gates and motion
// params treat them alike); the OPEN flip only marks "entrance settled".
// Any future consumer distinguishing them needs a generation guard -- the
// ENTERING timer can fire into a second entrance after a fast reopen.
enum InboxPhase {
  CLOSED = 0,
  ENTERING = 1,
  OPEN = 2,
  EXITING = 3,
  LAUNCHING = 4
}

@ComponentV2
export struct InboxSheet {
  @Local appState: AppState = AppState.shared;
  @Local urlText: string = '';
  @Local titleText: string = '';
  @Local tagsText: string = '';
  @Local noteText: string = '';
  @Local batchUrls: string[] = [];
  @Local dyingUrls: string[] = [];
  @Local busy: boolean = false;
  @Local phase: InboxPhase = InboxPhase.CLOSED;
  @Local launchExit: boolean = false;
  @Local launchRisen: boolean = false;
  @Local fieldsShown: boolean = false;
  @Local pulseDown: boolean = false;
  @Local denyNudge: boolean = false;
  // Panel travel as a plain numeric state (drawer's proven pattern): the
  // transition entry points write numeric targets and the outer node's
  // implicit .animation() interpolates; .translate binds the number
  // directly. No percent strings (never validated in this project) and no
  // Visibility toggling -- a None->Visible frame snapshots the new geometry
  // instead of interpolating from the old one (round-2 root cause).
  @Local panelOffsetY: number = WIDE_TRAVEL_VP;
  @Param isWide: boolean = false;
  @Param isLarge: boolean = false;

  aboutToAppear(): void {
    // Cold start with a share want already routed: the mount-time open
    // never fires the monitor.
    if (this.appState.showInbox) {
      this.beginEnter();
    } else {
      // Start from the breakpoint-correct hidden offset so the very first
      // phone entrance (900vp, not the wide 2000vp default) matches every
      // later one.
      this.panelOffsetY = this.hiddenOffset();
    }
  }

  private parseTags(): string[] {
    const tags: string[] = [];
    const raw = this.tagsText.split(',');
    for (let i = 0; i < raw.length; i++) {
      const name = raw[i].trim();
      if (name.length > 0 && tags.indexOf(name) < 0) {
        tags.push(name);
      }
    }
    const rawCn = this.tagsText.split('，');
    for (let i = 0; i < rawCn.length; i++) {
      const name = rawCn[i].trim();
      if (name.length > 0 && tags.indexOf(name) < 0) {
        tags.push(name);
      }
    }
    return tags;
  }

  private seedForm(): void {
    this.urlText = this.appState.inboxUrl;
    this.titleText = '';
    this.tagsText = '';
    this.noteText = '';
    this.batchUrls = [];
    this.dyingUrls = [];
    this.launchExit = false;
    this.launchRisen = false;
  }

  private hiddenOffset(): number {
    return this.isWide ? WIDE_TRAVEL_VP : INBOX_TRAVEL_PHONE;
  }

  // The launch dip rides a nested node so its offset composes with (not
  // replaces) the outer travel state; depth is breakpoint-scoped (see
  // PHONE/WIDE_LAUNCH_DIP_Y).
  private dipY(): number {
    if (this.phase !== InboxPhase.LAUNCHING || this.launchRisen) {
      return 0;
    }
    return this.isWide ? WIDE_LAUNCH_DIP_Y : PHONE_LAUNCH_DIP_Y;
  }

  // Drawer-proven driver: the outer node's implicit .animation() carries
  // the travel. Params are phase-scoped so each leg keeps its own curve;
  // CLOSED resolves to duration 0 so offscreen resets (launch finish,
  // breakpoint re-hide) snap instead of animating back through the screen.
  // The panel body itself must stay scale/opacity-free (repaint cost and
  // the security-component ancestor rule).
  private motionParams(): AnimateParam {
    if (this.phase === InboxPhase.CLOSED) {
      return { duration: 0 };
    }
    if (this.phase === InboxPhase.LAUNCHING) {
      return { duration: INBOX_LAUNCH_RISE, curve: Curve.FastOutSlowIn };
    }
    if (this.phase === InboxPhase.EXITING) {
      return { duration: INBOX_EXIT_DURATION, curve: Curve.EaseIn };
    }
    return { duration: INBOX_ENTER_DURATION, curve: Curve.FastOutSlowIn };
  }

  private panelWidth(): string {
    if (this.isLarge) {
      return '70%';
    }
    if (this.isWide) {
      return '84%';
    }
    // A bare '100%' resolves against the full parent width and the side
    // margins then overflow (pixel-verified: the insets never rendered);
    // calc keeps width and margins consistent.
    return `calc(100% - ${PHONE_CARD_MARGIN * 2}vp)`;
  }

  private panelMaxWidth(): number {
    if (this.isLarge) {
      return WIDE_CARD_MAX_W_LARGE;
    }
    if (this.isWide) {
      return WIDE_CARD_MAX_W_MID;
    }
    return PHONE_CARD_MAX_W;
  }

  private panelMargin(): Margin {
    // Phone keeps bottom anchoring for thumb reach but presents as a
    // floating card (rounded corners + inset edges): a square full-width
    // slab launching upward reads as a curtain being ripped off the edge
    // (round-5 feedback), while a card reads as an object that can fly.
    // The scrim alone keeps the system-bar immersion.
    if (this.isWide) {
      return {};
    }
    return { left: PHONE_CARD_MARGIN, right: PHONE_CARD_MARGIN, bottom: PHONE_CARD_MARGIN };
  }

  private hintOpen(): boolean {
    return this.urlText.length > 0 && isValidHttpUrl(this.urlText);
  }

  private hintDomain(): string {
    return this.hintOpen() ? domainOf(this.urlText) : '';
  }

  private rowDying(url: string): boolean {
    return this.dyingUrls.indexOf(url) >= 0;
  }

  private liveBatchUrls(): string[] {
    return this.batchUrls.filter((one: string): boolean => !this.rowDying(one));
  }

  private liveCount(): number {
    return this.liveBatchUrls().length;
  }

  private batchOpen(): boolean {
    return this.liveCount() > 0;
  }

  private beginEnter(): void {
    if (!this.appState.showInbox || this.phase === InboxPhase.ENTERING
      || this.phase === InboxPhase.OPEN) {
      return;
    }
    this.seedForm();
    // Plain writes: the outer node's implicit .animation() animates the
    // travel (drawer pattern); the phase handoff rides a guarded timer
    // because onFinish timing is unreliable on this node. A reopen mid-exit
    // simply retargets from wherever the exit currently is.
    this.phase = InboxPhase.ENTERING;
    this.panelOffsetY = 0;
    setTimeout(() => {
      if (this.appState.showInbox && this.phase === InboxPhase.ENTERING) {
        this.phase = InboxPhase.OPEN;
      }
    }, INBOX_ENTER_DURATION);
    // Cascade flips with the entrance so the per-field delays apply; the
    // fields stay interactive while they fade in.
    this.fieldsShown = true;
  }

  private snapClosed(): void {
    this.phase = InboxPhase.CLOSED;
    this.launchRisen = false;
    this.fieldsShown = false;
    this.dyingUrls = [];
    // Plain write under the CLOSED duration-0 params: the panel is already
    // offscreen, and a mid-exit reopen needs the next entrance to start
    // from a clean hidden offset.
    this.panelOffsetY = this.hiddenOffset();
  }

  private beginDismiss(): void {
    // Plain writes + guarded timer (see beginEnter); the implicit
    // .animation() picks the EaseIn leg from the EXITING phase.
    this.phase = InboxPhase.EXITING;
    this.panelOffsetY = this.hiddenOffset();
    setTimeout(() => {
      this.finalizeClose();
    }, INBOX_EXIT_DURATION);
  }

  private beginLaunch(): void {
    // The dip rides the nested node's own implicit animation (phase flip);
    // both sequencing hops use guarded timers because onFinish timing is
    // unreliable on this node.
    this.phase = InboxPhase.LAUNCHING;
    setTimeout(() => {
      // A reopen mid-launch hands the panel back to the entrance; the
      // rise must not fire into the new trajectory.
      if (this.phase !== InboxPhase.LAUNCHING || this.launchRisen || this.appState.showInbox) {
        return;
      }
      this.launchRisen = true;
      this.panelOffsetY = -this.hiddenOffset();
      setTimeout(() => {
        this.finalizeClose();
      }, INBOX_LAUNCH_RISE);
    }, INBOX_LAUNCH_DIP);
  }

  private beginExit(): void {
    // Persistent mount keeps TextInput focus; drop it so the keyboard
    // collapses with the exit instead of lingering over the page.
    this.getUIContext().getFocusController().clearFocus();
    if (this.launchExit) {
      this.beginLaunch();
    } else {
      this.beginDismiss();
    }
  }

  private finalizeClose(): void {
    if (this.appState.showInbox) {
      return;
    }
    this.snapClosed();
  }

  // Button transients ride bare timers on purpose: the sheet is
  // app-lifetime mounted and any stale write after a reseed is an idempotent
  // no-op (flags reset, lists emptied), so no cancellation bookkeeping.
  private pulse(): void {
    this.pulseDown = true;
    setTimeout(() => {
      this.pulseDown = false;
    }, BTN_PULSE_MS);
  }

  private deny(): void {
    this.denyNudge = true;
    setTimeout(() => {
      this.denyNudge = false;
    }, DENY_NUDGE_MS);
  }

  private async save(): Promise<void> {
    if (this.busy) {
      return;
    }
    if (!isValidHttpUrl(this.urlText)) {
      this.deny();
      AppState.shared.toast('这不是一个可收的链接');
      return;
    }
    this.busy = true;
    try {
      const outcome = await FlowRepository.get().saveUrl(
        this.urlText,
        this.titleText,
        this.parseTags(),
        this.noteText,
        BookmarkSource.MANUAL
      );
      if (outcome.created) {
        this.launchExit = true;
        this.appState.closeInbox();
        AppState.shared.toast('收下了');
        FlowRepository.get().applyMetadata(outcome.bookmark.id).catch(() => {});
      } else {
        this.deny();
        AppState.shared.toast('这一笺已经收过');
      }
    } catch (error) {
      this.deny();
      AppState.shared.toast('没收下，请检查链接');
    } finally {
      this.busy = false;
    }
  }

  private async readClipboard(): Promise<void> {
    try {
      const data = await pasteboard.getSystemPasteboard().getData();
      const text = data.getPrimaryText();
      const all = extractAllUrls(text);
      if (all.length > 1) {
        this.batchUrls = all;
        this.dyingUrls = [];
        return;
      }
      if (all.length === 1) {
        this.batchUrls = [];
        this.dyingUrls = [];
        this.urlText = all[0];
        return;
      }
      // Legacy single-link path: keep inferring bare domains for hand-typed
      // text; batch extraction above is strictly explicit http(s).
      const found = extractFirstUrl(text);
      if (found.length === 0) {
        AppState.shared.toast('剪贴板里没有链接');
        return;
      }
      this.urlText = found;
    } catch (error) {
      AppState.shared.toast('读不到剪贴板');
    }
  }

  private async saveBatch(): Promise<void> {
    if (this.busy || this.liveCount() === 0) {
      return;
    }
    this.busy = true;
    try {
      const outcome = await FlowRepository.get().saveUrls(this.liveBatchUrls(), BookmarkSource.MANUAL);
      if (outcome.done === 0 && outcome.skipped > 0) {
        this.deny();
        AppState.shared.toast('这些都已收过');
      } else {
        this.launchExit = true;
        this.appState.closeInbox();
        const skipSuffix = outcome.skipped > 0 ? `、跳过 ${outcome.skipped} 条` : '';
        AppState.shared.toast(`收下 ${outcome.done} 条${skipSuffix}`);
      }
    } catch (error) {
      this.deny();
      AppState.shared.toast('没收下，请检查链接');
    } finally {
      this.busy = false;
    }
  }

  private removeBatchUrl(url: string): void {
    if (this.rowDying(url)) {
      return;
    }
    // The list keeps render order: the row dies visually first, then the
    // data commits after the collapse so siblings slide instead of jump.
    this.dyingUrls = this.dyingUrls.concat([url]);
    setTimeout(() => {
      this.batchUrls = this.liveBatchUrls();
      this.dyingUrls = [];
    }, ROW_CLEAR);
  }

  @Monitor('appState.showInbox')
  onShowInboxChange(): void {
    if (this.appState.showInbox) {
      // Reopen mid-exit retargets in place: the ENTERING phase write swaps
      // the implicit-animation params and the offset write drags the value
      // back from wherever the exit currently is -- no timers to cancel, no
      // snap (a timed restart raced the in-flight animation and froze the
      // panel mid-screen in device testing).
      this.beginEnter();
      return;
    }
    if (this.phase !== InboxPhase.CLOSED) {
      this.beginExit();
    }
  }

  @Monitor('appState.inboxUrl')
  onInboxUrlChange(): void {
    // Live reseed while the sheet is already open (second share intent).
    if (this.appState.showInbox && this.appState.inboxUrl.length > 0) {
      this.urlText = this.appState.inboxUrl;
    }
  }

  @Monitor('isWide')
  onIsWideChange(): void {
    // A breakpoint change while closed must re-hide: the phone travel does
    // not clear a centered card (and vice versa).
    if (this.phase === InboxPhase.CLOSED) {
      this.panelOffsetY = this.hiddenOffset();
    }
  }

  build() {
    Stack({ alignContent: this.isWide ? Alignment.Center : Alignment.Bottom }) {
      // Scrim binds to the intent flag (not the phase) so it stays out of
      // the panel's travel writes; hit testing drops the moment the exit
      // starts so the layer below is tappable immediately.
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .hitTestBehavior(this.appState.showInbox ? HitTestMode.Default : HitTestMode.None)
        .opacity(this.appState.showInbox ? 1 : 0)
        .animation({
          duration: this.appState.showInbox
            ? INBOX_SCRIM_IN
            : (this.launchExit ? INBOX_SCRIM_LAUNCH_OUT : INBOX_SCRIM_OUT),
          curve: Curve.FastOutSlowIn
        })
        .onClick(() => this.appState.closeInbox())

      // Outer motion node: binds the numeric travel state directly (no
      // percent strings, no Visibility toggling -- see panelOffsetY). The
      // styled panel below carries only the small dip offset.
      Column() {
        Column() {
          Row()
            .width(36)
            .height(3)
            .backgroundColor($r('app.color.line_strong'))
            .borderRadius(2)
            .margin({ bottom: 8 })

          Row() {
            Text('收一笺')
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
            Blank()
            Text('关闭')
              .fontSize(13)
              .fontColor($r('app.color.ink_secondary'))
              .height(44)
              .padding({ left: 10 })
              .accessibilityText('关闭收笺面板')
              .onClick(() => this.appState.closeInbox())
          }
          .width('100%')
          .margin({ top: 12 })

          Row({ space: 8 }) {
            TextInput({ text: this.urlText, placeholder: 'https://…' })
              .fontSize(14)
              .fontColor($r('app.color.ink'))
              .placeholderColor($r('app.color.ink_tertiary'))
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(6)
              .height(44)
              .layoutWeight(1)
              .onChange((value: string) => {
                this.urlText = value;
              })
            PasteButton({ text: PasteDescription.PASTE })
              .fontSize(14)
              .fontColor($r('app.color.ink_secondary'))
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(6)
              .height(44)
              .padding({ left: 16, right: 16 })
              .onClick((event: ClickEvent, result: PasteButtonOnClickResult) => {
                if (result === PasteButtonOnClickResult.SUCCESS) {
                  this.readClipboard();
                } else {
                  AppState.shared.toast('没有获得剪贴板授权');
                }
              })
          }
          // Rise-only cascade (no fade): PasteButton is a security component
          // and any ancestor with opacity != 1 fails its validity check, so
          // the row that hosts it must never change opacity.
          .width('100%')
          .margin({ top: 12 })
          .translate({ y: this.fieldsShown ? 0 : CASCADE_RISE })
          .animation({ delay: CASCADE_DELAY, duration: CASCADE_FIELD, curve: Curve.FastOutSlowIn })

          // Domain hint: persistent node with an animated height cap so the
          // appearance and disappearance are symmetric reveals.
          Text(this.hintDomain())
            .fontSize(12)
            .fontColor($r('app.color.ink_tertiary'))
            .width('100%')
            .constraintSize({ maxHeight: this.hintOpen() ? HINT_MAX_H : 0 })
            .clip(true)
            .opacity(this.hintOpen() ? 1 : 0)
            .margin({ top: this.hintOpen() ? 12 : 0 })
            .animation({ duration: HINT_MOTION, curve: Curve.FastOutSlowIn })

          // Batch block: persistent clipped container; rows keep their order
          // while dying rows collapse in place.
          Column({ space: 10 }) {
            Row() {
              Text(`识别到 ${this.liveCount()} 条链接`)
                .fontSize(13)
                .fontColor($r('app.color.ink'))
              Blank()
              Text('点一条移除一条')
                .fontSize(11)
                .fontColor($r('app.color.ink_tertiary'))
            }
            .width('100%')

            Scroll() {
              Column() {
                ForEach(this.batchUrls, (url: string, index: number) => {
                  Column() {
                    Column({ space: 2 }) {
                      Text(domainOf(url).length > 0 ? domainOf(url) : url)
                        .fontSize(12)
                        .fontColor($r('app.color.ink'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(url)
                        .fontSize(11)
                        .fontColor($r('app.color.ink_tertiary'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .width('100%')
                    .constraintSize({ minHeight: 44 })
                    .justifyContent(FlexAlign.Center)
                    .opacity(this.batchOpen() ? 1 : 0)
                    .translate({ y: this.batchOpen() ? 0 : CASCADE_RISE })
                    .animation({
                      delay: Math.min(index * BATCH_STEP, BATCH_CASCADE_CAP * BATCH_STEP),
                      duration: CASCADE_FIELD,
                      curve: Curve.FastOutSlowIn
                    })
                    .onClick(() => this.removeBatchUrl(url))
                  }
                  .constraintSize({ maxHeight: this.rowDying(url) ? 0 : ROW_MAX_H })
                  .clip(true)
                  .opacity(this.rowDying(url) ? 0 : 1)
                  .animation({ duration: ROW_COLLAPSE, curve: Curve.FastOutSlowIn })
                }, (url: string) => url)
              }
              .width('100%')
            }
            .width('100%')
            .constraintSize({ maxHeight: 216 })
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.None)

            Row({ space: 10 }) {
              Text(this.busy ? '正在收下…' : `收下这 ${this.liveCount()} 条`)
                .fontSize(14)
                .fontColor($r('app.color.inverse_ink'))
                .backgroundColor($r('app.color.ink'))
                .borderRadius(6)
                .height(44)
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .accessibilityText(`收下这 ${this.liveCount()} 条链接`)
                .scale({
                  x: this.pulseDown ? 0.96 : 1,
                  y: this.pulseDown ? 0.96 : 1
                })
                .translate({ x: this.denyNudge ? DENY_NUDGE_X : 0 })
                .animation({ duration: BTN_PULSE_MS, curve: Curve.FastOutSlowIn })
                .onClick(() => {
                  this.pulse();
                  this.saveBatch();
                })
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(16)
                .fontColor([$r('app.color.ink_secondary')])
                .height(44)
                .padding({ left: 10, right: 4 })
                .accessibilityText('忽略这批链接')
                .onClick(() => {
                  this.batchUrls = [];
                  this.dyingUrls = [];
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .padding(10)
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(8)
          .alignItems(HorizontalAlign.Start)
          .constraintSize({ maxHeight: this.batchOpen() ? BATCH_MAX_H : 0 })
          .clip(true)
          .opacity(this.batchOpen() ? 1 : 0)
          .margin({ top: this.batchOpen() ? 12 : 0 })
          .animation({ duration: BATCH_REVEAL, curve: Curve.FastOutSlowIn })

          if (this.isLarge) {
            // Responsive two-column row (>=1000vp): title and tags share one
            // line; cascade order and per-field motion are unchanged.
            Row({ space: 8 }) {
              TextInput({ text: this.titleText, placeholder: '标题（可留空，稍后自动补全）' })
                .fontSize(15)
                .fontColor($r('app.color.ink'))
                .placeholderColor($r('app.color.ink_tertiary'))
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(6)
                .height(44)
                .layoutWeight(1)
                .opacity(this.fieldsShown ? 1 : 0)
                .translate({ y: this.fieldsShown ? 0 : CASCADE_RISE })
                .animation({
                  delay: CASCADE_DELAY + CASCADE_STEP,
                  duration: CASCADE_FIELD,
                  curve: Curve.FastOutSlowIn
                })
                .onChange((value: string) => {
                  this.titleText = value;
                })
              TextInput({ text: this.tagsText, placeholder: '标签，用逗号分隔' })
                .fontSize(14)
                .fontColor($r('app.color.ink'))
                .placeholderColor($r('app.color.ink_tertiary'))
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(6)
                .height(44)
                .layoutWeight(1)
                .opacity(this.fieldsShown ? 1 : 0)
                .translate({ y: this.fieldsShown ? 0 : CASCADE_RISE })
                .animation({
                  delay: CASCADE_DELAY + CASCADE_STEP * 2,
                  duration: CASCADE_FIELD,
                  curve: Curve.FastOutSlowIn
                })
                .onChange((value: string) => {
                  this.tagsText = value;
                })
            }
            .width('100%')
            .margin({ top: 12 })
          } else {
            TextInput({ text: this.titleText, placeholder: '标题（可留空，稍后自动补全）' })
              .fontSize(15)
              .fontColor($r('app.color.ink'))
              .placeholderColor($r('app.color.ink_tertiary'))
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(6)
              .height(44)
              .margin({ top: 12 })
              .opacity(this.fieldsShown ? 1 : 0)
              .translate({ y: this.fieldsShown ? 0 : CASCADE_RISE })
              .animation({
                delay: CASCADE_DELAY + CASCADE_STEP,
                duration: CASCADE_FIELD,
                curve: Curve.FastOutSlowIn
              })
              .onChange((value: string) => {
                this.titleText = value;
              })

            TextInput({ text: this.tagsText, placeholder: '标签，用逗号分隔' })
              .fontSize(14)
              .fontColor($r('app.color.ink'))
              .placeholderColor($r('app.color.ink_tertiary'))
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(6)
              .height(44)
              .margin({ top: 12 })
              .opacity(this.fieldsShown ? 1 : 0)
              .translate({ y: this.fieldsShown ? 0 : CASCADE_RISE })
              .animation({
                delay: CASCADE_DELAY + CASCADE_STEP * 2,
                duration: CASCADE_FIELD,
                curve: Curve.FastOutSlowIn
              })
              .onChange((value: string) => {
                this.tagsText = value;
              })
          }

          TextArea({ text: this.noteText, placeholder: '备注（可选）' })
            .fontSize(14)
            .fontColor($r('app.color.ink'))
            .placeholderColor($r('app.color.ink_tertiary'))
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(6)
            .height(76)
            .margin({ top: 12 })
            .opacity(this.fieldsShown ? 1 : 0)
            .translate({ y: this.fieldsShown ? 0 : CASCADE_RISE })
            .animation({
              delay: CASCADE_DELAY + CASCADE_STEP * 3,
              duration: CASCADE_FIELD,
              curve: Curve.FastOutSlowIn
            })
            .onChange((value: string) => {
              this.noteText = value;
            })

          Column() {
            Text(this.busy ? '正在收下…' : '收下')
              .fontSize(15)
              .fontColor($r('app.color.inverse_ink'))
              .backgroundColor($r('app.color.ink'))
              .borderRadius(6)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 12, bottom: 12 })
              .scale({
                x: this.pulseDown ? 0.96 : 1,
                y: this.pulseDown ? 0.96 : 1
              })
              .translate({ x: this.denyNudge ? DENY_NUDGE_X : 0 })
              .animation({ duration: BTN_PULSE_MS, curve: Curve.FastOutSlowIn })
              .onClick(() => {
                this.pulse();
                this.save();
              })
          }
          .width('100%')
          .margin({ top: 16 })
          .opacity(this.fieldsShown ? 1 : 0)
          .translate({ y: this.fieldsShown ? 0 : CASCADE_RISE })
          .animation({
            delay: CASCADE_DELAY + CASCADE_STEP * 4,
            duration: CASCADE_FIELD,
            curve: Curve.FastOutSlowIn
          })
        }
        .width(this.panelWidth())
        .constraintSize({ maxWidth: this.panelMaxWidth() })
        .margin(this.panelMargin())
        .padding({ left: 22, right: 22, top: 12, bottom: 28 })
        .backgroundColor($r('app.color.surface'))
        .borderRadius(16)
        .translate({ y: this.dipY() })
        .animation({ duration: INBOX_LAUNCH_DIP, curve: Curve.FastOutSlowIn })
        .enabled(this.phase === InboxPhase.ENTERING || this.phase === InboxPhase.OPEN)
        .hitTestBehavior(this.phase === InboxPhase.ENTERING || this.phase === InboxPhase.OPEN
          ? HitTestMode.Default
          : HitTestMode.None)
        .onClick(() => {})
      }
      .translate({ y: this.panelOffsetY })
      .animation(this.motionParams())
      // Hiding is purely geometric (the travel offsets always clear the
      // window); hit-test / enablement / a11y gates below handle the rest.
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel(this.phase === InboxPhase.CLOSED ? 'no-hide-descendants' : 'auto')
  }
}
