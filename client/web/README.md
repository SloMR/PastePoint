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
│   │   │   ├── components/     # Shared layout and UI
│   │   │   ├── i18n/           # Localization
│   │   │   ├── interfaces/     # Shared types
│   │   │   └── services/       # Communication, files, rooms, and UI
│   │   ├── features/           # Feature UI and flows
│   │   ├── testing/            # Test utilities
│   │   └── utils/              # Shared helpers and constants
│   ├── environments/           # Build-specific configuration
│   ├── main.ts                 # Browser entry point
│   ├── server.ts               # SSR entry point
│   └── styles.css              # Global styles
├── public/
│   ├── assets/                 # Logos and app icons
│   ├── fonts/                  # Custom fonts
│   └── icons/                  # SVG icons
├── angular.json                # Angular workspace configuration
├── package.json                # Scripts and dependencies
├── tailwind.config.js          # Tailwind configuration
├── tsconfig.json               # TypeScript configuration
├── Dockerfile                  # Container build
└── README.md
```

## Quick Start

### Prerequisites

- **Node.js**: v24.16.0 (specified in `../../.nvmrc`)
- **npm**: Latest version

### Development Setup

1. **Navigate to client directory**:

   ```bash
   cd client/web
   ```

2. **Install dependencies**:

   ```bash
   npm ci
   ```

3. **Generate the development certificate**:

   ```bash
   ../../scripts/generate-certs.sh
   ```

4. **Start the development server**:

   ```bash
   npm start
   ```

5. **Open the browser**:
   Navigate to `https://localhost`.

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
  apiUrl: '127.0.0.1:9000',
  webUrl: '127.0.0.1',
  logLevel: NgxLoggerLevel.DEBUG,
  enableSourceMaps: true,
  disableFileDetails: false,
  disableConsoleLogging: false,
  sentry: {
    enabled: false,
    dsn: '',
    environment: 'development',
    tracesSampleRate: 0.25,
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
- [iOS client readme](../ios/README.md)
- [Server readme](../../server/README.md)
- [Docker Compose setup](../../docker-compose.yml)
