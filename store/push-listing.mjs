#!/usr/bin/env node
// Pushes the store listing to App Store Connect: the words from listing.md and
// the images from screenshots/.
//
//   node store/push-listing.mjs
//
// Credentials come from ~/.appstoreconnect/env, the same file the other App
// Store scripts read. listing.md stays the one place the words live, so nothing
// here has to be kept in step by hand.
//
// What still cannot be done from here: the age rating questionnaire and Submit
// for Review, both of which App Store Connect only exposes through its web
// interface.

import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const APP_NAME = 'Kvill';
const here = path.dirname(new URL(import.meta.url).pathname);

// --- credentials -----------------------------------------------------------

function loadEnvFile(file) {
  if (!fs.existsSync(file)) return;
  for (const raw of fs.readFileSync(file, 'utf8').split('\n')) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const eq = line.indexOf('=');
    if (eq < 1) continue;
    const key = line.slice(0, eq).trim().replace(/^export\s+/, '');
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key) || key in process.env) continue;
    let value = line.slice(eq + 1).trim();
    if ((value.startsWith("'") && value.endsWith("'")) ||
        (value.startsWith('"') && value.endsWith('"'))) value = value.slice(1, -1);
    process.env[key] = value.replace(/\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?/g,
      (w, n) => process.env[n] ?? w);
  }
}
for (const f of [path.join(os.homedir(), '.appstoreconnect', 'env'),
  path.join(os.homedir(), '.env')]) loadEnvFile(f);

const { ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH } = process.env;
if (!ASC_KEY_ID || !ASC_ISSUER_ID || !ASC_KEY_PATH) {
  console.error('Missing ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH.');
  process.exit(1);
}

const b64url = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const header = b64url({ alg: 'ES256', kid: ASC_KEY_ID, typ: 'JWT' });
const now = Math.floor(Date.now() / 1000);
const payload = b64url({ iss: ASC_ISSUER_ID, iat: now, exp: now + 1200, aud: 'appstoreconnect-v1' });
const signer = crypto.createSign('SHA256');
signer.update(`${header}.${payload}`);
const signingKey = fs.readFileSync(ASC_KEY_PATH.replace('~', os.homedir()), 'utf8');
const token = `${header}.${payload}.${signer.sign({ key: signingKey, dsaEncoding: 'ieee-p1363' }).toString('base64url')}`;

