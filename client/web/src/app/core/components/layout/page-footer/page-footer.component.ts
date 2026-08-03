import { Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { TranslateModule } from '@ngx-translate/core';
import { SocialLinksComponent } from '../social-links/social-links.component';

@Component({
  selector: 'app-page-footer',
  imports: [CommonModule, RouterLink, TranslateModule, SocialLinksComponent],
  templateUrl: './page-footer.component.html',
  styleUrl: './page-footer.component.css',
})
export class PageFooterComponent {
  @Input() appVersion = '';
  @Input() showPrivacyLink = false;
  @Input() showAcknowledgementsLink = true;
}
