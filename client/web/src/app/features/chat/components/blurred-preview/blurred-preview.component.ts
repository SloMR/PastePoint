import { ChangeDetectionStrategy, Component, EventEmitter, Input, Output } from '@angular/core';
import { TranslateModule } from '@ngx-translate/core';

@Component({
  selector: 'app-blurred-preview',
  imports: [TranslateModule],
  templateUrl: './blurred-preview.component.html',
  styleUrl: './blurred-preview.component.css',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class BlurredPreviewComponent {
  @Input() src?: string;
  @Input() alt = '';
  @Input() revealed = false;

  @Output() revealedChange = new EventEmitter<boolean>();

  protected reveal(): void {
    this.revealed = true;
    this.revealedChange.emit(true);
  }
}
