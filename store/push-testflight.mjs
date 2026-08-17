// Sets up TestFlight internal testing from store/testflight.md.
//
//   node store/push-testflight.mjs           prints what it would send
//   node store/push-testflight.mjs --apply   sends it
//
// Internal only, and deliberately so. It creates an internal beta group, puts
// the newest build that is actually ready for beta testing in it, fills the
// beta app localization TestFlight needs before it will hand out a build, and
// adds the account holder as a tester. It never enables a public link, never
// sets an external build state and never creates a betaAppReviewSubmission,
// because all three reach people outside the company.
//
// Every write is read back afterwards. A 200 on a POST is not evidence that
// the resource holds what you meant, which is the lesson from the listing that
// reported 2619 characters while Apple held 80.
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
// App Store Connect caps expiry at 20 minutes and answers 401 to anything longer.
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
// A failed read is a failure, never an empty set to carry on from.
const must = async (what, method, p, body) => {
  const r = await api(method, p, body);
  if (!r.ok) {
    console.error(`${what}: ${r.status} ${JSON.stringify(r.json).slice(0, 500)}`);
    process.exit(1);
  }
  return r;
};
const detail = (r) => (r.json.errors || []).map((e) => `${e.title}: ${e.detail}`).join('; ')
  || JSON.stringify(r.json).slice(0, 400);

// --- What to send -----------------------------------------------------------
const source = fs.readFileSync(new URL('./testflight.md', import.meta.url), 'utf8');

// The table may hold `$NAME` instead of a value, because this repository is
// public. An unset variable is a hard stop, never an empty string.
const field = (label) => {
  const row = source.match(new RegExp(`^\\|\\s*${label}\\s*\\|\\s*(.+?)\\s*\\|`, 'm'));
  if (!row) { console.error(`testflight.md has no "${label}" row.`); process.exit(1); }
  const value = row[1].replace(/\$([A-Za-z_][A-Za-z0-9_]*)/g, (whole, name) => {
    const found = process.env[name];
    if (!found) {
      console.error(`testflight.md wants ${whole} for "${label}", and it is not set.`);
      console.error('Set it in ~/.appstoreconnect/env. Refusing to send a blank.');
      process.exit(1);
    }
    return found;
  });
  if (!value.trim()) { console.error(`"${label}" came out empty. Refusing to send it.`); process.exit(1); }
  return value;
};

const groupName = field('Group name');
const locale = field('Locale');
const feedbackEmail = field('Feedback email');

const description = source.split('## Description')[1]?.trim();
if (!description) { console.error('testflight.md has no "## Description" section.'); process.exit(1); }
if (description.length > 4000) {
  console.error(`description is ${description.length} characters, Apple's limit is 4000.`);
  process.exit(1);
}

// --- Where it goes ----------------------------------------------------------
const APP_ID = '6801623848';
const app = await must('cannot read the app', 'GET', `/v1/apps/${APP_ID}`);
if (app.json.data.attributes.name !== 'Kvill') {
  console.error(`app ${APP_ID} is called ${app.json.data.attributes.name}, not Kvill.`);
  process.exit(1);
}

// The build. Newest first, and it has to be genuinely ready: a build can sit at
// processingState VALID with internalBuildState PROCESSING_EXCEPTION, which is
// what two of the three uploads here did.
const builds = await must('cannot list builds', 'GET',
  `/v1/builds?filter[app]=${APP_ID}&sort=-version&limit=20`);
let build = null;
for (const b of builds.json.data) {
  const bd = await api('GET', `/v1/builds/${b.id}/buildBetaDetail`);
  const state = bd.ok ? bd.json.data.attributes.internalBuildState : `unreadable (${bd.status})`;
  const ok = bd.ok && b.attributes.processingState === 'VALID' && !b.attributes.expired
    && state === 'READY_FOR_BETA_TESTING';
  console.log(`build ${b.attributes.version}  ${b.attributes.processingState}  ${state}` +
    `${b.attributes.expired ? '  EXPIRED' : ''}${ok && !build ? '   <- using this one' : ''}`);
  if (ok && !build) build = b;
}
if (!build) {
  console.error('no build is VALID, unexpired and READY_FOR_BETA_TESTING. Nothing to distribute.');
  process.exit(1);
}

const groups = await must('cannot list beta groups', 'GET', `/v1/apps/${APP_ID}/betaGroups?limit=50`);
const existingGroup = groups.json.data.find((g) => g.attributes.name === groupName);
const locs = await must('cannot list beta app localizations', 'GET',
  `/v1/apps/${APP_ID}/betaAppLocalizations?limit=50`);
const existingLoc = locs.json.data.find((l) => l.attributes.locale === locale);

// Internal testers have to be App Store Connect users already, so the tester is
// read off the account rather than written down in this public repository.
const users = await must('cannot list App Store Connect users', 'GET', '/v1/users?limit=200');
const holder = users.json.data.find((u) => u.attributes.roles.includes('ACCOUNT_HOLDER'))
  ?? users.json.data[0];
if (!holder) { console.error('the account lists no users, so there is nobody to add.'); process.exit(1); }
const testers = await must('cannot list beta testers', 'GET',
  `/v1/betaTesters?filter[apps]=${APP_ID}&limit=200`);
const existingTester = testers.json.data.find(
  (t) => t.attributes.email?.toLowerCase() === holder.attributes.username.toLowerCase());

