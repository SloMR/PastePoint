import { Injectable } from '@angular/core';
import { Observable, of } from 'rxjs';
import { ToastConfig } from '@ngxpert/hot-toast';

@Injectable()
export class MockHotToastService {
  toasts: { type: string; message: string; title: string }[] = [];
  private _config: Partial<ToastConfig> | undefined;

  success(message: string, title?: string, config?: Partial<ToastConfig>): Observable<unknown> {
    this._config = config;
    this.toasts.push({ type: 'success', message, title: title ?? '' });
    return of({});
  }

  error(message: string, title?: string, config?: Partial<ToastConfig>): Observable<unknown> {
    this._config = config;
    this.toasts.push({ type: 'error', message, title: title ?? '' });
    return of({});
  }

  info(message: string, title?: string, config?: Partial<ToastConfig>): Observable<unknown> {
    this._config = config;
    this.toasts.push({ type: 'info', message, title: title ?? '' });
    return of({});
  }

  warning(message: string, title?: string, config?: Partial<ToastConfig>): Observable<unknown> {
    this._config = config;
    this.toasts.push({ type: 'warning', message, title: title ?? '' });
    return of({});
  }

  clear() {
    this.toasts = [];
    return of({});
  }
}
