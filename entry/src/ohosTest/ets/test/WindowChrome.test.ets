import { describe, it, expect } from '@ohos/hypium';
import { window } from '@kit.ArkUI';
import { showStrip, avoidanceWidth, sunkButtonAvoidance } from '../../../main/ets/common/WindowChrome';

export default function windowChromeTest() {
  describe('WindowChromeTest', () => {
    it('rendersStripOnlyInFreeformFloatingOrMaximized', 0, () => {
      expect(showStrip(true, window.WindowStatusType.FLOATING)).assertTrue();
      expect(showStrip(true, window.WindowStatusType.MAXIMIZE)).assertTrue();
    });

    it('hidesStripInTrueFullscreenSplitMinimizedAndUndefined', 0, () => {
      expect(showStrip(true, window.WindowStatusType.FULL_SCREEN)).assertFalse();
      expect(showStrip(true, window.WindowStatusType.SPLIT_SCREEN)).assertFalse();
      expect(showStrip(true, window.WindowStatusType.MINIMIZE)).assertFalse();
      expect(showStrip(true, window.WindowStatusType.UNDEFINED)).assertFalse();
    });

    it('hidesStripInNonFreeformModes', 0, () => {
      expect(showStrip(false, window.WindowStatusType.FLOATING)).assertFalse();
      expect(showStrip(false, window.WindowStatusType.MAXIMIZE)).assertFalse();
      expect(showStrip(false, window.WindowStatusType.FULL_SCREEN)).assertFalse();
      expect(showStrip(false, window.WindowStatusType.SPLIT_SCREEN)).assertFalse();
      expect(showStrip(false, window.WindowStatusType.UNDEFINED)).assertFalse();
    });

    it('avoidanceSumsRightGapButtonBandAndMargin', 0, () => {
      const rect: window.TitleButtonRect = { right: 8, top: 6, width: 138, height: 40 };
      expect(avoidanceWidth(rect, 12)).assertEqual(158);
      expect(avoidanceWidth(rect, 0)).assertEqual(146);
    });

    it('avoidanceFallsBackToMarginWithoutButtonRect', 0, () => {
      const empty: window.TitleButtonRect = { right: 0, top: 0, width: 0, height: 0 };
      expect(avoidanceWidth(empty, 12)).assertEqual(12);
    });

    it('sunkAvoidanceStaysZeroOutsideFreeform', 0, () => {
      expect(sunkButtonAvoidance(false, 0, 140, 12)).assertEqual(0);
      expect(sunkButtonAvoidance(false, 8, 140, 12)).assertEqual(0);
    });

    it('sunkAvoidanceSumsPartsInFreeform', 0, () => {
      expect(sunkButtonAvoidance(true, 0, 140, 12)).assertEqual(152);
      expect(sunkButtonAvoidance(true, 8, 140, 12)).assertEqual(160);
      expect(sunkButtonAvoidance(true, 0, 0, 12)).assertEqual(12);
    });
  });
}
