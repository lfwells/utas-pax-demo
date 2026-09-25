import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:web/web.dart' as web;
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

void main() {
  runApp(const MyApp());
}

final GlobalKey rootRepaintKey = GlobalKey();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: rootRepaintKey,
      child: MaterialApp(
        title: 'Pax Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        textTheme: GoogleFonts.montserratTextTheme(Theme.of(context).textTheme),
      ),
      builder: (context, child) => Container(
        color: Colors.black,
        child: Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRect(child: child!),
          ),
        ),
      ),
      home: const BaseUrlPage(),
    ));
  }
}

enum GameMode {
  utas(jsonFile: 'utas.json', label: 'UTAS'),
  tasgm(jsonFile: 'tasgm.json', label: 'TasGM'),
  video(jsonFile: 'video.json', label: 'Video');

  final String jsonFile;
  final String label;
  const GameMode({required this.jsonFile, required this.label});

  ThemeData getTheme(BuildContext context) {
    switch (this) {
      case GameMode.utas:
        return ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
          useMaterial3: true,
          textTheme: GoogleFonts.montserratTextTheme(ThemeData.dark().textTheme),
          scaffoldBackgroundColor: Colors.black,
        );
      case GameMode.tasgm:
        return ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange, brightness: Brightness.dark),
          useMaterial3: true,
          textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
          scaffoldBackgroundColor: const Color(0xFF1A1A1A),
        );
      case GameMode.video:
        return ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.red, brightness: Brightness.dark),
          useMaterial3: true,
          textTheme: GoogleFonts.montserratTextTheme(ThemeData.dark().textTheme),
          scaffoldBackgroundColor: Colors.black,
        );
    }
  }
}

class ModeSelectorPage extends StatelessWidget {
  final String baseUrl;
  const ModeSelectorPage({super.key, required this.baseUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Select Mode'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: GameMode.values.map((mode) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: SizedBox(
                width: 280,
                height: 80,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    if (mode == GameMode.video) {
                      final bool? record = await showDialog<bool>(
                        context: context,
                        builder: (BuildContext context) {
                          return AlertDialog(
                            title: const Text('Video Mode Configuration'),
                            content: const Text('Would you like to record this sequence execution to an MP4 file?'),
                            actions: <Widget>[
                              TextButton(
                                child: const Text('Live Playback Only'),
                                onPressed: () => Navigator.of(context).pop(false),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
                                child: const Text('Record to MP4'),
                                onPressed: () => Navigator.of(context).pop(true),
                              ),
                            ],
                          );
                        },
                      );
                      if (record == null) return; // Dialogue cancelled

                      if (context.mounted) {
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) =>
                                GameGridPage(baseUrl: baseUrl, mode: mode, startWithRecording: record),
                            transitionsBuilder: (context, animation, secondaryAnimation, child) =>
                                FadeTransition(opacity: animation, child: child),
                          ),
                        );
                      }
                    } else {
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (context, animation, secondaryAnimation) =>
                              GameGridPage(baseUrl: baseUrl, mode: mode),
                          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
                              FadeTransition(opacity: animation, child: child),
                        ),
                      );
                    }
                  },
                  child: Text(mode.label,
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold)),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class BaseUrlPage extends StatefulWidget {
  const BaseUrlPage({super.key});

  @override
  State<BaseUrlPage> createState() => _BaseUrlPageState();
}

class _BaseUrlPageState extends State<BaseUrlPage> {
  //determine the default base url from the current browser url
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();

    // Get the base URL from the browser's current location
    final uri = Uri.base;
    final protocol = uri.scheme.isEmpty ? 'http' : uri.scheme;
    final host = uri.host.isEmpty ? 'localhost' : uri.host;
    final port = uri.port == 0 ? 5999 : uri.port;

    final currentBaseUrl = kDebugMode ? "http://localhost:5001/" : '$protocol://$host:$port/';

    _controller = TextEditingController(text: currentBaseUrl);

