// Attaches a file to App Review Information, where the reviewer looks for
// supporting material.
//
//   node store/push-review-attachment.mjs <file>            what it would do
//   node store/push-review-attachment.mjs <file> --apply    sends it
//
// This is NOT the Resolution Center reply. That is a web-only form and the API
// has no endpoint for it. This puts the file on the review detail, which the
// notes already refer to; the reply itself still has to be written in the
// browser.
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
const payload = b64url({ iss: ASC_ISSUER_ID, iat: now, exp: now + 1140, aud: 'appstoreconnect-v1' });
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
const problem = (r) => (r.json.errors ?? []).map((e) => e.detail || e.title).join('; ') || '';

const file = process.argv[2];
if (!file || !fs.existsSync(file)) {
  console.error('usage: node store/push-review-attachment.mjs <file> [--apply]');
  process.exit(2);
}
const bytes = fs.readFileSync(file);
const name = path.basename(file);

const apps = await api('GET', '/v1/apps?limit=200');
if (!apps.ok) { console.error('cannot list apps:', apps.status); process.exit(1); }
const app = apps.json.data.find((a) => a.attributes.name === 'Kvill');
const versions = await api('GET', `/v1/apps/${app.id}/appStoreVersions?limit=1`);
const version = versions.json.data[0];
const detail = await api('GET', `/v1/appStoreVersions/${version.id}/appStoreReviewDetail`);
if (!detail.ok) { console.error('cannot read review detail:', detail.status); process.exit(1); }
const detailId = detail.json.data.id;

const existing = await api('GET', `/v1/appStoreReviewDetails/${detailId}/appStoreReviewAttachments`);
console.log(`version ${version.attributes.versionString} (${version.attributes.appStoreState})`);
console.log(`review detail ${detailId}`);
console.log(`already attached: ${existing.ok ? existing.json.data.length : `unreadable (${existing.status})`}`);
console.log(`${name}  ${(bytes.length / 1048576).toFixed(1)} MB`);

if (!process.argv.includes('--apply')) {
  console.log('\nDry run. Add --apply to send it.');
  process.exit(0);
}

// Reserve: Apple answers with where to put the bytes.
const reserved = await api('POST', '/v1/appStoreReviewAttachments', {
  data: {
    type: 'appStoreReviewAttachments',
    attributes: { fileName: name, fileSize: bytes.length },
    relationships: {
      appStoreReviewDetail: { data: { type: 'appStoreReviewDetails', id: detailId } },
    },
  },
});
if (!reserved.ok) {
  console.error(`reserve failed: ${reserved.status} ${problem(reserved)}`);
  process.exit(1);
}

const attachment = reserved.json.data;
let sent = 0;
for (const operation of attachment.attributes.uploadOperations ?? []) {
  const headers = {};
  for (const h of operation.requestHeaders ?? []) headers[h.name] = h.value;
  const chunk = bytes.subarray(operation.offset, operation.offset + operation.length);
  const put = await fetch(operation.url, { method: operation.method, headers, body: chunk });
  if (!put.ok) { console.error(`upload part failed: ${put.status}`); process.exit(1); }
  sent += chunk.length;
}
console.log(`sent ${(sent / 1048576).toFixed(1)} MB in ${attachment.attributes.uploadOperations?.length ?? 0} parts`);

// Commit, with a checksum so Apple can tell the bytes arrived intact.
const checksum = crypto.createHash('md5').update(bytes).digest('hex');
const committed = await api('PATCH', `/v1/appStoreReviewAttachments/${attachment.id}`, {
  data: {
    type: 'appStoreReviewAttachments',
    id: attachment.id,
    attributes: { uploaded: true, sourceFileChecksum: checksum },
  },
});
if (!committed.ok) {
  console.error(`commit failed: ${committed.status} ${problem(committed)}`);
  process.exit(1);
}

// Read it back. A 200 on the commit is not evidence Apple kept the file.
const after = await api('GET', `/v1/appStoreReviewDetails/${detailId}/appStoreReviewAttachments`);
const found = (after.json.data ?? []).find((a) => a.id === attachment.id);
console.log(found
  ? `stored: ${found.attributes.fileName}, state ${found.attributes.assetDeliveryState?.state ?? 'unknown'}`
  : 'committed, but it is not in the list. Check App Store Connect.');
process.exit(found ? 0 : 1);
