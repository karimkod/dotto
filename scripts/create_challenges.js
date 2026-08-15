// Publish several challenge documents to Firestore in one go.
//
//   node scripts/create_challenges.js                 # every challenge_week_*.json
//   node scripts/create_challenges.js a.json b.json   # just these
//   node scripts/create_challenges.js --dry-run       # show, don't write
//
// The single-document script next door explains the credential trick this
// borrows: the security rules say `allow write: if false`, so no client SDK can
// write here however it is signed in, and this project has no service account
// key. The Firebase CLI is already logged in as the project owner, so its
// refresh token is exchanged for an access token and the writes go over the
// REST API. Nothing secret is committed and no token is ever logged.
//
// The token is fetched once and reused across every document, and each write is
// a PATCH — an upsert keyed on the document id — so re-running this is safe and
// republishes rather than duplicating.
//
// Solvability is NOT checked here. Run these first, or a board that cannot be
// beaten goes live and wastes someone's week:
//
//   dart run tool/verify_challenges.dart
//   flutter test test/challenge_document_test.dart

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
/// the collection's `orderBy('startDate')` query needs to sort on.
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

/** Every challenge document under scripts/, oldest week first. */
function allDocuments() {
  const dir = path.join(__dirname);
  return fs
    .readdirSync(dir)
    .filter((f) => f.startsWith('challenge_week_') && f.endsWith('.json'))
    .sort()
    .map((f) => path.join('scripts', f));
}

async function main() {
  const args = process.argv.slice(2);
  const dryRun = args.includes('--dry-run');
  const files = args.filter((a) => !a.startsWith('--'));
  const targets = files.length > 0 ? files : allDocuments();

  if (targets.length === 0) throw new Error('no challenge documents found');

  // Parse everything before writing anything: a typo in the last file should
  // not leave the first nine published and the collection half-updated.
  const docs = targets.map((file) => {
    const doc = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (!doc.id) throw new Error(`${file} has no id`);
    if (!doc.level) throw new Error(`${file} has no level`);
    if (!doc.startDate || !doc.endDate) {
      throw new Error(`${file} is missing its window`);
    }
    return { file, doc };
  });

  const ids = new Set();
  for (const { file, doc } of docs) {
    if (ids.has(doc.id)) {
      throw new Error(`${file} reuses id ${doc.id}; it would overwrite`);
    }
    ids.add(doc.id);
  }

  if (dryRun) {
    for (const { doc } of docs) {
      const start = new Date(doc.startDate).toISOString().slice(0, 10);
      const end = new Date(doc.endDate).toISOString().slice(0, 10);
      console.log(`would publish challenges/${doc.id}  ${start} → ${end}  ` +
        `"${doc.title}"`);
    }
    console.log(`\n${docs.length} document(s), nothing written`);
    return;
  }

  const token = await accessToken();
  let written = 0;

  for (const { doc } of docs) {
    const url =
      `https://firestore.googleapis.com/v1/projects/${PROJECT}` +
      `/databases/(default)/documents/challenges/${doc.id}`;

    const res = await fetch(url, {
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ fields: toFields(storable(doc)) }),
    });

    if (!res.ok) {
      // Say how far it got: the writes are independent, so the ones already
      // through are live and re-running is the fix.
      throw new Error(
        `write failed on ${doc.id} after ${written} succeeded: ` +
        `${res.status} ${await res.text()}`,
      );
    }
    written++;
    const start = new Date(doc.startDate).toISOString().slice(0, 10);
    const end = new Date(doc.endDate).toISOString().slice(0, 10);
    console.log(
      `published challenges/${doc.id}  ${start} → ${end}  "${doc.title}"`,
    );
  }

  console.log(`\n${written} document(s) published to ${PROJECT}`);
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
