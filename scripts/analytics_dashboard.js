// Build the Dotto analytics dashboard from the GA4 BigQuery export.
//
//   node scripts/analytics_dashboard.js --dataset analytics_123456789
//   node scripts/analytics_dashboard.js --dataset analytics_123456789 --days 90
//
// Reads every .sql in analytics/queries, runs it against BigQuery, and writes a
// single self-contained HTML file to analytics/out/dashboard.html. No server,
// no build step, nothing to deploy: the output is a file you open.
//
// Credentials work the way scripts/create_challenge.js does — the Firebase CLI
// is already logged in as the project owner, so this borrows that refresh token
// rather than requiring a service account key that does not exist. The OAuth
// client is read out of the installed firebase-tools so nothing secret is
// committed. Tokens are never logged.
//
// THE DATASET IS NOT THE FIREBASE PROJECT. GA4 exports into a dataset named
// after the *GA4 property* id — `analytics_123456789` — inside the linked GCP
// project. Firebase console -> Project settings -> Integrations -> BigQuery is
// where the link is made, and it must be switched on before any of this has
// anything to read: the export is not retroactive, so the first table appears
// the day after it is enabled, and no query here can recover the days before.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execSync } = require('child_process');

const PROJECT = 'dotto-d817e';
const ROOT = path.join(__dirname, '..');
const QUERY_DIR = path.join(ROOT, 'analytics', 'queries');
const OUT_DIR = path.join(ROOT, 'analytics', 'out');

// ----- credentials (see scripts/create_challenge.js) -----

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

// ----- BigQuery -----

/**
 * Run one query and return {columns, rows, bytes} with values already typed.
 *
 * A query that outruns the inline timeout comes back incomplete rather than
 * failing, so the job is polled instead of assumed finished — a first run over
 * a wide date range routinely takes longer than the ten seconds asked for.
 */
async function runQuery(token, sql) {
  let res = await fetch(
    `https://bigquery.googleapis.com/bigquery/v2/projects/${PROJECT}/queries`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        query: sql,
        useLegacySql: false,
        timeoutMs: 10000,
        maxResults: 2000,
      }),
    },
  );
  let body = await res.json();
  if (!res.ok) {
    throw new Error(body.error?.message || `BigQuery ${res.status}`);
  }

  while (!body.jobComplete) {
    await new Promise((r) => setTimeout(r, 1500));
    const id = body.jobReference.jobId;
    const loc = body.jobReference.location || '';
    res = await fetch(
      `https://bigquery.googleapis.com/bigquery/v2/projects/${PROJECT}`
        + `/queries/${id}?timeoutMs=10000&maxResults=2000`
        + (loc ? `&location=${loc}` : ''),
      { headers: { Authorization: `Bearer ${token}` } },
    );
    body = await res.json();
    if (!res.ok) throw new Error(body.error?.message || 'BigQuery poll failed');
  }

  const fields = body.schema?.fields || [];
  const columns = fields.map((f) => f.name);
  const rows = (body.rows || []).map((r) =>
    r.f.map((cell, i) => coerce(cell.v, fields[i].type)),
  );
  return { columns, rows, bytes: Number(body.totalBytesProcessed || 0) };
}

/** BigQuery returns every scalar as a string; put the numbers back. */
function coerce(v, type) {
  if (v === null || v === undefined) return null;
  if (['INTEGER', 'INT64', 'FLOAT', 'FLOAT64', 'NUMERIC'].includes(type)) {
    return Number(v);
  }
  return v;
}

// ----- rendering -----

const ESCAPES = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' };
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ESCAPES[c]);

/**
 * The leading `--` comment block of a .sql file, as the panel's explanation.
 *
 * Keeping the prose in the SQL rather than here means the caveat about a metric
 * lives next to the definition of it, and cannot drift away from it.
 */
function headerComment(sql) {
  const lines = [];
  for (const line of sql.split('\n')) {
    if (!line.startsWith('--')) break;
    lines.push(line.replace(/^--\s?/, ''));
  }
  return lines.join('\n').trim();
}

function table(columns, rows) {
  if (!rows.length) {
    return '<p class="empty">No rows. See the note above for whether that is '
      + 'expected.</p>';
  }
  const head = columns.map((c) => `<th>${esc(c)}</th>`).join('');
  const body = rows
    .map((r) => {
      const cells = r
        .map((v) => {
          if (v === null) return '<td class="null">—</td>';
          const num = typeof v === 'number';
          return `<td class="${num ? 'num' : ''}">${esc(v)}</td>`;
        })
        .join('');
      return `<tr>${cells}</tr>`;
    })
    .join('');
  return `<div class="scroll"><table><thead><tr>${head}</tr></thead>`
    + `<tbody>${body}</tbody></table></div>`;
}

