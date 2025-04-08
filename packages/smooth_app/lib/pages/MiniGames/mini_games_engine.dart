import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

abstract class MiniGamesEngine {
  final BuildContext context;
  final Function onScoreUpdate;
  final Function onGameComplete;

  final Map<String, dynamic> gameArgs;

  bool isRunning = false;

  late ScoreManager score;
  late AssetManager asset;
  late AnimationManager animation;

  MiniGamesEngine({
    required this.context,
    required this.onScoreUpdate,
    required this.onGameComplete,
    this.gameArgs = const {},
  });

  void initialize();
  void start();
  void pause();
  void resume();
  void reset();
  void update();
  void stop();
}

abstract class GameState {
  final MiniGamesEngine engine;

  GameState(this.engine);

  void enter();
  void exit();
  void update(Duration deltaTime);

  Widget render();
}

class AssetManager {
  final Map<String, dynamic> _assets = {};

  Future<void> preloadAssets(List<String> assetPaths) async {
    for (final String path in assetPaths) {
      final AssetImage image = AssetImage(path);
      _assets[path] = image;
    }
  }

  Future<void> preloadNetworkAssets(List<String> urls) async {
    for (final String url in urls) {
      try {
        final http.Response response = await http.get(Uri.parse(url));

        if (response.statusCode == 200) {
          final Completer<ImageInfo> completer = Completer();
          final ImageStreamListener listener = ImageStreamListener(
            (ImageInfo info, bool _) {
              if (!completer.isCompleted) {
                completer.complete(info);
              }
            },
            onError: (dynamic exception, StackTrace? stackTrace) {
              if (!completer.isCompleted) {
                completer.completeError(exception);
              }
            },
          );

          final NetworkImage image = NetworkImage(url);
          final ImageStream stream = image.resolve(ImageConfiguration());
          stream.addListener(listener);

          await completer.future;
          _assets[url] = image;
        } else {
          print(
              'Failed to load network asset: $url (Status: ${response.statusCode})');
        }
      } catch (e) {
        print('Error loading network asset: $url - $e');
      }
    }
  }

  dynamic getAsset(String path) {
    return _assets[path];
  }

  void clearAssets() {
    _assets.clear();
  }
}

class ScoreManager {
  final Map<String, List<ScoreEntry>> _scores = {};
  static const String _prefsKey = 'sugar_game_scores';

  void addScore(String gameType, String playerName, int score) {
    if (!_scores.containsKey(gameType)) {
      _scores[gameType] = [];
    }

    _scores[gameType]!.add(ScoreEntry(
      playerName: playerName,
      score: score,
      timestamp: DateTime.now(),
    ));

    _scores[gameType]!.sort((a, b) => b.score.compareTo(a.score));

    saveScores();
  }

  List<ScoreEntry> getHighScores(String gameType, {int limit = 10}) {
    if (!_scores.containsKey(gameType)) {
      return [];
    }

    return _scores[gameType]!.take(limit).toList();
  }

  int getBestScore(String gameType, String playerName) {
    if (!_scores.containsKey(gameType)) {
      return 0;
    }

    final playerScores = _scores[gameType]!
        .where((entry) => entry.playerName == playerName)
        .toList();

    if (playerScores.isEmpty) {
      return 0;
    }

    return playerScores.reduce((a, b) => a.score > b.score ? a : b).score;
  }

  Future<void> saveScores() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final Map<String, List<Map<String, dynamic>>> serializedScores = {};

      _scores.forEach((gameType, scoreList) {
        serializedScores[gameType] = scoreList
            .map((entry) => {
                  'playerName': entry.playerName,
                  'score': entry.score,
                  'timestamp': entry.timestamp.toIso8601String(),
                })
            .toList();
      });

      final String jsonString = jsonEncode(serializedScores);
      await prefs.setString(_prefsKey, jsonString);
    } catch (e) {
      print('Error saving scores: $e');
    }
  }

  Future<void> loadScores() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString(_prefsKey);

      if (jsonString == null) return;

      final Map<String, dynamic> decodedJson = jsonDecode(jsonString);

      _scores.clear();

      decodedJson.forEach((gameType, scoreListJson) {
        final List<dynamic> scoreList = scoreListJson as List<dynamic>;
        _scores[gameType] = scoreList
            .map((scoreJson) => ScoreEntry(
                  playerName: scoreJson['playerName'],
                  score: scoreJson['score'],
                  timestamp: DateTime.parse(scoreJson['timestamp']),
                ))
            .toList();
      });
    } catch (e) {
      print('Error loading scores: $e');
    }
  }

  void resetScore(String gameType, String playerName) {
    if (_scores.containsKey(gameType)) {
      _scores[gameType]!.removeWhere((entry) => entry.playerName == playerName);
      saveScores();
    }
  }
}

class ScoreEntry {
  final String playerName;
  final int score;
  final DateTime timestamp;
  ScoreEntry({
    required this.playerName,
    required this.score,
    required this.timestamp,
  });
}

class AnimationManager {
  final Map<String, Animation<double>> _animations = {};
  final Map<String, AnimationController> _controllers = {};
  final TickerProvider _vsync;

  AnimationManager(this._vsync);

  // Add this getter to expose the controllers map
  Map<String, AnimationController> get controllers => _controllers;

  AnimationController createController({
    required String id,
    required Duration duration,
    double initialValue = 0.0,
    double lowerBound = 0.0,
    double upperBound = 1.0,
  }) {
    if (_controllers.containsKey(id)) {
      return _controllers[id]!;
    }

    final controller = AnimationController(
      vsync: _vsync,
      duration: duration,
      lowerBound: lowerBound,
      upperBound: upperBound,
      value: initialValue,
    );

    _controllers[id] = controller;
    return controller;
  }

  Animation<double> createAnimation({
    required String id,
    required String controllerId,
    required Curve curve,
    double begin = 0.0,
    double end = 1.0,
  }) {
    if (!_controllers.containsKey(controllerId)) {
      throw Exception('Controller with ID $controllerId not found');
    }

    final animation = CurvedAnimation(
      parent: _controllers[controllerId]!,
      curve: curve,
    );

    final tween = Tween<double>(begin: begin, end: end).animate(animation);
    _animations[id] = tween;

    return tween;
  }

  Animation<double>? getAnimation(String id) {
    return _animations[id];
  }

  AnimationController? getController(String id) {
    return _controllers[id];
  }

  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    _animations.clear();
  }
}
