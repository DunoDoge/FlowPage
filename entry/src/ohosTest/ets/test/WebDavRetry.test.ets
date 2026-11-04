import { describe, it, expect } from '@ohos/hypium';
import { WebDavPacer, WebDavRetryPlanner } from '../../../main/ets/core/sync/WebDavRetryPlanner';

export default function webDavRetryTest() {
  describe('WebDavRetryTest', () => {
    it('retriesTransientStatusesWithBackoffLadder', 0, () => {
      const statuses: number[] = [429, 502, 503, 504];
      for (let i = 0; i < statuses.length; i++) {
        const first = WebDavRetryPlanner.planForStatus(1, statuses[i], 0);
        expect(first.retry).assertTrue();
        expect(first.delayMs).assertEqual(500);
        const second = WebDavRetryPlanner.planForStatus(2, statuses[i], 0);
        expect(second.retry).assertTrue();
        expect(second.delayMs).assertEqual(1000);
      }
    });

    it('givesUpAfterThirdAttempt', 0, () => {
      const decision = WebDavRetryPlanner.planForStatus(3, 429, 0);
      expect(decision.retry).assertFalse();
      expect(decision.delayMs).assertEqual(0);
      const network = WebDavRetryPlanner.planForNetworkError(3);
      expect(network.retry).assertFalse();
    });

    it('doesNotRetryNonTransientStatuses', 0, () => {
      const statuses: number[] = [200, 401, 403, 404, 409, 412, 500];
      for (let i = 0; i < statuses.length; i++) {
        const decision = WebDavRetryPlanner.planForStatus(1, statuses[i], 0);
        expect(decision.retry).assertFalse();
      }
    });

    it('retriesNetworkErrors', 0, () => {
      const decision = WebDavRetryPlanner.planForNetworkError(1);
      expect(decision.retry).assertTrue();
      expect(decision.delayMs).assertEqual(500);
      const second = WebDavRetryPlanner.planForNetworkError(2);
      expect(second.retry).assertTrue();
      expect(second.delayMs).assertEqual(1000);
    });

    it('retryAfterTakesPrecedenceOverBackoff', 0, () => {
      const decision = WebDavRetryPlanner.planForStatus(1, 429, 1200);
      expect(decision.retry).assertTrue();
      expect(decision.delayMs).assertEqual(1200);
    });

    it('retryAfterAboveCapFailsFast', 0, () => {
      const decision = WebDavRetryPlanner.planForStatus(1, 429, 5001);
      expect(decision.retry).assertFalse();
      const atCap = WebDavRetryPlanner.planForStatus(1, 503, 5000);
      expect(atCap.retry).assertTrue();
      expect(atCap.delayMs).assertEqual(5000);
    });

    it('invalidRetryAfterFallsBackToBackoff', 0, () => {
      expect(WebDavRetryPlanner.retryAfterMillis(0)).assertEqual(0);
      expect(WebDavRetryPlanner.retryAfterMillis(-3)).assertEqual(0);
      const decision = WebDavRetryPlanner.planForStatus(1, 429, WebDavRetryPlanner.retryAfterMillis(0));
      expect(decision.retry).assertTrue();
      expect(decision.delayMs).assertEqual(500);
    });

    it('exposesMaxAttemptsConstant', 0, () => {
      expect(WebDavRetryPlanner.MAX_ATTEMPTS).assertEqual(3);
    });

    it('pacerIdleUntilFirstThrottle', 0, () => {
      const pacer = new WebDavPacer();
      expect(pacer.pacing()).assertFalse();
      expect(pacer.currentDelayMs()).assertEqual(0);
      pacer.recordSuccess();
      expect(pacer.pacing()).assertFalse();
    });

    it('pacerActivatesAndDecaysOnSuccess', 0, () => {
      const pacer = new WebDavPacer();
      pacer.recordThrottled(429, 0);
      expect(pacer.pacing()).assertTrue();
      expect(pacer.currentDelayMs()).assertEqual(1000);
      pacer.recordSuccess();
      expect(pacer.currentDelayMs()).assertEqual(800);
      pacer.recordSuccess();
      expect(pacer.currentDelayMs()).assertEqual(640);
      for (let i = 0; i < 12; i++) {
        pacer.recordSuccess();
      }
      expect(pacer.pacing()).assertFalse();
    });

    it('pacerRetryAfterRaisesPaceWithCap', 0, () => {
      const pacer = new WebDavPacer();
      pacer.recordThrottled(429, 15000);
      expect(pacer.currentDelayMs()).assertEqual(15000);
      pacer.recordSuccess();
      pacer.recordThrottled(503, 60000);
      expect(pacer.currentDelayMs()).assertEqual(30000);
    });

    it('pacerIgnoresNonRateLimitExhaustions', 0, () => {
      const pacer = new WebDavPacer();
      expect(pacer.recordThrottled(502, 0)).assertFalse();
      expect(pacer.recordThrottled(504, 0)).assertFalse();
      expect(pacer.pacing()).assertFalse();
    });

    it('pacerAbortRequiresConsecutiveExhaustions', 0, () => {
      const pacer = new WebDavPacer();
      expect(pacer.recordThrottled(429, 0)).assertFalse();
      expect(pacer.recordThrottled(429, 0)).assertFalse();
      pacer.recordSuccess();
      expect(pacer.recordThrottled(429, 0)).assertFalse();
      expect(pacer.recordThrottled(429, 0)).assertFalse();
      expect(pacer.recordThrottled(429, 0)).assertTrue();
    });
  });
}
