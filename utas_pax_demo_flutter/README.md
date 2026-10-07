# UTAS PAX Demo Flutter

A Flutter Web application for displaying interactive game options, video grid sequences, and kiosk modes for UTAS and Tasmanian Game Makers.

---

## 🔗 URL Deep-Linking Parameters

You can open the web app with query parameters to automatically bypass selection screens and launch straight into a specific mode or JSON grid sequence.

### Supported Query Parameters:

* `option`: Specify the JSON filename (e.g. `pax_video.json`, `video.json`, `tasgm.json`) or option name (e.g. `option=PAX%20Video`) or option index (`0`, `1`).
* `mode`: Execution mode for video sequences (`live`, `kiosk`, or `record`). Default is `live`.
* `baseUrl`: Override the backend server base URL (e.g. `baseUrl=http://localhost:5001/`).

### Examples:
* Automatically start `video.json` in Live mode:
  `http://localhost:5001/?option=video.json&mode=live`
* Automatically start `pax_video.json` in Kiosk mode:
  `http://localhost:5001/?option=pax_video.json&mode=kiosk`

---

## 🎬 60fps Screen Recorder

Using Chromium's native video engine and `ffmpeg-static`, `record.js` records the Flutter Canvas + WebGL + HTML Video DOM elements at full 1080p 60fps and automatically converts the video to a high-quality MP4.

### Command Usage:
```bash
node record.js [JsonFileName] [DurationInSeconds] [BaseUrlOrPort]
```

### Examples:

* **Record `video.json` for 30 seconds (default base URL http://localhost:5001):**
  ```bash
  node record.js video.json 30
  ```

* **Record `video.json` for 30 seconds pointing to port 5001:**
  ```bash
  node record.js video.json 30 60 http://localhost:5001
  ```
  *(Note: Any extra numbers or URLs in the command line are automatically parsed so passing an optional `60` or full URL works seamlessly).*

* **Record `pax_video.json` for 60 seconds:**
  ```bash
  node record.js pax_video.json 60
  ```

Recordings are automatically saved as full 1080p `.webm` and `.mp4` video files inside `./recordings/`.

## Standalone Launcher Folder

The packaged launcher saves the selected games folder in `config.json` beside the executable and reuses it on later launches. On first launch on Windows, the folder picker defaults to `C:\Users\Admin\Desktop\PAXAus2026\games` when that directory exists. To choose a different folder, close the launcher and remove `config.json`; the picker will appear again.
