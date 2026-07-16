import { Component, OnInit, PLATFORM_ID, ChangeDetectionStrategy, inject } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { isPlatformBrowser } from '@angular/common';
import { MetaInitService } from './core/services/ui/meta-init.service';
import { UpdateGateComponent } from './core/components/update-gate/update-gate.component';
import { AppUpdateService } from './core/services/update/app-update.service';

@Component({
  selector: 'app-root',
  templateUrl: './app.component.html',
  styleUrls: ['./app.component.css'],
  imports: [RouterOutlet, UpdateGateComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class AppComponent implements OnInit {
  private platformId = inject(PLATFORM_ID);
  private metaInitService = inject(MetaInitService);
  private updateService = inject(AppUpdateService);

  protected title = 'PastePoint';

  ngOnInit(): void {
    if (isPlatformBrowser(this.platformId)) {
      // Initialize application metadata
      this.metaInitService.initializeAppMetadata();

      // Display console message
      this.displayConsoleMessage();

      // Fire-and-forget client version check (gate/nudge if out of date)
      this.updateService.startMonitoring();
    }
  }

  /**
   * Displays a message in the browser console when DevTools is opened
   */
  private displayConsoleMessage(): void {
    console.log(
      `%c👀 WHOA THERE, CURIOUS HUMAN! 👀\n\n` +
        `%c🎉 Welcome to PastePoint Console - Where the Magic Happens! 🎉\n\n` +
        `%c🚀 You just unlocked Developer Mode!\n` +
        `%c(No actual achievements unlocked, sorry)\n\n` +
        `%c💡 Fun Fact:%c You're looking at code that moves your files at the speed of... well, your internet connection 🐢\n\n` +
        `%c⚡ Powered by:\n` +
        `%c  → Angular %c(because we like to live dangerously)\n` +
        `%c  → Rust %c(for that blazingly fast™ backend)\n` +
        `%c  → WebRTC %c(basically telepathy for computers)\n\n` +
        `%c💜 Built with ☕, 🍕, and questionable amounts of Stack Overflow\n\n` +
        `%c⚠️ P.S. Don't paste random code here unless you want your computer to start mining Bitcoin for strangers 💰`,
      // Title
      'color: #E5E7EB; font-size: 26px; font-weight: bold; text-shadow: 0 1px 2px rgba(0,0,0,0.3);',
      // Welcome line
      'color: #3B82F6; font-size: 18px; font-weight: 600;',
      // Developer mode
      'color: #22C55E; font-size: 15px; font-weight: 600;',
      // Joke
      'color: #a1a1aa; font-style: italic;',
      // Fun Fact label
      'color: #FACC15; font-weight: bold;',
      // Fun Fact text
      'color: #E5E7EB;',
      // “Powered by”
      'color: #F97316; font-weight: bold;',
      // → Angular
      'color: #DD0031; font-weight: bold;',
      'color: #9CA3AF;',
      // → Rust
      'color: #DEA584; font-weight: bold;',
      'color: #9CA3AF;',
      // → WebRTC
      'color: #60A5FA; font-weight: bold;',
      'color: #9CA3AF;',
      // Built with
      'color: #C084FC; font-weight: bold;',
      // P.S.
      'color: #FBBF24; font-weight: bold;'
    );
  }
}
