import { Injectable, DOCUMENT, inject } from '@angular/core';

import { Meta, Title } from '@angular/platform-browser';
import { MetaConfig, StructuredData } from '../../../utils/constants';

@Injectable({
  providedIn: 'root',
})
export class MetaService {
  private document = inject<Document>(DOCUMENT);
  private meta = inject(Meta);
  private titleService = inject(Title);

  //=============================================================================
  // PUBLIC API: Primary methods for metadata updates
  //=============================================================================

  /**
   * Update all metadata with a single configuration object
   * This is the primary method for setting multiple meta tags at once
   *
   * @param config Configuration object containing metadata values
   */
  public update(config: MetaConfig): void {
    // Title
    if (config.title) {
      this.setTitle(config.title);
    }

    // Basic meta tags
    if (config.description) {
      this.setTag('description', config.description);
    }

    if (config.keywords) {
      this.setTag('keywords', config.keywords);
    }

    if (config.author) {
      this.setTag('author', config.author);
    }

    if (config.robots) {
      this.setTag('robots', config.robots);
    }

    if (config.themeColor) {
      this.setTag('theme-color', config.themeColor);
    }

    if (config.canonical) {
      this.setCanonical(config.canonical);
    }

    // Viewport configuration
    if (config.viewport) {
      this.setTag('viewport', config.viewport);
    }

    // Cache control headers
    if (config.cacheControl) {
      if (config.cacheControl.pragma) {
        this.setHttpEquiv('pragma', config.cacheControl.pragma);
      }

      if (config.cacheControl.cacheControl) {
        this.setHttpEquiv('cache-control', config.cacheControl.cacheControl);
      }

      if (config.cacheControl.expires) {
        this.setHttpEquiv('expires', config.cacheControl.expires);
      }
    }

    // Open Graph tags
    if (config.og) {
      if (config.og.title) {
        this.setProperty('og:title', config.og.title);
      }

      if (config.og.description) {
        this.setProperty('og:description', config.og.description);
      }

      if (config.og.type) {
        this.setProperty('og:type', config.og.type);
      }

      if (config.og.url) {
        this.setProperty('og:url', config.og.url);
      }

      if (config.og.image) {
        this.setProperty('og:image', config.og.image);
      }

      if (config.og.siteName) {
        this.setProperty('og:site_name', config.og.siteName);
      }
    }

    // Twitter Cards
    if (config.twitter) {
      if (config.twitter.card) {
        this.setTag('twitter:card', config.twitter.card);
      }

      if (config.twitter.title) {
        this.setTag('twitter:title', config.twitter.title);
      }

      if (config.twitter.description) {
        this.setTag('twitter:description', config.twitter.description);
      }

      if (config.twitter.image) {
        this.setTag('twitter:image', config.twitter.image);
      }

      if (config.twitter.site) {
        this.setTag('twitter:site', config.twitter.site);
      }

      if (config.twitter.creator) {
        this.setTag('twitter:creator', config.twitter.creator);
      }
    }
  }

  /**
   * Update metadata for Chat component
   *
   * @param isPrivateSession whether this is a private chat session
   */
  public updateChatMetadata(isPrivateSession = false): void {
    if (isPrivateSession) {
      // Private session - no indexing
      this.setTag('robots', 'noindex');
      this.update({
        title: 'Invite-only · PastePoint',
        canonical: 'https://pastepoint.com/',
        og: {
          title: 'Join on PastePoint',
          description:
            'PastePoint lets you share files and chat instantly with end-to-end encryption. No cloud, no accounts, no tracking—secure peer-to-peer transfers made simple.',
          type: 'website',
          url: 'https://pastepoint.com/',
          image: 'https://pastepoint.com/assets/pastepoint-og-image.png',
          siteName: 'PastePoint',
        },
        twitter: {
          card: 'summary_large_image',
          site: '@pastepoint',
          creator: '@pastepoint',
          title: 'Join on PastePoint',
          description:
            'PastePoint lets you share files and chat instantly with end-to-end encryption. No cloud, no accounts, no tracking—secure peer-to-peer transfers made simple.',
          image: 'https://pastepoint.com/assets/pastepoint-og-image.png',
        },
      });
    } else {
      // Regular chat page
      this.update({
        title: 'PastePoint | Secure Peer-to-Peer File Sharing & Encrypted Messaging',
        description:
          'PastePoint lets you share files and chat instantly with end-to-end encryption. No cloud, no accounts, no tracking—secure peer-to-peer transfers made simple.',
        keywords:
          'secure file sharing, encrypted messaging, peer-to-peer transfer, private file sharing, WebRTC chat, direct file transfer, real-time messaging, zero tracking, no cloud, local network sharing',
        robots: 'index, follow',
        canonical: 'https://pastepoint.com/',
        og: {
          url: 'https://pastepoint.com/',
          title: 'PastePoint | Secure Peer-to-Peer File Sharing & Encrypted Messaging',
          description:
            'PastePoint lets you share files and chat instantly with end-to-end encryption. No cloud, no accounts, no tracking—secure peer-to-peer transfers made simple.',
          type: 'website',
          image: 'https://pastepoint.com/assets/pastepoint-og-image.png',
          siteName: 'PastePoint',
        },
        twitter: {
          card: 'summary_large_image',
          site: '@pastepoint',
          creator: '@pastepoint',
          title: 'PastePoint | Secure Peer-to-Peer File Sharing & Encrypted Messaging',
          description:
            'PastePoint lets you share files and chat instantly with end-to-end encryption. No cloud, no accounts, no tracking—secure peer-to-peer transfers made simple.',
          image: 'https://pastepoint.com/assets/pastepoint-og-image.png',
        },
      });
    }
  }

