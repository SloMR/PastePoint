import { ChangeDetectionStrategy, Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';
import { TranslateModule } from '@ngx-translate/core';

@Component({
  selector: 'app-welcome-card',
  imports: [CommonModule, TranslateModule],
  templateUrl: './welcome-card.component.html',
  styleUrl: './welcome-card.component.css',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class WelcomeCardComponent {
  @Input({ required: true }) title!: string;
  @Input({ required: true }) message!: string;
  @Input() isRTL = false;
  @Input() isDarkMode = false;

  /** Glyph beside the title; `iconDark` is used when the theme is dark. */
  @Input({ required: true }) icon!: string;
  @Input({ required: true }) iconDark!: string;
}
