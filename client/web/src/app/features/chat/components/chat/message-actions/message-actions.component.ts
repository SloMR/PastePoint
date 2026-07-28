import {
  ChangeDetectionStrategy,
  Component,
  ElementRef,
  EventEmitter,
  HostListener,
  Input,
  Output,
  inject,
  signal,
} from '@angular/core';
import { TranslateModule } from '@ngx-translate/core';

@Component({
  selector: 'app-message-actions',
  imports: [TranslateModule],
  templateUrl: './message-actions.component.html',
  styleUrl: './message-actions.component.css',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class MessageActionsComponent {
  @Input() isRTL = false;

  @Output() blockRequested = new EventEmitter<void>();
  @Output() reportRequested = new EventEmitter<void>();

  protected readonly isOpen = signal(false);

  private host = inject(ElementRef<HTMLElement>);

  protected toggle(): void {
    this.isOpen.update((open) => !open);
  }

  protected block(): void {
    this.isOpen.set(false);
    this.blockRequested.emit();
  }

  protected report(): void {
    this.isOpen.set(false);
    this.reportRequested.emit();
  }

  @HostListener('document:click', ['$event'])
  protected onDocumentClick(event: MouseEvent): void {
    if (!this.isOpen()) return;
    const target = event.target as Node | null;
    if (target && !this.host.nativeElement.contains(target)) {
      this.isOpen.set(false);
    }
  }

  @HostListener('document:keydown.escape')
  protected onEscape(): void {
    if (this.isOpen()) this.isOpen.set(false);
  }
}
