export class MockTurnCredentials {
  readonly iceServers: RTCIceServer[] = [];
  private isPaused = false;
  private waiting: (() => void)[] = [];

  get pausedConnections(): number {
    return this.waiting.length;
  }

  pauseNewConnections(): void {
    this.isPaused = true;
  }

  resumeNewConnections(): void {
    this.isPaused = false;
    const waiting = this.waiting;
    this.waiting = [];
    waiting.forEach((resume) => resume());
  }

  ready(): Promise<void> {
    if (!this.isPaused) {
      return Promise.resolve();
    }
    return new Promise((resume) => this.waiting.push(resume));
  }

  async refresh(): Promise<void> {
    return;
  }
}