const STYLE = `
  :root { color-scheme: light dark;
    --bg:#faf8f5; --fg:#1d1f24; --dim:#6a6f7a; --line:#e4dfd7; --card:#fff;
    --warn:#a35400; }
  @media (prefers-color-scheme: dark) { :root {
    --bg:#15171b; --fg:#e9eaec; --dim:#9aa0aa; --line:#2b2f36; --card:#1c1f24;
    --warn:#e0a35c; } }
  * { box-sizing: border-box; }
  body { margin:0; padding:32px 20px 80px; background:var(--bg); color:var(--fg);
    font:15px/1.55 ui-sans-serif,system-ui,-apple-system,Segoe UI,sans-serif; }
  main { max-width: 1080px; margin: 0 auto; }
  h1 { font-size:26px; margin:0 0 4px; letter-spacing:-.01em; }
  .meta { color:var(--dim); font-size:13px; margin-bottom:32px; }
  section { background:var(--card); border:1px solid var(--line);
    border-radius:12px; padding:20px 22px; margin-bottom:22px; }
  h2 { font-size:17px; margin:0 0 10px; text-transform:capitalize; }
  .note { color:var(--dim); font-size:13px; white-space:pre-wrap; margin:0 0 16px; }
  .scroll { overflow-x:auto; }
  table { border-collapse:collapse; width:100%; font-size:13px;
    font-variant-numeric: tabular-nums; }
  th, td { text-align:left; padding:6px 12px 6px 0;
    border-bottom:1px solid var(--line); white-space:nowrap; }
  th { color:var(--dim); font-weight:600; }
  th:not(:first-child), td.num, td.null { text-align:right; padding-right:18px; }
  td.null { color:var(--dim); }
  .empty, .err { color:var(--warn); font-size:13px; margin:0; white-space:pre-wrap; }
  footer { color:var(--dim); font-size:12px; max-width:1080px; margin:40px auto 0; }
`;

function page(panels, meta) {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Dotto analytics</title>
<style>${STYLE}</style></head><body><main>
<h1>Dotto analytics</h1>
<div class="meta">${esc(meta)}</div>
${panels}
<footer>Generated by <code>scripts/analytics_dashboard.js</code> from the GA4
BigQuery export. Every metric's definition and caveats are the comment block at
the top of its file in <code>analytics/queries/</code>.</footer>
</main></body></html>`;
}

// ----- main -----

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i > -1 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}

const yyyymmdd = (d) =>
  `${d.getUTCFullYear()}${String(d.getUTCMonth() + 1).padStart(2, '0')}`
  + `${String(d.getUTCDate()).padStart(2, '0')}`;

async function main() {
  const dataset = arg('dataset', process.env.GA4_DATASET);
  if (!dataset) {
    console.error(
      'Missing --dataset. It is the GA4 export dataset, e.g.\n'
      + '  node scripts/analytics_dashboard.js --dataset analytics_123456789\n\n'
      + 'Find it in the Firebase console under Project settings -> Integrations\n'
      + '-> BigQuery, or in BigQuery itself as the dataset named analytics_<id>.',
    );
    process.exit(1);
  }
  const days = Number(arg('days', '30'));
  const end = new Date();
  const start = new Date(end.getTime() - days * 86400000);

  const token = await accessToken();
  const files = fs.readdirSync(QUERY_DIR)
    .filter((f) => f.endsWith('.sql'))
    .sort();

  const panels = [];
  let totalBytes = 0;
  for (const file of files) {
    const raw = fs.readFileSync(path.join(QUERY_DIR, file), 'utf8');
    const sql = raw
      .replaceAll('__DATASET__', `${PROJECT}.${dataset}`)
      .replaceAll('__START__', yyyymmdd(start))
      .replaceAll('__END__', yyyymmdd(end));
    const title = file.replace(/^\d+_/, '').replace(/\.sql$/, '')
      .replace(/_/g, ' ');
    process.stdout.write(`  ${file} ... `);
    let inner;
    try {
      const { columns, rows, bytes } = await runQuery(token, sql);
      totalBytes += bytes;
      console.log(`${rows.length} rows`);
      inner = table(columns, rows);
    } catch (e) {
      // One broken query must not cost the whole dashboard: the panel carries
      // its own error and every other panel still renders.
      console.log(`FAILED: ${e.message}`);
      inner = `<p class="err">Query failed: ${esc(e.message)}</p>`;
    }
    panels.push(
      `<section><h2>${esc(title)}</h2>`
      + `<p class="note">${esc(headerComment(raw))}</p>`
      + `${inner}</section>`,
    );
  }

  fs.mkdirSync(OUT_DIR, { recursive: true });
  const outPath = path.join(OUT_DIR, 'dashboard.html');
  const meta = `${dataset} · ${yyyymmdd(start)}–${yyyymmdd(end)} (${days} days)`
    + ` · generated ${new Date().toISOString().replace('T', ' ').slice(0, 16)} UTC`
    + ` · ${(totalBytes / 1e9).toFixed(3)} GB scanned`;
  fs.writeFileSync(outPath, page(panels.join('\n'), meta));
  console.log(`\nWrote ${outPath}`);
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
