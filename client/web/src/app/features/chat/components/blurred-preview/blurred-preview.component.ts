import { ChangeDetectionStrategy, Component, Input, signal } from '@angular/core';
import { TranslateModule } from '@ngx-translate/core';

@Component({
  selector: 'app-blurred-preview',
  imports: [TranslateModule],
  templateUrl: './blurred-preview.component.html',
  styleUrl: './blurred-preview.component.css',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class BlurredPreviewComponent {
  @Input()
  set src(value: string | undefined) {
    this.source = value;
    this.revealed.set(false);
  }

  @Input() alt = '';

  protected source?: string;
  protected readonly revealed = signal(false);

  protected reveal(): void {
    this.revealed.set(true);
  }
}