    // If we are running on a server (like inside Electron/Express),
    // automatically navigate to the grid.
    if (uri.host.isNotEmpty || uri.port != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _saveAndNavigate();
      });
    }
  }

  void _saveAndNavigate() {
    final url = "${_controller.text.trim()}games/"; // Ensure it ends with a slash for consistency
    if (url.isNotEmpty) {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              ModeSelectorPage(baseUrl: url),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enter Base URL')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 400,
              child: TextField(
                controller: _controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _saveAndNavigate(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saveAndNavigate,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class Game {
  final String name;
  final String url;
  final String author;
  final String? execute;
  final String? steam;
  final bool isVideo;
  final String? description;
  final String? qr;
  final bool onBooth;
  final bool showLowerThird;

  Game({
    required this.name,
    required this.url,
    required this.author,
    this.execute,
    this.steam,
    this.isVideo = false,
    this.description,
    this.qr,
    this.onBooth = false,
    this.showLowerThird = true,
  });

  factory Game.fromJson(Map<String, dynamic> json) {
    final rawDescription = json['description'] as String?;
    final parsedDescription = rawDescription
        ?.replaceAll('[', '<span style="background-color:#3a3a3c; color:#ffffff; border:1px solid #666666; border-radius:4px; padding:2px 6px; display:inline-block">')
        .replaceAll(']', '</span>')
      .replaceAll('\n', '<br>');

    return Game(
      name: json['name'] as String,
      url: json['url'] as String,
      author: json['author'] as String? ?? 'Unknown',
      execute: json['execute'] as String?,
      steam: json['steam'] as String?,
      isVideo: json['video'] as bool? ?? false,
      description: parsedDescription,
      qr: json['qr'] as String?,
      onBooth: (json['onBooth'] as bool?) ?? (json['on_booth'] as bool?) ?? false,
      showLowerThird: (json['showLowerThird'] as bool?) ?? (json['show_lower_third'] as bool?) ?? true,
    );
  }
}

class GameGridPage extends StatefulWidget {
  final String baseUrl;
  final GameMode mode;
  final bool startWithRecording;
  final double gridSpacing;
  const GameGridPage({
    super.key,
    required this.baseUrl,
    required this.mode,
    this.startWithRecording = false,
    this.gridSpacing = 8.0,
  });

  @override
  State<GameGridPage> createState() => _GameGridPageState();
}

class _GameGridPageState extends State<GameGridPage> {
  late Future<List<Game>> _gamesFuture;
  bool _isSequenceRunning = false;
  bool _isRecording = false;
  final List<Future<void>> _pendingFrameUploads = [];

  Completer<void>? _gridWaitCompleter;
  int? _nextSequenceIndex;

  void _skipGridWait([int? targetIndex]) {
    if (widget.mode != GameMode.video) return;
    if (targetIndex != null) {
      _nextSequenceIndex = targetIndex;
    }
    if (_gridWaitCompleter != null && !_gridWaitCompleter!.isCompleted) {
      _gridWaitCompleter!.complete();
    }
  }

  Future<void> _waitOnGrid(Duration duration) async {
    _gridWaitCompleter = Completer<void>();
    await Future.any([
      Future.delayed(duration),
      _gridWaitCompleter!.future,
    ]);
    _gridWaitCompleter = null;
  }

  @override
  void initState() {
    super.initState();
    _isRecording = widget.startWithRecording;
    _gamesFuture = _fetchGames();
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    super.dispose();
  }

  bool _onKeyEvent(KeyEvent event) {
    if (widget.mode != GameMode.video) return false;
    
    if (event is KeyDownEvent) {
      debugPrint('Key pressed: ${event.logicalKey.debugName} - Stopping sequence.');
      _stopSequenceAndGoBack();
      return true;
    }
    return false;
  }

  void _stopSequenceAndGoBack() {
    if (!mounted) return;
    setState(() {
      _isRecording = false;
    });

    final route = ModalRoute.of(context);
    // If the current route is not this page, it's likely a GameDetailPage
    if (route != null && !route.isCurrent) {
      Navigator.of(context).pop(); // Pop GameDetailPage
    }
    
    // Use a small delay or ensure grid is popped if still mounted
    if (mounted) {
      Navigator.of(context).pop(); // Pop GameGridPage to return to ModeSelectorPage
    }
  }

  Future<void> _recordFrame(Duration simulatedTime, String apiBaseUrl) async {
    final boundary = rootRepaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary != null) {
      // Capture the pixels - we MUST await this to ensure we capture the current frame state
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData != null) {
        final frameNum = (simulatedTime.inMicroseconds / 16666).round();
        final bytes = byteData.buffer.asUint8List();


        debugPrint('Captured frame $frameNum at simulated time ${simulatedTime.inMilliseconds}ms, size: ${bytes.lengthInBytes} bytes');
        // Concurrently upload the frame.
        // We do NOT await the HTTP request here so that we can proceed to capture the next frame
        // as quickly as possible. We track the future to ensure we finish all uploads at the end.
        final uploadFuture = http.post(
          Uri.parse('$apiBaseUrl/captureFrame'),
          headers: {
            'Content-Type': 'application/octet-stream',
            'X-Frame-Number': frameNum.toString(),
          },
          body: bytes,
        ).then((response) {
          if (response.statusCode != 200) {
            debugPrint('Error uploading frame $frameNum: ${response.statusCode}');
          }
        }).catchError((e) {
          debugPrint('Failed to send frame $frameNum: $e');
        });

        _pendingFrameUploads.add(uploadFuture);
        
        // To prevent browser memory exhaustion or request throttling, 
        // we can periodically wait for a batch of uploads to finish if the queue gets too large.
        if (_pendingFrameUploads.length > 30) {
          final oldest = _pendingFrameUploads.removeAt(0);
          await oldest.catchError((_) {});
        }
      }
    }
  }

  Future<void> _playSequence(List<Game> games) async {
    if (_isSequenceRunning) return;
    _isSequenceRunning = true;

    if (_isRecording) {
      await _playSequenceRecorded(games);
    } else {
      await _playSequenceLive(games);
    }

    _isSequenceRunning = false;
  }

  Future<void> _playSequenceLive(List<Game> games) async {
    await Future.delayed(const Duration(seconds: 2));

    debugPrint("Starting live sequence playback for ${games.length} games.");

    // Start with a 5-second delay on the grid at the start
    await _waitOnGrid(const Duration(seconds: 10));

    int index = 0;
    while (mounted && widget.mode == GameMode.video) {
      if (_nextSequenceIndex != null) {
        index = _nextSequenceIndex!;
        _nextSequenceIndex = null;
      }

      final game = games[index];
      if (!mounted) break;

      await Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              GameDetailPage(
            game: game,
            baseUrl: widget.baseUrl,
            mode: widget.mode,
            isRecording: _isRecording,
          ),
          transitionDuration: const Duration(milliseconds: 500),
          reverseTransitionDuration: const Duration(milliseconds: 500),
          transitionsBuilder:
              (context, animation, secondaryAnimation, child) => child,
        ),
      );

      if (_nextSequenceIndex != null) {
        index = _nextSequenceIndex!;
        _nextSequenceIndex = null;
      } else {
        index = (index + 1) % games.length;
      }

      // Spend 5 seconds on the grid between videos
      await _waitOnGrid(const Duration(seconds: 5));
    }
  }

  Future<void> _playSequenceRecorded(List<Game> games) async {
    // Capture necessary state before starting potentially long async work
    final cleanBaseUrl = widget.baseUrl.endsWith('/')
        ? widget.baseUrl.substring(0, widget.baseUrl.length - 1)
        : widget.baseUrl;
    final apiBaseUrl = cleanBaseUrl.replaceAll("/games", "");

    // Escape current frame phase
    await Future.delayed(const Duration(seconds: 2));

    // Deterministic recording at 60 FPS
    const frameInterval = Duration(microseconds: 16666);
    // Start from the current clock time to avoid jumping backwards in internal tickers
    Duration simulatedTime = SchedulerBinding.instance.currentSystemFrameTimeStamp;

    debugPrint("Start recording frames via HTTP API stream...");

    // 1. Initial 5 seconds on grid
    for (int i = 0; i < 5 * 60; i++) {
      if (!_isRecording) break;
      simulatedTime += frameInterval;
      
      await Future.delayed(Duration.zero);
      
      SchedulerBinding.instance.handleBeginFrame(simulatedTime);
      SchedulerBinding.instance.handleDrawFrame();
      // Ensure the frame is fully processed and painted before snapshotting
      await WidgetsBinding.instance.endOfFrame;
      await _recordFrame(simulatedTime, apiBaseUrl);
    }

    int index = 0;
    while (mounted && widget.mode == GameMode.video && _isRecording) {
      final game = games[index];
      if (!mounted) break;

      // 2. Record Navigation Push Transition (500ms)
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              GameDetailPage(
            game: game,
            baseUrl: widget.baseUrl,
            mode: widget.mode,
            isRecording: _isRecording,
          ),
          transitionDuration: const Duration(milliseconds: 500),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              child,
        ),
      );

      // Allow one "real" frame to happen so Navigator can register the transition
      await Future.delayed(Duration.zero);

      for (int i = 0; i < 30; i++) { // 500ms at 60fps = 30 frames
        if (!_isRecording) break;
        simulatedTime += frameInterval;
        
        await Future.delayed(Duration.zero);
        
        SchedulerBinding.instance.handleBeginFrame(simulatedTime);
        SchedulerBinding.instance.handleDrawFrame();
        await WidgetsBinding.instance.endOfFrame;
        await _recordFrame(simulatedTime, apiBaseUrl);
      }
      if (!_isRecording) break;

      // 3. Record Video Playback (We'd need to know duration, assume 10s for demo)
      // Note: toImage does not capture PlatformViews like video elements.
      for (int i = 0; i < 10 * 60; i++) {
        if (!_isRecording) break;
        simulatedTime += frameInterval;
        
        await Future.delayed(Duration.zero);
        
        SchedulerBinding.instance.handleBeginFrame(simulatedTime);
        SchedulerBinding.instance.handleDrawFrame();
        await WidgetsBinding.instance.endOfFrame;
        await _recordFrame(simulatedTime, apiBaseUrl);
      }
      if (!_isRecording) break;

      // 4. Record Navigation Pop Transition (500ms)
      if (mounted) Navigator.pop(context);
      
      // Allow Navigator to settle the pop
      await Future.delayed(Duration.zero);

      for (int i = 0; i < 30; i++) {
        if (!_isRecording) break;
        simulatedTime += frameInterval;
        
        await Future.delayed(Duration.zero);
        
        SchedulerBinding.instance.handleBeginFrame(simulatedTime);
        SchedulerBinding.instance.handleDrawFrame();
        await WidgetsBinding.instance.endOfFrame;
        await _recordFrame(simulatedTime, apiBaseUrl);
      }
      if (!_isRecording) break;

      index = (index + 1) % games.length;

      // 5. 5 seconds on grid between videos
      for (int i = 0; i < 5 * 60; i++) {
        if (!_isRecording) break;
        simulatedTime += frameInterval;
        
        await Future.delayed(Duration.zero);

        SchedulerBinding.instance.handleBeginFrame(simulatedTime);
        SchedulerBinding.instance.handleDrawFrame();
        await WidgetsBinding.instance.endOfFrame;
        await _recordFrame(simulatedTime, apiBaseUrl);
      }
    }

    // WAIT for all pending uploads to finish before triggering compilation
    if (_pendingFrameUploads.isNotEmpty) {
      debugPrint("Waiting for ${_pendingFrameUploads.length} frames to finish uploading...");
      await Future.wait(_pendingFrameUploads);
      _pendingFrameUploads.clear();
    }

    try {
      await http.post(Uri.parse('$apiBaseUrl/captureEnd'));
      debugPrint('Recording compilation triggered successfully on backend server.');
    } catch (e) {
      debugPrint('Failed to trigger video compilation: $e');
    }
  }

  Future<List<Game>> _fetchGames() async {
    final cleanBaseUrl = widget.baseUrl.endsWith('/')
        ? widget.baseUrl.substring(0, widget.baseUrl.length - 1)
        : widget.baseUrl;

    if (kDebugMode) print('Fetching games from $cleanBaseUrl/${widget.mode.jsonFile}');

    final response = await http.get(Uri.parse('$cleanBaseUrl/${widget.mode.jsonFile}'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      final gamesList = data['games'] as List;
      final games = gamesList
          .map((json) => Game.fromJson(json))
          .toList();
      
      if (widget.mode == GameMode.video) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _playSequence(games);
        });
      }
      
      return games;
    } else {
      throw Exception('Failed to load games from ${widget.mode.jsonFile}');
    }
  }

  PreferredSizeWidget? _buildAppBar() {
    if (widget.mode == GameMode.video) {
      return null;
    }

    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: 64,
      foregroundColor: widget.mode == GameMode.utas ? Colors.white : Colors.white,
      backgroundColor: widget.mode == GameMode.tasgm ? Color(0xFF3bd9e5) : Colors.black,
      centerTitle: false,
      title: Text(
        widget.mode == GameMode.utas ? "Study Games at UTAS" : "Tasmanian Game Makers",
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
          child: Image.network(
            "${widget.baseUrl}_thumbs/${widget.mode == GameMode.utas ? 'utas_dark.png' : 'tasgm_logo.png'}",
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _buildModeContent(BuildContext context, List<Game> games) {
    switch (widget.mode) {
      case GameMode.utas:
        return _buildUtasGrid(context, games);
      case GameMode.tasgm:
        return _buildTasgmGrid(context, games);
      case GameMode.video:
        return _buildVideoGrid(context, games);
    }
  }

  Widget _buildUtasGrid(BuildContext context, List<Game> games) {
    return _buildDefaultGrid(context, games, 4);
  }

  Widget _buildTasgmGrid(BuildContext context, List<Game> games) {
    return _buildDefaultGrid(context, games, 3);
  }

  Widget _buildVideoGrid(BuildContext context, List<Game> games) {
    return _buildDefaultGrid(context, games, 4);
  }

  Widget _buildDefaultGrid(BuildContext context, List<Game> games, int crossAxisCount) {
    final spacing = widget.gridSpacing;

    return Container(
      color: Colors.black,
      padding: EdgeInsets.all(spacing),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth - (crossAxisCount - 1) * spacing;
          final cellWidth = availableWidth / crossAxisCount;

          final rowCount = (games.length / crossAxisCount).ceil();
          final effectiveRows = rowCount < crossAxisCount ? crossAxisCount : rowCount;
          final availableHeight = constraints.maxHeight - (effectiveRows - 1) * spacing;
          final cellHeight = availableHeight / effectiveRows;

          final aspectRatio = (cellWidth > 0 && cellHeight > 0)
              ? cellWidth / cellHeight
              : 16 / 9;

          Widget grid = GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              childAspectRatio: aspectRatio,
            ),
            itemCount: games.length,
            itemBuilder: (context, index) {
              final game = games[index];
              return GameThumb(
                game: game,
                gridPage: widget,
                cleanBaseUrl: widget.baseUrl,
                onTap: widget.mode == GameMode.video
                    ? () => _skipGridWait(index)
                    : null,
              );
            },
          );

          if (widget.mode == GameMode.video) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _skipGridWait(),
              child: grid,
            );
          }

          return grid;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.mode.getTheme(context);
    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: _buildAppBar(),
        body: FutureBuilder<List<Game>>(
          future: _gamesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(child: Text('No games found', style: TextStyle(color: Colors.white)));
            }

            return _buildModeContent(context, snapshot.data!);
          },
        ),
      ),
    );
  }
}

