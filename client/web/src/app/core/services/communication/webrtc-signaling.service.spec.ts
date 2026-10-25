import { afterEach, beforeEach, describe, expect, test, vitest } from 'vitest';
import { SignalingFixture } from '../../../testing/signaling-fixture';
import { DATA_CHANNEL_MESSAGE_TYPES, SignalMessageType } from '../../../utils/constants';

function chat(text: string) {
  return { type: DATA_CHANNEL_MESSAGE_TYPES.CHAT, payload: { text } };
}

function textOf(frame: string): string {
  return (JSON.parse(frame) as { payload: { text: string } }).payload.text;
}

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

  test('a frame sent when the peer connects arrives after the frames queued before it', async () => {
    fixture.signaling.initiateConnection('bob');
    await vitest.advanceTimersByTimeAsync(0);
    const channel = fixture.factory.lastChannel();

    fixture.communication.sendData(chat('one'), 'bob');
    fixture.communication.sendData(chat('two'), 'bob');
    fixture.signaling.peerConnected$.subscribe(() => {
      fixture.communication.sendData(chat('three'), 'bob');
    });

    channel.open();
    expect(channel.sent.map(textOf)).toEqual(['one', 'two', 'three']);
  });

  test('a teardown followed by a new attempt never leaves two live connections', async () => {
    fixture.turnCredentials.pauseNewConnections();
    fixture.signaling.initiateConnection('bob');
    fixture.signaling.closeConnection('bob');
    fixture.signaling.initiateConnection('bob');
    expect(fixture.turnCredentials.pausedConnections).toBe(2);

    fixture.turnCredentials.resumeNewConnections();
    await vitest.advanceTimersByTimeAsync(0);

    expect(fixture.factory.connections).toHaveLength(1);
    expect(fixture.factory.liveConnections).toHaveLength(1);
  });

  test("after a peer's connection closes, a retry starts a new one", async () => {
    fixture.signaling.initiateConnection('bob');
    await vitest.advanceTimersByTimeAsync(0);
    const channel = fixture.factory.lastChannel();

    channel.open();
    channel.close();
    await vitest.advanceTimersByTimeAsync(2_000);

    const offers = fixture.transport.sent.filter(
      (message) => message.type === SignalMessageType.OFFER
    );
    expect(fixture.factory.connections).toHaveLength(2);
    expect(fixture.signaling.getPeerConnection('bob')).toBe(fixture.factory.connections[1]);
    expect(offers).toHaveLength(2);
  });
});
