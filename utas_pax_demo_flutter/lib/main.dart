import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:web/web.dart' as web;
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:path_provider/path_provider.dart';

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
                  onPressed: () {
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) =>
                            GameGridPage(baseUrl: baseUrl, mode: mode),
                        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
                            FadeTransition(opacity: animation, child: child),
                      ),
                    );
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

    final currentBaseUrl = "http://localhost:5001/";//'$protocol://$host:$port/';

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
  final bool isVideo;
  final String? description;

  Game({
    required this.name,
    required this.url,
    required this.author,
    this.execute,
    this.isVideo = false,
    this.description,
  });

  factory Game.fromJson(Map<String, dynamic> json) {
    return Game(
      name: json['name'] as String,
      url: json['url'] as String,
      author: json['author'] as String? ?? 'Unknown',
      execute: json['execute'] as String?,
      isVideo: json['video'] as bool? ?? false,
      description: json['description'] as String?,
    );
  }
}

class GameGridPage extends StatefulWidget {
  final String baseUrl;
  final GameMode mode;
  const GameGridPage({super.key, required this.baseUrl, required this.mode});

  @override
  State<GameGridPage> createState() => _GameGridPageState();
}

class _GameGridPageState extends State<GameGridPage> {
  late Future<List<Game>> _gamesFuture;
  bool _isSequenceRunning = false;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _gamesFuture = _fetchGames();
  }

  Future<void> _recordFrame(Duration simulatedTime) async {
    final boundary = rootRepaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary != null) {
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final tempDir = await getTemporaryDirectory();
        final frameNum = (simulatedTime.inMicroseconds / 16666).round();
        final file = File('${tempDir.path}/frame_$frameNum.png');
        await file.writeAsBytes(byteData.buffer.asUint8List());
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
    // Start with a 5-second delay on the grid at the start
    await Future.delayed(const Duration(seconds: 5));

    int index = 0;
    while (mounted && widget.mode == GameMode.video) {
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
          ),
          transitionDuration: const Duration(milliseconds: 500),
          reverseTransitionDuration: const Duration(milliseconds: 500),
          transitionsBuilder:
              (context, animation, secondaryAnimation, child) => child,
        ),
      );

      index = (index + 1) % games.length;
      // Spend 5 seconds on the grid between videos
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  Future<void> _playSequenceRecorded(List<Game> games) async {
    // Deterministic recording at 60 FPS
    const frameInterval = Duration(microseconds: 16666);
    Duration simulatedTime = Duration.zero;

    // 1. Initial 5 seconds on grid
    for (int i = 0; i < 5 * 60; i++) {
      simulatedTime += frameInterval;
      SchedulerBinding.instance.handleBeginFrame(simulatedTime);
      SchedulerBinding.instance.handleDrawFrame();
      await _recordFrame(simulatedTime);
    }

    int index = 0;
    while (mounted && widget.mode == GameMode.video) {
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
          ),
          transitionDuration: const Duration(milliseconds: 500),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              child,
        ),
      );

      for (int i = 0; i < 30; i++) { // 500ms at 60fps = 30 frames
        simulatedTime += frameInterval;
        SchedulerBinding.instance.handleBeginFrame(simulatedTime);
        SchedulerBinding.instance.handleDrawFrame();
        await _recordFrame(simulatedTime);
      }

      // 3. Record Video Playback (We'd need to know duration, assume 10s for demo)
      // Note: toImage does not capture PlatformViews like video elements.
      for (int i = 0; i < 10 * 60; i++) {
        simulatedTime += frameInterval;
        SchedulerBinding.instance.handleBeginFrame(simulatedTime);
        SchedulerBinding.instance.handleDrawFrame();
        await _recordFrame(simulatedTime);
      }

      // 4. Record Navigation Pop Transition (500ms)
      Navigator.pop(context);
      for (int i = 0; i < 30; i++) {
        simulatedTime += frameInterval;
        SchedulerBinding.instance.handleBeginFrame(simulatedTime);
        SchedulerBinding.instance.handleDrawFrame();
        await _recordFrame(simulatedTime);
      }

      index = (index + 1) % games.length;

      // 5. 5 seconds on grid between videos
      for (int i = 0; i < 5 * 60; i++) {
        simulatedTime += frameInterval;
        SchedulerBinding.instance.handleBeginFrame(simulatedTime);
        SchedulerBinding.instance.handleDrawFrame();
        await _recordFrame(simulatedTime);
      }
      
      // Stop after one loop for safety in this demo
      break; 
    }

    // Compile to MP4
    final tempDir = await getTemporaryDirectory();
    final outputPath = '${tempDir.path}/output.mp4';
    final command = '-framerate 60 -i ${tempDir.path}/frame_%d.png -c:v libx264 -pix_fmt yuv420p -y $outputPath';
    await FFmpegKit.execute(command);
    debugPrint('Recording saved to $outputPath');
  }

  Future<List<Game>> _fetchGames() async {
    final cleanBaseUrl = widget.baseUrl.endsWith('/')
        ? widget.baseUrl.substring(0, widget.baseUrl.length - 1)
        : widget.baseUrl;
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
      return AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_isRecording ? Icons.stop_circle : Icons.fiber_manual_record, color: Colors.red),
            onPressed: () {
              setState(() {
                _isRecording = !_isRecording;
              });
              if (_isRecording && !_isSequenceRunning) {
                _gamesFuture.then((games) => _playSequence(games));
              }
            },
          ),
        ],
      );
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
    return _buildDefaultGrid(context, games, 3);
  }

  Widget _buildTasgmGrid(BuildContext context, List<Game> games) {
    return _buildDefaultGrid(context, games, 2);
  }

  Widget _buildVideoGrid(BuildContext context, List<Game> games) {
    return _buildDefaultGrid(context, games, 4);
  }

  Widget _buildDefaultGrid(BuildContext context, List<Game> games, int crossAxisCount) {
    final appBarHeight = widget.mode == GameMode.video ? 0.0 : 64.0;
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = constraints.maxWidth / crossAxisCount;
        final cellHeight = constraints.maxHeight / 3; // Assume 3 rows for demo
        final aspectRatio = cellWidth / cellHeight;

        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 0,
            mainAxisSpacing: 0,
            childAspectRatio: aspectRatio,
          ),
          itemCount: games.length,
          itemBuilder: (context, index) {
            final game = games[index];
            return GameThumb(game: game, gridPage: widget, cleanBaseUrl: widget.baseUrl);
          },
        );
      }
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
              return const Center(child: Text('No games found', style: const TextStyle(color: Colors.white)));
            }

            return _buildModeContent(context, snapshot.data!);
          },
        ),
      ),
    );
  }
}