class GameImageThumb extends StatelessWidget {
  final String cleanBaseUrl;
  final String gameUrl;
  final BoxFit fit;

  const GameImageThumb({
    super.key,
    required this.cleanBaseUrl,
    required this.gameUrl,
    this.fit = BoxFit.contain,
  });

  Widget _buildPair(String imageUrl) {
    if (fit == BoxFit.cover) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      );
    }

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Scaled up & blurred copy to fill letterbox / pillarbox
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
            ),
          ),
          Container(
            color: Colors.black.withValues(alpha: 0.25),
          ),
          // Primary clear image fitted on shortest side
          Image.network(
            imageUrl,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cleanUrl = cleanBaseUrl.endsWith('/')
        ? cleanBaseUrl.substring(0, cleanBaseUrl.length - 1)
        : cleanBaseUrl;
    final pngUrl = "$cleanUrl/_thumbs$gameUrl.png";
    final jpgUrl = "$cleanUrl/_thumbs$gameUrl.jpg";

    return Image.network(
      pngUrl,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame == null) return const SizedBox.shrink();
        return _buildPair(pngUrl);
      },
      errorBuilder: (context, error, stackTrace) {
        return Image.network(
          jpgUrl,
          fit: fit,
          width: double.infinity,
          height: double.infinity,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (frame == null) return const SizedBox.shrink();
            return _buildPair(jpgUrl);
          },
          errorBuilder: (context, error, stackTrace) {
            return const SizedBox.shrink();
          },
        );
      },
    );
  }
}

