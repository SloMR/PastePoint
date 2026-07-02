import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { TranslateModule } from '@ngx-translate/core';
import { AppUpdateService } from '../../services/update/app-update.service';

@Component({
  selector: 'app-update-gate',
  imports: [CommonModule, TranslateModule],
  templateUrl: './update-gate.component.html',
  styleUrl: './update-gate.component.css',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class UpdateGateComponent {
  private updateService = inject(AppUpdateService);

  protected readonly recommendation = this.updateService.recommendation;

  /** Reload same-origin (fetches the new bundle) or navigate to the given URL. */
  protected update(url: string): void {
    try {
      const target = new URL(url, window.location.href);
      if (target.origin === window.location.origin) {
        window.location.reload();
      } else {
        window.location.href = target.href;
      }
    } catch {
      window.location.reload();
    }
  }

  protected dismiss(): void {
    this.updateService.dismissOptional();
  }
}
