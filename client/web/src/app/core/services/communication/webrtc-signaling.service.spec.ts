import { afterEach, beforeEach, describe, expect, test, vitest } from 'vitest';
import { SignalingFixture } from '../../../testing/signaling-fixture';

describe('WebRTCSignalingService', () => {
  let fixture: SignalingFixture;

  beforeEach(() => {
    vitest.useFakeTimers();
    fixture = new SignalingFixture();
  });

  afterEach(() => {
    vitest.useRealTimers();
  });

  test("after a connection fails to build, the peer isn't left connecting", async () => {
    fixture.factory.failsToConnect = true;

    fixture.signaling.initiateConnection('bob');
    expect(fixture.signaling.isConnecting('bob')).toBe(true);

    await vitest.advanceTimersByTimeAsync(0);
    expect(fixture.signaling.isConnecting('bob')).toBe(false);
  });
});
