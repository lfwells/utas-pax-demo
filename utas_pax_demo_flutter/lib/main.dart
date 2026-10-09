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
  // Prevent Google Fonts from trying to download fonts over the network offline
  GoogleFonts.config.allowRuntimeFetching = false;

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
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
          textTheme: GoogleFonts.montserratTextTheme(
            Theme.of(context).textTheme,
          ),
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
  final String? fileName;
  final int cols;
  final bool isVideoMode;
  final bool isTasgmStyle;
  final List<GridItem> items;

  GameOption({
    required this.name,
    this.fileName,
    required this.cols,
    required this.isVideoMode,
    required this.isTasgmStyle,
    required this.items,
  });

  factory GameOption.fromJson(Map<String, dynamic> json, {String? fileName}) {
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
      fileName: fileName,
      cols: (json['cols'] as num?)?.toInt() ?? 4,
      isVideoMode: modeStr == 'video',
      isTasgmStyle: (json['tasgm'] as bool?) ?? false,
      items: parsedItems,
    );
  }

  ThemeData getTheme(BuildContext context) {
    if (isTasgmStyle) {
      return ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.orange,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
        scaffoldBackgroundColor: const Color(0xFF1A1A1A),
      );
    } else if (isVideoMode) {
      return ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.montserratTextTheme(ThemeData.dark().textTheme),
        scaffoldBackgroundColor: Colors.black,
      );
    } else {
      return ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.montserratTextTheme(ThemeData.dark().textTheme),
        scaffoldBackgroundColor: Colors.black,
      );
    }
  }
}

enum VideoExecutionMode { live, record, kiosk }

class VideoModeSelection {
  final VideoExecutionMode mode;
  final bool thumbnailOnlyInGridMode;

  const VideoModeSelection({
    required this.mode,
    required this.thumbnailOnlyInGridMode,
  });
}

const String _thumbnailOnlyInGridModePrefKey = 'utas.thumbnailOnlyInGridMode';

bool loadThumbnailOnlyInGridModePreference() {
  if (!kIsWeb) return false;
  try {
    final stored = web.window.localStorage.getItem(
      _thumbnailOnlyInGridModePrefKey,
    );
    return stored == '1' || stored == 'true';
  } catch (_) {
    return false;
  }
}

void saveThumbnailOnlyInGridModePreference(bool value) {
  if (!kIsWeb) return;
  try {
    web.window.localStorage.setItem(
      _thumbnailOnlyInGridModePrefKey,
      value ? '1' : '0',
    );
  } catch (_) {}
}

Map<String, String> getQueryParams() {
  final queryParams = Uri.base.queryParameters;
  if (queryParams.isNotEmpty) {
    return queryParams;
  }
  final fragment = Uri.base.fragment;
  if (fragment.contains('?')) {
    final queryStr = fragment.substring(fragment.indexOf('?'));
    return Uri.parse('http://localhost$queryStr').queryParameters;
  }
  return {};
}

String buildVideoUrl(String baseUrl, String rawPath) {
  final trimmedPath = rawPath.trim();
  if (trimmedPath.startsWith('http://') || trimmedPath.startsWith('https://')) {
    return trimmedPath;
  }

  final cleanBase = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  String p = trimmedPath;

  if (p.startsWith('/_thumbs/')) {
    p = p.substring('/_thumbs'.length);
  } else if (p.startsWith('_thumbs/')) {
    p = p.substring('_thumbs'.length);
  }

  if (!p.startsWith('/')) {
    p = '/$p';
  }

  if (!p.toLowerCase().endsWith('.mp4')) {
    p = '$p.mp4';
  }

  return '$cleanBase/_thumbs$p';
}

String resolvePlayableVideoUrl(String baseUrl, String rawPath) {
  final trimmedPath = rawPath.trim();
  if (trimmedPath.startsWith('http://') || trimmedPath.startsWith('https://')) {
    return trimmedPath;
  }
  return buildVideoUrl(baseUrl, trimmedPath);
}

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
  bool _autoNavigated = false;
  bool _thumbnailOnlyInGridModePreference = false;

  @override
  void initState() {
    super.initState();
    _thumbnailOnlyInGridModePreference =
        loadThumbnailOnlyInGridModePreference();
    _optionsFuture = _fetchOptions().then((options) {
      _checkAutoNavigate(options);
      return options;
    });
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

  void _checkAutoNavigate(List<GameOption> options) {
    if (_autoNavigated || options.isEmpty) return;

    final params = getQueryParams();
    final optionParam =
        params['option'] ?? params['optionName'] ?? params['optionIndex'];
    if (optionParam == null || optionParam.isEmpty) return;

    GameOption? selectedOption;

    final rawTarget = optionParam.toLowerCase().trim();
    final cleanTarget = rawTarget.replaceAll('.json', '');

    // 1. Check filename match (e.g. pax_video.json or pax_video)
    for (final opt in options) {
      if (opt.fileName != null) {
        final rawFile = opt.fileName!.toLowerCase().trim();
        final cleanFile = rawFile.replaceAll('.json', '');
        if (rawFile == rawTarget || cleanFile == cleanTarget) {
          selectedOption = opt;
          break;
        }
      }
    }

    // 2. Check name match (e.g. PAX Video Grid)
    if (selectedOption == null) {
      for (final opt in options) {
        final optNameLower = opt.name.toLowerCase();
        final cleanOptName = optNameLower.replaceAll('.json', '');
        if (optNameLower == rawTarget ||
            cleanOptName == cleanTarget ||
            optNameLower.contains(cleanTarget) ||
            cleanTarget.contains(cleanOptName)) {
          selectedOption = opt;
          break;
        }
      }
    }

    // 3. Fallback to index match (e.g. 0, 1)
    if (selectedOption == null) {
      final parsedIndex = int.tryParse(optionParam);
      if (parsedIndex != null &&
          parsedIndex >= 0 &&
          parsedIndex < options.length) {
        selectedOption = options[parsedIndex];
      }
    }

    if (selectedOption != null) {
      _autoNavigated = true;
      final modeParam =
          (params['mode'] ?? params['execMode'])?.toLowerCase() ?? 'live';
      VideoExecutionMode execMode = VideoExecutionMode.live;
      if (modeParam == 'kiosk') {
        execMode = VideoExecutionMode.kiosk;
      } else if (modeParam == 'record') {
        execMode = VideoExecutionMode.record;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _preloadAndNavigate(
          context: context,
          baseUrl: widget.baseUrl,
          option: selectedOption!,
          startWithRecording: execMode == VideoExecutionMode.record,
          isKioskMode: execMode == VideoExecutionMode.kiosk,
          thumbnailOnlyInGridMode: _thumbnailOnlyInGridModePreference,
        );
      });
    }
  }

  List<String> _getOptionUrlsToPreload(GameOption option, String baseUrl) {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    final Set<String> urls = {};

    // Logo
    final logoName = option.isTasgmStyle ? 'tasgm_logo.png' : 'utas_dark.png';
    urls.add('$cleanBaseUrl/_thumbs/$logoName');

    // Extract all games
    final List<Game> games = [];
    for (final item in option.items) {
      if (item is Game) {
        games.add(item);
      } else if (item is GameCompilation) {
        if (item.thumbnailUrl.isNotEmpty) {
          urls.add('$cleanBaseUrl/_thumbs${item.thumbnailUrl}.png');
          urls.add('$cleanBaseUrl/_thumbs${item.thumbnailUrl}.jpg');
        }
        games.addAll(item.games);
      }
    }

    for (final game in games) {
      if (game.url.isNotEmpty) {
        urls.add('$cleanBaseUrl/_thumbs${game.url}.png');
        urls.add('$cleanBaseUrl/_thumbs${game.url}.jpg');
        urls.add(buildVideoUrl(cleanBaseUrl, game.url));

        if (!option.isVideoMode && !game.isVideo) {
          urls.add('$cleanBaseUrl${game.url}');
        }
      }

      if (game.hasVideoSelection) {
        for (final v in game.videoSelection!) {
          urls.add(buildVideoUrl(cleanBaseUrl, v));
        }
      }

      if (game.qr != null && game.qr!.isNotEmpty) {
        final qr = game.qr!;
        final lower = qr.toLowerCase();
        final isImage =
            lower.endsWith('.png') ||
            lower.endsWith('.jpg') ||
            lower.endsWith('.jpeg') ||
            lower.endsWith('.svg') ||
            lower.endsWith('.webp');
        if (isImage) {
          if (qr.startsWith('http://') || qr.startsWith('https://')) {
            urls.add(qr);
          } else if (qr.startsWith('/')) {
            urls.add('$cleanBaseUrl$qr');
          } else {
            urls.add('$cleanBaseUrl/$qr');
          }
        }
      }
    }

    return urls.toList();
  }

  Future<void> _preloadAndNavigate({
    required BuildContext context,
    required String baseUrl,
    required GameOption option,
    bool startWithRecording = false,
    bool isKioskMode = false,
    bool thumbnailOnlyInGridMode = false,
  }) async {
    final urls = _getOptionUrlsToPreload(option, baseUrl);

    if (urls.isNotEmpty && context.mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) =>
            PreloadDialog(option: option, urls: urls, parentContext: context),
      );
    }

    if (context.mounted) {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => GameGridPage(
            baseUrl: baseUrl,
            option: option,
            startWithRecording: startWithRecording,
            isKioskMode: isKioskMode,
            thumbnailOnlyInGridMode: thumbnailOnlyInGridMode,
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
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
              final fileResponse = await http.get(
                Uri.parse('$cleanBaseUrl/$item'),
              );
              if (fileResponse.statusCode == 200) {
                final fileData =
                    json.decode(fileResponse.body) as Map<String, dynamic>;
                options.add(GameOption.fromJson(fileData, fileName: item));
              }
            } catch (e) {
              debugPrint('Error fetching json configuration $item: $e');
            }
          }
        }
      } else if (decodedIndex is Map<String, dynamic>) {
        if (decodedIndex.containsKey('files')) {
          final files = (decodedIndex['files'] as List)
              .map((e) => e.toString())
              .toList();
          for (final file in files) {
            try {
              final fileResponse = await http.get(
                Uri.parse('$cleanBaseUrl/$file'),
              );
              if (fileResponse.statusCode == 200) {
                final fileData =
                    json.decode(fileResponse.body) as Map<String, dynamic>;
                options.add(GameOption.fromJson(fileData, fileName: file));
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
            icon: Icon(
              _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
            ),
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
              child: Text(
                'Error loading options: ${snapshot.error}',
                style: const TextStyle(color: Colors.white),
              ),
            );
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                'No JSON options found',
                style: TextStyle(color: Colors.white),
              ),
            );
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
                          backgroundColor: option.isVideoMode
                              ? Colors.teal.shade800
                              : Colors.deepPurple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          if (option.isVideoMode) {
                            final VideoModeSelection?
                            selection = await showDialog<VideoModeSelection>(
                              context: context,
                              builder: (BuildContext context) {
                                bool thumbnailOnlyInGridMode =
                                    _thumbnailOnlyInGridModePreference;
                                return AlertDialog(
                                  title: const Text('Video Mode Configuration'),
                                  content: StatefulBuilder(
                                    builder: (context, setDialogState) {
                                      return Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Select how you would like to run this video grid sequence:',
                                          ),
                                          const SizedBox(height: 12),
                                          CheckboxListTile(
                                            value: thumbnailOnlyInGridMode,
                                            contentPadding: EdgeInsets.zero,
                                            dense: true,
                                            title: const Text(
                                              'Grid mode: thumbnails only until a tile is expanded',
                                            ),
                                            onChanged: (value) {
                                              setDialogState(() {
                                                thumbnailOnlyInGridMode =
                                                    value ?? false;
                                              });
                                            },
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                  actionsAlignment: MainAxisAlignment.center,
                                  actions: <Widget>[
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.teal,
                                            foregroundColor: Colors.white,
                                          ),
                                          child: const Text(
                                            'Kiosk Mode (Interactive Manual Play)',
                                          ),
                                          onPressed: () =>
                                              Navigator.of(context).pop(
                                                VideoModeSelection(
                                                  mode:
                                                      VideoExecutionMode.kiosk,
                                                  thumbnailOnlyInGridMode:
                                                      thumbnailOnlyInGridMode,
                                                ),
                                              ),
                                        ),
                                        const SizedBox(height: 8),
                                        const SizedBox(height: 4),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.deepPurple,
                                            foregroundColor: Colors.white,
                                          ),
                                          child: const Text(
                                            'Live Playback Only',
                                          ),
                                          onPressed: () =>
                                              Navigator.of(context).pop(
                                                VideoModeSelection(
                                                  mode: VideoExecutionMode.live,
                                                  thumbnailOnlyInGridMode:
                                                      thumbnailOnlyInGridMode,
                                                ),
                                              ),
                                        ),
                                      ],
                                    ),
                                  ],
                                );
                              },
                            );
                            if (selection == null) return;

                            setState(() {
                              _thumbnailOnlyInGridModePreference =
                                  selection.thumbnailOnlyInGridMode;
                            });
                            saveThumbnailOnlyInGridModePreference(
                              selection.thumbnailOnlyInGridMode,
                            );

                            if (context.mounted) {
                              await _preloadAndNavigate(
                                context: context,
                                baseUrl: widget.baseUrl,
                                option: option,
                                startWithRecording:
                                    selection.mode == VideoExecutionMode.record,
                                isKioskMode:
                                    selection.mode == VideoExecutionMode.kiosk,
                                thumbnailOnlyInGridMode:
                                    selection.thumbnailOnlyInGridMode,
                              );
                            }
                          } else {
                            if (context.mounted) {
                              await _preloadAndNavigate(
                                context: context,
                                baseUrl: widget.baseUrl,
                                option: option,
                              );
                            }
                          }
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              option.isVideoMode
                                  ? Icons.ondemand_video
                                  : Icons.sports_esports,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                option.name,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
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

