import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
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
      ),
    );
  }
}

class GameOption {
  final String name;
  final int cols;
  final bool isVideoMode;
  final bool isTasgmStyle;
  final List<GridItem> items;

  GameOption({
    required this.name,
    required this.cols,
    required this.isVideoMode,
    required this.isTasgmStyle,
    required this.items,
  });

  factory GameOption.fromJson(Map<String, dynamic> json) {
    final rawGames = json['games'] as List? ?? [];
    final parsedItems = rawGames.map<GridItem>((itemJson) {
      final map = itemJson as Map<String, dynamic>;
      if (map.containsKey('games') && map['games'] is List) {
        return GameCompilation.fromJson(map);
      }
      return Game.fromJson(map);
    }).toList();

    final modeStr = (json['mode'] as String?)?.toLowerCase() ?? '';

    return GameOption(
      name: json['name'] as String? ?? 'Unnamed Option',
      cols: (json['cols'] as num?)?.toInt() ?? 4,
      isVideoMode: modeStr == 'video',
      isTasgmStyle: (json['tasgm'] as bool?) ?? false,
      items: parsedItems,
    );
  }

  ThemeData getTheme(BuildContext context) {
    if (isTasgmStyle) {
      return ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange, brightness: Brightness.dark),
        useMaterial3: true,
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
        scaffoldBackgroundColor: const Color(0xFF1A1A1A),
      );
    } else if (isVideoMode) {
      return ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red, brightness: Brightness.dark),
        useMaterial3: true,
        textTheme: GoogleFonts.montserratTextTheme(ThemeData.dark().textTheme),
        scaffoldBackgroundColor: Colors.black,
      );
    } else {
      return ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
        useMaterial3: true,
        textTheme: GoogleFonts.montserratTextTheme(ThemeData.dark().textTheme),
        scaffoldBackgroundColor: Colors.black,
      );
    }
  }
}

enum VideoExecutionMode { live, record, kiosk }

class ModeSelectorPage extends StatefulWidget {
  final String baseUrl;
  const ModeSelectorPage({super.key, required this.baseUrl});

  @override
  State<ModeSelectorPage> createState() => _ModeSelectorPageState();
}

class _ModeSelectorPageState extends State<ModeSelectorPage> {
  late Future<List<GameOption>> _optionsFuture;
  bool _isFullscreen = false;
  JSFunction? _fullscreenListener;

  @override
  void initState() {
    super.initState();
    _optionsFuture = _fetchOptions();
    if (kIsWeb) {
      _isFullscreen = web.document.fullscreenElement != null;
      _fullscreenListener = ((web.Event _) {
        if (mounted) {
          setState(() {
            _isFullscreen = web.document.fullscreenElement != null;
          });
        }
      }).toJS;
      web.document.addEventListener('fullscreenchange', _fullscreenListener);
    }
  }

  @override
  void dispose() {
    if (kIsWeb && _fullscreenListener != null) {
      web.document.removeEventListener('fullscreenchange', _fullscreenListener);
    }
    super.dispose();
  }

