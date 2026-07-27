import { ChangeDetectionStrategy, Component, EventEmitter, Output, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { TranslateModule } from '@ngx-translate/core';
import { DeviceDetectorService } from 'ngx-device-detector';

import { extractSessionCode } from '../../../../utils/session-link.util';

@Component({
  selector: 'app-join-code-form',
  imports: [CommonModule, FormsModule, TranslateModule],
  templateUrl: './join-code-form.component.html',
  styleUrl: './join-code-form.component.css',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class JoinCodeFormComponent {
  @Output() joinRequested = new EventEmitter<string>();
  @Output() scanRequested = new EventEmitter<void>();

  protected code = '';

  private deviceDetector = inject(DeviceDetectorService);

  protected get showScan(): boolean {
    return !this.deviceDetector.isDesktop();
  }

  protected get canJoin(): boolean {
    return this.code.trim().length > 0;
  }

  protected submit(): void {
    if (!this.canJoin) return;

    this.joinRequested.emit(extractSessionCode(this.code) ?? this.code.trim());
    this.code = '';
  }
}
