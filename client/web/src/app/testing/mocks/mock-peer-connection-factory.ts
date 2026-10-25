import { MockDataChannel } from './mock-data-channel';
import { MockPeerConnection } from './mock-peer-connection';

export class MockPeerConnectionFactory {
  failsToConnect = false;
  readonly connections: MockPeerConnection[] = [];

  get liveConnections(): MockPeerConnection[] {
    return this.connections.filter((connection) => !connection.closed);
  }

  isSupported(): boolean {
    return true;
  }

  create(): RTCPeerConnection {
    if (this.failsToConnect) {
      throw new Error('could not create a peer connection');
    }
    const connection = new MockPeerConnection();
    this.connections.push(connection);
    return connection as unknown as RTCPeerConnection;
  }

  lastChannel(): MockDataChannel {
    const channel = this.connections.at(-1)?.channel;
    if (!channel) {
      throw new Error('no data channel yet');
    }
    return channel;
  }
}