  void _toggleFullscreen() {
    if (kIsWeb) {
      if (web.document.fullscreenElement != null) {
        web.document.exitFullscreen();
      } else {
        web.document.documentElement?.requestFullscreen();
      }
    } else {
      setState(() {
        _isFullscreen = !_isFullscreen;
        if (_isFullscreen) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        } else {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        }
      });
    }
  }

  Future<List<GameOption>> _fetchOptions() async {
    final cleanBaseUrl = widget.baseUrl.endsWith('/')
        ? widget.baseUrl.substring(0, widget.baseUrl.length - 1)
        : widget.baseUrl;

    final indexResponse = await http.get(Uri.parse('$cleanBaseUrl/index'));
    if (indexResponse.statusCode == 200) {
      final dynamic decodedIndex = json.decode(indexResponse.body);
      List<GameOption> options = [];

      if (decodedIndex is List) {
        for (final item in decodedIndex) {
          if (item is Map<String, dynamic>) {
            options.add(GameOption.fromJson(item));
          } else if (item is String && item.toLowerCase().endsWith('.json')) {
            try {
              final fileResponse = await http.get(Uri.parse('$cleanBaseUrl/$item'));
              if (fileResponse.statusCode == 200) {
                final fileData = json.decode(fileResponse.body) as Map<String, dynamic>;
                options.add(GameOption.fromJson(fileData));
              }
            } catch (e) {
              debugPrint('Error fetching json configuration $item: $e');
            }
          }
        }
      } else if (decodedIndex is Map<String, dynamic>) {
        if (decodedIndex.containsKey('files')) {
          final files = (decodedIndex['files'] as List).map((e) => e.toString()).toList();
          for (final file in files) {
            try {
              final fileResponse = await http.get(Uri.parse('$cleanBaseUrl/$file'));
              if (fileResponse.statusCode == 200) {
                final fileData = json.decode(fileResponse.body) as Map<String, dynamic>;
                options.add(GameOption.fromJson(fileData));
              }
            } catch (e) {
              debugPrint('Error fetching json configuration $file: $e');
            }
          }
        } else {
          options.add(GameOption.fromJson(decodedIndex));
        }
      }

      return options;
    } else {
      throw Exception('Failed to fetch index endpoint');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Select Mode'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
            tooltip: _isFullscreen ? 'Exit Fullscreen' : 'Fullscreen',
            onPressed: _toggleFullscreen,
          ),
        ],
      ),
      body: FutureBuilder<List<GameOption>>(
        future: _optionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(
              child: Text('Error loading options: ${snapshot.error}', style: const TextStyle(color: Colors.white)),
            );
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No JSON options found', style: TextStyle(color: Colors.white)));
          }

          final options = snapshot.data!;
          return Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: options.map((option) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: SizedBox(
                      width: 340,
                      height: 80,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: option.isVideoMode ? Colors.teal.shade800 : Colors.deepPurple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          if (option.isVideoMode) {
                            final VideoExecutionMode? execMode = await showDialog<VideoExecutionMode>(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: const Text('Video Mode Configuration'),
                                  content: const Text('Select how you would like to run this video grid sequence:'),
                                  actionsAlignment: MainAxisAlignment.center,
                                  actions: <Widget>[
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.teal,
                                            foregroundColor: Colors.white,
                                          ),
                                          child: const Text('Kiosk Mode (Interactive Manual Play)'),
                                          onPressed: () => Navigator.of(context).pop(VideoExecutionMode.kiosk),
                                        ),
                                        const SizedBox(height: 8),
                                        const SizedBox(height: 4),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.deepPurple,
                                            foregroundColor: Colors.white,
                                          ),
                                          child: const Text('Live Playback Only'),
                                          onPressed: () => Navigator.of(context).pop(VideoExecutionMode.live),
                                        ),
                                        /*
                                        const SizedBox(height: 4),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.deepPurple,
                                            foregroundColor: Colors.white,
                                          ),
                                          child: const Text('Record to MP4'),
                                          onPressed: () => Navigator.of(context).pop(VideoExecutionMode.record),
                                        ),*/
                                      ],
                                    ),
                                  ],
                                );
                              },
                            );
                            if (execMode == null) return;

                            if (context.mounted) {
                              Navigator.push(
                                context,
                                PageRouteBuilder(
                                  pageBuilder: (context, animation, secondaryAnimation) => GameGridPage(
                                    baseUrl: widget.baseUrl,
                                    option: option,
                                    startWithRecording: execMode == VideoExecutionMode.record,
                                    isKioskMode: execMode == VideoExecutionMode.kiosk,
                                  ),
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
                                    GameGridPage(baseUrl: widget.baseUrl, option: option),
                                transitionsBuilder: (context, animation, secondaryAnimation, child) =>
                                    FadeTransition(opacity: animation, child: child),
                              ),
                            );
                          }
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              option.isVideoMode ? Icons.ondemand_video : Icons.sports_esports,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                option.name,
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          );
        },
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
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();

    final uri = Uri.base;
    final protocol = uri.scheme.isEmpty ? 'http' : uri.scheme;
    final host = uri.host.isEmpty ? 'localhost' : uri.host;
    final port = uri.port == 0 ? 5999 : uri.port;

    final currentBaseUrl = kDebugMode ? "http://localhost:5001/" : '$protocol://$host:$port/';

    _controller = TextEditingController(text: currentBaseUrl);

    if (uri.host.isNotEmpty || uri.port != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _saveAndNavigate();
      });
    }
  }

  void _saveAndNavigate() {
    final url = "${_controller.text.trim()}games/";
    if (url.isNotEmpty) {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => ModeSelectorPage(baseUrl: url),
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

abstract class GridItem {
  String get name;
  String get displayUrl;
}

class Game extends GridItem {
  @override
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
  final bool tasgm;
  final bool stillThumbnail;
  final double aspectRatio;

  @override
  String get displayUrl => url;

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
    this.tasgm = false,
    this.stillThumbnail = false,
    this.aspectRatio = 16 / 9,
  });

  factory Game.fromJson(Map<String, dynamic> json) {
    bool parseBool(dynamic val, bool defaultValue) {
      if (val == null) return defaultValue;
      if (val is bool) return val;
      if (val is num) return val != 0;
      if (val is String) {
        final lower = val.toLowerCase().trim();
        if (lower == 'true' || lower == '1') return true;
        if (lower == 'false' || lower == '0') return false;
      }
      return defaultValue;
    }

    double parseAspectRatio(dynamic val, {double defaultValue = 16 / 9}) {
      if (val == null) return defaultValue;
      if (val is num) return val.toDouble();
      if (val is String) {
        final str = val.trim();
        if (str.contains(':')) {
          final parts = str.split(':');
          if (parts.length == 2) {
            final w = double.tryParse(parts[0].trim());
            final h = double.tryParse(parts[1].trim());
            if (w != null && h != null && h != 0) return w / h;
          }
        } else if (str.contains('/')) {
          final parts = str.split('/');
          if (parts.length == 2) {
            final w = double.tryParse(parts[0].trim());
            final h = double.tryParse(parts[1].trim());
            if (w != null && h != null && h != 0) return w / h;
          }
        } else if (str.contains('x')) {
          final parts = str.split('x');
          if (parts.length == 2) {
            final w = double.tryParse(parts[0].trim());
            final h = double.tryParse(parts[1].trim());
            if (w != null && h != null && h != 0) return w / h;
          }
        } else {
          final parsed = double.tryParse(str);
          if (parsed != null && parsed > 0) return parsed;
        }
      }
      return defaultValue;
    }

    final rawDescription = json['description'] as String?;
    final parsedDescription = rawDescription
        ?.replaceAll('[', '<span style="background-color:#3a3a3c; color:#ffffff; border:1px solid #666666; border-radius:4px; padding:2px 6px; display:inline-block">')
        .replaceAll(']', '</span>')
        .replaceAll('\n', '<br>');

    return Game(
      name: json['name'] as String? ?? 'Untitled Game',
      url: json['url'] as String? ?? '',
      author: json['author'] as String? ?? 'Unknown',
      execute: json['execute'] as String?,
      steam: json['steam'] as String?,
      isVideo: parseBool(json['video'], false),
      description: parsedDescription,
      qr: json['qr'] as String?,
      onBooth: parseBool(json['onBooth'] ?? json['on_booth'], false),
      showLowerThird: parseBool(json['showLowerThird'] ?? json['show_lower_third'], true),
      tasgm: parseBool(json['tasgm'], false),
      stillThumbnail: parseBool(json['still_thumbnail'] ?? json['stillThumbnail'], false),
      aspectRatio: parseAspectRatio(json['aspectRatio'] ?? json['aspect_ratio']),
    );
  }

  TextStyle getTitleStyle({required double fontSize, required bool forceTasgm}) {
    final useTasgm = forceTasgm || tasgm;
    if (useTasgm) {
      return GoogleFonts.poppins(
        color: Colors.white,
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
      );
    }
    return GoogleFonts.montserrat(
      color: Colors.white,
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
    );
  }

  TextStyle getAuthorStyle({required double fontSize, required bool forceTasgm}) {
    final useTasgm = forceTasgm || tasgm;
    if (useTasgm) {
      return GoogleFonts.poppins(
        color: Colors.white70,
        fontSize: fontSize,
      );
    }
    return GoogleFonts.montserrat(
      color: Colors.white70,
      fontSize: fontSize,
    );
  }

  TextStyle getRibbonStyle({required double fontSize, required bool forceTasgm}) {
    final useTasgm = forceTasgm || tasgm;
    if (useTasgm) {
      return GoogleFonts.poppins(
        color: Colors.white,
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.4,
      );
    }
    return GoogleFonts.montserrat(
      color: Colors.white,
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
      letterSpacing: 1.4,
    );
  }
}

