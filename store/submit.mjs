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


const apps = await api('GET', '/v1/apps?limit=200');
const app = apps.json.data.find((a) => a.attributes.name === 'Kvill');
const versions = await api('GET', `/v1/apps/${app.id}/appStoreVersions?limit=5`);
const version = versions.json.data[0];

// Any submission left over from the withdrawn attempt has to go first.
const existing = await api('GET', `/v1/reviewSubmissions?filter[app]=${app.id}&limit=10`);
for (const s of existing.json.data ?? []) {
  console.log('existing submission', s.id, s.attributes.state);
  if (s.attributes.state === 'READY_FOR_REVIEW' || s.attributes.state === 'UNRESOLVED_ISSUES') {
    await api('DELETE', `/v1/reviewSubmissions/${s.id}`);
  }
}

const made = await api('POST', '/v1/reviewSubmissions', {
  data: {
    type: 'reviewSubmissions',
    attributes: { platform: 'MAC_OS' },
    relationships: { app: { data: { type: 'apps', id: app.id } } },
  },
});
if (!made.ok) {
  console.error('create:', made.status, JSON.stringify(made.json.errors ?? '').slice(0, 400));
  process.exit(1);
}
const submission = made.json.data;
console.log('submission', submission.id, submission.attributes.state);

const item = await api('POST', '/v1/reviewSubmissionItems', {
  data: {
    type: 'reviewSubmissionItems',
    relationships: {
      reviewSubmission: { data: { type: 'reviewSubmissions', id: submission.id } },
      appStoreVersion: { data: { type: 'appStoreVersions', id: version.id } },
    },
  },
});
console.log('add version:', item.ok ? 'done' : `${item.status} ${JSON.stringify(item.json.errors ?? '').slice(0, 300)}`);
if (!item.ok) process.exit(1);

const sent = await api('PATCH', `/v1/reviewSubmissions/${submission.id}`, {
  data: { type: 'reviewSubmissions', id: submission.id, attributes: { submitted: true } },
});
console.log('submit:', sent.ok ? sent.json.data.attributes.state : `${sent.status} ${JSON.stringify(sent.json.errors ?? '').slice(0, 400)}`);
