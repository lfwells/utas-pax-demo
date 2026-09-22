const http = require('http');
const path = require('path');
const fs = require('fs');
const { exec } = require('child_process');
const portfinder = require('portfinder');

// Express App
const app = require('./utas_pax_demo_api/app');

// Persist config relative to executable runtime directory
const CONFIG_FILE = path.join(process.cwd(), 'config.json');

/**
 * Load saved configuration or return an empty object
 */
function loadConfig() {
  if (fs.existsSync(CONFIG_FILE)) {
    try {
      return JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
    } catch (e) {
      console.warn('Failed to parse config.json, resetting...');
    }
  }
  return {};
}

/**
 * Save configuration to disk
 */
function saveConfig(config) {
  try {
    fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2), 'utf8');
  } catch (e) {
    console.error('Failed to save config file:', e.message);
  }
}

/**
 * Cross-platform native OS Folder Picker
 * Returns string path if selected, or null if cancelled/failed
 */
function selectFolderDialog(defaultPath) {
  return new Promise((resolve) => {
    const platform = process.platform;
    const initialDir = defaultPath && fs.existsSync(defaultPath) ? defaultPath : process.cwd();

    let command = '';

    if (platform === 'win32') {
      // Windows Native Folder Picker Dialog via PowerShell
      const psScript = `
        Add-Type -AssemblyName System.Windows.Forms;
        $f = New-Object System.Windows.Forms.FolderBrowserDialog;
        $f.Description = 'Select Games Root Directory';
        $f.SelectedPath = '${initialDir.replace(/\\/g, '\\\\')}';
        if ($f.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
          Write-Output $f.SelectedPath
        }
      `.replace(/\n/g, ' ');

      command = `powershell -NoProfile -ExecutionPolicy Bypass -Command "${psScript}"`;
    } else if (platform === 'darwin') {
      // macOS Native Folder Picker via AppleScript
      command = `osascript -e 'POSIX path of (choose folder with prompt "Select Games Root Directory" default location POSIX file "${initialDir}")'`;
    } else {
      // Linux Zenity / Kdialog fallback
      command = `zenity --file-selection --directory --title="Select Games Root Directory" --filename="${initialDir}/" 2>/dev/null || kdialog --getexistingdirectory "${initialDir}" 2>/dev/null`;
    }

    exec(command, (error, stdout) => {
      if (error || !stdout || !stdout.trim()) {
        return resolve(null); // Return null on cancel/error
      }

      const selectedPath = stdout.trim();
      if (fs.existsSync(selectedPath)) {
        resolve(selectedPath);
      } else {
        resolve(null);
      }
    });
  });
}

async function start() {
  try {
    const config = loadConfig();

    // 1. Determine default starting path
    let defaultPath = config.gamesPath;
    if (!defaultPath || !fs.existsSync(defaultPath)) {
      defaultPath = path.join(process.cwd(), 'games');
      if (!fs.existsSync(defaultPath)) {
        defaultPath = process.cwd();
      }
    }

    // 2. Prompt user with native OS folder dialog
    console.log('Opening folder picker dialog...');
    const selectedGamesPath = await selectFolderDialog(defaultPath);

    // 3. Handle cancellation -> terminate app
    if (!selectedGamesPath) {
      console.log('\nFolder selection was cancelled. Terminating application...');
      process.exit(0);
    }

    // 4. Save selection to config
    config.gamesPath = selectedGamesPath;
    saveConfig(config);

    // 5. Register Games folder path on Express app
    app.set('gamesPath', selectedGamesPath);

    // 6. Initialize Server & find available port
    const port = await portfinder.getPortPromise({ port: 5000 });
    app.set('port', port);

    const server = http.createServer(app);

    server.listen(port, () => {
      const url = `http://localhost:${port}`;
      console.log('================================================');
      console.log('   UTAS PAX DEMO SERVER IS RUNNING');
      console.log(`   Games Directory: ${selectedGamesPath}`);
      console.log(`   URL: ${url}`);
      console.log('================================================');

      const startCmd = process.platform === 'darwin' ? 'open' :
                       process.platform === 'win32' ? 'start ""' :
                       'xdg-open';

      exec(`${startCmd} ${url}`);

      console.log('\nNOTE: Keep this terminal window open while using the app.');
      console.log('Press Ctrl+C to shut down the server.');
    });
  } catch (err) {
    console.error('Failed to start server:', err);
    process.exit(1);
  }
}

start();