class GameCompilation extends GridItem {
  @override
  final String name;
  final List<Game> games;

  GameCompilation({required this.name, required this.games});

  @override
  String get displayUrl => games.isNotEmpty ? games.first.url : '';

  factory GameCompilation.fromJson(Map<String, dynamic> json) {
    final rawGames = json['games'] as List? ?? json['game'] as List? ?? [];
    final parsedGames = rawGames.map((g) => Game.fromJson(g as Map<String, dynamic>)).toList();
    return GameCompilation(
      name: json['name'] as String? ?? 'Compilation',
      games: parsedGames,
    );
  }
}

class GameGridPage extends StatefulWidget {
  final String baseUrl;
  final GameOption option;
  final bool startWithRecording;
  final bool isKioskMode;
  final double gridSpacing;

  const GameGridPage({
    super.key,
    required this.baseUrl,
    required this.option,
    this.startWithRecording = false,
    this.isKioskMode = false,
    this.gridSpacing = 8.0,
  });

  @override
  State<GameGridPage> createState() => _GameGridPageState();
}

class _GameGridPageState extends State<GameGridPage> {
  bool _isSequenceRunning = false;
  bool _isRecording = false;
  int _gridCycle = 0;
  final List<Future<void>> _pendingFrameUploads = [];

  Completer<void>? _gridWaitCompleter;
  Completer<void>? _fullscreenWaitCompleter;
  int? _nextSequenceIndex;
  int? _expandedVideoIndex;
  Game? _currentActiveGame;
  int? _topTileIndex;
  Timer? _topTileTimer;

  final Map<int, GlobalKey<_GameThumbState>> _thumbKeys = {};
  final Map<int, GlobalKey> _tileGlobalKeys = {};

  GlobalKey<_GameThumbState> _getThumbKey(int index) {
    return _thumbKeys.putIfAbsent(index, () => GlobalKey<_GameThumbState>());
  }

  GlobalKey _getTileGlobalKey(int index) {
    return _tileGlobalKeys.putIfAbsent(index, () => GlobalKey());
  }

  void _alignThumb(int index, double leadTime) {
    _getThumbKey(index).currentState?.alignVideoToLoopStart(leadTime);
  }

  void _expandVideo(int index, Game activeGame) {
    if (mounted) {
      _topTileTimer?.cancel();
      setState(() {
        _expandedVideoIndex = index;
        _currentActiveGame = activeGame;
        _topTileIndex = index;
      });
    }
  }

  void _collapseVideo() {
    if (mounted) {
      if (_expandedVideoIndex != null) {
        _getThumbKey(_expandedVideoIndex!).currentState?.resetThumbnailIfStill();
      }
      setState(() {
        _expandedVideoIndex = null;
      });
      _topTileTimer?.cancel();
      _topTileTimer = Timer(const Duration(milliseconds: 1000), () {
        if (mounted) {
          setState(() {
            _topTileIndex = null;
            _currentActiveGame = null;
            _gridCycle++;
          });
        }
      });
    }
  }

  void _skipFullscreenWait() {
    if (_fullscreenWaitCompleter != null && !_fullscreenWaitCompleter!.isCompleted) {
      _fullscreenWaitCompleter!.complete();
    }
  }

  Future<void> _waitOnFullscreenWithVideoCompletion(
      int index,
      Future<double> durationFuture,
      Stream<void>? endedStream,
      ) async {
    _fullscreenWaitCompleter = Completer<void>();

    final double dur = await durationFuture;
    final fallbackDuration = (dur > 0 && !dur.isNaN)
        ? Duration(milliseconds: (dur * 1000).round() + 200)
        : const Duration(seconds: 15);

    StreamSubscription? endedSub;
    if (endedStream != null) {
      endedSub = endedStream.listen((_) {
        _skipFullscreenWait();
      });
    }

    await Future.any([
      Future.delayed(fallbackDuration),
      _fullscreenWaitCompleter!.future,
    ]);

    await endedSub?.cancel();
    _fullscreenWaitCompleter = null;
  }

  void _skipGridWait([int? targetIndex]) {
    if (!widget.option.isVideoMode || widget.isKioskMode) return;
    if (_expandedVideoIndex != null) {
      _skipFullscreenWait();
      return;
    }
    if (targetIndex != null) {
      _nextSequenceIndex = targetIndex;
      _alignThumb(targetIndex, 0.5);
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
    HardwareKeyboard.instance.addHandler(_onKeyEvent);

    if (widget.option.isVideoMode && !widget.isKioskMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _playSequence(widget.option.items);
      });
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    super.dispose();
  }

