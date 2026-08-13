// Push the Play Store listing for com.karimkod.dotto.
//
//   node scripts/update_play_listing.js                # dry run: show the diff
//   node scripts/update_play_listing.js --commit       # actually publish it
//
// Dry run by default on purpose. This writes to a public store page, and the
// commit is not reversible except by pushing the old text back — so the normal
// invocation shows exactly what would change and stops.
//
// No dependencies. The Play Developer API is plain REST and a service-account
// JWT is thirty lines of node:crypto, which is a smaller thing to carry than
// node_modules inside a Flutter repo.
//
// The key is NEVER read from this repo. It lives in the Rextory checkout,
// which is where it was already committed — see the note at the bottom.

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const PACKAGE = 'com.karimkod.dotto';
const API = 'https://androidpublisher.googleapis.com/androidpublisher/v3';
const SCOPE = 'https://www.googleapis.com/auth/androidpublisher';

/// Google's published maxima. Exceeding one is a 400 from the API, but the
/// error names the field and not the limit — so they are checked here, where
/// the number can be reported alongside what was actually given.
const LIMITS = { title: 30, shortDescription: 80, fullDescription: 4000 };

const KEY_CANDIDATES = [
  path.join(__dirname, '..', '..', 'rextory', 'rextory-cad9dbcdb694.json'),
  path.join(process.env.USERPROFILE || process.env.HOME || '',
    'projects', 'repos', 'rextory', 'rextory-cad9dbcdb694.json'),
];

function loadKey() {
  for (const p of KEY_CANDIDATES) {
    if (fs.existsSync(p)) return JSON.parse(fs.readFileSync(p, 'utf8'));
  }
  throw new Error(`no service account key found. Looked in:\n  ${KEY_CANDIDATES.join('\n  ')}`);
}

const b64url = (buf) =>
  Buffer.from(buf).toString('base64')
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

/// Service-account JWT, exchanged for an access token.
async function accessToken(key) {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = b64url(JSON.stringify({
    iss: key.client_email,
    scope: SCOPE,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }));
  const signature = b64url(
    crypto.createSign('RSA-SHA256')
      .update(`${header}.${claims}`)
      .sign(key.private_key),
  );

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${header}.${claims}.${signature}`,
    }),
  });
  if (!res.ok) throw new Error(`token exchange failed: ${res.status} ${await res.text()}`);
  return (await res.json()).access_token;
}

async function api(token, method, url, body) {
  const res = await fetch(url.startsWith('http') ? url : `${API}${url}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${url} -> ${res.status}\n${text}`);
  return text ? JSON.parse(text) : {};
}

/// Refuse to send anything Play will reject, and say by how much.
function validate(listing) {
  const errors = [];
  for (const [field, max] of Object.entries(LIMITS)) {
    const value = listing[field] || '';
    if (value.length > max) {
      errors.push(
        `${field}: ${value.length}/${max} — over by ${value.length - max}\n` +
        `    ${JSON.stringify(value.slice(0, 60))}${value.length > 60 ? '…' : ''}`,
      );
    }
  }
  if (errors.length) {
    throw new Error(`listing exceeds Play's limits:\n  ${errors.join('\n  ')}`);
  }
  for (const [field, max] of Object.entries(LIMITS)) {
    console.log(`  ${field.padEnd(16)} ${String((listing[field] || '').length).padStart(4)}/${max}`);
  }
}

/// Field-by-field before/after, so a commit is never a leap.
function diff(before, after) {
  let changed = 0;
  for (const field of Object.keys(LIMITS)) {
    const a = (before && before[field]) || '';
    const b = after[field] || '';
    if (a === b) {
      console.log(`  = ${field} unchanged`);
      continue;
    }
    changed++;
    console.log(`  ~ ${field}`);
    if (field === 'fullDescription') {
      console.log(`      was ${a.length} chars, now ${b.length}`);
    } else {
      console.log(`      was: ${JSON.stringify(a)}`);
      console.log(`      now: ${JSON.stringify(b)}`);
    }
  }
  return changed;
}

async function main() {
  const commit = process.argv.includes('--commit');
  const file = path.join(__dirname, 'play_listing_en-US.json');
  const listing = JSON.parse(fs.readFileSync(file, 'utf8'));
  const language = listing.language || 'en-US';

  console.log(`Play listing for ${PACKAGE} (${language})\n`);
  console.log('Lengths:');
  validate(listing);

  const key = loadKey();
  console.log(`\nAuthenticating as ${key.client_email}`);
  const token = await accessToken(key);

  const edit = await api(token, 'POST', `/applications/${PACKAGE}/edits`);
  console.log(`Edit ${edit.id} opened`);

  let cleanUp = true;
  try {
    let current = null;
    try {
      current = await api(token, 'GET',
        `/applications/${PACKAGE}/edits/${edit.id}/listings/${language}`);
    } catch (e) {
      // A listing that does not exist yet is a create, not an error.
      if (!/404/.test(e.message)) throw e;
      console.log(`No existing ${language} listing — this would create one`);
    }

    console.log('\nChanges:');
    const changed = diff(current, listing);
    if (!changed) {
      console.log('\nNothing to do — the live listing already matches.');
      return;
    }

    if (!commit) {
      console.log('\nDRY RUN — nothing was published. Re-run with --commit to apply.');
      return;
    }

    await api(token, 'PUT',
      `/applications/${PACKAGE}/edits/${edit.id}/listings/${language}`, {
        language,
        title: listing.title,
        shortDescription: listing.shortDescription,
        fullDescription: listing.fullDescription,
      });
    console.log('\nListing written to the edit');

    await api(token, 'POST',
      `/applications/${PACKAGE}/edits/${edit.id}:commit`);
    cleanUp = false;
    console.log(`Edit ${edit.id} COMMITTED — the store page is updated`);
  } finally {
    if (cleanUp) {
      // An abandoned edit is harmless but blocks nothing either; deleting keeps
      // the console's edit list from filling with dead drafts.
      try {
        await api(token, 'DELETE', `/applications/${PACKAGE}/edits/${edit.id}`);
        console.log(`Edit ${edit.id} discarded`);
      } catch (_) { /* already gone, or committed */ }
    }
  }
}

main().catch((e) => {
  console.error(`\n${e.message}`);
  process.exit(1);
});
