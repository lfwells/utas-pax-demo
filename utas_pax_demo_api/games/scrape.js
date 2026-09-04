const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const axios = require('axios');
const cheerio = require('cheerio');

// Parse command-line arguments
const [baseUrlArg, destDirArg] = process.argv.slice(2);

if (!baseUrlArg || !destDirArg) {
  console.error('Usage: node scrape.js <FULL_IFRAME_URL> <DEST_DIR>');
  console.error('Example: node scrape.js "https://html-classic.itch.zone/html/1234567/index.html?v=123" "./my-game"');
  process.exit(1);
}

// Parse input URL into components to handle query params safely
const targetUrl = new URL(baseUrlArg);
const queryParams = targetUrl.search; // e.g., "?v=12345"

// Extract base directory (e.g., "https://html-classic.itch.zone/html/1234567")
let basePath = targetUrl.origin + targetUrl.pathname;
if (basePath.endsWith('/index.html')) {
  basePath = basePath.slice(0, -'/index.html'.length);
}
basePath = basePath.replace(/\/+$/, '');

const ROOT_DEST = path.resolve(process.cwd(), destDirArg);

async function downloadFile(relativeUrl, subFolder) {
  // Clean relative URL of any existing query params
  const cleanRelative = relativeUrl.split('?')[0].replace(/^\//, '');
  const isAbsolute = relativeUrl.startsWith('http://') || relativeUrl.startsWith('https://');

  // If the file is Brotli-compressed (.br), save it locally without .br
  const isBrotli = cleanRelative.endsWith('.br');
  const targetRelative = isBrotli ? cleanRelative.slice(0, -3) : cleanRelative;

  const fileUrl = isAbsolute 
    ? relativeUrl 
    : `${basePath}/${cleanRelative}${queryParams}`;

  const fileName = path.basename(targetRelative);
  const targetDir = isAbsolute 
    ? path.join(ROOT_DEST, 'vendor') 
    : path.join(ROOT_DEST, subFolder);
  
  const destPath = path.join(targetDir, fileName);

  if (!fs.existsSync(targetDir)) {
    fs.mkdirSync(targetDir, { recursive: true });
  }

  console.log(` Downloading: ${cleanRelative}`);
  try {
    const response = await axios({
      method: 'GET',
      url: fileUrl,
      responseType: 'arraybuffer'
    });

    let data = response.data;
    const sample = data.toString('utf-8', 0, 100);

    // Check if CDN silently returned HTML fallback instead of real asset
    if (sample.trim().toLowerCase().startsWith('<!doctype html') || sample.trim().startsWith('<html')) {
      console.error(`  Warning: Received HTML fallback instead of real asset for "${cleanRelative}".`);
      return;
    }

    // Decompress Brotli files locally
    if (isBrotli) {
      try {
        data = zlib.brotliDecompressSync(data);
        console.log(`   Decompressed Brotli -> ${fileName}`);
      } catch (e) {
        console.warn(`   Could not decompress ${cleanRelative}, saving original.`);
      }
    }

    fs.writeFileSync(destPath, data);
    console.log(`   Saved -> ${path.relative(ROOT_DEST, destPath)} (${data.length} bytes)`);
  } catch (err) {
    console.error(`   Failed to download ${cleanRelative}: ${err.message}`);
  }
}

async function scrapeGame() {
  const indexUrl = `${basePath}/index.html${queryParams}`;
  console.log(`Fetching index.html from: ${indexUrl}\n`);
  
  let htmlContent = '';
  try {
    const indexResponse = await axios.get(indexUrl);
    htmlContent = indexResponse.data;
  } catch (err) {
    console.error(`Failed to fetch index page: ${err.message}`);
    process.exit(1);
  }

  // Ensure root destination folder exists
  if (!fs.existsSync(ROOT_DEST)) {
    fs.mkdirSync(ROOT_DEST, { recursive: true });
  }

  // --- APPLY HTML FIXES ---

  // Fix 1: Remove itch.io anti-hotlinking script (fixes "You should be using itch.io" screen in Flutter)
  htmlContent = htmlContent.replace(/<script[^>]*htmlgame\.js[^>]*><\/script>/gi, '');

  // Fix 2: Remove .br references from config and script tags so Unity loads uncompressed files
  htmlContent = htmlContent.replace(/\.br/g, '');

  // Fix 3: Suppress Unity HTTP header warning banner
  htmlContent = htmlContent.replace(/showBanner\s*:\s*unityShowBanner\s*,?/gi, '// showBanner: unityShowBanner,');

  // Fix 4: Auto-inject fullscreen-on-first-click logic into index.html
  const autoFullscreenSnippet = `unityInstance.SetFullscreen(1);
  const triggerFS = () => { unityInstance.SetFullscreen(1); window.removeEventListener('click', triggerFS); window.removeEventListener('touchend', triggerFS); };
  window.addEventListener('click', triggerFS);
  window.addEventListener('touchend', triggerFS);`;

  htmlContent = htmlContent.replace(
    'unityInstance.SetFullscreen(1);',
    autoFullscreenSnippet
  );

  // Fix 5: Inject custom CSS for 90% size and global fullscreen button image
  const customStyles = `
  <style>
    body { background-color: black !important; overflow: hidden; margin: 0; padding: 0; }
    #unity-container { width: 90vw !important; height: 90vh !important; position: absolute !important; top: 50% !important; left: 50% !important; transform: translate(-50%, -50%) !important; }
    #unity-canvas { width: 100% !important; height: 100% !important; }
    #unity-footer { background: #231f20; }
    #unity-fullscreen-button { background-image: url('/fullscreen-button.png') !important; }
  </style>
  `;
  htmlContent = htmlContent.replace('</head>', `${customStyles}</head>`);

  // Save patched index.html locally
  fs.writeFileSync(path.join(ROOT_DEST, 'index.html'), htmlContent);
  console.log(` Saved patched local index.html to ${path.join(destDirArg, 'index.html')}\n`);

  const $ = cheerio.load(htmlContent);
  const assetMap = new Map(); // key: cleanRelativeUrl, value: folder

  // 1. Scrape standard HTML tags
  $('link[href]').each((_, el) => {
    const href = $(el).attr('href');
    if (href && !href.startsWith('data:')) {
      const cleanHref = href.split('?')[0];
      assetMap.set(cleanHref, path.dirname(cleanHref));
    }
  });

  $('script[src]').each((_, el) => {
    const src = $(el).attr('src');
    if (src) {
      const cleanSrc = src.split('?')[0];
      assetMap.set(cleanSrc, cleanSrc.startsWith('http') ? 'vendor' : path.dirname(cleanSrc));
    }
  });

  // 2. Extract Unity config object paths using Regex
  const scriptContent = $('script').not('[src]').text();

  const buildUrlMatch = scriptContent.match(/var\s+buildUrl\s*=\s*["']([^"']+)["']/);
  const buildFolder = buildUrlMatch ? buildUrlMatch[1] : 'Build';

  const configPatterns = [
    /loaderUrl\s*=\s*buildUrl\s*\+\s*["']([^"']+)["']/,
    /dataUrl\s*:\s*buildUrl\s*\+\s*["']([^"']+)["']/,
    /frameworkUrl\s*:\s*buildUrl\s*\+\s*["']([^"']+)["']/,
    /codeUrl\s*:\s*buildUrl\s*\+\s*["']([^"']+)["']/
  ];

  configPatterns.forEach(pattern => {
    const match = scriptContent.match(pattern);
    if (match) {
      const cleanPath = match[1].split('?')[0];
      // Note: Re-add .br temporarily if present in original regex so downloader fetches compressed asset from CDN
      const relativePath = `${buildFolder}${cleanPath}${cleanPath.endsWith('.br') ? '' : '.br'}`;
      assetMap.set(relativePath, buildFolder);
    }
  });

  // 3. Download all gathered assets
  for (const [url, folder] of assetMap.entries()) {
    await downloadFile(url, folder);
  }

  console.log(`\n Scrape Complete! Files saved and patched for Flutter inside "${destDirArg}".`);
}

scrapeGame();