  bool _onKeyEvent(KeyEvent event) {
    if (!widget.option.isVideoMode || widget.isKioskMode) return false;

    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space) {
      if (_expandedVideoIndex != null) {
        _skipFullscreenWait();
      } else {
        _skipGridWait();
      }
      return true;
    }
    return false;
  }

  Future<void> _recordFrame(Duration simulatedTime, String apiBaseUrl) async {
    final boundary = rootRepaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary != null) {
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final frameNum = (simulatedTime.inMicroseconds / 16666).round();
        final bytes = byteData.buffer.asUint8List();

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

        if (_pendingFrameUploads.length > 30) {
          final oldest = _pendingFrameUploads.removeAt(0);
          await oldest.catchError((_) {});
        }
      }
    }
  }

  Future<void> _playSequence(List<GridItem> items) async {
    if (_isSequenceRunning) return;
    _isSequenceRunning = true;

    if (_isRecording) {
      await _playSequenceRecorded(items);
    } else {
      await _playSequenceLive(items);
    }

    _isSequenceRunning = false;
  }

  Future<void> _playSequenceLive(List<GridItem> items) async {
    await Future.delayed(const Duration(seconds: 2));

    _alignThumb(0, 5.5);
    await _waitOnGrid(const Duration(seconds: 5));

    int index = 0;
    while (mounted && widget.option.isVideoMode) {
      if (_nextSequenceIndex != null) {
        index = _nextSequenceIndex!;
        _nextSequenceIndex = null;
      }

      if (!mounted) break;

      final item = items[index];

      if (item is Game) {
        final thumbState = _getThumbKey(index).currentState;
        thumbState?.playFromStart(item);
        _expandVideo(index, item);

        final durFuture = thumbState?.getValidDuration() ?? Future.value(15.0);
        final endedStream = thumbState?.onVideoEnded;

        await _waitOnFullscreenWithVideoCompletion(index, durFuture, endedStream);
        _collapseVideo();
      } else if (item is GameCompilation) {
        for (int subIndex = 0; subIndex < item.games.length; subIndex++) {
          if (!mounted) break;
          final subGame = item.games[subIndex];

          final thumbState = _getThumbKey(index).currentState;
          thumbState?.loadAndPlaySubGame(subGame);
          _expandVideo(index, subGame);

          final durFuture = thumbState?.getValidDuration() ?? Future.value(15.0);
          final endedStream = thumbState?.onVideoEnded;

          await _waitOnFullscreenWithVideoCompletion(index, durFuture, endedStream);

          if (_nextSequenceIndex != null) {
            break;
          }
        }
        _collapseVideo();
      }

      if (_nextSequenceIndex != null) {
        index = _nextSequenceIndex!;
        _nextSequenceIndex = null;
      } else {
        index = (index + 1) % items.length;
      }

      _alignThumb(index, 5.5);
      await _waitOnGrid(const Duration(seconds: 5));
    }
  }

  Future<void> _playSequenceRecorded(List<GridItem> items) async {
    final cleanBaseUrl = widget.baseUrl.endsWith('/')
        ? widget.baseUrl.substring(0, widget.baseUrl.length - 1)
        : widget.baseUrl;
    final apiBaseUrl = cleanBaseUrl.replaceAll("/games", "");

    await Future.delayed(const Duration(seconds: 2));

    const frameInterval = Duration(microseconds: 16666);
    Duration simulatedTime = SchedulerBinding.instance.currentSystemFrameTimeStamp;

    for (int i = 0; i < 5 * 60; i++) {
      if (!_isRecording) break;
      simulatedTime += frameInterval;

      await Future.delayed(Duration.zero);

      SchedulerBinding.instance.handleBeginFrame(simulatedTime);
      SchedulerBinding.instance.handleDrawFrame();
      await WidgetsBinding.instance.endOfFrame;
      await _recordFrame(simulatedTime, apiBaseUrl);
    }

    int index = 0;
    while (mounted && widget.option.isVideoMode && _isRecording) {
      final item = items[index];
      final Game firstGame = item is Game ? item : (item as GameCompilation).games.first;
      if (!mounted) break;

      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => GameDetailPage(
            game: firstGame,
            baseUrl: widget.baseUrl,
            option: widget.option,
            isRecording: _isRecording,
          ),
          transitionDuration: const Duration(milliseconds: 500),
          transitionsBuilder: (context, animation, secondaryAnimation, child) => child,
        ),
      );

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

      if (mounted) Navigator.pop(context);

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

      index = (index + 1) % items.length;

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

    if (_pendingFrameUploads.isNotEmpty) {
      await Future.wait(_pendingFrameUploads);
      _pendingFrameUploads.clear();
    }

    try {
      await http.post(Uri.parse('$apiBaseUrl/captureEnd'));
    } catch (e) {
      debugPrint('Failed to trigger video compilation: $e');
    }
  }

  PreferredSizeWidget? _buildAppBar() {
    if (widget.option.isVideoMode) {
      return null;
    }

    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: 64,
      foregroundColor: Colors.white,
      backgroundColor: widget.option.isTasgmStyle ? const Color(0xFF3bd9e5) : Colors.black,
      centerTitle: false,
      title: Text(
        widget.option.isTasgmStyle ? "Tasmanian Game Makers" : "Study Games at UTAS",
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
          child: Image.network(
            "${widget.baseUrl}_thumbs/${widget.option.isTasgmStyle ? 'tasgm_logo.png' : 'utas_dark.png'}",
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _buildModeContent(BuildContext context, List<GridItem> items) {
    if (widget.option.isVideoMode) {
      return _buildVideoGrid(context, items);
    }
    return _buildDefaultGrid(context, items, widget.option.cols);
  }

  Widget _buildVideoGrid(BuildContext context, List<GridItem> items) {
    final spacing = widget.gridSpacing;
    final crossAxisCount = widget.option.cols;

    return Container(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth - (crossAxisCount + 1) * spacing;
          final cellWidth = availableWidth / crossAxisCount;

          final rowCount = (items.length / crossAxisCount).ceil();
          final effectiveRows = rowCount < crossAxisCount ? crossAxisCount : rowCount;
          final availableHeight = constraints.maxHeight - (effectiveRows + 1) * spacing;
          final cellHeight = availableHeight / effectiveRows;

          List<Widget> tiles = [];

          for (int i = 0; i < items.length; i++) {
            final left = spacing + (i % crossAxisCount) * (cellWidth + spacing);
            final top = spacing + (i ~/ crossAxisCount) * (cellHeight + spacing);
            tiles.add(
              Positioned(
                key: Key('grid-placeholder-$i'),
                left: left,
                top: top,
                width: cellWidth,
                height: cellHeight,
                child: Material(
                  color: const Color(0xFF1E1E1E),
                  child: ClipRect(
                    child: GameImageThumb(
                      cleanBaseUrl: widget.baseUrl,
                      gameUrl: items[i].displayUrl,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            );
          }

          for (int i = 0; i < items.length; i++) {
            if (i != _topTileIndex) {
              tiles.add(
                _buildVideoTile(
                  index: i,
                  item: items[i],
                  isExpanded: (_expandedVideoIndex == i),
                  cellLeft: spacing + (i % crossAxisCount) * (cellWidth + spacing),
                  cellTop: spacing + (i ~/ crossAxisCount) * (cellHeight + spacing),
                  cellWidth: cellWidth,
                  cellHeight: cellHeight,
                  screenWidth: constraints.maxWidth,
                  screenHeight: constraints.maxHeight,
                ),
              );
            }
          }

          if (_topTileIndex != null && _topTileIndex! < items.length) {
            final i = _topTileIndex!;
            tiles.add(
              _buildVideoTile(
                index: i,
                item: items[i],
                isExpanded: (_expandedVideoIndex == i),
                cellLeft: spacing + (i % crossAxisCount) * (cellWidth + spacing),
                cellTop: spacing + (i ~/ crossAxisCount) * (cellHeight + spacing),
                cellWidth: cellWidth,
                cellHeight: cellHeight,
                screenWidth: constraints.maxWidth,
                screenHeight: constraints.maxHeight,
              ),
            );
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_expandedVideoIndex != null) {
                _skipFullscreenWait();
              } else {
                _skipGridWait();
              }
            },
            child: Stack(
              children: tiles,
            ),
          );
        },
      ),
    );
  }

  void _onKioskTileClick(int index, GridItem item) async {
    if (_expandedVideoIndex != null) {
      _collapseVideo();
      return;
    }

    if (item is Game) {
      final thumbState = _getThumbKey(index).currentState;
      thumbState?.playFromStart(item);
      _expandVideo(index, item);

      final durFuture = thumbState?.getValidDuration() ?? Future.value(15.0);
      final endedStream = thumbState?.onVideoEnded;

      await _waitOnFullscreenWithVideoCompletion(index, durFuture, endedStream);
      _collapseVideo();
    } else if (item is GameCompilation) {
      for (int subIndex = 0; subIndex < item.games.length; subIndex++) {
        if (!mounted) break;
        final subGame = item.games[subIndex];

        final thumbState = _getThumbKey(index).currentState;
        thumbState?.loadAndPlaySubGame(subGame);
        _expandVideo(index, subGame);

        final durFuture = thumbState?.getValidDuration() ?? Future.value(15.0);
        final endedStream = thumbState?.onVideoEnded;

        await _waitOnFullscreenWithVideoCompletion(index, durFuture, endedStream);
      }
      _collapseVideo();
    }
  }

  Widget _buildVideoTile({
    required int index,
    required GridItem item,
    required bool isExpanded,
    required double cellLeft,
    required double cellTop,
    required double cellWidth,
    required double cellHeight,
    required double screenWidth,
    required double screenHeight,
  }) {
    final cleanBaseUrl = widget.baseUrl.endsWith('/')
        ? widget.baseUrl.substring(0, widget.baseUrl.length - 1)
        : widget.baseUrl;

    final activeGame = (_currentActiveGame != null && (_expandedVideoIndex == index || _topTileIndex == index))
        ? _currentActiveGame!
        : (item is Game ? item : (item as GameCompilation).games.first);

    final useTasgmColor = activeGame.tasgm || widget.option.isTasgmStyle;
    final progressColor = useTasgmColor ? const Color(0xFF3BD9E5) : const Color(0xFFE53935);

    return VideoTileWidget(
      key: _getTileGlobalKey(index),
      index: index,
      item: item,
      isExpanded: isExpanded,
      cellLeft: cellLeft,
      cellTop: cellTop,
      cellWidth: cellWidth,
      cellHeight: cellHeight,
      screenWidth: screenWidth,
      screenHeight: screenHeight,
      onTap: () {
        if (widget.isKioskMode) {
          _onKioskTileClick(index, item);
        } else {
          if (isExpanded) {
            _skipFullscreenWait();
          } else {
            _skipGridWait(index);
          }
        }
      },
      progressBar: ValueListenableBuilder<double>(
        key: ValueKey('progress-${activeGame.name}'),
        valueListenable: _getThumbKey(index).currentState?.playbackProgressNotifier ?? ValueNotifier(0.0),
        builder: (context, progress, child) {
          return Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 10,
            child: Container(
              color: Colors.transparent,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: progress.clamp(0.0, 1.0),
                heightFactor: 1.0,
                child: Container(
                  color: progressColor.withValues(alpha: 0.5),
                ),
              ),
            ),
          );
        },
      ),
      lowerThird: activeGame.showLowerThird
          ? Positioned(
        key: ValueKey('lower-third-${activeGame.name}'),
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
                      activeGame.name,
                      style: activeGame.getTitleStyle(
                        fontSize: 32,
                        forceTasgm: widget.option.isTasgmStyle,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      activeGame.author,
                      style: activeGame.getAuthorStyle(
                        fontSize: 20,
                        forceTasgm: widget.option.isTasgmStyle,
                      ),
                    ),
                  ],
                ),
              ),
              if (activeGame.qr != null && activeGame.qr!.isNotEmpty) ...[
                const SizedBox(width: 24),
                _buildQrCode(activeGame.qr!, cleanBaseUrl, size: 100),
              ],
            ],
          ),
        ),
      )
          : const SizedBox.shrink(),
      boothRibbon: activeGame.onBooth
          ? Positioned(
        key: ValueKey('booth-ribbon-${activeGame.name}'),
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
                    child: Text(
                      'PLAY ON THE BOOTH',
                      style: activeGame.getRibbonStyle(
                        fontSize: 18,
                        forceTasgm: widget.option.isTasgmStyle,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      )
          : const SizedBox.shrink(),
      child: GameThumb(
        key: _getThumbKey(index),
        item: item,
        gridPage: widget,
        cleanBaseUrl: widget.baseUrl,
        gridCycle: _gridCycle,
        isTileActive: (_expandedVideoIndex == index || _topTileIndex == index),
      ),
    );
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

  Widget _buildDefaultGrid(BuildContext context, List<GridItem> items, int crossAxisCount) {
    final spacing = widget.gridSpacing;

    return Container(
      color: Colors.black,
      padding: EdgeInsets.all(spacing),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth - (crossAxisCount - 1) * spacing;
          final cellWidth = availableWidth / crossAxisCount;

          final rowCount = (items.length / crossAxisCount).ceil();
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
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return GameThumb(
                key: _getThumbKey(index),
                item: item,
                gridPage: widget,
                cleanBaseUrl: widget.baseUrl,
                gridCycle: _gridCycle,
                isTileActive: (_expandedVideoIndex == index || _topTileIndex == index),
                onTap: (widget.option.isVideoMode && !widget.isKioskMode)
                    ? () => _skipGridWait(index)
                    : null,
              );
            },
          );

          if (widget.option.isVideoMode && !widget.isKioskMode) {
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
    final theme = widget.option.getTheme(context);
    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: _buildAppBar(),
        body: widget.option.items.isEmpty
            ? const Center(child: Text('No games found', style: TextStyle(color: Colors.white)))
            : _buildModeContent(context, widget.option.items),
      ),
    );
  }
}

