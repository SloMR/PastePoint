import { ChangeDetectionStrategy, Component, EventEmitter, Input, Output } from '@angular/core';
import { CommonModule } from '@angular/common';
import { TranslateModule } from '@ngx-translate/core';

import { WelcomeCardComponent } from './welcome-card/welcome-card.component';
import { JoinCodeFormComponent } from '../join-code-form/join-code-form.component';

interface WelcomeFeature {
  icon: string;
  iconDark: string;
  label: string;
}

@Component({
  selector: 'app-welcome',
  imports: [CommonModule, TranslateModule, WelcomeCardComponent, JoinCodeFormComponent],
  templateUrl: './welcome.component.html',
  styleUrl: './welcome.component.css',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class WelcomeComponent {
  @Input() sessionCode = '';
  @Input() memberCount = 0;
  @Input() isRTL = false;
  @Input() isDarkMode = false;

  @Output() connectDeviceRequested = new EventEmitter<void>();
  @Output() shareInviteRequested = new EventEmitter<void>();
  @Output() joinRequested = new EventEmitter<string>();
  @Output() scanRequested = new EventEmitter<void>();

  protected readonly features: WelcomeFeature[] = [
    { icon: '/icons/lock.svg', iconDark: '/icons/lock-white.svg', label: 'FEATURE_ENCRYPTED' },
    { icon: '/icons/upload.svg', iconDark: '/icons/upload-light.svg', label: 'FEATURE_NO_CLOUD' },
    {
      icon: '/icons/file-unknown.svg',
      iconDark: '/icons/file-unknown-white.svg',
      label: 'FEATURE_ANY_FILE',
    },
    { icon: '/icons/users.svg', iconDark: '/icons/users-white.svg', label: 'FEATURE_NO_ACCOUNT' },
    {
      icon: '/icons/arrows-up-down.svg',
      iconDark: '/icons/arrows-up-down-light.svg',
      label: 'FEATURE_LOCAL_SPEED',
    },
    { icon: '/icons/code.svg', iconDark: '/icons/code-white.svg', label: 'FEATURE_FREE' },
  ];
}