async function api(method, endpoint, body) {
  const response = await fetch(`https://api.appstoreconnect.apple.com${endpoint}`, {
    method,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  let json;
  try { json = text ? JSON.parse(text) : {}; } catch { json = { raw: text.slice(0, 300) }; }
  return { ok: response.ok, status: response.status, json };
}

const problem = (result) =>
  JSON.stringify(result.json.errors ?? result.json).slice(0, 300);

// --- listing.md ------------------------------------------------------------

const listing = fs.readFileSync(path.join(here, 'listing.md'), 'utf8');

// Split on the headings rather than matching between them. A lazy match ending
// at `$` under the multiline flag stops at the first line break, not at the end
// of the section, so every field went up as its opening line and nothing else.
const sections = new Map();
for (const chunk of listing.split(/^## /m).slice(1)) {
  const breakAt = chunk.indexOf('\n');
  sections.set(chunk.slice(0, breakAt).trim(), chunk.slice(breakAt + 1).trim());
}
const section = (name) => sections.get(name) ?? null;
const field = (name) => {
  const match = listing.match(new RegExp(`^- \\*\\*${name}\\*\\*: (.+)$`, 'm'));
  return match ? match[1].trim() : null;
};

// --- the app ---------------------------------------------------------------

const apps = await api('GET', '/v1/apps?limit=200');
const app = apps.json.data?.find((a) => a.attributes.name === APP_NAME);
if (!app) { console.error(`No app record named ${APP_NAME}.`); process.exit(1); }
console.log(`${app.attributes.name}  ${app.id}  ${app.attributes.bundleId}`);

const versions = await api('GET', `/v1/apps/${app.id}/appStoreVersions?limit=10`);
const version = versions.json.data[0];
console.log(`version ${version.attributes.versionString}  ${version.attributes.appStoreState}`);

const localizations = await api(
  'GET', `/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations`);
const localization = localizations.json.data.find((l) => l.attributes.locale === 'en-US');

// --- words -----------------------------------------------------------------

// `whatsNew` is refused on a first version: there is nothing new in a 1.0.
const words = await api('PATCH', `/v1/appStoreVersionLocalizations/${localization.id}`, {
  data: {
    type: 'appStoreVersionLocalizations',
    id: localization.id,
    attributes: {
      description: section('Description'),
      keywords: section('Keywords'),
      promotionalText: section('Promotional text'),
      supportUrl: field('Support URL'),
      marketingUrl: field('Marketing URL'),
    },
  },
});
console.log('description, keywords, promotional text, URLs:',
  words.ok ? 'set' : `${words.status} ${problem(words)}`);

// Copyright lives on the version itself, not on its localization.
const rights = await api('PATCH', `/v1/appStoreVersions/${version.id}`, {
  data: {
    type: 'appStoreVersions',
    id: version.id,
    attributes: { copyright: field('Copyright') },
  },
});
console.log('copyright:', rights.ok ? field('Copyright') : `${rights.status} ${problem(rights)}`);

const infos = await api('GET', `/v1/apps/${app.id}/appInfos`);
const info = infos.json.data[0];
const infoLocalizations = await api('GET', `/v1/appInfos/${info.id}/appInfoLocalizations`);
const infoLocalization = infoLocalizations.json.data.find((l) => l.attributes.locale === 'en-US');

const appWords = await api('PATCH', `/v1/appInfoLocalizations/${infoLocalization.id}`, {
  data: {
    type: 'appInfoLocalizations',
    id: infoLocalization.id,
    attributes: {
      subtitle: field('Subtitle'),
      privacyPolicyUrl: field('Privacy policy URL'),
    },
  },
});
console.log('subtitle, privacy policy URL:',
  appWords.ok ? 'set' : `${appWords.status} ${problem(appWords)}`);

const categories = await api('PATCH', `/v1/appInfos/${info.id}`, {
  data: {
    type: 'appInfos',
    id: info.id,
    relationships: {
      primaryCategory: { data: { type: 'appCategories', id: 'PRODUCTIVITY' } },
      secondaryCategory: { data: { type: 'appCategories', id: 'DEVELOPER_TOOLS' } },
    },
  },
});
console.log('categories:', categories.ok ? 'set' : `${categories.status} ${problem(categories)}`);

// --- screenshots -----------------------------------------------------------

const shots = fs.readdirSync(path.join(here, 'screenshots'))
  .filter((f) => f.endsWith('.png')).sort();
if (!shots.length) { console.log('no screenshots to upload'); process.exit(0); }

// One set per display type. APP_DESKTOP is the macOS one.
const sets = await api(
  'GET', `/v1/appStoreVersionLocalizations/${localization.id}/appScreenshotSets`);
let screenshotSet = sets.json.data?.find(
  (s) => s.attributes.screenshotDisplayType === 'APP_DESKTOP');

if (!screenshotSet) {
  const made = await api('POST', '/v1/appScreenshotSets', {
    data: {
      type: 'appScreenshotSets',
      attributes: { screenshotDisplayType: 'APP_DESKTOP' },
      relationships: {
        appStoreVersionLocalization: {
          data: { type: 'appStoreVersionLocalizations', id: localization.id },
        },
      },
    },
  });
  if (!made.ok) { console.error('screenshot set:', made.status, problem(made)); process.exit(1); }
  screenshotSet = made.json.data;
}

// Anything already there is replaced, so re-running this does not stack up
// duplicates.
const existing = await api('GET', `/v1/appScreenshotSets/${screenshotSet.id}/appScreenshots`);
for (const old of existing.json.data ?? []) {
  await api('DELETE', `/v1/appScreenshots/${old.id}`);
}

for (const name of shots) {
  const file = path.join(here, 'screenshots', name);
  const bytes = fs.readFileSync(file);

  // Reserve: Apple answers with where to put the bytes.
  const reserved = await api('POST', '/v1/appScreenshots', {
    data: {
      type: 'appScreenshots',
      attributes: { fileName: name, fileSize: bytes.length },
      relationships: {
        appScreenshotSet: { data: { type: 'appScreenshotSets', id: screenshotSet.id } },
      },
    },
  });
  if (!reserved.ok) { console.error(` ${name}: ${reserved.status} ${problem(reserved)}`); continue; }

  const screenshot = reserved.json.data;
  for (const operation of screenshot.attributes.uploadOperations) {
    const headers = {};
    for (const h of operation.requestHeaders ?? []) headers[h.name] = h.value;
    const chunk = bytes.subarray(operation.offset, operation.offset + operation.length);
    const put = await fetch(operation.url, { method: operation.method, headers, body: chunk });
    if (!put.ok) { console.error(` ${name}: upload ${put.status}`); }
  }

  // Commit, with a checksum so Apple can tell the bytes arrived intact.
  const checksum = crypto.createHash('md5').update(bytes).digest('hex');
  const committed = await api('PATCH', `/v1/appScreenshots/${screenshot.id}`, {
    data: {
      type: 'appScreenshots',
      id: screenshot.id,
      attributes: { uploaded: true, sourceFileChecksum: checksum },
    },
  });
  console.log(` ${name}: ${committed.ok ? 'uploaded' : `${committed.status} ${problem(committed)}`}`);
}
