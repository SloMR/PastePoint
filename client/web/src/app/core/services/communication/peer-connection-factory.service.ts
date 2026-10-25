import { Injectable } from '@angular/core';

@Injectable({
  providedIn: 'root',
})
export class PeerConnectionFactory {
  isSupported(): boolean {
    return typeof RTCPeerConnection !== 'undefined';
  }

  create(configuration: RTCConfiguration): RTCPeerConnection {
    return new RTCPeerConnection(configuration);
  }
}