class GameThumb extends StatefulWidget {
  const GameThumb({
    super.key,
    required this.game,
    required this.gridPage,
    required this.cleanBaseUrl,
  });

  final Game game;
  final GameGridPage gridPage;
  final String cleanBaseUrl;

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
        final video = web.document.createElement('video') as web.HTMLVideoElement;
        final cleanBaseUrl = widget.cleanBaseUrl.endsWith('/')
            ? widget.cleanBaseUrl.substring(0, widget.cleanBaseUrl.length - 1)
            : widget.cleanBaseUrl;
        video.src = '$cleanBaseUrl/_thumbs${widget.game.url}.mp4';
        video.style.border = 'none';
        video.style.width = '100%';
        video.style.height = '100%';
        video.style.objectFit = 'cover';
        video.autoplay = true;
        video.loop = true;
        video.muted = true;
        video.setAttribute('playsinline', 'true');
        return video;
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
      return Hero(
        tag: widget.game.name,
        child: Material(
          color: const Color(0xFF1E1E1E),
          child: SizedBox.expand(
            child: showVideoPreview
                ? PointerInterceptor(
                    child: HtmlElementView(viewType: _videoViewId),
                  )
                : Image.network(
                    "$cleanBaseUrl/_thumbs${widget.game.url}.png",
                    fit: BoxFit.cover,
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
                        : Image.network(
                            "$cleanBaseUrl/_thumbs${widget.game.url}.png",
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
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
                  opacity: _isHovered ? 1.0 : 0.0,
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
              ],
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

  const GameDetailPage({super.key, required this.game, required this.baseUrl, required this.mode});

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

    _hasDescription = widget.game.description != null && widget.game.description!.isNotEmpty;
    if (_hasDescription && !widget.game.isVideo) {
      _showDescription = true;
    }

    if (widget.game.execute != null) {
      _isExecuting = true;
      _handleExecute();
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
            final video = web.document.createElement('video') as web.HTMLVideoElement;
            video.src = '$cleanBaseUrl/_thumbs${widget.game.url}.mp4';
            video.style.border = 'none';
            video.style.width = '100%';
            video.style.height = '100%';
            video.style.objectFit = 'cover';
            video.autoplay = true;
            video.controls = false;
            video.onEnded.listen((_) {
              if (mounted) Navigator.of(context).pop();
            });
            return video;
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
            child: SizedBox.expand(
              child: Stack(
              children: [

                if (!widget.game.isVideo) ...[
                  Positioned.fill(
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 7.0, sigmaY: 7.0),
                      child: Image.network(
                        "$cleanBaseUrl/_thumbs${widget.game.url}.png",
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                ],


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


                if (_hasDescription && !widget.game.isVideo && widget.mode != GameMode.video) ...[
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    left: 0,
                    right: 0,
                    bottom: _showDescription ? 0 : -MediaQuery.of(context).size.height / 3,
                    height: MediaQuery.of(context).size.height / 3,
                    child: GestureDetector(
                      onTap: () => setState(() => _showDescription = false),
                      child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(24),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.game.name,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  widget.game.description!,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    color: Colors.black87,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ),

                  ),

                  if (!_showDescription && widget.mode != GameMode.video)
                    Positioned(
                      bottom: 20,
                      right: 20,
                      child: FloatingActionButton(
                        mini: true,
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        onPressed: () => setState(() => _showDescription = true),
                        child: const Icon(Icons.info_outline),
                      ),
                    ),

                ],

                if (widget.mode == GameMode.video)
                  Positioned(
                      left:64,
                      right: 0,
                      bottom: 64,
                      height: 200,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.game.name, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                          Text(widget.game.author, style: const TextStyle(fontSize: 20))
                        ]
                      )
                ),
              ],
              )
          ),
          ),
        ),
      ),
    );
  }
}
