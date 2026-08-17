// Fills in the App Review Information section from store/review-notes.md.
//
//   node store/push-review-notes.mjs           prints what it would send
//   node store/push-review-notes.mjs --apply   sends it
//
// This is the section that was empty on the submission Apple rejected under
// 2.1. It is read back after writing, because a 200 on a PATCH is not evidence
// that the field holds what you meant.
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

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
    process.env[key] = value.replace(/\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?/g, (w, n) => process.env[n] ?? w);
  }
}
for (const f of [path.join(os.homedir(), '.appstoreconnect', 'env'),
  path.join(os.homedir(), '.env')]) loadEnvFile(f);

const { ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH } = process.env;
const b64url = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const header = b64url({ alg: 'ES256', kid: ASC_KEY_ID, typ: 'JWT' });
const now = Math.floor(Date.now() / 1000);
const payload = b64url({ iss: ASC_ISSUER_ID, iat: now, exp: now + 900, aud: 'appstoreconnect-v1' });
const signer = crypto.createSign('SHA256');
signer.update(`${header}.${payload}`);
const key = fs.readFileSync(ASC_KEY_PATH.replace('~', os.homedir()), 'utf8');
const token = `${header}.${payload}.${signer.sign({ key, dsaEncoding: 'ieee-p1363' }).toString('base64url')}`;

async function api(method, p, body) {
  const r = await fetch(`https://api.appstoreconnect.apple.com${p}`, {
    method,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await r.text();
  let json; try { json = JSON.parse(text); } catch { json = { raw: text }; }
  return { ok: r.ok, status: r.status, json };
}

// --- What to send -----------------------------------------------------------
const source = fs.readFileSync(new URL('./review-notes.md', import.meta.url), 'utf8');

const notes = source.split('## Notes field')[1]?.trim();
if (!notes) {
  console.error('review-notes.md has no "## Notes field" section.');
  process.exit(1);
}
if (notes.length > 4000) {
  console.error(`notes are ${notes.length} characters, Apple's limit is 4000.`);
  process.exit(1);
}

// The contact table may hold `$NAME` instead of a value, because this
// repository is public and a phone number published to GitHub cannot be taken
// back. Anything of that shape is expanded from the environment, which is
// `~/.appstoreconnect/env` in practice.
//
// An unset variable is a hard stop, never an empty string. App Review
// Information being blank is exactly what got 1.0 rejected under 2.1, and this
// script would otherwise be able to blank it again by running with no
// environment.
const field = (label) => {
  const row = source.match(new RegExp(`^\\|\\s*${label}\\s*\\|\\s*(.+?)\\s*\\|`, 'm'));
  if (!row) { console.error(`review-notes.md has no "${label}" row.`); process.exit(1); }
  const value = row[1].replace(/\$([A-Za-z_][A-Za-z0-9_]*)/g, (whole, name) => {
    const found = process.env[name];
    if (!found) {
      console.error(`review-notes.md wants ${whole} for "${label}", and it is not set.`);
      console.error('Set it in ~/.appstoreconnect/env. Refusing to send a blank contact field.');
      process.exit(1);
    }
    return found;
  });
  if (!value.trim()) {
    console.error(`"${label}" came out empty. Refusing to send it.`);
    process.exit(1);
  }
  return value;
};

const attributes = {
  contactFirstName: field('First name'),
  contactLastName: field('Last name'),
  contactEmail: field('Email'),
  contactPhone: field('Phone'),
  demoAccountRequired: false,
  notes,
};

// --- Where it goes ----------------------------------------------------------
const apps = await api('GET', '/v1/apps?limit=200');
if (!apps.ok) { console.error('cannot list apps:', apps.status); process.exit(1); }
const app = apps.json.data.find((a) => a.attributes.name === 'Kvill');
if (!app) { console.error('no app named Kvill'); process.exit(1); }

const versions = await api('GET', `/v1/apps/${app.id}/appStoreVersions?limit=1`);
if (!versions.ok) { console.error('cannot read versions:', versions.status); process.exit(1); }
const version = versions.json.data[0];

const existing = await api('GET', `/v1/appStoreVersions/${version.id}/appStoreReviewDetail`);
if (!existing.ok) { console.error('cannot read review detail:', existing.status); process.exit(1); }
const detailId = existing.json.data.id;

console.log(`app ${app.attributes.name} ${app.id}`);
console.log(`version ${version.attributes.versionString} (${version.attributes.appStoreState})`);
console.log(`review detail ${detailId}`);
console.log(`  contact  ${attributes.contactFirstName} ${attributes.contactLastName}`);
console.log(`  email    ${attributes.contactEmail}`);
console.log(`  phone    ${attributes.contactPhone}`);
console.log(`  notes    ${notes.length} characters, currently ${(existing.json.data.attributes.notes || '').length}`);

if (!process.argv.includes('--apply')) {
  console.log('\nDry run. Add --apply to send it.');
  process.exit(0);
}

const patched = await api('PATCH', `/v1/appStoreReviewDetails/${detailId}`, {
  data: { type: 'appStoreReviewDetails', id: detailId, attributes },
});
if (!patched.ok) {
  console.error('PATCH failed:', patched.status, JSON.stringify(patched.json).slice(0, 500));
  process.exit(1);
}

// Read it back. A 200 is not evidence that the field holds what you meant.
const after = await api('GET', `/v1/appStoreVersions/${version.id}/appStoreReviewDetail`);
if (!after.ok) { console.error('wrote it, but cannot read it back:', after.status); process.exit(1); }
const got = after.json.data.attributes;
const same = got.notes === notes
  && got.contactEmail === attributes.contactEmail
  && got.contactPhone === attributes.contactPhone;
console.log(same
  ? `\nStored and read back: ${got.notes.length} characters, contact ${got.contactFirstName} ${got.contactLastName}.`
  : `\nWROTE SOMETHING ELSE. Apple holds ${got.notes.length} characters. Check App Store Connect.`);
process.exit(same ? 0 : 1);
