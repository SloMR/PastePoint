import { Component, Input, ChangeDetectionStrategy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { TranslatePipe } from '@ngx-translate/core';
import { SocialLinksComponent } from '../social-links/social-links.component';

@Component({
  selector: 'app-page-footer',
  imports: [CommonModule, RouterLink, TranslatePipe, SocialLinksComponent],
  templateUrl: './page-footer.component.html',
  changeDetection: ChangeDetectionStrategy.Eager,
  styleUrl: './page-footer.component.css',
})
export class PageFooterComponent {
  @Input() appVersion = '';
  @Input() showPrivacyLink = false;
  @Input() showAcknowledgementsLink = true;
}