class PreloadDialog extends StatefulWidget {
  final GameOption option;
  final List<String> urls;
  final BuildContext parentContext;

  const PreloadDialog({
    super.key,
    required this.option,
    required this.urls,
    required this.parentContext,
  });

  @override
  State<PreloadDialog> createState() => _PreloadDialogState();
}

class _PreloadDialogState extends State<PreloadDialog> {
  int _completed = 0;
  String _currentFile = '';

  @override
  void initState() {
    super.initState();
    _startPreloading();
  }

  Future<void> _startPreloading() async {
    if (widget.urls.isEmpty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final total = widget.urls.length;
    const maxConcurrent = 4;
    int currentIndex = 0;

    Future<void> worker() async {
      while (true) {
        if (currentIndex >= total) break;
        final index = currentIndex++;
        final url = widget.urls[index];
        final fileName = Uri.parse(url).pathSegments.isNotEmpty
            ? Uri.parse(url).pathSegments.last
            : url;

        if (mounted) {
          setState(() {
            _currentFile = fileName;
          });
        }

        try {
          final pathLower = Uri.parse(url).path.toLowerCase();
          final isPng = pathLower.endsWith('.png');
          final isJpg =
              pathLower.endsWith('.jpg') || pathLower.endsWith('.jpeg');
          final isImg =
              isPng ||
              isJpg ||
              pathLower.endsWith('.webp') ||
              pathLower.endsWith('.svg');
          final isMp4 = pathLower.endsWith('.mp4');

          final response = await http.get(Uri.parse(url));

          if (response.statusCode == 200) {
            if (isMp4) {
              GameImageThumb._verifiedVideoUrls.add(url);
            } else if (isImg) {
              if (url.contains('/_thumbs/')) {
                final uriPath = Uri.parse(url).path;
                final gameKey = uriPath
                    .replaceAll(RegExp(r'.*/_thumbs'), '')
                    .replaceAll(RegExp(r'\.(png|jpg|jpeg|webp)$'), '');
                if (!GameImageThumb._resolvedThumbUrls.containsKey(gameKey) ||
                    isPng) {
                  GameImageThumb._resolvedThumbUrls[gameKey] = url;
                }
              }
              if (widget.parentContext.mounted && !pathLower.endsWith('.svg')) {
                await precacheImage(
                  NetworkImage(url),
                  widget.parentContext,
                ).catchError((_) {});
              }
            }
          }
        } catch (_) {}

        if (mounted) {
          setState(() {
            _completed++;
          });
        }
      }
    }

    final workers = List.generate(
      math.min(maxConcurrent, total),
      (_) => worker(),
    );

    await Future.wait(workers);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Color get _accentColor {
    if (widget.option.isTasgmStyle) {
      return const Color(0xFF3BD9E5);
    } else if (widget.option.isVideoMode) {
      return Colors.teal;
    }
    return Colors.deepPurpleAccent;
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.urls.length;
    final progress = total > 0 ? (_completed / total).clamp(0.0, 1.0) : 1.0;
    final percent = (progress * 100).toInt();

    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(
          children: [
            Text(
              'Preloading Assets',
              style: TextStyle(
                color: _accentColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.option.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(_accentColor),
                  minHeight: 12,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$_completed of $total files',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  Text(
                    '$percent%',
                    style: TextStyle(
                      color: _accentColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              if (_currentFile.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _currentFile,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
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
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();

    final uri = Uri.base;
    final params = getQueryParams();
    final protocol = uri.scheme.isEmpty ? 'http' : uri.scheme;
    final host = uri.host.isEmpty ? 'localhost' : uri.host;
    final port = uri.port == 0 ? 5999 : uri.port;

    final paramBaseUrl = params['baseUrl'];
    final currentBaseUrl = (paramBaseUrl != null && paramBaseUrl.isNotEmpty)
        ? (paramBaseUrl.endsWith('/') ? paramBaseUrl : '$paramBaseUrl/')
        : (kDebugMode ? "http://localhost:5001/" : '$protocol://$host:$port/');

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

abstract class GridItem {
  String get name;
  String get displayUrl;
  String get thumbnailUrl;
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
  final double skipSeconds;
  final double duration;
  final double scale;
  final List<String>? videoSelection;

  bool get hasVideoSelection =>
      videoSelection != null && videoSelection!.isNotEmpty;

  @override
  String get displayUrl => url;

  @override
  String get thumbnailUrl => url;

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
    this.skipSeconds = 0.0,
    this.duration = 0.0,
    this.scale = 1.0,
    this.videoSelection,
  });

  Game copyWithVideoUrl(String videoUrl) {
    final cleanUrl = videoUrl.trim();
    return Game(
      name: name,
      url: cleanUrl.isEmpty ? url : cleanUrl,
      author: author,
      execute: execute,
      steam: steam,
      isVideo: true,
      description: description,
      qr: qr,
      onBooth: onBooth,
      showLowerThird: showLowerThird,
      tasgm: tasgm,
      stillThumbnail: stillThumbnail,
      aspectRatio: aspectRatio,
      skipSeconds: skipSeconds,
      duration: duration,
      scale: scale,
      videoSelection: videoSelection,
    );
  }

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

    double parseDouble(dynamic val, {double defaultValue = 0.0}) {
      if (val == null) return defaultValue;
      if (val is num) return val.toDouble();
      if (val is String) {
        final parsed = double.tryParse(val.trim());
        if (parsed != null) return parsed;
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
        ?.replaceAll(
          '[',
          '<span style="background-color:#3a3a3c; color:#ffffff; border:1px solid #666666; border-radius:4px; padding:2px 6px; display:inline-block">',
        )
        .replaceAll(']', '</span>')
        .replaceAll('\n', '<br>');

    final rawVideoSelection = json['video_selection'] ?? json['videoSelection'];
    List<String>? parsedVideoSelection;
    if (rawVideoSelection is List) {
      parsedVideoSelection = rawVideoSelection
          .map((e) => e.toString())
          .toList();
    }

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
      showLowerThird: parseBool(
        json['showLowerThird'] ?? json['show_lower_third'],
        true,
      ),
      tasgm: parseBool(json['tasgm'], false),
      stillThumbnail: parseBool(
        json['still_thumbnail'] ?? json['stillThumbnail'],
        false,
      ),
      aspectRatio: parseAspectRatio(
        json['aspectRatio'] ?? json['aspect_ratio'],
      ),
      skipSeconds: parseDouble(json['skip_seconds'] ?? json['skipSeconds']),
      duration: parseDouble(
        json['duration'] ?? json['duration_seconds'] ?? json['durationSeconds'],
      ),
      scale: parseDouble(json['scale'], defaultValue: 1.0),
      videoSelection: parsedVideoSelection,
    );
  }

  TextStyle getTitleStyle({
    required double fontSize,
    required bool forceTasgm,
  }) {
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

  TextStyle getAuthorStyle({
    required double fontSize,
    required bool forceTasgm,
  }) {
    final useTasgm = forceTasgm || tasgm;
    if (useTasgm) {
      return GoogleFonts.poppins(color: Colors.white70, fontSize: fontSize);
    }
    return GoogleFonts.montserrat(color: Colors.white70, fontSize: fontSize);
  }

  TextStyle getRibbonStyle({
    required double fontSize,
    required bool forceTasgm,
  }) {
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
  final String url;
  final List<Game> games;

  GameCompilation({required this.name, required this.url, required this.games});

  @override
  String get displayUrl => games.isNotEmpty ? games.first.url : '';

  @override
  String get thumbnailUrl => url.isNotEmpty ? url : displayUrl;

  factory GameCompilation.fromJson(Map<String, dynamic> json) {
    final rawGames = json['games'] as List? ?? json['game'] as List? ?? [];
    final parsedGames = rawGames
        .map((g) => Game.fromJson(g as Map<String, dynamic>))
        .toList();
    return GameCompilation(
      name: json['name'] as String? ?? 'Compilation',
      url: json['url'] as String? ?? '',
      games: parsedGames,
    );
  }
}

class GameGridPage extends StatefulWidget {
  final String baseUrl;
  final GameOption option;
  final bool startWithRecording;
  final bool isKioskMode;
  final bool thumbnailOnlyInGridMode;
  final double gridSpacing;

  const GameGridPage({
    super.key,
    required this.baseUrl,
    required this.option,
    this.startWithRecording = false,
    this.isKioskMode = false,
    this.thumbnailOnlyInGridMode = false,
    this.gridSpacing = 8.0,
  });

  @override
  State<GameGridPage> createState() => _GameGridPageState();
}

class _GameGridPageState extends State<GameGridPage>
    with TickerProviderStateMixin {
  static const Duration _minFullscreenDwellForEnded = Duration(
    milliseconds: 1400,
  );

  bool _isSequenceRunning = false;
  bool _isRecording = false;
  int _gridCycle = 0;
  final List<Future<void>> _pendingFrameUploads = [];

  double _scrollRowOffset = 0.0;
  AnimationController? _scrollAnimationController;

  Completer<void>? _gridWaitCompleter;
  Completer<void>? _fullscreenWaitCompleter;
  int? _nextSequenceIndex;
  int? _expandedVideoIndex;
  int _kioskPlaybackSession = 0;
  Game? _currentActiveGame;
  int? _topTileIndex;
  Timer? _topTileTimer;
  bool _spaceKeyDown = false;
  DateTime? _lastSkipTriggerAt;

  static const Duration _skipDebounce = Duration(milliseconds: 250);

  final Map<int, GlobalKey<_GameThumbState>> _thumbKeys = {};
  final Map<int, GlobalKey> _tileGlobalKeys = {};

  void _scrollToRow(double targetRow) {
    _scrollAnimationController?.dispose();
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    final animation = Tween<double>(
      begin: _scrollRowOffset,
      end: targetRow,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut));

    animation.addListener(() {
      if (mounted) {
        setState(() {
          _scrollRowOffset = animation.value;
        });
      }
    });

    _scrollAnimationController = controller;
    controller.forward();
  }

  GlobalKey<_GameThumbState> _getThumbKey(int index) {
    return _thumbKeys.putIfAbsent(index, () => GlobalKey<_GameThumbState>());
  }

  Future<_GameThumbState?> _waitForThumbState(
    int index, {
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (mounted && DateTime.now().isBefore(deadline)) {
      final state = _getThumbKey(index).currentState;
      if (state != null) {
        return state;
      }
      await WidgetsBinding.instance.endOfFrame;
    }
    return _getThumbKey(index).currentState;
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
      _topTileTimer = null;
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
        _getThumbKey(
          _expandedVideoIndex!,
        ).currentState?.resetThumbnailIfStill();
      }
      setState(() {
        _expandedVideoIndex = null;
      });
      _topTileTimer?.cancel();
      _topTileTimer = Timer(const Duration(milliseconds: 1000), () {
        if (mounted) {
          if (_expandedVideoIndex == null) {
            setState(() {
              _topTileIndex = null;
              _currentActiveGame = null;
              _gridCycle++;
            });
          }
        }
      });
    }
  }

  void _skipFullscreenWait() {
    if (_fullscreenWaitCompleter != null &&
        !_fullscreenWaitCompleter!.isCompleted) {
      _fullscreenWaitCompleter!.complete();
    }
  }

  int _beginKioskPlaybackSession() {
    _kioskPlaybackSession += 1;
    return _kioskPlaybackSession;
  }

  void _cancelKioskPlaybackSession() {
    _kioskPlaybackSession += 1;
    _skipFullscreenWait();
  }

  bool _isCurrentKioskPlaybackSession(int session) {
    return mounted && session == _kioskPlaybackSession;
  }

  Future<void> _waitOnFullscreenWithVideoCompletion(
    int index,
    Future<double> durationFuture,
    Stream<void>? endedStream,
    Game activeGame,
  ) async {
    _fullscreenWaitCompleter = Completer<void>();
    final waitStartedAt = DateTime.now();

    final configuredDuration =
        activeGame.duration > 0 && !activeGame.duration.isNaN
        ? Duration(milliseconds: (activeGame.duration * 1000).round())
        : null;

    final fallbackDuration =
        configuredDuration ??
        await () async {
          final double dur = await durationFuture;
          return (dur > 0 && !dur.isNaN)
              ? Duration(milliseconds: (dur * 1000).round() + 200)
              : const Duration(seconds: 15);
        }();

    final effectiveWaitDuration = fallbackDuration < _minFullscreenDwellForEnded
        ? _minFullscreenDwellForEnded
        : fallbackDuration;

    StreamSubscription? endedSub;
    if (endedStream != null) {
      endedSub = endedStream.listen((_) {
        // Ignore immediate ended events from rapid source/element transitions.
        if (DateTime.now().difference(waitStartedAt) <
            _minFullscreenDwellForEnded) {
          return;
        }
        _skipFullscreenWait();
      });
    }

    await Future.any([
      Future.delayed(effectiveWaitDuration),
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
    await Future.any([Future.delayed(duration), _gridWaitCompleter!.future]);
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
    _scrollAnimationController?.dispose();
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    super.dispose();
  }

  bool _canTriggerSkip() {
    final now = DateTime.now();
    if (_lastSkipTriggerAt != null &&
        now.difference(_lastSkipTriggerAt!) < _skipDebounce) {
      return false;
    }
    _lastSkipTriggerAt = now;
    return true;
  }

  bool _onKeyEvent(KeyEvent event) {
    if (!widget.option.isVideoMode || widget.isKioskMode) return false;

    if (event.logicalKey != LogicalKeyboardKey.space) {
      return false;
    }

    if (event is KeyUpEvent) {
      _spaceKeyDown = false;
      return true;
    }

    if (event is! KeyDownEvent) {
      return false;
    }

    if (_spaceKeyDown) {
      return true;
    }
    _spaceKeyDown = true;

    if (!_canTriggerSkip()) {
      return true;
    }

    if (_expandedVideoIndex != null) {
      _skipFullscreenWait();
    } else {
      _skipGridWait();
    }
    return true;
  }

  Future<void> _recordFrame(Duration simulatedTime, String apiBaseUrl) async {
    final boundary =
        rootRepaintKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary != null) {
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final frameNum = (simulatedTime.inMicroseconds / 16666).round();
        final bytes = byteData.buffer.asUint8List();

        final uploadFuture = http
            .post(
              Uri.parse('$apiBaseUrl/captureFrame'),
              headers: {
                'Content-Type': 'application/octet-stream',
                'X-Frame-Number': frameNum.toString(),
              },
              body: bytes,
            )
            .then((response) {
              if (response.statusCode != 200) {
                debugPrint(
                  'Error uploading frame $frameNum: ${response.statusCode}',
                );
              }
            })
            .catchError((e) {
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

  final Map<int, int> _kioskVsPointers = {};

  Future<void> _playSequenceLive(List<GridItem> items) async {
    await Future.delayed(const Duration(seconds: 2));

    final List<int> normalIndices = [];
    final List<int> vsIndices = [];

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is Game && item.hasVideoSelection) {
        vsIndices.add(i);
      } else {
        normalIndices.add(i);
      }
    }

    if (normalIndices.isEmpty) {
      normalIndices.addAll(List.generate(items.length, (i) => i));
      vsIndices.clear();
    }

    final Map<int, int> vsPointers = {};
    final Map<int, Set<int>> vsSeenSelections = {};
    final Set<int> exhaustedVsIndices = {};
    int vsSeqIndex = 0;
    int normalSeqIndex = 0;

    Future<void> playVsTile(int vsGridIndex) async {
      final item = items[vsGridIndex];
      if (item is! Game || !item.hasVideoSelection) return;

      final selectionCount = item.videoSelection!.length;
      final p = (vsPointers[vsGridIndex] ?? 0) % selectionCount;
      final selectedVideo = item.videoSelection![p];

      final vsVideoGame = item.copyWithVideoUrl(selectedVideo);

      final cols = widget.option.cols;
      final maxScrollRow = math.max(0, (items.length / cols).ceil() - cols);
      final itemRow = vsGridIndex ~/ cols;
      if (itemRow < _scrollRowOffset || itemRow >= _scrollRowOffset + cols) {
        _scrollToRow(itemRow.clamp(0, maxScrollRow).toDouble());
      }

      final thumbState = await _waitForThumbState(vsGridIndex);
      if (thumbState == null) {
        return;
      }
      _expandVideo(vsGridIndex, vsVideoGame);
      thumbState.playFromStart(vsVideoGame);
      await thumbState.waitUntilVideoReady(
        timeout: const Duration(milliseconds: 4000),
      );
      if (!thumbState.isVideoReady) {
        return;
      }

      vsPointers[vsGridIndex] = (p + 1) % selectionCount;
      final seenSelections = vsSeenSelections.putIfAbsent(
        vsGridIndex,
        () => <int>{},
      );
      seenSelections.add(p);
      if (seenSelections.length >= selectionCount) {
        exhaustedVsIndices.add(vsGridIndex);
      }

      final durFuture = thumbState.getValidDuration();
      final endedStream = thumbState.onVideoEnded;

      await _waitOnFullscreenWithVideoCompletion(
        vsGridIndex,
        durFuture,
        endedStream,
        vsVideoGame,
      );
      _collapseVideo();
    }

    _alignThumb(normalIndices[0], 5.5);
    await _waitOnGrid(const Duration(seconds: 5));

    while (mounted && widget.option.isVideoMode) {
      if (_nextSequenceIndex != null) {
        final target = _nextSequenceIndex!;
        _nextSequenceIndex = null;

        if (vsIndices.contains(target)) {
          await playVsTile(target);
          if (normalIndices.isNotEmpty) {
            final nextNormal = normalIndices[normalSeqIndex];
            _alignThumb(nextNormal, 5.5);
            await _waitOnGrid(const Duration(seconds: 5));
          }
          continue;
        } else if (normalIndices.contains(target)) {
          normalSeqIndex = normalIndices.indexOf(target);
        }
      }

      if (!mounted) break;

      final int index = normalIndices[normalSeqIndex];
      final cols = widget.option.cols;
      final maxScrollRow = math.max(0, (items.length / cols).ceil() - cols);
      final itemRow = index ~/ cols;
      if (itemRow < _scrollRowOffset || itemRow >= _scrollRowOffset + cols) {
        _scrollToRow(itemRow.clamp(0, maxScrollRow).toDouble());
      }

      final item = items[index];

      if (item is Game) {
        final thumbState = _getThumbKey(index).currentState;
        _expandVideo(index, item);
        thumbState?.playFromStart(item);
        if (thumbState != null) {
          await thumbState.waitUntilVideoReady();
        }

        final durFuture = thumbState?.getValidDuration() ?? Future.value(15.0);
        final endedStream = thumbState?.onVideoEnded;

        await _waitOnFullscreenWithVideoCompletion(
          index,
          durFuture,
          endedStream,
          item,
        );
        _collapseVideo();
      } else if (item is GameCompilation) {
        for (int subIndex = 0; subIndex < item.games.length; subIndex++) {
          if (!mounted) break;
          final subGame = item.games[subIndex];

          final thumbState = _getThumbKey(index).currentState;
          _expandVideo(index, subGame);
          thumbState?.loadAndPlaySubGame(subGame);
          if (thumbState != null) {
            await thumbState.waitUntilVideoReady();
          }

          final durFuture =
              thumbState?.getValidDuration() ?? Future.value(15.0);
          final endedStream = thumbState?.onVideoEnded;

          await _waitOnFullscreenWithVideoCompletion(
            index,
            durFuture,
            endedStream,
            subGame,
          );

          if (_nextSequenceIndex != null) {
            break;
          }
        }
        _collapseVideo();
      }

      normalSeqIndex = (normalSeqIndex + 1) % normalIndices.length;

      final activeVsIndices = vsIndices
          .where((index) => !exhaustedVsIndices.contains(index))
          .toList();
      if (activeVsIndices.isNotEmpty && _nextSequenceIndex == null) {
        if (vsSeqIndex >= activeVsIndices.length) {
          vsSeqIndex = 0;
        }
        final int vsGridIndex = activeVsIndices[vsSeqIndex];
        vsSeqIndex = (vsSeqIndex + 1) % activeVsIndices.length;

        _alignThumb(vsGridIndex, 5.5);
        await _waitOnGrid(const Duration(seconds: 5));

        if (_nextSequenceIndex == null) {
          await playVsTile(vsGridIndex);
        }
      }

      if (_nextSequenceIndex != null) {
        continue;
      }

      final int nextNormalIndex = normalIndices[normalSeqIndex];
      _alignThumb(nextNormalIndex, 5.5);
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
    Duration simulatedTime =
        SchedulerBinding.instance.currentSystemFrameTimeStamp;

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
      final Game firstGame = item is Game
          ? item
          : (item as GameCompilation).games.first;
      if (!mounted) break;

      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              GameDetailPage(
                game: firstGame,
                baseUrl: widget.baseUrl,
                option: widget.option,
                isRecording: _isRecording,
              ),
          transitionDuration: const Duration(milliseconds: 500),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              child,
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
      backgroundColor: widget.option.isTasgmStyle
          ? const Color(0xFF3bd9e5)
          : Colors.black,
      centerTitle: false,
      title: Text(
        widget.option.isTasgmStyle
            ? "Tasmanian Game Makers"
            : "Study Games at UTAS",
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
          child: Image.network(
            "${widget.baseUrl}_thumbs/${widget.option.isTasgmStyle ? 'tasgm_logo.png' : 'utas_dark.png'}",
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
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
          final availableWidth =
              constraints.maxWidth - (crossAxisCount + 1) * spacing;
          final cellWidth = availableWidth / crossAxisCount;

          final rowCount = (items.length / crossAxisCount).ceil();
          final effectiveRows = rowCount < crossAxisCount
              ? crossAxisCount
              : rowCount;
          final availableHeight =
              constraints.maxHeight - (effectiveRows + 1) * spacing;
          final cellHeight = availableHeight / effectiveRows;

          List<Widget> tiles = [];

          for (int i = 0; i < items.length; i++) {
            final left = spacing + (i % crossAxisCount) * (cellWidth + spacing);
            final top =
                spacing + (i ~/ crossAxisCount) * (cellHeight + spacing);
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
                      gameUrl: items[i].thumbnailUrl,
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
                  cellLeft:
                      spacing + (i % crossAxisCount) * (cellWidth + spacing),
                  cellTop:
                      spacing + (i ~/ crossAxisCount) * (cellHeight + spacing),
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
                cellLeft:
                    spacing + (i % crossAxisCount) * (cellWidth + spacing),
                cellTop:
                    spacing + (i ~/ crossAxisCount) * (cellHeight + spacing),
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
            child: Stack(children: tiles),
          );
        },
      ),
    );
  }

  void _onKioskTileClick(int index, GridItem item) async {
    if (_expandedVideoIndex != null) {
      _cancelKioskPlaybackSession();
      _getThumbKey(
        _expandedVideoIndex!,
      ).currentState?.stopPlayback(resetToStart: true);
      _collapseVideo();
      return;
    }

    if (item is Game) {
      final playbackSession = _beginKioskPlaybackSession();
      Game gameToPlay = item;
      if (item.hasVideoSelection) {
        final p = _kioskVsPointers[index] ?? 0;
        final selectedVideo = item.videoSelection![p];
        _kioskVsPointers[index] = (p + 1) % item.videoSelection!.length;
        gameToPlay = item.copyWithVideoUrl(selectedVideo);
      }

      final thumbState = _getThumbKey(index).currentState;
      _expandVideo(index, gameToPlay);
      thumbState?.playFromStart(gameToPlay);
      if (thumbState != null) {
        await thumbState.waitUntilVideoReady();
      }

      final durFuture = thumbState?.getValidDuration() ?? Future.value(15.0);
      final endedStream = thumbState?.onVideoEnded;

      await _waitOnFullscreenWithVideoCompletion(
        index,
        durFuture,
        endedStream,
        gameToPlay,
      );
      if (!_isCurrentKioskPlaybackSession(playbackSession)) {
        return;
      }
      _collapseVideo();
    } else if (item is GameCompilation) {
      final playbackSession = _beginKioskPlaybackSession();
      for (int subIndex = 0; subIndex < item.games.length; subIndex++) {
        if (!_isCurrentKioskPlaybackSession(playbackSession)) {
          return;
        }
        final subGame = item.games[subIndex];

        final thumbState = _getThumbKey(index).currentState;
        _expandVideo(index, subGame);
        thumbState?.loadAndPlaySubGame(subGame);
        if (thumbState != null) {
          await thumbState.waitUntilVideoReady();
        }

        final durFuture = thumbState?.getValidDuration() ?? Future.value(15.0);
        final endedStream = thumbState?.onVideoEnded;

        await _waitOnFullscreenWithVideoCompletion(
          index,
          durFuture,
          endedStream,
          subGame,
        );

        if (!_isCurrentKioskPlaybackSession(playbackSession)) {
          return;
        }
      }

      if (!_isCurrentKioskPlaybackSession(playbackSession)) {
        return;
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

    final thumbState = _getThumbKey(index).currentState;
    final stateGame = thumbState?.currentGame;
    final activeGame =
        stateGame ??
        ((_currentActiveGame != null &&
                (_expandedVideoIndex == index || _topTileIndex == index))
            ? _currentActiveGame!
            : (item is Game ? item : (item as GameCompilation).games.first));
    final isActiveTile =
        (_expandedVideoIndex == index || _topTileIndex == index);

    final useTasgmColor = activeGame.tasgm || widget.option.isTasgmStyle;
    final progressColor = useTasgmColor
        ? const Color(0xFF3BD9E5)
        : const Color(0xFFE53935);

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
        valueListenable:
            _getThumbKey(index).currentState?.playbackProgressNotifier ??
            ValueNotifier(0.0),
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
                child: Container(color: progressColor.withValues(alpha: 0.5)),
              ),
            ),
          );
        },
      ),
      lowerThird: Positioned(
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
      ),
      showLowerThirdEnabled: activeGame.showLowerThird,
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
          : const Positioned.fill(child: SizedBox.shrink()),
      isActiveTile: isActiveTile,
      child: GameThumb(
        key: _getThumbKey(index),
        item: item,
        gridPage: widget,
        cleanBaseUrl: widget.baseUrl,
        gridCycle: _gridCycle,
        isTileActive: isActiveTile,
        isExpandedTile: isExpanded,
      ),
    );
  }

  Widget _buildQrCode(String qrData, String cleanBaseUrl, {double size = 76}) {
    final isImage =
        qrData.toLowerCase().endsWith('.png') ||
        qrData.toLowerCase().endsWith('.jpg') ||
        qrData.toLowerCase().endsWith('.jpeg') ||
        qrData.toLowerCase().endsWith('.svg') ||
        qrData.toLowerCase().endsWith('.webp');

    Widget qrWidget;
    if (isImage) {
      final imageUrl =
          qrData.startsWith('http://') || qrData.startsWith('https://')
          ? qrData
          : (qrData.startsWith('/')
                ? '$cleanBaseUrl$qrData'
                : '$cleanBaseUrl/$qrData');
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
          BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: SizedBox(width: size, height: size, child: qrWidget),
    );
  }

  Widget _buildDefaultGrid(
    BuildContext context,
    List<GridItem> items,
    int crossAxisCount,
  ) {
    final spacing = widget.gridSpacing;

    return Container(
      color: Colors.black,
      padding: EdgeInsets.all(spacing),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth =
              constraints.maxWidth - (crossAxisCount - 1) * spacing;
          final cellWidth = availableWidth / crossAxisCount;

          final rowCount = (items.length / crossAxisCount).ceil();
          final effectiveRows = rowCount < crossAxisCount
              ? crossAxisCount
              : rowCount;
          final availableHeight =
              constraints.maxHeight - (effectiveRows - 1) * spacing;
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
                isTileActive:
                    (_expandedVideoIndex == index || _topTileIndex == index),
                isExpandedTile: _expandedVideoIndex == index,
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
            ? const Center(
                child: Text(
                  'No games found',
                  style: TextStyle(color: Colors.white),
                ),
              )
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
  final bool isActiveTile;
  final bool showLowerThirdEnabled;

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
    required this.isActiveTile,
    required this.showLowerThirdEnabled,
  });

  @override
  State<VideoTileWidget> createState() => _VideoTileWidgetState();
}

class _VideoTileWidgetState extends State<VideoTileWidget>
    with SingleTickerProviderStateMixin {
  static const Duration _lowerThirdFadeDuration = Duration(milliseconds: 250);
  static const double _lowerThirdRevealProgressThreshold = 1;

  late AnimationController _controller;
  late Animation<double> _animation;

  bool get _canShowLowerThird {
    return widget.isExpanded && widget.showLowerThirdEnabled;
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);

    if (widget.isExpanded) {
      _controller.forward(from: 1.0);
    }
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
      return;
    }

    if (widget.isExpanded &&
        _controller.value < 1.0 &&
        !_controller.isAnimating) {
      _controller.forward(from: _controller.value);
      return;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildAnimatedLowerThird(double opacity) {
    final lowerThird = widget.lowerThird;

    if (lowerThird is Positioned) {
      return Positioned(
        key: lowerThird.key,
        left: lowerThird.left,
        top: lowerThird.top,
        right: lowerThird.right,
        bottom: lowerThird.bottom,
        width: lowerThird.width,
        height: lowerThird.height,
        child: AnimatedOpacity(
          opacity: opacity,
          duration: _lowerThirdFadeDuration,
          curve: Curves.easeOut,
          child: lowerThird.child,
        ),
      );
    }

    return AnimatedOpacity(
      opacity: opacity,
      duration: _lowerThirdFadeDuration,
      curve: Curves.easeOut,
      child: lowerThird,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final progress = _animation.value;
        final left = ui.lerpDouble(widget.cellLeft, 0, progress)!;
        final top = ui.lerpDouble(widget.cellTop, 0, progress)!;
        final width = ui.lerpDouble(
          widget.cellWidth,
          widget.screenWidth,
          progress,
        )!;
        final height = ui.lerpDouble(
          widget.cellHeight,
          widget.screenHeight,
          progress,
        )!;

        final overlayOpacity = (progress - 0.3).clamp(0.0, 0.7) / 0.7;
        final effectiveOverlayOpacity = widget.isActiveTile
            ? 1.0
            : overlayOpacity;
        final lowerThirdProgress =
            ((progress - _lowerThirdRevealProgressThreshold) /
                    (1.0 - _lowerThirdRevealProgressThreshold))
                .clamp(0.0, 1.0);
        final lowerThirdOpacity = _canShowLowerThird ? lowerThirdProgress : 0.0;

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
                  if (effectiveOverlayOpacity > 0)
                    Opacity(
                      opacity: effectiveOverlayOpacity,
                      child: PointerInterceptor(
                        intercepting: false,
                        child: IgnorePointer(
                          child: Stack(
                            children: [
                              widget.boothRibbon,
                              widget.progressBar,
                              _buildAnimatedLowerThird(lowerThirdOpacity),
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

class GameImageThumb extends StatefulWidget {
  final String cleanBaseUrl;
  final String gameUrl;
  final BoxFit fit;

  static final Map<String, String> _resolvedThumbUrls = {};
  static final Set<String> _verifiedVideoUrls = {};

  const GameImageThumb({
    super.key,
    required this.cleanBaseUrl,
    required this.gameUrl,
    this.fit = BoxFit.contain,
  });

  @override
  State<GameImageThumb> createState() => _GameImageThumbState();
}

class _GameImageThumbState extends State<GameImageThumb> {
  String? _effectiveUrl;

  @override
  void initState() {
    super.initState();
    _resolveUrl();
  }

  @override
  void didUpdateWidget(GameImageThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.gameUrl != oldWidget.gameUrl ||
        widget.cleanBaseUrl != oldWidget.cleanBaseUrl) {
      _resolveUrl();
    }
  }

  void _resolveUrl() {
    final cleanUrl = widget.cleanBaseUrl.endsWith('/')
        ? widget.cleanBaseUrl.substring(0, widget.cleanBaseUrl.length - 1)
        : widget.cleanBaseUrl;

    final key = widget.gameUrl;
    final cleanKey = key.startsWith('/') ? key : '/$key';

    if (GameImageThumb._resolvedThumbUrls.containsKey(key)) {
      _effectiveUrl = GameImageThumb._resolvedThumbUrls[key];
    } else if (GameImageThumb._resolvedThumbUrls.containsKey(cleanKey)) {
      _effectiveUrl = GameImageThumb._resolvedThumbUrls[cleanKey];
    } else {
      _effectiveUrl = "$cleanUrl/_thumbs${widget.gameUrl}.png";
    }
  }

  Widget _buildPair(String imageUrl) {
    if (widget.fit == BoxFit.cover) {
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
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
          Container(color: Colors.black.withValues(alpha: 0.25)),
          Image.network(
            imageUrl,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cleanUrl = widget.cleanBaseUrl.endsWith('/')
        ? widget.cleanBaseUrl.substring(0, widget.cleanBaseUrl.length - 1)
        : widget.cleanBaseUrl;
    final pngUrl = "$cleanUrl/_thumbs${widget.gameUrl}.png";
    final jpgUrl = "$cleanUrl/_thumbs${widget.gameUrl}.jpg";

    final currentUrl = _effectiveUrl ?? pngUrl;

    return Image.network(
      currentUrl,
      fit: widget.fit,
      width: double.infinity,
      height: double.infinity,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame == null) return const SizedBox.shrink();
        return _buildPair(currentUrl);
      },
      errorBuilder: (context, error, stackTrace) {
        if (currentUrl == pngUrl && currentUrl != jpgUrl) {
          GameImageThumb._resolvedThumbUrls[widget.gameUrl] = jpgUrl;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _effectiveUrl = jpgUrl;
              });
            }
          });
        }
        return const SizedBox.shrink();
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
    this.isExpandedTile = false,
  });

  final GridItem item;
  final GameGridPage gridPage;
  final String cleanBaseUrl;
  final VoidCallback? onTap;
  final int gridCycle;
  final bool isTileActive;
  final bool isExpandedTile;

  @override
  State<GameThumb> createState() => _GameThumbState();
}

class _GameThumbState extends State<GameThumb> with TickerProviderStateMixin {
  bool _isHovered = false;
  bool _useVideo = false;
  bool _revealVideo = false;
  bool _isVideoReady = false;
  Timer? _randomRevealTimer;
  late String _videoViewId;
  web.HTMLVideoElement? _videoFg;
  web.HTMLVideoElement? _videoBg;
  double? _pendingLeadTime;
  Game? _activeSubGame;

  bool get _shouldRestrictPlaybackToExpandedTile =>
      widget.gridPage.option.isVideoMode &&
      widget.gridPage.thumbnailOnlyInGridMode;

  bool get _canPlayInGrid =>
      !_shouldRestrictPlaybackToExpandedTile || widget.isExpandedTile;

  bool get _shouldPlayNow => _canPlayInGrid;

  void _setVideoReady(bool ready) {
    if (_isVideoReady == ready) return;
    if (mounted) {
      setState(() {
        _isVideoReady = ready;
      });
      return;
    }
    _isVideoReady = ready;
  }

  void _safePlay(web.HTMLVideoElement? video) {
    if (video == null) return;
    unawaited(
      video.play().toDart.catchError((_) {
        // Expected when a rapid state/source change interrupts a pending play().
        return null;
      }),
    );
  }

  Game get _currentGame =>
      _activeSubGame ??
      (widget.item is Game
          ? (widget.item as Game)
          : (widget.item as GameCompilation).games.first);

  Game get currentGame => _currentGame;

  final ValueNotifier<double> playbackProgressNotifier = ValueNotifier<double>(
    0.0,
  );
  Ticker? _progressTicker;

  final StreamController<void> _videoEndedController =
      StreamController<void>.broadcast();
  Stream<void> get onVideoEnded => _videoEndedController.stream;

  double? get videoDuration => _videoFg?.duration;
  bool get isVideoReady => _isVideoReady;

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
    final primaryGame = widget.item is Game
        ? (widget.item as Game)
        : (widget.item as GameCompilation).games.first;
    if (primaryGame.stillThumbnail || primaryGame.hasVideoSelection) {
      if (mounted) {
        setState(() {
          _useVideo = false;
          _activeSubGame = null;
        });
      }
      stopPlayback(resetToStart: true);
    }
  }

  void stopPlayback({bool resetToStart = false}) {
    final skip = _currentGame.skipSeconds;

    if (_videoFg != null) {
      _videoFg!.pause();
      _videoFg!.muted = true;
      if (resetToStart) {
        _videoFg!.currentTime = skip;
      }
    }

    if (_videoBg != null) {
      _videoBg!.pause();
      _videoBg!.muted = true;
      if (resetToStart) {
        _videoBg!.currentTime = skip;
      }
    }

    if (resetToStart) {
      playbackProgressNotifier.value = 0.0;
    }
  }

  Future<double> getValidDuration() async {
    if (_videoFg == null) {
      _ensurePlatformViewRegistered();
    }
    final skip = _currentGame.skipSeconds;
    final d = _videoFg?.duration;
    if (d != null && d > 0 && !d.isNaN) {
      return math.max(0.0, d - skip);
    }

    final completer = Completer<double>();
    StreamSubscription? subMeta;
    StreamSubscription? subChange;

    void check() {
      final cd = _videoFg?.duration;
      if (cd != null && cd > 0 && !cd.isNaN && !completer.isCompleted) {
        completer.complete(math.max(0.0, cd - skip));
      }
    }

    if (_videoFg != null) {
      subMeta = _videoFg!.onLoadedMetadata.listen((_) => check());
      subChange = _videoFg!.onDurationChange.listen((_) => check());
      check();
    }

    return completer.future
        .timeout(
          const Duration(seconds: 4),
          onTimeout: () => math.max(1.0, 15.0 - skip),
        )
        .whenComplete(() {
          subMeta?.cancel();
          subChange?.cancel();
        });
  }

  bool _isPlatformViewRegistered = false;

  void alignVideoToLoopStart(double leadTimeInSeconds) {
    if (widget.gridPage.isKioskMode) return;
    _pendingLeadTime = leadTimeInSeconds;
    _applyLeadTime();
  }

  void playFromStart(Game game) {
    _activeSubGame = game;
    // Active fullscreen playback should start from game skip time, not grid lead-time.
    _pendingLeadTime = null;
    if (mounted && !_useVideo) {
      setState(() {
        _useVideo = true;
      });
    }
    _ensurePlatformViewRegistered();
    _loadCurrentVideo();
  }

  void loadAndPlaySubGame(Game subGame) {
    _activeSubGame = subGame;
    // Subsequence playback should ignore any pre-alignment used for grid previews.
    _pendingLeadTime = null;
    if (mounted) {
      setState(() {
        _useVideo = true;
      });
    }
    _ensurePlatformViewRegistered();
    _loadCurrentVideo();
  }

  Future<void> waitUntilVideoReady({
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    if (_videoFg == null) {
      _ensurePlatformViewRegistered();
    }

    final deadline = DateTime.now().add(timeout);
    while (mounted && _videoFg == null && DateTime.now().isBefore(deadline)) {
      await WidgetsBinding.instance.endOfFrame;
    }

    final fg = _videoFg;
    if (fg == null) {
      return;
    }

    final expectedUrl = resolvePlayableVideoUrl(
      widget.cleanBaseUrl,
      _currentGame.url,
    );
    final expectedPath = Uri.tryParse(expectedUrl)?.path;

    bool sourceMatchesExpected() {
      if (expectedPath == null || expectedPath.isEmpty) {
        return true;
      }
      final currentPath = Uri.tryParse(fg.src)?.path;
      if (currentPath == null || currentPath.isEmpty) {
        return false;
      }
      if (currentPath == expectedPath) {
        return true;
      }
      final decodedCurrent = Uri.decodeFull(currentPath);
      final decodedExpected = Uri.decodeFull(expectedPath);
      return decodedCurrent.endsWith(decodedExpected) ||
          decodedExpected.endsWith(decodedCurrent);
    }

    if (fg.src.isNotEmpty && fg.readyState >= 2 && sourceMatchesExpected()) {
      _setVideoReady(true);
      return;
    }

    final completer = Completer<void>();
    StreamSubscription? subCanPlay;
    StreamSubscription? subMeta;

    void markReady() {
      if (!completer.isCompleted) {
        _setVideoReady(true);
        completer.complete();
      }
    }

    subCanPlay = fg.onCanPlay.listen((_) {
      if (sourceMatchesExpected() && fg.readyState >= 2) {
        markReady();
      }
    });
    subMeta = fg.onLoadedMetadata.listen((_) {
      if (sourceMatchesExpected() && fg.readyState >= 2) {
        markReady();
      }
    });

    if (fg.src.isNotEmpty && fg.readyState >= 2 && sourceMatchesExpected()) {
      markReady();
    }

    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      await subCanPlay.cancel();
      await subMeta.cancel();
      return;
    }

    await completer.future.timeout(remaining, onTimeout: () {});
    await subCanPlay.cancel();
    await subMeta.cancel();
  }

  void _loadCurrentVideo() {
    if (_videoFg == null || _videoBg == null) return;

    final targetUrl = resolvePlayableVideoUrl(
      widget.cleanBaseUrl,
      _currentGame.url,
    );
    final currentSrc = _videoFg!.src;

    playbackProgressNotifier.value = 0.0;

    final currentUri = Uri.tryParse(currentSrc);
    final targetUri = Uri.tryParse(targetUrl);
    final isSameSrc =
        currentSrc == targetUrl ||
        (currentUri != null &&
            targetUri != null &&
            currentUri.path == targetUri.path);

    _setVideoReady(isSameSrc && _videoFg!.readyState >= 2);

    if (isSameSrc && _videoFg!.readyState >= 2) {
      _videoFg!.currentTime = _currentGame.skipSeconds;
      if (_videoBg != null) _videoBg!.currentTime = _currentGame.skipSeconds;
      if (_shouldPlayNow) {
        _safePlay(_videoFg);
        _safePlay(_videoBg);
      } else {
        _videoFg!.pause();
        if (_videoBg != null) _videoBg!.pause();
      }
    } else {
      _videoFg!.src = targetUrl;
      if (_videoBg != null) _videoBg!.src = targetUrl;

      StreamSubscription? subMeta;
      subMeta = _videoFg!.onLoadedMetadata.listen((_) {
        if (_videoFg!.readyState < 2) {
          return;
        }
        subMeta?.cancel();
        if (_videoFg != null) {
          _videoFg!.currentTime = _currentGame.skipSeconds;
          if (_videoBg != null) {
            _videoBg!.currentTime = _currentGame.skipSeconds;
          }
          if (_shouldPlayNow) {
            _safePlay(_videoFg);
            _safePlay(_videoBg);
          } else {
            _videoFg!.pause();
            if (_videoBg != null) _videoBg!.pause();
          }
          _setVideoReady(true);
        }
      });

      _videoFg!.load();
      if (_videoBg != null) _videoBg!.load();
    }

    _syncGridMediaState();
  }

  void _syncGridMediaState() {
    if (_videoFg == null || _videoBg == null) return;

    // Foreground audio is only enabled for the expanded tile.
    _videoFg!.muted = !widget.isExpandedTile;
    _videoBg!.muted = true;

    if (!_shouldPlayNow) {
      if (!_videoFg!.paused) {
        _videoFg!.pause();
      }
      if (!_videoBg!.paused) {
        _videoBg!.pause();
      }
      return;
    }

    if (_videoFg!.src.isNotEmpty && _videoFg!.paused) {
      _safePlay(_videoFg);
      _safePlay(_videoBg);
    }
  }

  void _enforceSkipTime() {
    if (_videoFg == null) return;
    final skip = _currentGame.skipSeconds;
    if (skip > 0 && _videoFg!.currentTime < skip) {
      _videoFg!.currentTime = skip;
      if (_videoBg != null) {
        _videoBg!.currentTime = skip;
      }
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
      final skip = _currentGame.skipSeconds;
      final eff = d - skip;
      if (eff > 0 && !eff.isNaN) {
        final lead = _pendingLeadTime!;
        double rem = eff - (lead % eff);
        if (rem >= eff) rem = 0.0;
        final startTime = skip + rem;
        _videoFg!.currentTime = startTime;
        if (_videoBg != null) {
          _videoBg!.currentTime = startTime;
        }
        _pendingLeadTime = null;
      }
    } catch (_) {}
  }

  void resetVideoToStart() {
    final skip = _currentGame.skipSeconds;
    if (_videoFg != null && _videoBg != null) {
      _videoFg!.currentTime = skip;
      _videoBg!.currentTime = skip;
    }
    playbackProgressNotifier.value = 0.0;
  }

  void _ensurePlatformViewRegistered() {
    if (_isPlatformViewRegistered) return;
    _isPlatformViewRegistered = true;

    ui_web.platformViewRegistry.registerViewFactory(_videoViewId, (int id) {
      final container = web.document.createElement('div') as web.HTMLDivElement;
      container.style.position = 'relative';
      container.style.width = '100%';
      container.style.height = '100%';
      container.style.overflow = 'hidden';
      container.style.backgroundColor = 'black';

      final videoBg =
          web.document.createElement('video') as web.HTMLVideoElement;
      videoBg.style.position = 'absolute';
      videoBg.style.top = '0';
      videoBg.style.left = '0';
      videoBg.style.width = '100%';
      videoBg.style.height = '100%';
      videoBg.style.objectFit = 'cover';
      videoBg.style.filter = 'blur(20px) brightness(0.7)';
      videoBg.style.transform = 'scale(1.1)';
      videoBg.autoplay = false;
      videoBg.loop = true;
      videoBg.muted = true;
      videoBg.setAttribute('playsinline', 'true');

      final videoFg =
          web.document.createElement('video') as web.HTMLVideoElement;
      videoFg.style.position = 'absolute';
      videoFg.style.top = '0';
      videoFg.style.left = '0';
      videoFg.style.width = '100%';
      videoFg.style.height = '100%';
      videoFg.style.objectFit = 'contain';
      videoFg.autoplay = false;
      videoFg.controls = false;
      videoFg.style.cursor = 'pointer';
      videoFg.muted = true;
      videoFg.setAttribute('playsinline', 'true');

      videoFg.onPlay.listen((_) {
        unawaited(videoBg.play().toDart.catchError((_) => null));
      });
      videoFg.onPause.listen((_) => videoBg.pause());
      videoFg.onEnded.listen((_) => _videoEndedController.add(null));
      videoFg.onLoadedMetadata.listen((_) {
        _enforceSkipTime();
        _applyLeadTime();
      });
      videoFg.onCanPlay.listen((_) {
        _enforceSkipTime();
        _applyLeadTime();
      });
      videoFg.onTimeUpdate.listen((_) => _enforceSkipTime());
      videoFg.onSeeked.listen((_) => _enforceSkipTime());

      _videoFg = videoFg;
      _videoBg = videoBg;

      container.appendChild(videoBg);
      container.appendChild(videoFg);

      _loadCurrentVideo();
      _syncGridMediaState();

      return container;
    });
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
        final skip = _currentGame.skipSeconds;
        final eff = dur - skip;
        if (eff > 0 && !eff.isNaN) {
          playbackProgressNotifier.value = ((cur - skip) / eff).clamp(0.0, 1.0);
        }
      }
    });
    _progressTicker?.start();

    final primaryGame = widget.item is Game
        ? (widget.item as Game)
        : (widget.item as GameCompilation).games.first;
    final isVideoMode = widget.gridPage.option.isVideoMode;

    final videoUrl = buildVideoUrl(widget.cleanBaseUrl, widget.item.displayUrl);

    if ((isVideoMode ||
            primaryGame.isVideo ||
            GameImageThumb._verifiedVideoUrls.contains(videoUrl)) &&
        !primaryGame.hasVideoSelection) {
      _useVideo = true;
    }

    if (!primaryGame.stillThumbnail && !primaryGame.hasVideoSelection) {
      _ensurePlatformViewRegistered();
      if (!_useVideo) {
        _checkVideoSource();
      }
    }
  }

  @override
  void didUpdateWidget(GameThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.gridCycle != oldWidget.gridCycle) {
      _scheduleRandomReveal();
    }
    if (widget.isExpandedTile != oldWidget.isExpandedTile ||
        widget.gridPage.thumbnailOnlyInGridMode !=
            oldWidget.gridPage.thumbnailOnlyInGridMode) {
      _syncGridMediaState();
    }
  }

  @override
  void dispose() {
    _randomRevealTimer?.cancel();
    stopPlayback();
    _progressTicker?.dispose();
    playbackProgressNotifier.dispose();
    _videoEndedController.close();
    super.dispose();
  }

  Future<void> _checkVideoSource() async {
    final videoUrl = buildVideoUrl(widget.cleanBaseUrl, widget.item.displayUrl);

    if (GameImageThumb._verifiedVideoUrls.contains(videoUrl)) {
      if (mounted) setState(() => _useVideo = true);
      return;
    }

    try {
      final response = await http.head(Uri.parse(videoUrl));
      if (response.statusCode == 200) {
        GameImageThumb._verifiedVideoUrls.add(videoUrl);
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

    final primaryGame = widget.item is Game
        ? (widget.item as Game)
        : (widget.item as GameCompilation).games.first;
    final showVideoPreview =
        isVideoMode &&
        _useVideo &&
        (_isVideoReady || widget.isExpandedTile) &&
        (widget.gridPage.thumbnailOnlyInGridMode
            ? widget.isExpandedTile
            : (widget.isTileActive ||
                  (_revealVideo && !primaryGame.hasVideoSelection)));

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
                  gameUrl: widget.item.thumbnailUrl,
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
                    child: Container(color: Colors.transparent),
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
                pageBuilder: (context, animation, secondaryAnimation) =>
                    GameDetailPage(
                      game: primaryGame,
                      baseUrl: widget.gridPage.baseUrl,
                      option: widget.gridPage.option,
                    ),
                transitionDuration: const Duration(milliseconds: 500),
                reverseTransitionDuration: const Duration(milliseconds: 500),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) => child,
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
                    tween: Tween<double>(
                      begin: 0.0,
                      end: _isHovered ? 7.0 : 0.0,
                    ),
                    duration: const Duration(milliseconds: 250),
                    builder: (context, blurValue, child) {
                      return Opacity(
                        opacity: _isHovered ? 0.5 : 1.0,
                        child: blurValue > 0
                            ? ImageFiltered(
                                imageFilter: ui.ImageFilter.blur(
                                  sigmaX: blurValue,
                                  sigmaY: blurValue,
                                ),
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
                            gameUrl: widget.item.thumbnailUrl,
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
                    color: Colors.white.withValues(
                      alpha: _isHovered ? 0.2 : 0.0,
                    ),
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
                                  forceTasgm:
                                      widget.gridPage.option.isTasgmStyle,
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

    _hasDescription =
        (widget.game.description != null &&
            widget.game.description!.isNotEmpty) ||
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
      ui_web.platformViewRegistry.registerViewFactory(_viewId, (int id) {
        final cleanBaseUrl = widget.baseUrl.endsWith('/')
            ? widget.baseUrl.substring(0, widget.baseUrl.length - 1)
            : widget.baseUrl;

        if (widget.game.isVideo || widget.option.isVideoMode) {
          final videoUrl = '$cleanBaseUrl/_thumbs${widget.game.url}.mp4';

          final container =
              web.document.createElement('div') as web.HTMLDivElement;
          container.style.position = 'relative';
          container.style.width = '100%';
          container.style.height = '100%';
          container.style.overflow = 'hidden';
          container.style.backgroundColor = 'black';

          final videoBg =
              web.document.createElement('video') as web.HTMLVideoElement;
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

          final videoFg =
              web.document.createElement('video') as web.HTMLVideoElement;
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

          final skip = widget.game.skipSeconds;
          void enforceSkip() {
            if (skip > 0 && videoFg.currentTime < skip) {
              videoFg.currentTime = skip;
              videoBg.currentTime = skip;
            }
          }

          videoFg.onLoadedMetadata.listen((_) => enforceSkip());
          videoFg.onCanPlay.listen((_) => enforceSkip());
          videoFg.onTimeUpdate.listen((_) => enforceSkip());
          videoFg.onSeeked.listen((_) => enforceSkip());

          videoFg.onPlay.listen((_) {
            unawaited(videoBg.play().toDart.catchError((_) => null));
          });
          videoFg.onPause.listen((_) => videoBg.pause());
          videoFg.onClick.listen((_) => _safePop());
          videoFg.onEnded.listen((_) => _safePop());

          container.appendChild(videoBg);
          container.appendChild(videoFg);
          return container;
        } else {
          final container =
              web.document.createElement('div') as web.HTMLDivElement;
          container.style.position = 'relative';
          container.style.width = '100%';
          container.style.height = '100%';
          container.style.overflow = 'hidden';
          container.style.backgroundColor = 'black';

          final gameScale = widget.game.scale <= 0 ? 1.0 : widget.game.scale;
          final viewportPercent = 100 / gameScale;

          final iframeHost =
              web.document.createElement('div') as web.HTMLDivElement;
          iframeHost.style.width = '100%';
          iframeHost.style.height = '100%';
          iframeHost.style.display = 'flex';
          iframeHost.style.justifyContent = 'center';
          iframeHost.style.alignItems = 'flex-start';
          iframeHost.style.overflow = 'hidden';

          final iframe =
              web.document.createElement('iframe') as web.HTMLIFrameElement;
          iframe.src = '$cleanBaseUrl${widget.game.url}';
          iframe.style.border = 'none';
          iframe.style.width = '${viewportPercent}%';
          iframe.style.height = '${viewportPercent}%';
          iframe.style.backgroundColor = 'black';
          iframe.allow =
              'fullscreen; autoplay; gamepad; encrypted-media; midi; clipboard-write';
          iframe.setAttribute('allowfullscreen', 'true');
          iframe.setAttribute('webkitallowfullscreen', 'true');
          iframe.setAttribute('mozallowfullscreen', 'true');

          if (gameScale != 1.0) {
            // Scale visuals while increasing iframe viewport to avoid clipping.
            iframe.style.transform = 'scale($gameScale)';
            iframe.style.transformOrigin = 'top center';
          }

          iframeHost.appendChild(iframe);
          container.appendChild(iframeHost);
          return container;
        }
      });

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
    final isImage =
        qrData.toLowerCase().endsWith('.png') ||
        qrData.toLowerCase().endsWith('.jpg') ||
        qrData.toLowerCase().endsWith('.jpeg') ||
        qrData.toLowerCase().endsWith('.svg') ||
        qrData.toLowerCase().endsWith('.webp');

    Widget qrWidget;
    if (isImage) {
      final imageUrl =
          qrData.startsWith('http://') || qrData.startsWith('https://')
          ? qrData
          : (qrData.startsWith('/')
                ? '$cleanBaseUrl$qrData'
                : '$cleanBaseUrl/$qrData');
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
          BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: SizedBox(width: size, height: size, child: qrWidget),
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
                  if (_hasDescription &&
                      !_showDescription &&
                      !widget.option.isVideoMode)
                    IconButton(
                      icon: const Icon(Icons.info_outline),
                      onPressed: () => setState(() => _showDescription = true),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 16.0,
                    ),
                    child: Image.network(
                      "${widget.baseUrl}_thumbs/${widget.option.isTasgmStyle ? 'tasgm_logo.png' : 'utas_dark.png'}",
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child:
                                      (widget.game.description != null &&
                                          widget.game.description!.isNotEmpty)
                                      ? HtmlWidget(widget.game.description!)
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
                        Positioned.fill(child: Container(color: Colors.black)),
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
                                    ? (widget.game.isVideo ||
                                              widget.option.isVideoMode
                                          ? PointerInterceptor(
                                              intercepting: !_showDescription,
                                              child: HtmlElementView(
                                                viewType: _viewId,
                                              ),
                                            )
                                          : Align(
                                              alignment: Alignment.topCenter,
                                              child: AspectRatio(
                                                aspectRatio:
                                                    widget.game.aspectRatio,
                                                child: PointerInterceptor(
                                                  intercepting:
                                                      !_showDescription,
                                                  child: HtmlElementView(
                                                    viewType: _viewId,
                                                  ),
                                                ),
                                              ),
                                            ))
                                    : Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              widget.game.name,
                                              style: widget.game.getTitleStyle(
                                                fontSize: 24,
                                                forceTasgm:
                                                    widget.option.isTasgmStyle,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                            Text(
                                              widget.game.author,
                                              style: widget.game.getAuthorStyle(
                                                fontSize: 16,
                                                forceTasgm:
                                                    widget.option.isTasgmStyle,
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
                                child: Container(color: Colors.transparent),
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 64,
                                  vertical: 32,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            widget.game.name,
                                            style: widget.game.getTitleStyle(
                                              fontSize: 32,
                                              forceTasgm:
                                                  widget.option.isTasgmStyle,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            widget.game.author,
                                            style: widget.game.getAuthorStyle(
                                              fontSize: 20,
                                              forceTasgm:
                                                  widget.option.isTasgmStyle,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (widget.game.qr != null &&
                                        widget.game.qr!.isNotEmpty) ...[
                                      const SizedBox(width: 24),
                                      _buildQrCode(
                                        widget.game.qr!,
                                        cleanBaseUrl,
                                        size: 100,
                                      ),
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
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
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
                                              forceTasgm:
                                                  widget.option.isTasgmStyle,
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