console.log(`\napp        Kvill ${APP_ID}`);
console.log(`group      ${groupName} ${existingGroup ? `(exists, ${existingGroup.id})` : '(to create, internal)'}`);
console.log(`build      ${build.attributes.version} ${build.id}`);
console.log(`locale     ${locale} ${existingLoc ? `(exists, ${existingLoc.id})` : '(to create)'}`);
console.log(`feedback   ${feedbackEmail}`);
console.log(`description ${description.length} characters`);
console.log(`tester     ${holder.attributes.firstName} ${holder.attributes.lastName}` +
  ` [${holder.attributes.roles.join(', ')}] ${existingTester ? '(already a tester)' : '(to add)'}`);

if (!process.argv.includes('--apply')) {
  console.log('\nDry run. Add --apply to send it.');
  process.exit(0);
}

// --- Send -------------------------------------------------------------------
let groupId = existingGroup?.id;
if (!groupId) {
  const made = await api('POST', '/v1/betaGroups', {
    data: {
      type: 'betaGroups',
      attributes: { name: groupName, isInternalGroup: true, hasAccessToAllBuilds: false },
      relationships: { app: { data: { type: 'apps', id: APP_ID } } },
    },
  });
  if (!made.ok) { console.error(`creating the group failed: ${made.status} ${detail(made)}`); process.exit(1); }
  groupId = made.json.data.id;
  console.log(`\ncreated group ${groupId}`);
}

const attached = await api('POST', `/v1/betaGroups/${groupId}/relationships/builds`, {
  data: [{ type: 'builds', id: build.id }],
});
if (!attached.ok && attached.status !== 409) {
  console.error(`attaching build ${build.attributes.version} failed: ${attached.status} ${detail(attached)}`);
  process.exit(1);
}

const locBody = { description, feedbackEmail };
const wroteLoc = existingLoc
  ? await api('PATCH', `/v1/betaAppLocalizations/${existingLoc.id}`,
    { data: { type: 'betaAppLocalizations', id: existingLoc.id, attributes: locBody } })
  : await api('POST', '/v1/betaAppLocalizations', {
    data: {
      type: 'betaAppLocalizations',
      attributes: { ...locBody, locale },
      relationships: { app: { data: { type: 'apps', id: APP_ID } } },
    },
  });
if (!wroteLoc.ok) {
  console.error(`writing the ${locale} localization failed: ${wroteLoc.status} ${detail(wroteLoc)}`);
  process.exit(1);
}

// Adding a tester may well be refused for an internal group, in which case say
// so precisely rather than pretending it worked or quietly making an external
// one instead.
let testerNote = 'already a tester';
if (!existingTester) {
  const made = await api('POST', '/v1/betaTesters', {
    data: {
      type: 'betaTesters',
      attributes: {
        email: holder.attributes.username,
        firstName: holder.attributes.firstName,
        lastName: holder.attributes.lastName,
      },
      relationships: { betaGroups: { data: [{ type: 'betaGroups', id: groupId }] } },
    },
  });
  testerNote = made.ok ? 'added' : `REFUSED ${made.status}: ${detail(made)}`;
} else if (existingGroup) {
  const joined = await api('POST', `/v1/betaGroups/${groupId}/relationships/betaTesters`, {
    data: [{ type: 'betaTesters', id: existingTester.id }],
  });
  testerNote = joined.ok || joined.status === 409 ? 'already a tester' : `not in the group: ${joined.status}`;
}

// --- Read it all back -------------------------------------------------------
const group = await must('wrote the group, cannot read it back', 'GET', `/v1/betaGroups/${groupId}`);
const groupBuilds = await must('cannot read the group builds', 'GET',
  `/v1/betaGroups/${groupId}/builds?limit=50`);
const groupTesters = await must('cannot read the group testers', 'GET',
  `/v1/betaGroups/${groupId}/betaTesters?limit=200`);
const after = await must('wrote the localization, cannot read it back', 'GET',
  `/v1/apps/${APP_ID}/betaAppLocalizations?limit=50`);
const got = after.json.data.find((l) => l.attributes.locale === locale);

const g = group.json.data.attributes;
console.log(`\ngroup      ${g.name}  internal=${g.isInternalGroup}  publicLink=${g.publicLinkEnabled}` +
  `  allBuilds=${g.hasAccessToAllBuilds}`);
console.log(`builds     ${groupBuilds.json.data.map((b) => b.attributes.version).join(', ') || 'none'}`);
console.log(`testers    ${groupTesters.json.data.map((t) => `${t.attributes.firstName} ${t.attributes.lastName}` +
  ` (${t.attributes.state ?? 'no state'})`).join(', ') || 'none'}  [${testerNote}]`);
console.log(`${locale}     description ${got?.attributes.description?.length ?? 0} characters,` +
  ` feedback ${got?.attributes.feedbackEmail ?? 'MISSING'}`);

const good = g.isInternalGroup === true
  && g.publicLinkEnabled !== true
  && groupBuilds.json.data.some((b) => b.id === build.id)
  && got?.attributes.description === description
  && got?.attributes.feedbackEmail === feedbackEmail;
console.log(good
  ? '\nStored and read back.'
  : '\nAPPLE HOLDS SOMETHING ELSE. Check App Store Connect before relying on this.');
process.exit(good ? 0 : 1);
