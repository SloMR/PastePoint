import { Component, EventEmitter, Input, Output, ChangeDetectionStrategy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { TranslatePipe } from '@ngx-translate/core';

@Component({
  selector: 'app-create-room-popup',
  imports: [CommonModule, FormsModule, TranslatePipe],
  templateUrl: './create-room-popup.component.html',
  changeDetection: ChangeDetectionStrategy.Eager,
  styleUrl: './create-room-popup.component.css',
})
export class CreateRoomPopupComponent {
  @Input() isOpen = false;
  @Input() roomName = '';

  @Output() roomNameChange = new EventEmitter<string>();
  @Output() closed = new EventEmitter<void>();
  @Output() submitted = new EventEmitter<void>();
}
