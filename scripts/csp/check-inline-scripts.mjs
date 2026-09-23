#!/usr/bin/env node
/**
 * Fails when the built web pages run inline script that the nginx Content-Security-Policy
 * doesn't allow: an inline <script> whose SHA-256 isn't listed in `$script_src`, or an
 * inline event handler, which the policy blocks outright. Run it after a production build.
 *
 *   node scripts/csp/check-inline-scripts.mjs
 */
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');
const DIST = join(ROOT, 'client/web/dist/web');
const HEADERS = join(ROOT, 'nginx/security/security_headers.conf');

const INLINE_SCRIPT = /<script(?![^>]*\ssrc=)([^>]*)>([\s\S]*?)<\/script>/gi;
const SCRIPT_TYPE = /\stype=["']?([^"'\s>]+)/i;
const EVENT_HANDLER = /<[a-z][^>]*\son[a-z]+\s*=/gi;
const JAVASCRIPT_TYPES = new Set(['', 'text/javascript', 'application/javascript', 'module']);

/** Every .html file under `dir`. */
function htmlFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return htmlFiles(path);
    return entry.name.endsWith('.html') ? [path] : [];
  });
}

/** The CSP source expression a browser matches against an inline script's text. */
function hashSource(text) {
  return `'sha256-${createHash('sha256').update(text, 'utf8').digest('base64')}'`;
}

if (!existsSync(DIST)) {
  console.error(`No build output at ${relative(ROOT, DIST)}; run a production build first.`);
  process.exit(1);
}

const scriptSrc = readFileSync(HEADERS, 'utf8').match(/set \$script_src "([^"]*)"/)?.[1] ?? '';
const allowed = new Set(scriptSrc.split(/\s+/));
const missing = new Map();
const handlers = [];

for (const file of htmlFiles(DIST)) {
  const html = readFileSync(file, 'utf8');
  for (const [, attributes, text] of html.matchAll(INLINE_SCRIPT)) {
    const type = (attributes.match(SCRIPT_TYPE)?.[1] ?? '').toLowerCase();
    if (!JAVASCRIPT_TYPES.has(type)) continue;

    const source = hashSource(text);
    if (!allowed.has(source)) missing.set(source, relative(ROOT, file));
  }
  const withoutScripts = html.replace(INLINE_SCRIPT, '');
  if (EVENT_HANDLER.test(withoutScripts)) handlers.push(relative(ROOT, file));
  EVENT_HANDLER.lastIndex = 0;
}

for (const [source, file] of missing) {
  console.error(`Inline script in ${file} is not allowed by $script_src; add ${source}`);
}
for (const file of handlers) {
  console.error(`${file} has an inline event handler, which $script_src blocks`);
}
if (missing.size > 0 || handlers.length > 0) process.exit(1);
console.log('Every inline script in the build is allowed by the Content-Security-Policy.');
