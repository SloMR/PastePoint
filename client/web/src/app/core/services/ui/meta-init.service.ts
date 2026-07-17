import { Injectable, PLATFORM_ID, inject } from '@angular/core';
import { isPlatformBrowser } from '@angular/common';
import { NavigationEnd, Router } from '@angular/router';
import { filter } from 'rxjs/operators';
import { MetaService } from './meta.service';
import { MetaConfig, StructuredData } from '../../../utils/constants';

@Injectable({
  providedIn: 'root',
})
export class MetaInitService {
  private metaService = inject(MetaService);
  private router = inject(Router);
  private platformId = inject(PLATFORM_ID);

  /**
   * Constructor - sets up route change listener to update metadata
   */
  constructor() {
    if (isPlatformBrowser(this.platformId)) {
      // Listen for navigation events to update metadata
      this.router.events
        .pipe(filter((event) => event instanceof NavigationEnd))
        .subscribe((event: NavigationEnd) => {
          this.handleRouteChange(event.url);
        });
    }
  }

  //=============================================================================
  // PUBLIC API
  //=============================================================================

  /**
   * Initialize default application metadata
   * Should be called once when the application starts
   */
  public initializeAppMetadata(): void {
    // Set basic meta information
    const defaultMetaConfig: MetaConfig = this.getDefaultMetaConfig();
    this.metaService.update(defaultMetaConfig);

    // Set Google site verification
    this.metaService.setVerification('google', 'zwaPPawWJXUKTH2XgrrfKkCOIbIwilUTBI');

    // Set app icons
    this.metaService.setIcons({
      favicon: '/assets/favicon-96x96.png',
      faviconSvg: '/assets/favicon.svg',
      shortcut: '/assets/favicon.ico',
      apple: '/assets/apple-touch-icon.png',
      manifest: '/site.webmanifest',
    });

    // Set structured data for the application
    this.metaService.setStructuredData(this.getApplicationStructuredData(), 'app-structured-data');

    // Set WebSite schema for sitelinks
    this.metaService.setStructuredData(this.getWebSiteStructuredData(), 'website-structured-data');
  }

  //=============================================================================
  // PRIVATE METHODS
  //=============================================================================

  /**
   * Handle route changes to update metadata
   * This ensures metadata updates even when navigating via links or logo clicks
   *
   * @param url Current URL after navigation
   */
  private handleRouteChange(url: string): void {
    // Handle different routes
    if (url.includes('/private/')) {
      // Private session - no indexing
      this.metaService.updateChatMetadata(true);
    } else if (url === '/' || url === '') {
      // Regular chat page (now at root)
      this.metaService.updateChatMetadata(false);
    } else if (url.includes('/404') || url.includes('not-found')) {
      // 404 page
      this.metaService.updateNotFoundMetadata();
    } else {
      // Other pages - use default metadata
      this.initializeAppMetadata();
    }
  }

  /**
   * Get default meta configuration for the application
   *
   * @returns MetaConfig object with default values
   */
  private getDefaultMetaConfig(): MetaConfig {
    return {
      title: 'PastePoint | Secure Peer-to-Peer File Sharing & Encrypted Messaging',
      description:
        'PastePoint lets you share files and chat instantly with end-to-end encryption. No cloud, no accounts, no tracking—secure peer-to-peer transfers made simple.',
      keywords:
        'pastepoint, paste point, PastePoint, Paste Point, secure file sharing, encrypted messaging, peer-to-peer transfer, private file sharing, WebRTC chat, direct file transfer, real-time messaging, zero tracking, no cloud, local network sharing',
      author: 'PastePoint',
      themeColor: '#4285f4',
      robots: 'index, follow',
      canonical: 'https://pastepoint.com',

      // Viewport configuration for responsive design
      viewport: 'width=device-width, initial-scale=1.0',

      // Open Graph metadata
      og: {
        type: 'website',
        title: 'PastePoint | Secure Peer-to-Peer File Sharing & Encrypted Messaging',
        description:
          'PastePoint is a secure, feature-rich file sharing and messaging platform. Transfer files directly using peer-to-peer WebRTC connections with no tracking or cloud storage.',
        siteName: 'PastePoint',
        url: 'https://pastepoint.com',
      },

      // Twitter Card metadata
      twitter: {
        card: 'summary_large_image',
        title: 'PastePoint | Secure Peer-to-Peer File Sharing & Encrypted Messaging',
        description:
          'Send messages and files securely with PastePoint. Peer-to-peer file transfers, end-to-end encryption, and no cloud.',
      },
    };
  }

  /**
   * Get structured data object for the application
   *
   * @returns StructuredData object for JSON-LD
   */
  private getApplicationStructuredData(): StructuredData {
    return {
      '@context': 'https://schema.org',
      '@type': 'WebApplication',
      name: 'PastePoint',
      alternateName: ['Paste Point', 'pastepoint', 'paste point'],
      url: 'https://pastepoint.com',
      applicationCategory: 'CommunicationApplication',
      applicationSubCategory: 'Peer-to-peer file sharing and encrypted messaging',
      operatingSystem: 'Web',
      description:
        'PastePoint (Paste Point) is a secure peer-to-peer file sharing and encrypted messaging solution. Transfer files directly with end-to-end encryption, no cloud storage or accounts required.',
      featureList: [
        'End-to-end encryption',
        'Peer-to-peer file transfer',
        'Real-time messaging',
        'No cloud storage',
        'No account required',
        'WebRTC connections',
        'Local network optimization',
      ],
      screenshot: 'https://pastepoint.com/assets/pastepoint-screenshot.png',
      softwareVersion: '0.14.0',
      logo: 'https://pastepoint.com/assets/pastepoint-og-image.png',
      offers: {
        '@type': 'Offer',
        price: '0',
        priceCurrency: 'USD',
      },
      author: {
        '@type': 'Organization',
        name: 'PastePoint',
        url: 'https://pastepoint.com',
      },
      publisher: {
        '@type': 'Organization',
        name: 'PastePoint',
        url: 'https://pastepoint.com',
        logo: 'https://pastepoint.com/assets/pastepoint-og-image.png',
      },
      potentialAction: {
        '@type': 'SendAction',
        target: {
          '@type': 'EntryPoint',
          urlTemplate: 'https://pastepoint.com/',
        },
        description: 'Send encrypted messages and files instantly via PastePoint',
      },
      sameAs: [
        'https://twitter.com/pastepoint',
        'https://github.com/SloMR/pastepoint',
        'https://www.linkedin.com/in/sulaiman-alromaih-845700202/',
      ],
    };
  }

  private getWebSiteStructuredData(): StructuredData {
    return {
      '@context': 'https://schema.org',
      '@type': 'WebSite',
      name: 'PastePoint',
      alternateName: ['Paste Point', 'pastepoint'],
      url: 'https://pastepoint.com',
    };
  }
}
