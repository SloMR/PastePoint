export class MockDataChannel {
  readyState: RTCDataChannelState = 'connecting';
  binaryType: BinaryType = 'blob';
  bufferedAmountLowThreshold = 0;
  readonly sent: string[] = [];
  onopen: (() => void) | null = null;
  onclose: (() => void) | null = null;

  send(data: string): void {
    this.sent.push(data);
  }

  open(): void {
    this.readyState = 'open';
    this.onopen?.();
  }

  close(): void {
    this.readyState = 'closed';
    this.onclose?.();
  }
}