class GameThumb extends StatefulWidget {
  const GameThumb({
    super.key,
    required this.game,
    required this.gridPage,
    required this.cleanBaseUrl,
    this.onTap,
  });

  final Game game;
  final GameGridPage gridPage;
  final String cleanBaseUrl;
  final VoidCallback? onTap;

  @override
  State<GameThumb> createState() => _GameThumbState();
}

class _GameThumbState extends State<GameThumb> {
  bool _isHovered = false;
  bool _useVideo = false;
  late String _videoViewId;

  @override
  void initState() {
    super.initState();
    _videoViewId = 'video-thumb-${widget.game.name.replaceAll(' ', '-')}';

    // Register the platform view factory for the video thumbnail
    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(
      _videoViewId,
      (int id) {
        final cleanBaseUrl = widget.cleanBaseUrl.endsWith('/')
            ? widget.cleanBaseUrl.substring(0, widget.cleanBaseUrl.length - 1)
            : widget.cleanBaseUrl;
        final videoUrl = '$cleanBaseUrl/_thumbs${widget.game.url}.mp4';

        final container = web.document.createElement('div') as web.HTMLDivElement;
        container.style.position = 'relative';
        container.style.width = '100%';
        container.style.height = '100%';
        container.style.overflow = 'hidden';
        container.style.backgroundColor = 'black';

        // Background duplicate video - scaled up and blurred
        final videoBg = web.document.createElement('video') as web.HTMLVideoElement;
        videoBg.src = videoUrl;
        videoBg.style.position = 'absolute';
        videoBg.style.top = '0';
        videoBg.style.left = '0';
        videoBg.style.width = '100%';
        videoBg.style.height = '100%';
        videoBg.style.objectFit = 'cover';
        videoBg.style.filter = 'blur(20px) brightness(0.7)';
        videoBg.style.transform = 'scale(1.1)';
        videoBg.autoplay = true;
        videoBg.loop = true;
        videoBg.muted = true;
        videoBg.setAttribute('playsinline', 'true');

        // Foreground primary video - fit on shortest side
        final videoFg = web.document.createElement('video') as web.HTMLVideoElement;
        videoFg.src = videoUrl;
        videoFg.style.position = 'absolute';
        videoFg.style.top = '0';
        videoFg.style.left = '0';
        videoFg.style.width = '100%';
        videoFg.style.height = '100%';
        videoFg.style.objectFit = 'contain';
        videoFg.autoplay = true;
        videoFg.loop = true;
        videoFg.muted = true;
        videoFg.setAttribute('playsinline', 'true');

        videoFg.onPlay.listen((_) => videoBg.play());
        videoFg.onPause.listen((_) => videoBg.pause());

        container.appendChild(videoBg);
        container.appendChild(videoFg);
        return container;
      },
    );

    _checkVideoSource();
  }

