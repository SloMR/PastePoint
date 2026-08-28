import { Injectable } from '@angular/core';
import * as Sentry from '@sentry/angular';
import { startNewTrace } from '@sentry/core';

export type TelemetrySpan = Sentry.Span;
export type TelemetryAttributes = Record<string, string | number | boolean>;

export interface TelemetrySpanEnd {
  ok: boolean;
  outcome?: string;
  message?: string;
  attributes?: TelemetryAttributes;
}

@Injectable({ providedIn: 'root' })
export class TelemetryService {
  /**
   * Starts a detached span.
   * Must be concluded with endSpan().
   */
  public startSpan(op: string, attributes?: TelemetryAttributes, name = op): TelemetrySpan {
    let span!: TelemetrySpan;
    startNewTrace(() => {
      span = Sentry.startInactiveSpan({ name, op, attributes });
    });
    return span;
  }

  /** Runs `work` inside a span in its own trace; the span ends when it settles. */
  public withSpan<T>(op: string, work: (span: TelemetrySpan) => Promise<T>): Promise<T> {
    return startNewTrace(() => Sentry.startSpan({ name: op, op }, (span) => work(span)));
  }

  public setAttributes(span: TelemetrySpan | undefined, attributes: TelemetryAttributes): void {
    if (!span) return;
    for (const [key, value] of Object.entries(attributes)) {
      span.setAttribute(key, value);
    }
  }

  /** Records how a span concluded without ending it (for spans that end elsewhere). */
  public markSpan(span: TelemetrySpan | undefined, end: TelemetrySpanEnd): void {
    if (!span) return;
    if (end.attributes) this.setAttributes(span, end.attributes);
    if (end.outcome) span.setAttribute('outcome', end.outcome);
    span.setStatus({
      code: end.ok ? 1 : 2,
      message: end.message ?? (end.ok ? 'ok' : (end.outcome ?? 'error')),
    });
  }

  public endSpan(span: TelemetrySpan | undefined, end: TelemetrySpanEnd): void {
    if (!span) return;
    this.markSpan(span, end);
    span.end();
  }

  /** Countable product event — counts/sizes/kinds only, never content. */
  public event(message: string, attributes?: TelemetryAttributes): void {
    Sentry.logger.info(message, attributes);
  }

  /** Countable anomaly event (warn); same rules as event(). */
  public warnEvent(message: string, attributes?: TelemetryAttributes): void {
    Sentry.logger.warn(message, attributes);
  }

  /** Diagnostic breadcrumb attached to future error events. */
  public breadcrumb(
    category: string,
    message: string,
    level: 'info' | 'warning' | 'error' = 'info',
    data?: Record<string, unknown>
  ): void {
    Sentry.addBreadcrumb({ category, message, level, data });
  }
}
