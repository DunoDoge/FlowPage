import { describe, it, expect } from '@ohos/hypium';
import { AppState, ToastAction } from '../../../main/ets/common/AppState';

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: (value: void) => void) => {
    setTimeout((): void => {
      resolve();
    }, ms);
  });
}

export default function toastTest() {
  describe('ToastTest', () => {
    it('actionToastStaysUntilTimeout', 0, async () => {
      const state = AppState.shared;
      state.toastWithAction('已删除一条笺', ToastAction.of('撤回', (): void => {}));
      await sleep(2700);
      // Still visible past the plain-toast window: pins the 5000ms duration
      // (a regression to 2400 would fail here).
      expect(state.toastText).assertEqual('已删除一条笺');
      expect(state.toastAction !== undefined).assertTrue();
      await sleep(2700);
      expect(state.toastText).assertEqual('');
      expect(state.toastAction).assertUndefined();
    });

    it('runToastActionInvokesCallbackOnceAndClears', 0, async () => {
      const state = AppState.shared;
      let calls: number = 0;
      state.toastWithAction('已删除一条笺', ToastAction.of('撤回', (): void => {
        calls = calls + 1;
      }));
      state.runToastAction();
      expect(calls).assertEqual(1);
      expect(state.toastText).assertEqual('');
      expect(state.toastAction).assertUndefined();
      await sleep(2700);
      expect(calls).assertEqual(1);
      expect(state.toastText).assertEqual('');
    });

    it('newToastOverwritesPreviousWithoutFiringOldAction', 0, async () => {
      const state = AppState.shared;
      let firstCalls: number = 0;
      state.toastWithAction('第一条', ToastAction.of('撤回', (): void => {
        firstCalls = firstCalls + 1;
      }));
      state.toastWithAction('第二条', ToastAction.of('撤回', (): void => {}));
      expect(state.toastText).assertEqual('第二条');
      state.toast('纯文本');
      expect(state.toastText).assertEqual('纯文本');
      expect(state.toastAction).assertUndefined();
      state.runToastAction();
      expect(state.toastText).assertEqual('');
      expect(firstCalls).assertEqual(0);
    });

    it('supersedingTimerIsCancelled', 0, async () => {
      const state = AppState.shared;
      state.toast('同一句');
      await sleep(2000);
      state.toastWithAction('同一句', ToastAction.of('撤回', (): void => {}));
      // Without timer cancellation the plain toast's 2400ms timeout would
      // clear this same-text action toast at t=2400.
      await sleep(900);
      expect(state.toastText).assertEqual('同一句');
      expect(state.toastAction !== undefined).assertTrue();
      state.runToastAction();
    });
  });
}
