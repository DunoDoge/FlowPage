import { window } from '@kit.ArkUI';

// Breathing gap between trailing content and the sunk window buttons.
export const AVOIDANCE_MARGIN_VP: number = 12;

// App-drawn strip height; must stay in sync with the hidden system decor
// strip height pinned by EntryAbility so the sunk window buttons keep
// their reserved band.
export const STRIP_HEIGHT_VP: number = 40;

// The title strip renders only in freeform windows: floating and maximized.
// True fullscreen relies on the system hover bar; split-screen and the
// non-freeform fullscreen app mode keep the system chrome untouched.
export function showStrip(freeWindow: boolean, windowStatus: window.WindowStatusType): boolean {
  return freeWindow && (windowStatus === window.WindowStatusType.FLOATING ||
    windowStatus === window.WindowStatusType.MAXIMIZE);
}

// Right-edge reserve keeping strip content clear of the sunk window buttons:
// rect.right is the gap from the window edge, width the button band itself.
// Units follow getTitleButtonRect output (device-calibrated, see tasks 4.5).
export function avoidanceWidth(rect: window.TitleButtonRect, margin: number): number {
  return rect.right + rect.width + margin;
}

// Trailing reserve for any top-band surface that shares the window edge
// with the sunk decor buttons (strip trailing content, full-window reading
// cover toolbar). Zero outside freeform windows: other modes keep the
// system chrome and have no floating button band to avoid.
export function sunkButtonAvoidance(freeWindow: boolean, rectRight: number,
  rectWidth: number, margin: number): number {
  if (!freeWindow) {
    return 0;
  }
  const rect: window.TitleButtonRect = {
    right: rectRight,
    top: 0,
    width: rectWidth,
    height: 0
  };
  return avoidanceWidth(rect, margin);
}