  /**
   * Update metadata for NotFound component (404 page)
   */
  public updateNotFoundMetadata(): void {
    this.update({
      title: 'Page Not Found – Secure File Sharing & Encrypted Chat App',
      description: 'The page you are looking for could not be found.',
      robots: 'noindex, nofollow',
      canonical: 'https://pastepoint.com/404',
      og: {
        title: 'Page Not Found – Secure File Sharing & Encrypted Chat App',
        description: 'The page you are looking for could not be found.',
        type: 'website',
        url: 'https://pastepoint.com/404',
        image: 'https://pastepoint.com/assets/pastepoint-og-image.png',
        siteName: 'PastePoint',
      },
      twitter: {
        card: 'summary_large_image',
        site: '@pastepoint',
        creator: '@pastepoint',
        title: 'Page Not Found – Secure File Sharing & Encrypted Chat App',
        description: 'The page you are looking for could not be found.',
        image: 'https://pastepoint.com/assets/pastepoint-og-image.png',
      },
    });
  }

  /**
   * Update metadata for Privacy and Terms component
   */
  public updatePrivacyAndTermsMetadata(): void {
    this.update({
      title: 'Privacy and Terms – Secure File Sharing & Encrypted Chat App',
      description:
        'Privacy policy and terms of service for PastePoint secure file sharing platform.',
      robots: 'index, follow',
      canonical: 'https://pastepoint.com/privacy',
      og: {
        title: 'Privacy and Terms – Secure File Sharing & Encrypted Chat App',
        description:
          'Privacy policy and terms of service for PastePoint secure file sharing platform.',
        type: 'website',
        url: 'https://pastepoint.com/privacy',
        image: 'https://pastepoint.com/assets/pastepoint-og-image.png',
        siteName: 'PastePoint',
      },
      twitter: {
        card: 'summary_large_image',
        site: '@pastepoint',
        creator: '@pastepoint',
        title: 'Privacy and Terms – Secure File Sharing & Encrypted Chat App',
        description:
          'Privacy policy and terms of service for PastePoint secure file sharing platform.',
        image: 'https://pastepoint.com/assets/pastepoint-og-image.png',
      },
    });
  }

  /**
   * Update metadata for Acknowledgements component
   */
  public updateAcknowledgementsMetadata(): void {
    const title = 'Acknowledgements – Secure File Sharing & Encrypted Chat App';
    const description = 'Open source packages used to build PastePoint, and their licenses.';

    this.update({
      title,
      description,
      robots: 'index, follow',
      canonical: 'https://pastepoint.com/acknowledgements',
      og: {
        title,
        description,
        type: 'website',
        url: 'https://pastepoint.com/acknowledgements',
        image: 'https://pastepoint.com/assets/pastepoint-og-image.png',
        siteName: 'PastePoint',
      },
      twitter: {
        card: 'summary_large_image',
        site: '@pastepoint',
        creator: '@pastepoint',
        title,
        description,
        image: 'https://pastepoint.com/assets/pastepoint-og-image.png',
      },
    });
  }

  //=============================================================================
  // INDIVIDUAL META ELEMENT SETTERS
  // Methods for updating specific meta elements
  //=============================================================================

  /**
   * Set page title
   *
   * @param title The page title to set
   */
  public setTitle(title: string): void {
    this.titleService.setTitle(title);
  }

  /**
   * Set a meta tag with name attribute
   *
   * @param name Meta tag name attribute value
   * @param content Meta tag content attribute value
   */
  public setTag(name: string, content: string): void {
    const tag = this.meta.getTag(`name="${name}"`);
    if (tag) {
      this.meta.updateTag({ name, content });
    } else {
      this.meta.addTag({ name, content });
    }
  }

  /**
   * Set a meta tag with property attribute (used by Open Graph)
   *
   * @param property Meta property attribute value (e.g., 'og:title')
   * @param content Meta content attribute value
   */
  public setProperty(property: string, content: string): void {
    const tag = this.meta.getTag(`property="${property}"`);
    if (tag) {
      this.meta.updateTag({ property, content });
    } else {
      this.meta.addTag({ property, content });
    }
  }

