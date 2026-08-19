// Record promo/dotto_promo.html to a video, deterministically.
//
//   node scripts/record_promo.js [--fps 30] [--seconds 30]
//
// Needs puppeteer, which is deliberately NOT a dependency of this repo — this
// is a Flutter project and it should not grow a node_modules. Install it
// anywhere and point NODE_PATH at it:
//
//   npm install puppeteer --prefix <somewhere>
//   NODE_PATH=<somewhere>/node_modules node scripts/record_promo.js
//
// WHY NOT SCREENSHOT IN REAL TIME
//
// The obvious loop — screenshot, sleep 1/30s, repeat — produces judder. Its
// frame times are whatever the machine happened to manage, while the page's
// requestAnimationFrame clock runs on wall time and keeps moving during the
// screenshot itself. Frames land at uneven points on the animation's timeline
// and the result stutters in a way no amount of encoding fixes.
//
// So the page's clock is replaced instead. rAF and performance.now are stubbed
// before any page script runs, callbacks are queued rather than scheduled, and
// each frame is rendered by setting the clock to an exact multiple of 1/fps and
// flushing the queue. The page cannot tell the difference, every frame lands
// exactly where it should, and the recording takes as long as it takes without
// affecting the result.
//
// The frame is read straight off the <canvas> rather than via a page
// screenshot: it is the same pixels without the capture pipeline, and quicker.

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const arg = (name, fallback) => {
  const i = process.argv.indexOf(`--${name}`);
  return i === -1 ? fallback : Number(process.argv[i + 1]);
};

const FPS = arg('fps', 30);
const SECONDS = arg('seconds', 30);
const WIDTH = 1080;
const HEIGHT = 1920;

const promoDir = path.resolve(__dirname, '..', 'promo');
const htmlPath = path.join(promoDir, 'dotto_promo.html');
const outPath = path.join(promoDir, 'dotto_promo_animated.mp4');

async function main() {
  if (!fs.existsSync(htmlPath)) {
    throw new Error(`no page to record at ${htmlPath}`);
  }
  const puppeteer = require('puppeteer');

  // Frames go to a temp directory, not into the repo — 900 PNGs at this size
  // is a few hundred MB and none of it is worth keeping.
  const framesDir = fs.mkdtempSync(path.join(require('os').tmpdir(), 'promo-'));

  const browser = await puppeteer.launch({
    headless: 'new',
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--force-device-scale-factor=1'],
  });

  try {
    const page = await browser.newPage();
    await page.setViewport({ width: WIDTH, height: HEIGHT, deviceScaleFactor: 1 });

    // Installed before the document exists, so the page's own script sees the
    // stubs rather than the real thing.
    await page.evaluateOnNewDocument(() => {
      window.__pending = [];
      window.__clock = 0;
      window.requestAnimationFrame = (cb) => window.__pending.push(cb);
      window.cancelAnimationFrame = () => {};
      const clock = () => window.__clock;
      performance.now = clock;
      Date.now = clock;
    });

    await page.goto(`file:///${htmlPath.replace(/\\/g, '/')}`, {
      waitUntil: 'load',
    });

    const total = Math.round(FPS * SECONDS);
    const step = 1000 / FPS;
    console.log(`Recording ${total} frames at ${FPS}fps (${SECONDS}s) from ${path.basename(htmlPath)}`);

    for (let i = 0; i < total; i++) {
      const dataUrl = await page.evaluate((clockMs) => {
        window.__clock = clockMs;
        // Drain the queue: a callback that re-registers must land in the NEXT
        // frame's batch, not loop forever inside this one.
        const due = window.__pending;
        window.__pending = [];
        for (const cb of due) cb(clockMs);
        return document.querySelector('canvas').toDataURL('image/png');
      }, i * step);

      fs.writeFileSync(
        path.join(framesDir, `frame_${String(i).padStart(5, '0')}.png`),
        Buffer.from(dataUrl.split(',')[1], 'base64'),
      );

      if (i % (FPS * 5) === 0) {
        console.log(`  ${i}/${total} (${Math.round((i / total) * 100)}%)`);
      }
    }

    await browser.close();

    console.log('Encoding…');
    execFileSync('ffmpeg', [
      '-y', '-hide_banner', '-v', 'error',
      '-framerate', String(FPS),
      '-i', path.join(framesDir, 'frame_%05d.png'),
      '-c:v', 'libx264', '-preset', 'medium', '-crf', '18',
      '-pix_fmt', 'yuv420p', '-movflags', '+faststart',
      outPath,
    ], { stdio: 'inherit' });

    console.log(`Done: ${outPath}`);
  } finally {
    fs.rmSync(framesDir, { recursive: true, force: true });
  }
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
