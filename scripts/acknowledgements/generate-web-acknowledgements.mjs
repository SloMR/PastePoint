#!/usr/bin/env node
/**
 * Generates client/web/public/legal/acknowledgements.json from package-lock.json,
 * so the acknowledgements page reads a committed file instead of bundler output that
 * only exists in some build configurations.
 *
 *   node scripts/acknowledgements/generate-web-acknowledgements.mjs           # write
 *   node scripts/acknowledgements/generate-web-acknowledgements.mjs --check   # check
 */
import { readFileSync, existsSync, readdirSync, mkdirSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');
const WEB = join(ROOT, 'client/web');
const LOCKFILE = join(WEB, 'package-lock.json');
const OUTPUT = join(WEB, 'public/legal/acknowledgements.json');

// Covers LICENSE, LICENSE.md, LICENCE.txt, LICENSE-MIT.txt, COPYING, NOTICE.
const LICENSE_FILE = /^(LICEN[CS]E|COPYING|NOTICE)([-._].*)?$/i;

/** A package's own directory name, e.g. "a/node_modules/@scope/b" -> "@scope/b". */
function packageName(lockKey) {
  return lockKey.slice(lockKey.lastIndexOf('node_modules/') + 'node_modules/'.length);
}

function licenseText(path) {
  if (!existsSync(path)) return '';

  return readdirSync(path)
    .filter((f) => LICENSE_FILE.test(f))
    .sort()
    .map((f) => readFileSync(join(path, f), 'utf8').trim())
    .join('\n\n')
    .trim();
}

function resolveKey(packages, importer, name) {
  let prefix = importer;

  for (;;) {
    const candidate = prefix ? `${prefix}/node_modules/${name}` : `node_modules/${name}`;
    if (packages[candidate]) return candidate;
    if (!prefix) return null;

    const parent = prefix.lastIndexOf('/node_modules/');
    prefix = parent === -1 ? '' : prefix.slice(0, parent);
  }
}

function build() {
  const lock = JSON.parse(readFileSync(LOCKFILE, 'utf8'));
  const packages = lock.packages;
  const root = packages[''];

  const seen = new Map();
  const queue = Object.keys(root.dependencies ?? {}).map((name) => ['', name]);

  while (queue.length) {
    const [importer, name] = queue.pop();
    const key = resolveKey(packages, importer, name);
    if (!key || seen.has(key)) continue;

    const entry = packages[key];
    if (entry.dev || entry.devOptional) continue;

    seen.set(key, {
      name: packageName(key),
      version: entry.version,
      license: entry.license ?? 'UNKNOWN',
      text: licenseText(join(WEB, key)),
    });

    for (const field of ['dependencies', 'optionalDependencies', 'peerDependencies']) {
      for (const next of Object.keys(entry[field] ?? {})) {
        queue.push([key, next]);
      }
    }
  }

  const sorted = [...seen.values()].sort(
    (a, b) => a.name.localeCompare(b.name) || a.version.localeCompare(b.version)
  );

  return `${JSON.stringify({ packages: sorted }, null, 2)}\n`;
}

const generated = build();
const count = JSON.parse(generated).packages.length;

if (process.argv.includes('--check')) {
  const current = existsSync(OUTPUT) ? readFileSync(OUTPUT, 'utf8') : '';
  if (current === generated) {
    console.log(`acknowledgements.json is up to date (${count} packages)`);
    process.exit(0);
  }

  const ids = (json) =>
    new Set(
      (JSON.parse(json || '{"packages":[]}').packages ?? []).map((p) => `${p.name}@${p.version}`)
    );
  const before = ids(current);
  const after = ids(generated);
  const added = [...after].filter((id) => !before.has(id));
  const removed = [...before].filter((id) => !after.has(id));

  console.error('acknowledgements.json is out of date. Run: npm run acknowledgements');
  if (added.length) console.error(`  added:   ${added.join(', ')}`);
  if (removed.length) console.error(`  removed: ${removed.join(', ')}`);
  if (!added.length && !removed.length) console.error('  license text or metadata changed');
  process.exit(1);
}

mkdirSync(dirname(OUTPUT), { recursive: true });
writeFileSync(OUTPUT, generated);
console.log(`wrote ${OUTPUT} (${count} packages)`);
