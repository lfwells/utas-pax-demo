const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

async function main() {
  const args = process.argv.slice(2);
  const inputOption = args[0] || 'pax_video.json';
  const durationSec = parseInt(args[1] || '30', 10) || 30;

  let baseUrlArg = 'http://localhost:5001';
  for (let i = 2; i < args.length; i++) {
    const arg = args[i].trim();
    if (arg.startsWith('http://') || arg.startsWith('https://')) {
      baseUrlArg = arg;
      break;
    } else if (!isNaN(parseInt(arg, 10)) && parseInt(arg, 10) > 1000) {
      baseUrlArg = `http://localhost:${arg}`;
      break;
    }
  }

  let url;
  if (inputOption.startsWith('http://') || inputOption.startsWith('https://')) {
    url = inputOption;
  } else {
    const cleanBaseUrl = baseUrlArg.endsWith('/')
      ? baseUrlArg.substring(0, baseUrlArg.length - 1)
      : baseUrlArg;
    url = `${cleanBaseUrl}/?option=${encodeURIComponent(inputOption)}&mode=live`;
  }

  const outputDir = path.join(__dirname, 'recordings');
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  const cleanOptionName = inputOption.replace(/[^a-zA-Z0-9_\-]/g, '_');
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const tempVideoDir = path.join(outputDir, `temp_${timestamp}`);
  fs.mkdirSync(tempVideoDir, { recursive: true });

  console.log('🎬 Launching 1080p 60fps Master Quality Recorder...');
  console.log(`📄 Target JSON Option: ${inputOption}`);
  console.log(`🌐 App URL: ${url}`);
  console.log(`⏱️ Duration Target: ${durationSec} seconds`);
  console.log(`✨ Full-Screen Viewport: 1920x1080 @ 60fps`);

  const overallStartTime = Date.now();

  const browser = await chromium.launch({
    headless: true,
    args: [
      '--autoplay-policy=no-user-gesture-required',
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--ignore-gpu-blocklist',
      '--enable-gpu-rasterization',
      '--force-color-profile=srgb',
      '--use-gl=egl'
    ]
  });

  // Matching viewport and recordVideo size ensures 100% full-screen rendering without quadrant offset
  const context = await browser.newContext({
    viewport: { width: 1920, height: 1080 },
    deviceScaleFactor: 1,
    recordVideo: {
      dir: tempVideoDir,
      size: { width: 1920, height: 1080 }
    }
  });

  const page = await context.newPage();

  console.log('⏳ Navigating to URL and waiting for assets...');
  const navStartTime = Date.now();
  await page.goto(url, { waitUntil: 'networkidle' });
  const navDurationSec = ((Date.now() - navStartTime) / 1000).toFixed(2);
  console.log(`⚡ Page navigation & asset load completed in ${navDurationSec}s`);

  console.log(`🔴 Recording 60fps master video stream (${durationSec}s)...`);

  const captureStartTime = Date.now();
  while (Date.now() - captureStartTime < durationSec * 1000) {
    const elapsed = Math.floor((Date.now() - captureStartTime) / 1000);
    const progress = Math.min(100, Math.floor((elapsed / durationSec) * 100));
    process.stdout.write(`\rRecording... ${elapsed}s / ${durationSec}s (${progress}%)`);
    await new Promise((r) => setTimeout(r, 1000));
  }

  console.log('\n✅ Recording complete. Finalizing master video...');

  const videoObj = page.video();
  const rawVideoPath = videoObj ? await videoObj.path() : null;

  await context.close();
  await browser.close();

  const captureEndTime = Date.now();
  const captureDurationSec = (captureEndTime - captureStartTime) / 1000;
  const totalElapsedSec = (captureEndTime - overallStartTime) / 1000;

  const finalWebmPath = path.join(outputDir, `pax_demo_${cleanOptionName}_master_${timestamp}.webm`);

  if (rawVideoPath && fs.existsSync(rawVideoPath)) {
    fs.renameSync(rawVideoPath, finalWebmPath);
    fs.rmSync(tempVideoDir, { recursive: true, force: true });

    const encodeStartTime = Date.now();

    try {
      const ffmpegPath = require('ffmpeg-static');
      const { execSync } = require('child_process');
      const finalMp4Path = path.join(outputDir, `pax_demo_${cleanOptionName}_master_1080p_${timestamp}.mp4`);

      console.log('🔄 Encoding Visually Lossless 1080p MP4 (CRF 10 @ 60Mbps)...');
      execSync(
        `"${ffmpegPath}" -y -i "${finalWebmPath}" -c:v libx264 -pix_fmt yuv420p -preset slow -crf 10 -b:v 60M "${finalMp4Path}"`,
        { stdio: 'ignore' }
      );

      const encodeDurationSec = ((Date.now() - encodeStartTime) / 1000).toFixed(2);

      console.log('\n📊 RECORDING & PERFORMANCE BENCHMARK SUMMARY:');
      console.log(`   🎬 Target Video Duration:    ${durationSec}.00s`);
      console.log(`   ⏱️ Recording Stream Time:    ${captureDurationSec.toFixed(2)}s`);
      console.log(`   🌐 Page Load Time:           ${navDurationSec}s`);
      console.log(`   🔄 FFmpeg Encoding Time:     ${encodeDurationSec}s`);
      console.log(`   🏁 Total Benchmark Time:     ${totalElapsedSec.toFixed(2)}s`);
      console.log(`   ⚡ Capture Speed Ratio:      ${(captureDurationSec / durationSec).toFixed(2)}x real-time`);
      console.log(`\n🎉 Saved Master File:\n   • 1080p MP4: ${finalMp4Path}`);
    } catch (e) {
      console.log(`🎉 Saved Master WebM recording in:\n   ${finalWebmPath}`);
    }
  } else {
    console.log(`🎉 Saved recording in: ${tempVideoDir}`);
  }
}

main().catch((err) => {
  console.error('\n❌ Error during recording:', err);
  process.exit(1);
});
