// Pure retry decision logic for WebDavTransport: maps a failed request
// (attempt count + HTTP status or network-error marker + Retry-After hint)
// to a wait-before-retry delay or a give-up verdict. Kept IO-free so device
// tests can cover the backoff ladder, Retry-After precedence and the
// fast-fail cap without a real server.

export class RetryDecision {
  retry: boolean = false;
  delayMs: number = 0;
}

export class WebDavRetryPlanner {
  static readonly MAX_ATTEMPTS: number = 3;
  private static readonly BACKOFF_MS: number[] = [500, 1000, 2000];
  private static readonly RETRY_AFTER_CAP_MS: number = 5000;

  // Transient server-side failures only; auth/permission/not-found/conflict
  // statuses must fail fast so LWW and tombstone semantics stay unchanged.
  static isRetryableStatus(status: number): boolean {
    return status === 429 || status === 502 || status === 503 || status === 504;
  }

  // Seconds from a Retry-After header; 0 (or negative/invalid) means absent.
  static retryAfterMillis(seconds: number): number {
    if (!Number.isFinite(seconds) || seconds <= 0) {
      return 0;
    }
    return Math.round(seconds * 1000);
  }

  static planForStatus(attemptsMade: number, status: number, retryAfterMs: number): RetryDecision {
    if (!WebDavRetryPlanner.isRetryableStatus(status)) {
      return new RetryDecision();
    }
    return WebDavRetryPlanner.plan(attemptsMade, retryAfterMs);
  }

  static planForNetworkError(attemptsMade: number): RetryDecision {
    return WebDavRetryPlanner.plan(attemptsMade, 0);
  }

  private static plan(attemptsMade: number, retryAfterMs: number): RetryDecision {
    const decision = new RetryDecision();
    if (attemptsMade >= WebDavRetryPlanner.MAX_ATTEMPTS) {
      return decision;
    }
    const index = attemptsMade < 1 ? 0 : attemptsMade - 1;
    let delay = WebDavRetryPlanner.BACKOFF_MS[index];
    if (retryAfterMs > 0) {
      if (retryAfterMs > WebDavRetryPlanner.RETRY_AFTER_CAP_MS) {
        // Server asks for more than the cap: fail this request now instead
        // of stalling the whole sync run.
        return decision;
      }
      delay = retryAfterMs;
    }
    decision.retry = true;
    decision.delayMs = delay;
    return decision;
  }
}

// Event-triggered AIMD pacing for throttle storms: activates only after a
// request exhausts its retries on 429/503, spaces subsequent requests, and
// decays back to zero on success. Sustained exhaustion while paced trips a
// run-level abort so the sync finishes fast and resumes next round.
export class WebDavPacer {
  private static readonly BASE_PACE_MS: number = 1000;
  private static readonly MAX_PACE_MS: number = 30000;
  private static readonly MIN_PACE_MS: number = 100;
  private static readonly DECAY_FACTOR: number = 0.8;
  private static readonly ABORT_STREAK: number = 3;

  private delayMs: number = 0;
  private streak: number = 0;

  pacing(): boolean {
    return this.delayMs > 0;
  }

  currentDelayMs(): number {
    return this.delayMs;
  }

  recordSuccess(): void {
    this.streak = 0;
    if (!this.pacing()) {
      return;
    }
    this.delayMs = Math.floor(this.delayMs * WebDavPacer.DECAY_FACTOR);
    if (this.delayMs < WebDavPacer.MIN_PACE_MS) {
      this.delayMs = 0;
    }
  }

  // Feeds one throttle-exhausted request; retryAfterMs (already bounded or 0)
  // raises the pace when the server asks for more. Only rate-limit signals
  // (429/503) feed the pacer: 502/504 exhaustion is server trouble, not
  // throttling, so it neither feeds nor clears the pace. Returns true when
  // the consecutive-exhaustion streak says the server is hard-limiting and
  // the whole run should abort.
  recordThrottled(status: number, retryAfterMs: number): boolean {
    if (status !== 429 && status !== 503) {
      return false;
    }
    this.streak = this.streak + 1;
    let pace = WebDavPacer.BASE_PACE_MS;
    if (retryAfterMs > pace) {
      pace = retryAfterMs > WebDavPacer.MAX_PACE_MS ? WebDavPacer.MAX_PACE_MS : retryAfterMs;
    }
    if (pace > this.delayMs) {
      this.delayMs = pace;
    }
    return this.streak >= WebDavPacer.ABORT_STREAK;
  }
}
