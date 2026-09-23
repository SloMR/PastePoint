import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { environment } from '../../../../environments/environment';
import { isSessionCode } from '../../../utils/session-link.util';

@Injectable({
  providedIn: 'root',
})
export class SessionService {
  private http = inject(HttpClient);

  /**
   * ==========================================================
   * PROPERTIES
   * Configuration for API endpoint
   * ==========================================================
   */
  private baseUrl = `https://${environment.apiUrl}`;

  /**
   * ==========================================================
   * PUBLIC METHODS
   * API for session management
   * ==========================================================
   */
  createNewSessionCode() {
    return this.http.get<{ code: string }>(`${this.baseUrl}/create-session`);
  }

  /**
   * Validates that the session code is one the server could have issued.
   */
  isValidSessionCode(code: string): boolean {
    return isSessionCode(code);
  }

  /**
   * Strips any non-alphanumeric characters from a session code.
   */
  sanitizeSessionCode(code: string): string {
    return code.replace(/[^a-zA-Z0-9]/g, '');
  }
}
