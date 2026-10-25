import { Subject } from 'rxjs';
import { SignalMessage } from '../../utils/constants';

export class MockWebSocketConnection {
  readonly signalMessages$ = new Subject<SignalMessage>();
  readonly connected$ = new Subject<void>();
  readonly sent: SignalMessage[] = [];

  isConnected(): boolean {
    return true;
  }

  sendSignalMessage(message: SignalMessage): void {
    this.sent.push(message);
  }
}
