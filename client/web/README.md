# PastePoint Client (Angular Frontend)

The PastePoint client is a modern Angular application with Server-Side Rendering (SSR) support, providing an intuitive interface for file sharing and communication on local networks. Features WebRTC file transfer capabilities, real-time chat, and comprehensive user experience enhancements.

[![Angular](https://img.shields.io/badge/Angular-21-red)](https://angular.io/)
[![Tailwind](https://img.shields.io/badge/Tailwind-3.4-blue)](https://tailwindcss.com/)
[![Flowbite](https://img.shields.io/badge/Flowbite-3.1-cyan)](https://flowbite.com/)

## Tech Stack

### Core Features

- **Rendering**: Server-Side Rendering with Angular SSR (`@angular/ssr` + Express)
- **WebRTC**: Native WebRTC API for peer-to-peer file transfers
- **File Integrity**: `hash-wasm` for fast client-side file hashing
- **QR Sharing**: `qrcode` for generation, `jsqr` for camera-based scanning
- **I18n**: `@ngx-translate/core` (English, Arabic (RTL), Spanish, French, Russian, Simplified Chinese)
- **Styling**: Tailwind CSS with class-based dark mode + Flowbite components
- **Notifications**: Hot-toast (`@ngxpert/hot-toast`) for real-time user feedback
- **Error Tracking**: `@sentry/angular` with privacy-tight redaction (off by default in dev)

### Development Tools

- **Build Tool**: Angular CLI (`@angular-devkit/build-angular:application`, esbuild-based)
- **Testing**: Jasmine and Karma for unit tests
- **Linting**: ESLint with Angular-specific rules
- **Formatting**: Prettier with custom configuration
- **Styling**: stylelint for CSS/SCSS validation

## Project Structure

```
web/
├── src/
│   ├── app/
│   │   ├── core/
│   │   │   ├── i18n/           # Internationalization
│   │   │   ├── components/     # Reusable layout & cross-cutting UI
│   │   │   ├── services/       # Core services
│   │   │   │   ├── communication/    # WebRTC, WebSocket, Chat
│   │   │   │   ├── file-management/  # File transfer services
│   │   │   │   ├── room-management/  # Room/session join, list, create
│   │   │   │   ├── session/          # Session lifecycle & QR sharing
│   │   │   │   ├── user-management/  # User identity & presence
│   │   │   │   ├── ui/               # Theme, Language services
│   │   │   │   ├── monitoring/       # Error tracking (Sentry)
│   │   │   │   └── migration/        # App migration
│   │   │   └── interfaces/     # TypeScript interfaces
│   │   ├── features/           # Features such as chat, file sharing, etc.
│   │   ├── utils/              # Utility functions
│   │   ├── testing/            # Test utilities
│   │   ├── app.component.*        # Root component
│   │   ├── app.routes.ts          # Application routes
│   │   └── app.config.*           # App configuration
│   ├── environments/           # Environment configs
│   ├── index.html                 # Main HTML file
│   ├── main.ts                    # Application entry point
│   ├── server.ts                  # SSR server
│   └── styles.css                 # Global styles
├── public/                     # Static assets
│   ├── assets/                 # Assets
│   │   ├── favicon.*              # Favicon files
│   │   ├── pastepoint-*.svg       # Logo files
│   │   └── *.png                  # App icons
│   ├── fonts/                  # Custom fonts
│   ├── icons/                  # SVG icons
│   └── site.webmanifest           # Web app manifest
├── dist/                       # Build output
├── node_modules/               # Dependencies
├── package.json                   # Project dependencies
├── angular.json                   # Angular CLI config
├── tailwind.config.js             # Tailwind CSS config
├── tsconfig.json                  # TypeScript config
├── Dockerfile                     # Docker configuration
└── README.md                      # Project documentation
```

## Quick Start

### Prerequisites

- **Node.js**: v24.16.0 (specified in `../.nvmrc`)
- **npm**: Latest version
- **Angular CLI**: `npm install -g @angular/cli`

### Development Setup

1. **Navigate to client directory**:

   ```bash
   cd client/web
   ```

2. **Install dependencies**:

   ```bash
   npm install
   ```

3. **Start development server**:

   ```bash
   ng serve
   ```

4. **Open browser**:
   Navigate to `http://localhost:4200`

### Available Scripts

```bash
npm start              # dev server (ng serve)
npm run start-local    # dev server bound to your local network IP
npm run watch          # rebuild on change (development configuration)
npm run build:dev      # development build
npm run build:prod     # production build
npm run serve:ssr:web  # run the built SSR server locally
npm run test           # unit tests (Karma/Jasmine)
npm run test:coverage  # unit tests with coverage report
npm run test:ci        # headless CI tests with coverage
npm run lint           # ESLint
npm run lint:fix       # ESLint with autofix
npm run format         # Prettier
```

## Configuration

### Environment Files

- `src/environments/environment.ts`: Development configuration
- `src/environments/environment.docker-dev.ts`: Docker development configuration
- `src/environments/environment.prod.ts`: Production configuration

Example environment configuration:

```typescript
export const environment = {
  production: false,
  apiUrl: 'https://localhost:9000',
  logLevel: NgxLoggerLevel.DEBUG,
  enableSourceMaps: true,
  disableFileDetails: false,
  disableConsoleLogging: false,
  sentry: {
    enabled: false,
    dsn: '',
    environment: 'development',
    tracesSampleRate: 0.1,
    enableLogs: true,
  },
};
```

> **Note:** `apiUrl` is host:port without a scheme — the client derives `https`/`wss`
> at runtime. Sentry is compiled into the bundle from these files; set `sentry.enabled`
> and `sentry.dsn` here to turn it on.

### Angular Configuration

Key configurations in `angular.json`:

- **Build optimization**: Bundle optimization and tree shaking
- **SSR configuration**: Server-side rendering setup
- **Asset optimization**: Image and font optimization

## Testing

### Unit Tests

```bash
# Run all tests
npm run test

# Run tests with coverage
npm run test:coverage

# Run tests in CI mode
npm run test:ci
```

### Linting and Formatting

```bash
# Run ESLint
npm run lint

# Fix ESLint issues
npm run lint:fix

# Run Prettier
npm run format
```

## Styling and Theming

### Tailwind CSS Configuration

The project uses a custom Tailwind configuration with:

- **Custom color palette**: Brand-specific colors
- **Dark mode**: Class-based dark mode switching
- **Custom components**: Reusable component classes
- **Responsive breakpoints**: Mobile-first design

### Flowbite Integration

Flowbite components are integrated for:

- Navigation components
- Form elements
- Modal dialogs
- Toast notifications
- Loading indicators

## Internationalization (i18n)

### Supported Languages

- English (default)
- Arabic (RTL)
- Spanish
- French
- Russian
- Simplified Chinese

### Translation Files

```
src/app/core/i18n/localizations/
├── en.json
├── ar.json
├── es.json
├── fr.json
├── ru.json
└── zh-CN.json
```

### Usage

```typescript
// In components
constructor(private translate: TranslateService) {}

// Get translation
this.translate.instant('WELCOME');
```

## Development Guide

### Adding New Features

1. **Generate component**:

   ```bash
   ng generate component features/feature-name
   ```

2. **Generate service**:

   ```bash
   ng generate service core/services/service-name
   ```

### Code Standards

- **TypeScript**: Strict mode enabled
- **ESLint**: Angular-specific rules
- **Prettier**: Consistent code formatting
- **Conventional Commits**: Standardized commit messages

## Troubleshooting

### Common Issues

1. **Node Version Mismatch**:

   ```bash
   # Use correct Node version
   nvm use
   # Or install the specified version
   nvm install 24.16.0
   ```

2. **WebSocket Connection Issues**:
   - Check backend server is running
   - Verify SSL certificates are valid
   - Check CORS configuration

## Contributing

- [Contributing](../../CONTRIBUTING.md)

## License

This project is licensed under the GPL-3.0 License. See the [LICENSE](../../LICENSE) file for details.

## Related Documentation

- [Main project readme](../../README.md)
- [Server readme](../../server/README.md)
- [Docker Compose setup](../../docker-compose.yml)
