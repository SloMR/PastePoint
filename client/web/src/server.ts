import { APP_BASE_HREF } from '@angular/common';
import { CommonEngine, isMainModule } from '@angular/ssr/node';
import express from 'express';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import compression from 'compression';
import bootstrap from './main.server';
import https from 'https';
import fs from 'fs';
import { environment } from './environments/environment';

// Helper function to find project root by looking for certs directory
function findProjectRoot(startPath: string): string {
  let currentPath = startPath;
  const root = resolve('/');

  // Traverse up until we find a directory containing 'certs' folder
  while (currentPath !== root) {
    const certsPath = join(currentPath, 'certs');
    try {
      if (fs.existsSync(certsPath) && fs.statSync(certsPath).isDirectory()) {
        return currentPath;
      }
    } catch {
      // Continue searching if we can't access the directory
    }
    currentPath = resolve(currentPath, '..');
  }

  // Fallback to process.cwd() if certs not found
  return process.cwd();
}

// The Express app is exported so that it can be used by serverless Functions.
export function app(): express.Express {
  const server = express();
  server.set('trust proxy', 1);
  const serverDistFolder = dirname(fileURLToPath(import.meta.url));
  const browserDistFolder = resolve(serverDistFolder, '../browser');
  const indexHtml = join(serverDistFolder, 'index.server.html');

  // Enable compression for all responses
  server.use(compression());

  // Our Universal express-engine
  const commonEngine = new CommonEngine({
    allowedHosts: ['localhost', 'ssr_server', process.env['SERVER_NAME'] || ''].filter(Boolean),
  });

  server.set('view engine', 'html');
  server.set('views', browserDistFolder);

  // Serve static files from /browser
  server.get(
    '*.*',
    express.static(browserDistFolder, {
      maxAge: '1y',
      etag: true,
      lastModified: true,
    })
  );

  server.get('*.*', (req, res) => {
    res.sendStatus(404);
  });

  // All regular routes use the Universal engine
  server.get('*', (req, res, next) => {
    const { protocol, originalUrl, baseUrl, headers } = req;

    // Get protocol from X-Forwarded-Proto header when behind a proxy
    const requestProtocol = headers['x-forwarded-proto'] || protocol;

    commonEngine
      .render({
        bootstrap,
        documentFilePath: indexHtml,
        url: `${requestProtocol}://${headers.host}${originalUrl}`,
        publicPath: browserDistFolder,
        providers: [{ provide: APP_BASE_HREF, useValue: baseUrl }],
      })
      .then((html) => res.send(html))
      .catch((err) => {
        console.error('Error rendering app:', err);
        next(err);
      });
  });

  return server;
}

function run(): void {
  const port = process.env['PORT'] ? parseInt(process.env['PORT'], 10) : 443;
  const host = process.env['HOST'] ?? '127.0.0.1';

  try {
    // Create the Express app
    const expressApp = app();

    // Only use SSL directly in development mode
    if (!environment.production) {
      // Find project root by searching for certs directory
      const serverDistFolder = dirname(fileURLToPath(import.meta.url));
      const projectRoot = findProjectRoot(serverDistFolder);

      const sslKeyPath = process.env['SSL_KEY_PATH'] ?? join(projectRoot, 'certs/key.pem');
      const sslCertPath = process.env['SSL_CERT_PATH'] ?? join(projectRoot, 'certs/cert.pem');

      try {
        const httpsOptions = {
          key: fs.readFileSync(sslKeyPath),
          cert: fs.readFileSync(sslCertPath),
        };

        // Create HTTPS server for development mode
        const httpsServer = https.createServer(httpsOptions, expressApp);
        httpsServer.listen(port, host, () => {
          console.log(`[DEV] HTTPS server listening on https://${host}:${port}`);
        });
      } catch (error) {
        console.error('Failed to start development HTTPS server:', error);
        console.log('Checking if key and cert files exist...');
        console.log('Key file:', sslKeyPath);
        console.log('Cert file:', sslCertPath);
        console.log('Falling back to HTTP...');
        startHttpServer(expressApp, port, host, true);
      }
    } else {
      // In production, use regular HTTP as Nginx handles HTTPS
      startHttpServer(expressApp, port, host, false);
    }
  } catch (error) {
    console.error('Failed to start server:', error);
    process.exit(1);
  }
}

function startHttpServer(app: express.Express, port: number, host: string, isDev: boolean): void {
  app.listen(port, host, () => {
    const mode = isDev ? '[DEV]' : '';
    console.log(`${mode} HTTP server listening on http://${host}:${port}`);
  });
}

// Webpack will replace 'isMainModule' with 'true' in the production bundle
if (isMainModule(import.meta.url)) {
  run();
}

export default app;
