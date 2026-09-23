import { Component, EventEmitter, Input, Output, ChangeDetectionStrategy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { TranslateModule } from '@ngx-translate/core';

@Component({
  selector: 'app-connection-warning',
  imports: [CommonModule, TranslateModule],
  templateUrl: './connection-warning.component.html',
  changeDetection: ChangeDetectionStrategy.Eager,
  styleUrl: './connection-warning.component.css',
})
export class ConnectionWarningComponent {
  @Input() show = false;

  @Output() refreshed = new EventEmitter<void>();
  @Output() dismissed = new EventEmitter<void>();
}