  /**
   * Set additional Open Graph image properties
   *
   * @param imageUrl The Open Graph image URL
   */
  public setOpenGraphImageProperties(imageUrl: string): void {
    this.setProperty('og:image', imageUrl);
    this.setProperty('og:image:width', '1200');
    this.setProperty('og:image:height', '630');
    this.setProperty('og:image:alt', 'PastePoint - Secure File Sharing Platform');
    this.setProperty('og:locale', 'en_US');
  }

  /**
   * Set canonical URL
   *
   * @param url The canonical URL to set
   */
  public setCanonical(url: string): void {
    const existingCanonical = this.document.querySelector('link[rel="canonical"]');
    if (existingCanonical) {
      existingCanonical.remove();
    }

    const link = this.document.createElement('link');
    link.setAttribute('rel', 'canonical');
    link.setAttribute('href', url);
    this.document.head.appendChild(link);
  }

  /**
   * Set verification meta tags for search engines (Google, Bing, etc.)
   *
   * @param provider Search engine provider name (e.g., 'google')
   * @param content Verification content/code
   */
  public setVerification(provider: string, content: string): void {
    this.setTag(`${provider}-site-verification`, content);
  }

  /**
   * Set favicon and app icons
   *
   * @param icons Object containing paths to different icon types
   */
  public setIcons(icons: {
    favicon?: string;
    faviconSvg?: string;
    shortcut?: string;
    apple?: string;
    manifest?: string;
  }): void {
    // Remove existing icon links
    const existingIcons = this.document.querySelectorAll(
      'link[rel="icon"], link[rel="shortcut icon"], link[rel="apple-touch-icon"]'
    );
    existingIcons.forEach((icon) => {
      icon.remove();
    });

    // Add new icons
    if (icons.favicon) {
      this.createLink('icon', icons.favicon);
    }

    if (icons.faviconSvg) {
      this.createLink('icon', icons.faviconSvg, undefined, 'image/svg+xml');
    }

    if (icons.shortcut) {
      this.createLink('shortcut icon', icons.shortcut);
    }

    if (icons.apple) {
      this.createLink('apple-touch-icon', icons.apple, '180x180');
    }

    if (icons.manifest) {
      this.createLink('manifest', icons.manifest);
    }
  }

  /**
   * Set structured data in JSON-LD format
   *
   * @param data The structured data object
   * @param id Optional ID for the script tag
   */
  public setStructuredData(data: StructuredData, id?: string): void {
    if (id) {
      const existingScript = this.document.getElementById(id);
      if (existingScript) {
        existingScript.remove();
      }
    }

    const script = this.document.createElement('script');
    script.type = 'application/ld+json';
    if (id) {
      script.id = id;
    }
    script.text = JSON.stringify(data);
    this.document.body.appendChild(script);
  }

  /**
   * Set preconnect links for external resources
   *
   * @param urls Array of URLs to preconnect to
   * @param crossorigin Whether to include crossorigin attribute
   */
  public setPreconnect(urls: string[], crossorigin = false): void {
    const existingLinks = this.document.querySelectorAll('link[rel="preconnect"]');
    existingLinks.forEach((link) => {
      link.remove();
    });

    urls.forEach((url) => {
      const link = this.document.createElement('link');
      link.setAttribute('rel', 'preconnect');
      link.setAttribute('href', url);
      if (crossorigin) {
        link.setAttribute('crossorigin', '');
      }
      this.document.head.appendChild(link);
    });
  }

  /**
   * Set a meta tag with http-equiv attribute
   *
   * @param httpEquiv The http-equiv attribute value
   * @param content The content attribute value
   */
  public setHttpEquiv(httpEquiv: string, content: string): void {
    const tag = this.meta.getTag(`http-equiv="${httpEquiv}"`);
    if (tag) {
      this.meta.updateTag({ 'http-equiv': httpEquiv, content });
    } else {
      this.meta.addTag({ 'http-equiv': httpEquiv, content });
    }
  }

  //=============================================================================
  // PRIVATE UTILITY METHODS
  //=============================================================================

  /**
   * Helper method to create link elements
   *
   * @param rel Link relation attribute value
   * @param href Link href attribute value
   * @param sizes Optional sizes attribute value
   * @param type Optional type attribute value
   */
  private createLink(rel: string, href: string, sizes?: string, type?: string): void {
    const link = this.document.createElement('link');
    link.setAttribute('rel', rel);
    link.setAttribute('href', href);
    if (sizes) {
      link.setAttribute('sizes', sizes);
    }
    if (type) {
      link.setAttribute('type', type);
    }
    this.document.head.appendChild(link);
  }
}
