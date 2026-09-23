import { Component, EventEmitter, Input, Output, ChangeDetectionStrategy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { TranslatePipe } from '@ngx-translate/core';

@Component({
  selector: 'app-end-session-popup',
  imports: [CommonModule, TranslatePipe],
  templateUrl: './end-session-popup.component.html',
  changeDetection: ChangeDetectionStrategy.Eager,
  styleUrl: './end-session-popup.component.css',
})
export class EndSessionPopupComponent {
  @Input() isOpen = false;

  @Output() closed = new EventEmitter<void>();
  @Output() confirmed = new EventEmitter<void>();
}
