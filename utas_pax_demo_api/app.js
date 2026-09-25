var createError = require('http-errors');
var express = require('express');
var path = require('path');
var logger = require('morgan');
var cors = require('cors');
var fs = require('fs');
const ffmpeg = require('fluent-ffmpeg');
const ffmpegStatic = require('ffmpeg-static');

var app = express();

app.use(cors());
app.use(logger('dev'));

// Enable SharedArrayBuffer for Unity 6 Multi-threading
app.use((req, res, next) => {
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
  res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin');
  next();
});

// --- BODY PARSERS ---
app.use(express.json());
app.use(express.urlencoded({ extended: false }));

// ✅ Add this line at the top of app.js with your other requires:
var bodyParser = require('body-parser');

// ✅ Update the middleware configuration:
app.use('/captureFrame', bodyParser.raw({ 
  type: ['image/png', 'application/octet-stream', '*/*'], 
  limit: '50mb' 
}));

// Tell fluent-ffmpeg where to find the static ffmpeg binary
ffmpeg.setFfmpegPath(ffmpegStatic);

// Keep track of frame numbers in memory
let frameCounter = 0;

// Helper getter to dynamically retrieve gamesPath set in launcher.js
function getGamesPath() {
  return app.get('gamesPath') || path.join(__dirname, 'games');
}

// Serve static files with correct MIME types
app.use("/games", (req, res, next) => {
  const gamesPath = getGamesPath();
  express.static(gamesPath, {
    setHeaders: (res, filePath) => {
      if (filePath.endsWith('.wasm')) {
        res.setHeader('Content-Type', 'application/wasm');
      }
    }, fallthrough: false
  })(req, res, next);
});

// Fallthrough handling for missing individual files within game folders
app.use("/games", (req, res, next) => {
  const gamesPath = getGamesPath();
  try {
    if (fs.existsSync(gamesPath)) {
      const gamesFolders = fs.readdirSync(gamesPath).filter(file => {
        const fullPath = path.join(gamesPath, file);
        return fs.existsSync(fullPath) && fs.statSync(fullPath).isDirectory();
      });

      const requestPath = req.path.split('/')[1]; // get first segment of request path
      if (gamesFolders.includes(requestPath)) {
        const filePath = path.join(gamesPath, req.path);
        if (!fs.existsSync(filePath)) {
          return res.status(404).send('File not found: ' + filePath);
        }
      }
    }
  } catch (e) {
    console.error('Error verifying game path files:', e.message);
  }
  next();
});

app.post("/execute", (req, res) => {
  let command = req.body.command;
  if (!command) {
    return res.status(400).send('Missing command parameter');
  }

  //if exe found in the command, replace with .app
  command = command.replace(/\.exe/g, '.app');

  const exec = require('child_process').exec;
  exec(command, (error, stdout, stderr) => {
    if (error) {
      console.error(`Error executing command: ${error}`);
      return res.status(500).send(`Error executing command: ${error.message}`);
    }
    res.send(stdout || stderr);
  });
});

app.get("/steam/:appID", (req, res) => {
  const appId = req.params.appID;
  if (!appId) {
    return res.status(400).send('Missing appID parameter');
  }
  let command = `open steam://rungameid/${appId}`;
  //if windows, its "start steam://rungameid/${appId}"
  if (process.platform === 'win32') {
    command = `start steam://rungameid/${appId}`;
  }
  const exec = require('child_process').exec;
  exec(command, (error, stdout, stderr) => {
    if (error) {
      console.error(`Error executing command: ${error}`);
      return res.status(500).send(`Error executing command: ${error.message}`);
    }
    res.send(stdout || stderr);
  });
});

// --- FRAME CAPTURE ROUTES ---
// --- FRAME CAPTURE ROUTES ---
app.post("/captureFrame", (req, res) => {
  // Guard against missing buffer
  if (!req.body || !Buffer.isBuffer(req.body)) {
    return res.status(400).send('Expected binary frame buffer in request body.');
  }

  const tempDir = path.join(__dirname, 'temp');
  if (!fs.existsSync(tempDir)) {
    fs.mkdirSync(tempDir, { recursive: true });
  }

  // Retrieve frame number from header (e.g. "1", "25", etc.)
  const frameNumHeader = req.get('X-Frame-Number') || req.get('x-frame-number');
  
  if (!frameNumHeader) {
    return res.status(400).send('Missing X-Frame-Number header.');
  }

  const frameNum = parseInt(frameNumHeader, 10);
  
  if (isNaN(frameNum)) {
    return res.status(400).send('Invalid X-Frame-Number header value.');
  }

  // Pad the frame number with leading zeros (e.g., frame-00001.png)
  const formattedIndex = String(frameNum).padStart(5, '0');
  const fileName = `frame-${formattedIndex}.png`;
  const filePath = path.join(tempDir, fileName);

  fs.writeFileSync(filePath, req.body);

  res.send(`Frame ${frameNum} saved to ${filePath}`);
});
app.post("/captureEnd", (req, res) => {
  const tempDir = path.join(__dirname, 'temp');

  if (!fs.existsSync(tempDir)) {
    return res.status(400).send('No frames folder found to generate video.');
  }

  const frames = fs.readdirSync(tempDir).filter(file => file.endsWith('.png'));
  if (frames.length === 0) {
    return res.status(400).send('No captured PNG frames found in temp folder.');
  }

  const gamesFolder = getGamesPath();
  if (!fs.existsSync(gamesFolder)) {
    fs.mkdirSync(gamesFolder, { recursive: true });
  }
  
  const outputPath = path.join(gamesFolder, `gameplay-${Date.now()}.mp4`);

  ffmpeg()
    .input(path.join(tempDir, 'frame-%05d.png'))
    .inputOptions(['-framerate 30'])
    .outputOptions([
      '-c:v libx264',
      '-pix_fmt yuv420p',
      // Force width and height to be divisible by 2 (trunc(iw/2)*2 : trunc(ih/2)*2)
      '-vf scale=trunc(iw/2)*2:trunc(ih/2)*2'
    ])
    .output(outputPath)
    .on('start', (cmd) => {
      console.log('Executing FFmpeg command:', cmd);
    })
    .on('end', () => {
      console.log(`Video created successfully: ${outputPath}`);

      // Cleanup temp directory after encoding completes
      fs.rmSync(tempDir, { recursive: true, force: true });

      res.status(200).json({
        message: 'Video rendering complete!',
        outputPath: outputPath
      });
    })
    .on('error', (err, stdout, stderr) => {
      console.error('FFmpeg encoding error:', err.message);
      console.error('FFmpeg stderr output:\n', stderr); // Logs exact error reason from ffmpeg binary
      res.status(500).send('Failed to encode video: ' + err.message)
    })
    .run();
});

const flutterPath = path.join(__dirname, '..', 'utas_pax_demo_flutter', 'build', 'web');
console.log('Flutter path:', flutterPath);
if (!fs.existsSync(flutterPath)) {
    console.warn('WARNING: Flutter path does not exist:', flutterPath);
}

app.use(express.static(flutterPath));

// Catch-all to handle Flutter routing
app.get('*', (req, res) => {
  const indexPath = path.join(flutterPath, 'index.html');
  if (fs.existsSync(indexPath)) {
    res.sendFile(indexPath);
  } else {
    res.status(404).send('Flutter build not found at ' + indexPath);
  }
});

module.exports = app;