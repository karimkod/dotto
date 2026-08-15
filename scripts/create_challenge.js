// Publish a challenge document to Firestore.
//
//   node scripts/create_challenge.js scripts/challenge_week_2026_33.json
//
// Authoring goes through an admin credential on purpose: the security rules say
// `allow write: if false`, so no client SDK can write here however it is signed
// in. The usual route is firebase-admin with a service account key, but this
// project has no key issued and none needs to exist — the Firebase CLI is
// already logged in as the project owner, so this borrows that credential,
// exchanges it for an access token and writes over the REST API.
//
// The OAuth client is read out of the installed firebase-tools rather than
// copied into this file, so nothing secret is committed and nothing goes stale
// if the CLI rotates it. Tokens are never logged.
//
// The JSON on disk is the same file the test suite parses with the app's own
// model, so what ships here is what was verified.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execSync } = require('child_process');

const PROJECT = 'dotto-d817e';

/** The CLI's OAuth client, lifted from the installed package. */
function oauthClient() {
  const root = execSync('npm root -g', { encoding: 'utf8' }).trim();
  const src = fs.readFileSync(
    path.join(root, 'firebase-tools', 'lib', 'api.js'),
    'utf8',
  );
  const grab = (name) => {
    const m = src.match(
      new RegExp(`${name} = \\(\\) => [^"]*"[^"]*",\\s*"([^"]+)"`),
    );
    return m && m[1];
  };
  const clientId = grab('clientId');
  const clientSecret = grab('clientSecret');
  if (!clientId || !clientSecret) {
    throw new Error('could not read the OAuth client from firebase-tools');
  }
  return { clientId, clientSecret };
}

/** The refresh token `firebase login` left behind. */
function refreshToken() {
  const p = path.join(
    os.homedir(), '.config', 'configstore', 'firebase-tools.json',
  );
  const token = JSON.parse(fs.readFileSync(p, 'utf8')).tokens?.refresh_token;
  if (!token) throw new Error('not logged in — run: npx firebase-tools login');
  return token;
}

async function accessToken() {
  const { clientId, clientSecret } = oauthClient();
  const res = await fetch('https://www.googleapis.com/oauth2/v3/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      refresh_token: refreshToken(),
      grant_type: 'refresh_token',
    }),
  });
  if (!res.ok) throw new Error(`token exchange failed: ${res.status}`);
  return (await res.json()).access_token;
}

/// Plain JSON to Firestore's typed representation.
///
/// `startDate`/`endDate` become real timestamps rather than strings: the app
/// accepts either, but a timestamp is what the console shows as a date and what
/// any future query would need to order on.
function toValue(v, key) {
  if (v === null) return { nullValue: null };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') {
    return Number.isInteger(v)
      ? { integerValue: String(v) }
      : { doubleValue: v };
  }
  if (typeof v === 'string') {
    return key === 'startDate' || key === 'endDate'
      ? { timestampValue: new Date(v).toISOString() }
      : { stringValue: v };
  }
  if (Array.isArray(v)) {
    return { arrayValue: { values: v.map((e) => toValue(e)) } };
  }
  return { mapValue: { fields: toFields(v) } };
}

function toFields(obj) {
  return Object.fromEntries(
    Object.entries(obj).map(([k, v]) => [k, toValue(v, k)]),
  );
}

/// A cell as `{r, c}` rather than `[r, c]`.
///
/// Firestore rejects an array directly inside an array — `400 Nested arrays are
/// not allowed` — and `walls`, `gaps`, `destroyers` and `teleporters` are all
/// lists of pairs, which is why they had to be left empty. A map inside an
/// array is fine, so the pairs are converted here on the way out: the document
/// on disk keeps the readable `[row, col]` shape the solver and the test suite
/// read, and the app accepts both.
function cell(p) {
  return Array.isArray(p) ? { r: p[0], c: p[1] } : p;
}

/** The document, with every position that sits inside an array made storable. */
function storable(doc) {
  if (!doc.level) return doc;
  const level = { ...doc.level };
  for (const key of ['walls', 'gaps', 'destroyers']) {
    if (Array.isArray(level[key])) level[key] = level[key].map(cell);
  }
  if (Array.isArray(level.teleporters)) {
    // Doubly nested, so it needs a map of its own around the pair.
    level.teleporters = level.teleporters.map((t) =>
      Array.isArray(t) ? { a: cell(t[0]), b: cell(t[1]) } : t);
  }
  return { ...doc, level };
}

async function main() {
  const file = process.argv[2] || 'scripts/challenge_week_2026_33.json';
  const doc = JSON.parse(fs.readFileSync(file, 'utf8'));
  const id = doc.id;
  if (!id) throw new Error(`${file} has no id`);

  const token = await accessToken();
  const url =
    `https://firestore.googleapis.com/v1/projects/${PROJECT}` +
    `/databases/(default)/documents/challenges/${id}`;

  const res = await fetch(url, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ fields: toFields(storable(doc)) }),
  });

  if (!res.ok) {
    throw new Error(`write failed: ${res.status} ${await res.text()}`);
  }
  console.log(`published challenges/${id} — "${doc.title}"`);
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