class VideoTileWidget extends StatefulWidget {
  final int index;
  final GridItem item;
  final bool isExpanded;
  final double cellLeft;
  final double cellTop;
  final double cellWidth;
  final double cellHeight;
  final double screenWidth;
  final double screenHeight;
  final VoidCallback onTap;
  final Widget child;
  final Widget lowerThird;
  final Widget boothRibbon;
  final Widget progressBar;

  const VideoTileWidget({
    super.key,
    required this.index,
    required this.item,
    required this.isExpanded,
    required this.cellLeft,
    required this.cellTop,
    required this.cellWidth,
    required this.cellHeight,
    required this.screenWidth,
    required this.screenHeight,
    required this.onTap,
    required this.child,
    required this.lowerThird,
    required this.boothRibbon,
    required this.progressBar,
  });

  @override
  State<VideoTileWidget> createState() => _VideoTileWidgetState();
}

class _VideoTileWidgetState extends State<VideoTileWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    if (widget.isExpanded) {
      _controller.forward(from: 1.0);
    }

    _controller.addStatusListener((status) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(VideoTileWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded != oldWidget.isExpanded) {
      if (widget.isExpanded) {
        _controller.forward(from: 0.0);
      } else {
        _controller.reverse(from: 1.0);
      }
    } else if (widget.isExpanded) {
      if (_controller.value < 1.0 && !_controller.isAnimating) {
        _controller.forward(from: 1.0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final progress = _animation.value;
        final left = ui.lerpDouble(widget.cellLeft, 0, progress)!;
        final top = ui.lerpDouble(widget.cellTop, 0, progress)!;
        final width = ui.lerpDouble(widget.cellWidth, widget.screenWidth, progress)!;
        final height = ui.lerpDouble(widget.cellHeight, widget.screenHeight, progress)!;

        final overlayOpacity = (progress - 0.3).clamp(0.0, 0.7) / 0.7;

        return Positioned(
          left: left,
          top: top,
          width: width,
          height: height,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: ClipRect(
              child: Stack(
                children: [
                  Positioned.fill(child: widget.child),
                  if (overlayOpacity > 0)
                    Opacity(
                      opacity: overlayOpacity,
                      child: PointerInterceptor(
                        intercepting: false,
                        child: IgnorePointer(
                          child: Stack(
                            children: [
                              widget.lowerThird,
                              widget.boothRibbon,
                              widget.progressBar,
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
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
    required this.item,
    required this.gridPage,
    required this.cleanBaseUrl,
    this.onTap,
    this.gridCycle = 0,
    this.isTileActive = false,
  });

  final GridItem item;
  final GameGridPage gridPage;
  final String cleanBaseUrl;
  final VoidCallback? onTap;
  final int gridCycle;
  final bool isTileActive;

  @override
  State<GameThumb> createState() => _GameThumbState();
}

class _GameThumbState extends State<GameThumb> with TickerProviderStateMixin {
  bool _isHovered = false;
  bool _useVideo = false;
  bool _revealVideo = false;
  Timer? _randomRevealTimer;
  late String _videoViewId;
  web.HTMLVideoElement? _videoFg;
  web.HTMLVideoElement? _videoBg;
  double? _pendingLeadTime;

  final ValueNotifier<double> playbackProgressNotifier = ValueNotifier<double>(0.0);
  Ticker? _progressTicker;

  final StreamController<void> _videoEndedController = StreamController<void>.broadcast();
  Stream<void> get onVideoEnded => _videoEndedController.stream;

  double? get videoDuration => _videoFg?.duration;

  void _scheduleRandomReveal() {
    _randomRevealTimer?.cancel();
    if (!widget.gridPage.option.isVideoMode) {
      _revealVideo = true;
      return;
    }

    _revealVideo = false;
    final randomMs = 300 + math.Random().nextInt(2900);
    _randomRevealTimer = Timer(Duration(milliseconds: randomMs), () {
      if (mounted) {
        setState(() {
          _revealVideo = true;
        });
      }
    });
  }

  void resetThumbnailIfStill() {
    final primaryGame = widget.item is Game ? (widget.item as Game) : (widget.item as GameCompilation).games.first;
    if (primaryGame.stillThumbnail) {
      if (mounted) {
        setState(() {
          _useVideo = false;
        });
      }
      if (_videoFg != null) {
        _videoFg!.pause();
        _videoFg!.currentTime = 0.0;
      }
      if (_videoBg != null) {
        _videoBg!.pause();
        _videoBg!.currentTime = 0.0;
      }
    }
  }

  Future<double> getValidDuration() async {
    if (_videoFg == null) {
      _ensurePlatformViewRegistered();
    }
    final d = _videoFg?.duration;
    if (d != null && d > 0 && !d.isNaN) {
      return d;
    }

    final completer = Completer<double>();
    StreamSubscription? subMeta;
    StreamSubscription? subChange;

    void check() {
      final cd = _videoFg?.duration;
      if (cd != null && cd > 0 && !cd.isNaN && !completer.isCompleted) {
        completer.complete(cd);
      }
    }

    if (_videoFg != null) {
      subMeta = _videoFg!.onLoadedMetadata.listen((_) => check());
      subChange = _videoFg!.onDurationChange.listen((_) => check());
      check();
    }

    return completer.future.timeout(const Duration(seconds: 4), onTimeout: () => 15.0).whenComplete(() {
      subMeta?.cancel();
      subChange?.cancel();
    });
  }

  void alignVideoToLoopStart(double leadTimeInSeconds) {
    if (widget.gridPage.isKioskMode) return;
    _pendingLeadTime = leadTimeInSeconds;
    _applyLeadTime();
  }

  void playFromStart(Game game) {
    if (!_useVideo) {
      setState(() {
        _useVideo = true;
      });
    }
    _ensurePlatformViewRegistered();
    loadAndPlaySubGame(game);
  }

  void loadAndPlaySubGame(Game subGame) {
    final cleanBaseUrl = widget.cleanBaseUrl.endsWith('/')
        ? widget.cleanBaseUrl.substring(0, widget.cleanBaseUrl.length - 1)
        : widget.cleanBaseUrl;
    final videoUrl = '$cleanBaseUrl/_thumbs${subGame.url}.mp4';

    if (_videoFg != null && _videoBg != null) {
      _videoFg!.src = videoUrl;
      _videoBg!.src = videoUrl;
      _videoFg!.currentTime = 0.0;
      _videoBg!.currentTime = 0.0;
      playbackProgressNotifier.value = 0.0;
      _videoFg!.play();
      _videoBg!.play();
    }
  }

  void _applyLeadTime() {
    if (_pendingLeadTime == null || _videoFg == null) return;
    if (widget.gridPage.isKioskMode) {
      _pendingLeadTime = null;
      return;
    }
    try {
      final d = _videoFg!.duration;
      if (d > 0 && !d.isNaN) {
        double startTime = d - _pendingLeadTime!;
        while (startTime < 0) {
          startTime += d;
        }
        _videoFg!.currentTime = startTime;
        if (_videoBg != null) {
          _videoBg!.currentTime = startTime;
        }
        _pendingLeadTime = null;
      }
    } catch (_) {}
  }

  void resetVideoToStart() {
    if (_videoFg != null && _videoBg != null) {
      _videoFg!.currentTime = 0.0;
      _videoBg!.currentTime = 0.0;
    }
    playbackProgressNotifier.value = 0.0;
  }

  void _ensurePlatformViewRegistered() {
    ui_web.platformViewRegistry.registerViewFactory(
      _videoViewId,
          (int id) {
        final cleanBaseUrl = widget.cleanBaseUrl.endsWith('/')
            ? widget.cleanBaseUrl.substring(0, widget.cleanBaseUrl.length - 1)
            : widget.cleanBaseUrl;
        final videoUrl = '$cleanBaseUrl/_thumbs${widget.item.displayUrl}.mp4';

        final container = web.document.createElement('div') as web.HTMLDivElement;
        container.style.position = 'relative';
        container.style.width = '100%';
        container.style.height = '100%';
        container.style.overflow = 'hidden';
        container.style.backgroundColor = 'black';

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
        videoBg.autoplay = !widget.gridPage.isKioskMode;
        videoBg.loop = true;
        videoBg.muted = true;
        videoBg.setAttribute('playsinline', 'true');

        final videoFg = web.document.createElement('video') as web.HTMLVideoElement;
        videoFg.src = videoUrl;
        videoFg.style.position = 'absolute';
        videoFg.style.top = '0';
        videoFg.style.left = '0';
        videoFg.style.width = '100%';
        videoFg.style.height = '100%';
        videoFg.style.objectFit = 'contain';
        videoFg.autoplay = !widget.gridPage.isKioskMode;
        videoFg.loop = true;
        videoFg.muted = true;
        videoFg.setAttribute('playsinline', 'true');

        videoFg.onPlay.listen((_) => videoBg.play());
        videoFg.onPause.listen((_) => videoBg.pause());
        videoFg.onEnded.listen((_) => _videoEndedController.add(null));
        videoFg.onLoadedMetadata.listen((_) => _applyLeadTime());
        videoFg.onCanPlay.listen((_) => _applyLeadTime());

        _videoFg = videoFg;
        _videoBg = videoBg;

        _applyLeadTime();

        container.appendChild(videoBg);
        container.appendChild(videoFg);
        return container;
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _videoViewId = 'video-thumb-${widget.item.name.replaceAll(' ', '-')}';
    _scheduleRandomReveal();

    _progressTicker = createTicker((_) {
      if (_videoFg != null) {
        final cur = _videoFg!.currentTime;
        final dur = _videoFg!.duration;
        if (dur > 0 && !dur.isNaN) {
          playbackProgressNotifier.value = cur / dur;
        }
      }
    });
    _progressTicker?.start();

    final primaryGame = widget.item is Game ? (widget.item as Game) : (widget.item as GameCompilation).games.first;

    if (!primaryGame.stillThumbnail) {
      _ensurePlatformViewRegistered();
      _checkVideoSource();
    }
  }

  @override
  void didUpdateWidget(GameThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.gridCycle != oldWidget.gridCycle) {
      _scheduleRandomReveal();
    }
  }

  @override
  void dispose() {
    _randomRevealTimer?.cancel();
    _progressTicker?.dispose();
    playbackProgressNotifier.dispose();
    _videoEndedController.close();
    super.dispose();
  }

  Future<void> _checkVideoSource() async {
    final cleanBaseUrl = widget.cleanBaseUrl.endsWith('/')
        ? widget.cleanBaseUrl.substring(0, widget.cleanBaseUrl.length - 1)
        : widget.cleanBaseUrl;
    final videoUrl = "$cleanBaseUrl/_thumbs${widget.item.displayUrl}.mp4";
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

    final isVideoMode = widget.gridPage.option.isVideoMode;
    final isKioskMode = widget.gridPage.isKioskMode;

    final primaryGame = widget.item is Game ? (widget.item as Game) : (widget.item as GameCompilation).games.first;
    final showVideoPreview = isVideoMode && _useVideo && (_revealVideo || widget.isTileActive);

    if (isVideoMode && !isKioskMode) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          resetVideoToStart();
          if (widget.onTap != null) widget.onTap!();
        },
        child: Material(
          color: const Color(0xFF1E1E1E),
          child: SizedBox.expand(
            child: Stack(
              children: [
                GameImageThumb(
                  cleanBaseUrl: cleanBaseUrl,
                  gameUrl: widget.item.displayUrl,
                  fit: BoxFit.contain,
                ),
                if (_useVideo)
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: showVideoPreview ? 1.0 : 0.0,
                    child: PointerInterceptor(
                      child: HtmlElementView(viewType: _videoViewId),
                    ),
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
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {
          resetVideoToStart();
          if (widget.onTap != null) {
            widget.onTap!();
          } else {
            Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => GameDetailPage(
                  game: primaryGame,
                  baseUrl: widget.gridPage.baseUrl,
                  option: widget.gridPage.option,
                ),
                transitionDuration: const Duration(milliseconds: 500),
                reverseTransitionDuration: const Duration(milliseconds: 500),
                transitionsBuilder: (context, animation, secondaryAnimation, child) => child,
              ),
            );
          }
        },
        child: Hero(
          tag: widget.item.name,
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
                      child: Stack(
                        children: [
                          GameImageThumb(
                            cleanBaseUrl: cleanBaseUrl,
                            gameUrl: widget.item.displayUrl,
                            fit: BoxFit.contain,
                          ),
                          if (_useVideo)
                            AnimatedOpacity(
                              duration: const Duration(milliseconds: 300),
                              opacity: showVideoPreview ? 1.0 : 0.0,
                              child: PointerInterceptor(
                                child: HtmlElementView(viewType: _videoViewId),
                              ),
                            ),
                        ],
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
                    child: Container(
                      padding: const EdgeInsets.all(16.0),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              widget.item.name,
                              style: primaryGame.getTitleStyle(
                                fontSize: 24,
                                forceTasgm: widget.gridPage.option.isTasgmStyle,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (widget.item is Game)
                              Text(
                                (widget.item as Game).author,
                                style: (widget.item as Game).getAuthorStyle(
                                  fontSize: 16,
                                  forceTasgm: widget.gridPage.option.isTasgmStyle,
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
  final GameOption option;
  final bool isRecording;

  const GameDetailPage({
    super.key,
    required this.game,
    required this.baseUrl,
    required this.option,
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

  void _safePop() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && route.isCurrent) {
      Navigator.of(context).pop();
    }
  }

  @override
  void initState() {
    super.initState();
    _viewId = 'detail-view-${widget.game.name.replaceAll(' ', '-')}';

    _hasDescription = (widget.game.description != null && widget.game.description!.isNotEmpty) ||
        (widget.game.qr != null && widget.game.qr!.isNotEmpty);
    if (_hasDescription && !widget.game.isVideo && !widget.option.isVideoMode) {
      _showDescription = true;
    }

    if (!widget.option.isVideoMode && widget.game.execute != null) {
      _isExecuting = true;
      _handleExecute();
    } else if (!widget.option.isVideoMode && widget.game.steam != null) {
      _isExecuting = true;
      _handleSteam();
    } else {
      ui_web.platformViewRegistry.registerViewFactory(
        _viewId,
            (int id) {
          final cleanBaseUrl = widget.baseUrl.endsWith('/')
              ? widget.baseUrl.substring(0, widget.baseUrl.length - 1)
              : widget.baseUrl;

          if (widget.game.isVideo || widget.option.isVideoMode) {
            final videoUrl = '$cleanBaseUrl/_thumbs${widget.game.url}.mp4';

            final container = web.document.createElement('div') as web.HTMLDivElement;
            container.style.position = 'relative';
            container.style.width = '100%';
            container.style.height = '100%';
            container.style.overflow = 'hidden';
            container.style.backgroundColor = 'black';

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
            videoFg.onClick.listen((_) => _safePop());
            videoFg.onEnded.listen((_) => _safePop());

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

      if (widget.game.isVideo || widget.option.isVideoMode) {
        _showHtml = true;
      } else {
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

    final theme = widget.option.getTheme(context);

    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: widget.option.isVideoMode
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
              Text(
                widget.game.name,
                style: widget.game.getTitleStyle(
                  fontSize: 20,
                  forceTasgm: widget.option.isTasgmStyle,
                ),
              ),
              Text(
                widget.game.author,
                style: widget.game.getAuthorStyle(
                  fontSize: 12,
                  forceTasgm: widget.option.isTasgmStyle,
                ),
              ),
            ],
          ),
          actions: [
            if (_hasDescription && !_showDescription && !widget.option.isVideoMode)
              IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: () => setState(() => _showDescription = true),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
              child: Image.network(
                "${widget.baseUrl}_thumbs/${widget.option.isTasgmStyle ? 'tasgm_logo.png' : 'utas_dark.png'}",
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
              ),
            ),
          ],
        ),
        body: Hero(
          tag: widget.game.name,
          child: Material(
            color: Colors.black,
            child: Column(
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: (_showDescription && !widget.option.isVideoMode)
                      ? GestureDetector(
                    onTap: () => setState(() => _showDescription = false),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: (widget.game.description != null && widget.game.description!.isNotEmpty)
                                ? HtmlWidget(
                              widget.game.description!,
                            )
                                : const SizedBox.shrink(),
                          ),
                          if (widget.game.qr != null && widget.game.qr!.isNotEmpty) ...[
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
                        if (!widget.game.isVideo && !widget.option.isVideoMode) ...[
                          Positioned.fill(
                            child: ImageFiltered(
                              imageFilter: ui.ImageFilter.blur(sigmaX: 7.0, sigmaY: 7.0),
                              child: GameImageThumb(
                                cleanBaseUrl: cleanBaseUrl,
                                gameUrl: widget.game.url,
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
                                  style: widget.game.getTitleStyle(
                                    fontSize: 24,
                                    forceTasgm: widget.option.isTasgmStyle,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                Text(
                                  widget.game.author,
                                  style: widget.game.getAuthorStyle(
                                    fontSize: 16,
                                    forceTasgm: widget.option.isTasgmStyle,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )),
                        ),
                        if (widget.option.isVideoMode)
                          Positioned.fill(
                            child: PointerInterceptor(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _safePop,
                                child: Container(
                                  color: Colors.transparent,
                                ),
                              ),
                            ),
                          ),
                        if (widget.option.isVideoMode) ...[
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
                                            style: widget.game.getTitleStyle(
                                              fontSize: 32,
                                              forceTasgm: widget.option.isTasgmStyle,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            widget.game.author,
                                            style: widget.game.getAuthorStyle(
                                              fontSize: 20,
                                              forceTasgm: widget.option.isTasgmStyle,
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
                                          child: Text(
                                            'PLAY ON THE BOOTH',
                                            style: widget.game.getRibbonStyle(
                                              fontSize: 18,
                                              forceTasgm: widget.option.isTasgmStyle,
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