  Future<void> _checkVideoSource() async {
    final cleanBaseUrl = widget.cleanBaseUrl.endsWith('/')
        ? widget.cleanBaseUrl.substring(0, widget.cleanBaseUrl.length - 1)
        : widget.cleanBaseUrl;
    final videoUrl = "$cleanBaseUrl/_thumbs${widget.game.url}.mp4";
    try {
      final response = await http.head(Uri.parse(videoUrl));
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _useVideo = true;
          });
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cleanBaseUrl = widget.cleanBaseUrl.endsWith('/')
        ? widget.cleanBaseUrl.substring(0, widget.cleanBaseUrl.length - 1)
        : widget.cleanBaseUrl;

    final isVideoMode = widget.gridPage.mode == GameMode.video;
    final showVideoPreview = isVideoMode && _useVideo;

    if (isVideoMode) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Hero(
          tag: widget.game.name,
          child: Material(
            color: const Color(0xFF1E1E1E),
            child: SizedBox.expand(
              child: Stack(
                children: [
                  if (showVideoPreview)
                    PointerInterceptor(
                      child: HtmlElementView(viewType: _videoViewId),
                    )
                  else
                    GameImageThumb(
                      cleanBaseUrl: cleanBaseUrl,
                      gameUrl: widget.game.url,
                      fit: BoxFit.contain,
                    ),
                  Positioned.fill(
                    child: PointerInterceptor(
                      child: Container(
                        color: Colors.transparent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  GameDetailPage(
                game: widget.game,
                baseUrl: widget.gridPage.baseUrl,
                mode: widget.gridPage.mode,
              ),
              transitionDuration: const Duration(milliseconds: 500),
              reverseTransitionDuration: const Duration(milliseconds: 500),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                return FadeTransition(
                  opacity: animation,
                  child: child,
                );
              },
            ),
          );
        },
        child: Hero(
          tag: widget.game.name,
          child: Material(
            color: const Color(0xFF1E1E1E),
            child: ClipRect(
              child: Stack(
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: _isHovered ? 7.0 : 0.0),
                  duration: const Duration(milliseconds: 250),
                  builder: (context, blurValue, child) {
                    return Opacity(
                      opacity: _isHovered ? 0.5 : 1.0,
                      child: blurValue > 0
                          ? ImageFiltered(
                              imageFilter: ui.ImageFilter.blur(sigmaX: blurValue, sigmaY: blurValue),
                              child: child!,
                            )
                          : child!,
                    );
                  },
                  child: SizedBox.expand(
                    child: showVideoPreview
                        ? PointerInterceptor(
                            child: HtmlElementView(viewType: _videoViewId),
                          )
                        : GameImageThumb(
                            cleanBaseUrl: cleanBaseUrl,
                            gameUrl: widget.game.url,
                            fit: BoxFit.contain,
                          ),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  color: Colors.white.withValues(alpha: _isHovered ? 0.2 : 0.0),
                  width: double.infinity,
                  height: double.infinity,
                ),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: (widget.gridPage.mode != GameMode.video && _isHovered) ? 1.0 : 0.0,
                  child: Container(
                    padding: const EdgeInsets.all(16.0),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.game.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                              shadows: [
                                Shadow(
                                  offset: Offset(0, 2),
                                  blurRadius: 4,
                                  color: Colors.black54,
                                ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            widget.game.author,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              shadows: [
                                Shadow(
                                  offset: Offset(0, 1),
                                  blurRadius: 2,
                                  color: Colors.black54,
                                ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }
}

class GameDetailPage extends StatefulWidget {
  final Game game;
  final String baseUrl;
  final GameMode mode;
  final bool isRecording;

  const GameDetailPage({
    super.key,
    required this.game,
    required this.baseUrl,
    required this.mode,
    this.isRecording = false,
  });

  @override
  State<GameDetailPage> createState() => _GameDetailPageState();
}

class _GameDetailPageState extends State<GameDetailPage> {
  bool _showHtml = false;
  late String _viewId;
  bool _isExecuting = false;
  bool _hasDescription = false;
  bool _showDescription = false;

  @override
  void initState() {
    super.initState();
    _viewId = 'detail-view-${widget.game.name.replaceAll(' ', '-')}';

    _hasDescription = (widget.game.description != null && widget.game.description!.isNotEmpty) ||
        (widget.game.qr != null && widget.game.qr!.isNotEmpty);
    if (_hasDescription && !widget.game.isVideo && widget.mode != GameMode.video) {
      _showDescription = true;
    }

    if (widget.game.execute != null) {
      _isExecuting = true;
      _handleExecute();
    } else if (widget.game.steam != null) {
      _isExecuting = true;
      _handleSteam();
    } else {
      // Register the platform view factory for either video or iframe
      // ignore: undefined_prefixed_name
      ui_web.platformViewRegistry.registerViewFactory(
        _viewId,
        (int id) {
          final cleanBaseUrl = widget.baseUrl.endsWith('/')
              ? widget.baseUrl.substring(0, widget.baseUrl.length - 1)
              : widget.baseUrl;
          
          if (widget.game.isVideo || widget.mode == GameMode.video) {
            final videoUrl = '$cleanBaseUrl/_thumbs${widget.game.url}.mp4';

            final container = web.document.createElement('div') as web.HTMLDivElement;
            container.style.position = 'relative';
            container.style.width = '100%';
            container.style.height = '100%';
            container.style.overflow = 'hidden';
            container.style.backgroundColor = 'black';

            // Background duplicate video - scaled up and blurred
            final videoBg = web.document.createElement('video') as web.HTMLVideoElement;
            videoBg.src = videoUrl;
            videoBg.style.position = 'absolute';
            videoBg.style.top = '0';
            videoBg.style.left = '0';
            videoBg.style.width = '100%';
            videoBg.style.height = '100%';
            videoBg.style.objectFit = 'cover';
            videoBg.style.filter = 'blur(20px) brightness(0.7)';
            videoBg.style.transform = 'scale(1.1)';
            videoBg.autoplay = true;
            videoBg.loop = true;
            videoBg.muted = true;
            videoBg.setAttribute('playsinline', 'true');

            // Foreground primary video - fit on shortest side
            final videoFg = web.document.createElement('video') as web.HTMLVideoElement;
            videoFg.src = videoUrl;
            videoFg.style.position = 'absolute';
            videoFg.style.top = '0';
            videoFg.style.left = '0';
            videoFg.style.width = '100%';
            videoFg.style.height = '100%';
            videoFg.style.objectFit = 'contain';
            videoFg.autoplay = true;
            videoFg.controls = false;
            videoFg.style.cursor = 'pointer';
            videoFg.setAttribute('playsinline', 'true');

            videoFg.onPlay.listen((_) => videoBg.play());
            videoFg.onPause.listen((_) => videoBg.pause());
            videoFg.onClick.listen((_) {
              if (mounted) Navigator.of(context).pop();
            });
            videoFg.onEnded.listen((_) {
              if (mounted) Navigator.of(context).pop();
            });

            container.appendChild(videoBg);
            container.appendChild(videoFg);
            return container;
          } else {
            final iframe = web.document.createElement('iframe') as web.HTMLIFrameElement;
            iframe.src = '$cleanBaseUrl${widget.game.url}';
            iframe.style.border = 'none';
            iframe.style.width = '100%';
            iframe.style.height = '100%';
            iframe.allow = 'fullscreen; autoplay; gamepad; encrypted-media; midi; clipboard-write';
            iframe.setAttribute('allowfullscreen', 'true');
            iframe.setAttribute('webkitallowfullscreen', 'true');
            iframe.setAttribute('mozallowfullscreen', 'true');
            return iframe;
          }
        },
      );

      // Wait for the Hero animation to complete
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final route = ModalRoute.of(context);
        if (route != null && route.animation != null) {
          void listener(AnimationStatus status) {
            if (status == AnimationStatus.completed) {
              if (mounted) {
                setState(() {
                  _showHtml = true;
                });
              }
              route.animation!.removeStatusListener(listener);
            }
          }

          route.animation!.addStatusListener(listener);
        } else {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              setState(() {
                _showHtml = true;
              });
            }
          });
        }
      });
    }
  }

  Future<void> _handleExecute() async {
    final cleanBaseUrl = widget.baseUrl.endsWith('/')
        ? widget.baseUrl.substring(0, widget.baseUrl.length - 1)
        : widget.baseUrl;
    
    try {
      await http.post(
        Uri.parse('$cleanBaseUrl/execute'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'command': widget.game.execute}),
      );
    } catch (e) {
      debugPrint('Execution failed: $e');
    }
  }

  Future<void> _handleSteam() async {
    final cleanBaseUrl = widget.baseUrl.endsWith('/')
        ? widget.baseUrl.substring(0, widget.baseUrl.length - 1)
        : widget.baseUrl;
    final apiBaseUrl = cleanBaseUrl.replaceAll("/games", "");
    
    try {
      await http.get(Uri.parse('$apiBaseUrl/steam/${widget.game.steam}'));
    } catch (e) {
      debugPrint('Steam launch failed: $e');
    }
  }

  Widget _buildQrCode(String qrData, String cleanBaseUrl, {double size = 76}) {
    final isImage = qrData.toLowerCase().endsWith('.png') ||
        qrData.toLowerCase().endsWith('.jpg') ||
        qrData.toLowerCase().endsWith('.jpeg') ||
        qrData.toLowerCase().endsWith('.svg') ||
        qrData.toLowerCase().endsWith('.webp');

    Widget qrWidget;
    if (isImage) {
      final imageUrl = qrData.startsWith('http://') || qrData.startsWith('https://')
          ? qrData
          : (qrData.startsWith('/') ? '$cleanBaseUrl$qrData' : '$cleanBaseUrl/$qrData');
      qrWidget = Image.network(
        imageUrl,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return QrImageView(
            data: qrData,
            version: QrVersions.auto,
            size: size,
            backgroundColor: Colors.white,
          );
        },
      );
    } else {
      qrWidget = QrImageView(
        data: qrData,
        version: QrVersions.auto,
        size: size,
        backgroundColor: Colors.white,
      );
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: qrWidget,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cleanBaseUrl = widget.baseUrl.endsWith('/')
        ? widget.baseUrl.substring(0, widget.baseUrl.length - 1)
        : widget.baseUrl;

    final theme = widget.mode.getTheme(context);

    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: Colors.black, // Ensure surroundings are pure black for full-screen elements
        appBar: widget.mode == GameMode.video
            ? null
            : AppBar(
                toolbarHeight: 64,
                foregroundColor: Colors.white,
                backgroundColor: Colors.black,
                centerTitle: false,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(widget.game.name,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      widget.game.author,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ],
                ),
                actions: [
                  if (_hasDescription && !_showDescription && widget.mode != GameMode.video)
                    IconButton(
                      icon: const Icon(Icons.info_outline),
                      onPressed: () => setState(() => _showDescription = true),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8.0, vertical: 16.0),
                    child: Image.network(
                      "${widget.baseUrl}_thumbs/${widget.mode == GameMode.utas ? 'utas_dark.png' : 'tasgm_logo.png'}",
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
        body: Hero(
          tag: widget.game.name,
          child: Material(
            color: Colors.black, // Ensure details card material has black backdrop for full-screen views
            child: Column(
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: (_showDescription && widget.mode != GameMode.video)
                      ? GestureDetector(
                          onTap: () => setState(() => _showDescription = false),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 8.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: (widget.game.description != null &&
                                          widget.game.description!.isNotEmpty)
                                      ? HtmlWidget(
                                          widget.game.description!,
                                          /*style: const TextStyle(
                                            fontSize: 18,
                                            height: 1.4,
                                          ),*/
                                        )
                                      : const SizedBox.shrink(),
                                ),
                                if (widget.game.qr != null &&
                                    widget.game.qr!.isNotEmpty) ...[
                                  const SizedBox(width: 16),
                                  _buildQrCode(widget.game.qr!, cleanBaseUrl),
                                ],
                              ],
                            ),
                          ),
                        )
                      : const SizedBox(width: double.infinity, height: 0),
                ),
                Expanded(
                  child: SizedBox.expand(
                    child: Stack(
                      children: [
                // Always render the thumbnail as a backdrop.
                // This ensures the recorder has pixels to capture instead of a grey square.
                Positioned.fill(
                  child: ImageFiltered(
                    imageFilter: (widget.game.isVideo || widget.mode == GameMode.video)
                        ? ui.ImageFilter.blur(sigmaX: 0, sigmaY: 0) // Clear for video
                        : ui.ImageFilter.blur(sigmaX: 7.0, sigmaY: 7.0), // Blurred for games
                    child: GameImageThumb(
                      cleanBaseUrl: cleanBaseUrl,
                      gameUrl: widget.game.url,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                if (!widget.game.isVideo && widget.mode != GameMode.video)
                  Positioned.fill(
                    child: Container(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                        SizedBox.expand(
                          child: _isExecuting
                            ? const Center(
                                child: Text(
                                  "Launching...",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            : (_showHtml
                              ? PointerInterceptor(
                                  intercepting: !_showDescription,
                                  child: HtmlElementView(viewType: _viewId),
                                )
                              : Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        widget.game.name,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 24,
                                          shadows: [
                                            Shadow(
                                              offset: Offset(0, 2),
                                              blurRadius: 4,
                                              color: Colors.black54,
                                            ),
                                          ],
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      Text(
                                        widget.game.author,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          shadows: [
                                            Shadow(
                                              offset: Offset(0, 1),
                                              blurRadius: 2,
                                              color: Colors.black54,
                                            ),
                                          ],
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                )),
                        ),
                        if (widget.mode == GameMode.video)
                          Positioned.fill(
                            child: PointerInterceptor(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  if (mounted) {
                                    Navigator.of(context).pop();
                                  }
                                },
                                child: Container(
                                  color: Colors.transparent,
                                ),
                              ),
                            ),
                          ),
                        if (widget.mode == GameMode.video) ...[
                          if (widget.game.showLowerThird)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 32),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),

                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            widget.game.name,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 32,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            widget.game.author,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 20,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (widget.game.qr != null && widget.game.qr!.isNotEmpty) ...[
                                      const SizedBox(width: 24),
                                      _buildQrCode(widget.game.qr!, cleanBaseUrl, size: 100),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          if (widget.game.onBooth)
                            Positioned(
                              top: 0,
                              right: 0,
                              width: 320,
                              height: 320,
                              child: ClipRect(
                                child: Stack(
                                  children: [
                                    Positioned(
                                      top: 80,
                                      right: -80,
                                      child: Transform.rotate(
                                        angle: math.pi / 4,
                                        child: Container(
                                          width: 360,
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFE53935),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black54,
                                                blurRadius: 8,
                                                offset: Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          alignment: Alignment.center,
                                          child: const Text(
                                            'PLAY ON THE BOOTH',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1.4,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
