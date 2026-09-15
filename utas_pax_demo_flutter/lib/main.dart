import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:web/web.dart' as web;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
    final url = _controller.text.trim();
    if (url.isNotEmpty) {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              GameGridPage(baseUrl: url),
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

  Game({
    required this.name,
    required this.url,
    required this.author,
  });

  factory Game.fromJson(Map<String, dynamic> json) {
    return Game(
      name: json['name'] as String,
      url: json['url'] as String,
      author: json['author'] as String? ?? 'Unknown',
    );
  }
}

class GameGridPage extends StatefulWidget {
  final String baseUrl;
  const GameGridPage({super.key, required this.baseUrl});

  @override
  State<GameGridPage> createState() => _GameGridPageState();
}

class _GameGridPageState extends State<GameGridPage> {
  late Future<List<Game>> _gamesFuture;

  @override
  void initState() {
    super.initState();
    _gamesFuture = _fetchGames();
  }

  Future<List<Game>> _fetchGames() async {
    final cleanBaseUrl = widget.baseUrl.endsWith('/')
        ? widget.baseUrl.substring(0, widget.baseUrl.length - 1)
        : widget.baseUrl;
    final response = await http.get(Uri.parse('$cleanBaseUrl/games.json'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      final gamesList = data['games'] as List;
      return gamesList
          .map((json) => Game.fromJson(json))
          .toList();
    } else {
      throw Exception('Failed to load games');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        toolbarHeight: 64,
        //backgroundColor: const Color(0xFFF9F9F9),
        //foregroundColor: Colors.black,
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Study Games at UTAS", style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
            child: Image.network(
              //"${cleanBaseUrl}/thumbs/utas.png",
              "${widget.baseUrl}thumbs/utas_dark.png",
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 200,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text(
                      'Logo Placeholder',
                      style: TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<Game>>(
        future: _gamesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No games found'));
          }

          //aspect ratio is whatever fits 3x3 into the remaining space minus the app bar
          final aspectRatio = (MediaQuery.of(context).size.width / 3) /
              ((MediaQuery.of(context).size.height - kToolbarHeight) / 3);

          final games = snapshot.data!;
          return GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
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
        },
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
        video.src = '$cleanBaseUrl/thumbs${widget.game.url}.mp4';
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
    final videoUrl = "$cleanBaseUrl/thumbs${widget.game.url}.mp4";
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
                  tween: Tween<double>(begin: 7.0, end: _isHovered ? 0.0 : 7.0),
                  duration: const Duration(milliseconds: 250),
                  builder: (context, blurValue, child) {
                    // image should be made darker too
                    return Opacity(opacity: 0.5,
                      child: ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(sigmaX: blurValue, sigmaY: blurValue),
                        child: child!,
                      )
                    );
                  },
                  child: SizedBox.expand(
                    child: _useVideo
                        ? PointerInterceptor(
                            child: HtmlElementView(viewType: _videoViewId),
                          )
                        : Image.network(
                            "$cleanBaseUrl/thumbs${widget.game.url}.png",
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  color: Colors.white.withValues(alpha: _isHovered ? 0.0 : 0.2),
                  width: double.infinity,
                  height: double.infinity,
                ),
                Center(
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

  const GameDetailPage({super.key, required this.game, required this.baseUrl});

  @override
  State<GameDetailPage> createState() => _GameDetailPageState();
}

class _GameDetailPageState extends State<GameDetailPage> {
  bool _showHtml = false;
  late String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'html-view-${widget.game.name.replaceAll(' ', '-')}';

    // Register the platform view factory
    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(
      _viewId,
      (int id) {
        final cleanBaseUrl = widget.baseUrl.endsWith('/')
            ? widget.baseUrl.substring(0, widget.baseUrl.length - 1)
            : widget.baseUrl;
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
        // Fallback if no route/animation found
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

  @override
  Widget build(BuildContext context) {
    final cleanBaseUrl = widget.baseUrl.endsWith('/')
        ? widget.baseUrl.substring(0, widget.baseUrl.length - 1)
        : widget.baseUrl;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        toolbarHeight: 64,
        //backgroundColor: const Color(0xFFF9F9F9),
        //foregroundColor: Colors.black,
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(widget.game.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(
              widget.game.author,
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
            child: Image.network(
              //"${cleanBaseUrl}/thumbs/utas.png",
              "$cleanBaseUrl/thumbs/utas_dark.png",
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 200,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text(
                      'Logo Placeholder',
                      style: TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: Hero(
        tag: widget.game.name,
        child: Material(
          color: const Color(0xFF1E1E1E),
          child: SizedBox.expand(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 7.0, sigmaY: 7.0),
                    child: Image.network(
                      "$cleanBaseUrl/thumbs${widget.game.url}.png",
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                SizedBox.expand(
                  child: _showHtml
                      ? PointerInterceptor(
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
