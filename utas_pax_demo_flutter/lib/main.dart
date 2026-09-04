import 'dart:convert';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
    
    final currentBaseUrl = '$protocol://$host:$port/';
    
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
  final Color color;

  Game({
    required this.name,
    required this.url,
    required this.author,
    required this.color,
  });

  factory Game.fromJson(Map<String, dynamic> json, int index) {
    // Generate a color based on index for the Hero animation
    final colors = [
      const Color(0xFF123456), // Deep Blue
      const Color(0xFF2D5A27), // Forest Green
      const Color(0xFF5D4037), // Brown
      const Color(0xFF4527A0), // Deep Purple
      const Color(0xFF006064), // Dark Cyan
      const Color(0xFF827717), // Olive
      const Color(0xFFBF360C), // Deep Orange
      const Color(0xFF37474F), // Blue Grey
      const Color(0xFF880E4F), // Maroon
    ];
    return Game(
      name: json['name'] as String,
      url: json['url'] as String,
      author: json['author'] as String? ?? 'Unknown',
      color: colors[index % colors.length],
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
          .asMap()
          .entries
          .map((entry) => Game.fromJson(entry.value, entry.key))
          .toList();
    } else {
      throw Exception('Failed to load games');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
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

          final games = snapshot.data!;
          return GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 0,
              mainAxisSpacing: 0,
              childAspectRatio: 16 / 9,
            ),
            itemCount: games.length,
            itemBuilder: (context, index) {
              final game = games[index];
              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) =>
                          GameDetailPage(
                        game: game,
                        baseUrl: widget.baseUrl,
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
                  tag: game.name,
                  child: Material(
                    color: game.color,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            game.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            game.author,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
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
        iframe.allow = 'fullscreen; autoplay';
        iframe.setAttribute('allowfullscreen', 'true');
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.game.name),
            Text(
              widget.game.author,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        backgroundColor: widget.game.color,
        foregroundColor:
            widget.game.color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
      ),
      body: Hero(
        tag: widget.game.name,
        child: Material(
          color: widget.game.color,
          child: SizedBox.expand(
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
                          ),
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          widget.game.author,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
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
