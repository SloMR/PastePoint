import { TestBed } from '@angular/core/testing';
import { of } from 'rxjs';
import { TestImports, TestProviders } from './test-helper';
import { MockPeerConnectionFactory } from './mocks/mock-peer-connection-factory';
import { MockTurnCredentials } from './mocks/mock-turn-credentials';
import { MockWebSocketConnection } from './mocks/mock-websocket-connection';
import { WebRTCSignalingService } from '../core/services/communication/webrtc-signaling.service';
import { WebRTCCommunicationService } from '../core/services/communication/webrtc-communication.service';
import { WebSocketConnectionService } from '../core/services/communication/websocket-connection.service';
import { TurnCredentialsService } from '../core/services/communication/turn-credentials.service';
import { PeerConnectionFactory } from '../core/services/communication/peer-connection-factory.service';
import { BlockService } from '../core/services/communication/block.service';
import { UserService } from '../core/services/user-management/user.service';

export class SignalingFixture {
  readonly me = 'alice';
  readonly transport = new MockWebSocketConnection();
  readonly turnCredentials = new MockTurnCredentials();
  readonly factory = new MockPeerConnectionFactory();
  readonly signaling: WebRTCSignalingService;
  readonly communication: WebRTCCommunicationService;

  constructor() {
    TestBed.configureTestingModule({
      imports: TestImports,
      providers: [
        ...TestProviders,
        { provide: WebSocketConnectionService, useValue: this.transport },
        { provide: TurnCredentialsService, useValue: this.turnCredentials },
        { provide: PeerConnectionFactory, useValue: this.factory },
        { provide: UserService, useValue: { user: this.me, user$: of(this.me) } },
        { provide: BlockService, useValue: { isBlocked: () => false } },
      ],
    });
    this.signaling = TestBed.inject(WebRTCSignalingService);
    this.communication = TestBed.inject(WebRTCCommunicationService);
  }
}
