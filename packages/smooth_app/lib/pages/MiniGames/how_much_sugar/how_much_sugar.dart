import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/data_models/continuous_scan_model.dart';
import 'package:smooth_app/data_models/partial_product_list.dart';
import 'package:smooth_app/data_models/product_list.dart';
import 'package:smooth_app/data_models/product_list_supplier.dart';
import 'package:smooth_app/data_models/product_query_model.dart';
import 'package:smooth_app/database/dao_product.dart';
import 'package:smooth_app/database/dao_product_list.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/generic_lib/widgets/images/smooth_image.dart';
import 'package:smooth_app/pages/MiniGames/mini_games_engine.dart';
import 'package:smooth_app/query/paged_product_query.dart';
import 'package:smooth_app/query/paged_search_product_query.dart';
import 'package:smooth_app/query/product_query.dart';
import 'package:smooth_app/query/search_products_manager.dart';

class HowMuchSugarGame extends StatefulWidget {
  final Function(int score) onGameComplete;
  final Map<String, dynamic> gameArgs;

  const HowMuchSugarGame(
      {Key? key, required this.onGameComplete, this.gameArgs = const {}})
      : super(key: key);

  @override
  _HowMuchSugarGameState createState() => _HowMuchSugarGameState();
}

class _HowMuchSugarGameState extends State<HowMuchSugarGame>
    with TickerProviderStateMixin {
  late SugarGuessEngine _engine;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _engine = SugarGuessEngine(
        context: context,
        onScoreUpdate: (int score) {},
        onGameComplete: (int finalScore) {
          widget.onGameComplete(finalScore);
        },
        vsync: this,
        gameArgs: widget.gameArgs);
    _initializeEngine();
  }

  Future<void> _initializeEngine() async {
    await _engine.initialize();
    if (mounted) {
      setState(() {
        _initialized = true;
      });
      _engine.start();
    }
  }

  @override
  void dispose() {
    _engine.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return ValueListenableBuilder<GameState>(
      valueListenable: _engine.currentStateNotifier,
      builder: (context, state, _) {
        return state.render();
      },
    );
  }
}

class SugarGuessEngine extends MiniGamesEngine {
  final TickerProvider vsync;
  final BuildContext context;
  final Map<String, dynamic> gameArgs;

  late ValueNotifier<GameState> currentStateNotifier;
  GameState get currentState => currentStateNotifier.value;
  set currentState(GameState state) => currentStateNotifier.value = state;

  final ValueNotifier<int> roundsPlayedNotifier = ValueNotifier(0);
  int get roundsPlayed => roundsPlayedNotifier.value;
  set roundsPlayed(int value) => roundsPlayedNotifier.value = value;

  final ValueNotifier<int> timeRemainingNotifier = ValueNotifier(0);
  int get timeRemaining => timeRemainingNotifier.value;
  set timeRemaining(int value) => timeRemainingNotifier.value = value;

  final ValueNotifier<int> scoreNotifier = ValueNotifier(0);
  int get currentScore => scoreNotifier.value;
  set currentScore(int value) => scoreNotifier.value = value;

  final ValueNotifier<Product?> currentProductNotifier = ValueNotifier(null);
  Product? get currentProduct => currentProductNotifier.value;
  set currentProduct(Product? value) => currentProductNotifier.value = value;

  final ValueNotifier<int> userGuessNotifier = ValueNotifier(5);
  int get userGuess => userGuessNotifier.value;
  set userGuess(int value) => userGuessNotifier.value = value;

  final ValueNotifier<bool> hasGuessedNotifier = ValueNotifier(false);
  bool get hasGuessed => hasGuessedNotifier.value;
  set hasGuessed(bool value) => hasGuessedNotifier.value = value;

  final ValueNotifier<bool> showingAnimationNotifier = ValueNotifier(false);
  bool get showingAnimation => showingAnimationNotifier.value;
  set showingAnimation(bool value) => showingAnimationNotifier.value = value;

  int totalRounds = 5;
  int timePerRound = 15;

  Timer? gameTimer;

  final List<Product> products = <Product>[];

  final Map<String, bool> _animationDisposed = {};

  SugarGuessEngine({
    required this.context,
    required Function onScoreUpdate,
    required Function onGameComplete,
    required this.vsync,
    required this.gameArgs,
  }) : super(
            context: context,
            onScoreUpdate: onScoreUpdate,
            onGameComplete: onGameComplete,
            gameArgs: gameArgs) {
    currentStateNotifier = ValueNotifier<GameState>(EmptyState(this));

    if (gameArgs.containsKey('totalRounds')) {
      totalRounds = gameArgs['totalRounds'];
    }

    if (gameArgs.containsKey('timePerRound')) {
      timePerRound = gameArgs['timePerRound'];
    }
  }

  @override
  Future<void> initialize() async {
    score = ScoreManager();
    asset = AssetManager();
    animation = AnimationManager(vsync);

    await score.loadScores();
    currentScore = score.getBestScore('sugar_guess', 'player');
    onScoreUpdate(currentScore);

    currentState = IntroState(this);

    await loadProducts();

    List<String> networkAssetPaths = [
      'https://www.kindpng.com/picc/m/604-6041708_sugar-cube-png-cartoon-transparent-png.png'
    ];
    await asset.preloadNetworkAssets(networkAssetPaths);
  }

  Future<void> loadProducts() async {
    if (gameArgs.containsKey('productList') &&
        gameArgs['productList'] is List<String>) {
      List<String> productList = gameArgs['productList'];
      if (productList.isNotEmpty) {
        await _loadProductsFromList(productList);
        return;
      }
    }

    List<String> productList = [
      '8886467122446',
      '8901764061257',
      '7622201710606',
      '8901725015879',
      '8901262070546',
      '8901233030548',
      '8901058903164',
      '8901719117183',
    ];

    await _loadProductsFromList(productList);
  }

  Future<void> _loadProductsFromList(List<String> productList) async {
    final db = Provider.of<LocalDatabase>(context, listen: false);
    final dao = DaoProduct(db);

    for (final String barcode in productList) {
      final Product? result = await dao.get(barcode);
      if (result != null &&
          result.nutriments
                  ?.getValue(Nutrient.sugars, PerSize.oneHundredGrams) !=
              null) {
        products.add(result);
      }
    }

    if (products.isEmpty) {
      throw Exception('Failed to load any products');
    }

    products.shuffle();
  }

  @override
  void start() {
    isRunning = true;
    currentState.enter();
  }

  @override
  void pause() {
    isRunning = false;
    if (gameTimer != null && gameTimer!.isActive) {
      gameTimer!.cancel();
    }
  }

  @override
  void resume() {
    if (!isRunning) {
      isRunning = true;
      startTimer();
    }
  }

  @override
  void reset() {
    roundsPlayed = 0;
    currentScore = 0;
    score.resetScore('sugar_guess', 'player');
    products.shuffle();

    if (gameTimer != null && gameTimer!.isActive) {
      gameTimer!.cancel();
    }

    safelyDisposeAnimations();
    _animationDisposed.clear();

    if (isRunning) {
      currentState.exit();
      currentState = IntroState(this);
      currentState.enter();
    }
  }

  @override
  void update() {
    if (isRunning) {
      currentState.update(const Duration(milliseconds: 16));
    }
  }

  @override
  void stop() {
    isRunning = false;
    if (gameTimer != null && gameTimer!.isActive) {
      gameTimer!.cancel();
    }

    safelyDisposeAnimations();

    if (animation != null) {
      animation.dispose();
    }

    currentStateNotifier.dispose();
    roundsPlayedNotifier.dispose();
    timeRemainingNotifier.dispose();
    scoreNotifier.dispose();
    currentProductNotifier.dispose();
    userGuessNotifier.dispose();
    hasGuessedNotifier.dispose();
    showingAnimationNotifier.dispose();

    score.saveScores();
  }

  void safelyDisposeAnimations() {
    animation.controllers.forEach((id, controller) {
      try {
        if (!(_animationDisposed[id] ?? false)) {
          if (controller.isAnimating) {
            controller.stop();
          }
          controller.dispose();
          _animationDisposed[id] = true;
        }
      } catch (e) {}
    });
  }

  void changeState(GameState newState) {
    if (isRunning) {
      currentState.exit();
      currentState = newState;
      currentState.enter();
    }
  }

  void startNewRound() {
    if (roundsPlayed >= totalRounds || products.isEmpty) {
      changeState(GameOverState(this));
      return;
    }

    int productIndex = roundsPlayed % products.length;
    currentProduct = products[productIndex];

    hasGuessed = false;
    userGuess = 5;
    showingAnimation = false;

    timeRemaining = timePerRound;
    startTimer();

    if (currentState is! GameplayState) {
      changeState(GameplayState(this));
    }
  }

  void startTimer() {
    if (gameTimer != null && gameTimer!.isActive) {
      gameTimer!.cancel();
    }

    gameTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (timeRemaining <= 0 || !isRunning) {
        timer.cancel();
        if (!hasGuessed && isRunning) {
          submitGuess(userGuess);
        }
      } else {
        timeRemaining--;
        onScoreUpdate(currentScore);
      }
    });
  }

  void submitGuess(int guess) {
    if (hasGuessed || currentProduct == null) return;

    hasGuessed = true;
    if (gameTimer != null && gameTimer!.isActive) {
      gameTimer!.cancel();
    }

    final double? sugarGrams = currentProduct!.nutriments
        ?.getValue(Nutrient.sugars, PerSize.oneHundredGrams);
    final int sugarCubes = sugarGrams != null ? (sugarGrams / 4).round() : 0;
    int difference = (guess - sugarCubes).abs();
    int pointsThisRound = max(10 - difference, 0) * 10;

    score.addScore('sugar_guess', 'player', pointsThisRound);
    currentScore += pointsThisRound;
    onScoreUpdate(currentScore);

    showingAnimation = true;

    Future.delayed(const Duration(seconds: 3), () {
      if (isRunning) {
        roundsPlayed++;
        startNewRound();
      }
    });
  }

  int getCurrentScore() {
    return currentScore;
  }

  int getSugarCubes(Product product) {
    final double? sugarGrams =
        product.nutriments?.getValue(Nutrient.sugars, PerSize.oneHundredGrams);
    return sugarGrams != null ? (sugarGrams / 4).round() : 0;
  }

  AnimationController createTrackedController({
    required String id,
    required Duration duration,
  }) {
    if (_animationDisposed[id] == true) {
      animation.controllers.remove(id);
      _animationDisposed[id] = false;
    }

    final controller = animation.createController(
      id: id,
      duration: duration,
    );

    return controller;
  }

  void safelyDisposeController(String id) {
    final controller = animation.getController(id);
    if (controller != null && !(_animationDisposed[id] ?? false)) {
      try {
        if (controller.isAnimating) {
          controller.stop();
        }
        controller.dispose();
        _animationDisposed[id] = true;
      } catch (e) {}
    }
  }
}

class EmptyState extends GameState {
  EmptyState(SugarGuessEngine engine) : super(engine);

  @override
  void enter() {}

  @override
  void exit() {}

  @override
  void update(Duration deltaTime) {}

  @override
  Widget render() {
    return const SizedBox.shrink();
  }
}

class IntroState extends GameState {
  IntroState(SugarGuessEngine engine) : super(engine);

  static const String animationId = 'intro';

  @override
  void enter() {
    final SugarGuessEngine gameEngine = engine as SugarGuessEngine;

    final controller = gameEngine.createTrackedController(
      id: animationId,
      duration: const Duration(milliseconds: 800),
    );

    gameEngine.animation.createAnimation(
      id: 'introScale',
      controllerId: animationId,
      curve: Curves.easeOutBack,
      begin: 0.5,
      end: 1.0,
    );

    controller.forward();
  }

  @override
  void exit() {
    final SugarGuessEngine gameEngine = engine as SugarGuessEngine;

    gameEngine.safelyDisposeController(animationId);
  }

  @override
  void update(Duration deltaTime) {}

  @override
  Widget render() {
    final SugarGuessEngine gameEngine = engine as SugarGuessEngine;
    final Animation<double>? scaleAnimation =
        gameEngine.animation.getAnimation('introScale');

    return Center(
      child: ScaleTransition(
        scale: scaleAnimation ?? const AlwaysStoppedAnimation(1.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'How Much Sugar?',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            const Text(
              'Guess how many sugar cubes are in each product!\n(1 sugar cube = 4g of sugar)',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            Text(
              'Your Best Score: ${gameEngine.gameArgs["high_score"]}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                gameEngine.startNewRound();
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Text('Start Game', style: TextStyle(fontSize: 20)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GameplayState extends GameState {
  GameplayState(SugarGuessEngine engine) : super(engine);

  static const String animationId = 'product';

  final Map<int, List<AnimationController>> _sugarCubeControllers = {};

  @override
  void enter() {
    final SugarGuessEngine gameEngine = engine as SugarGuessEngine;

    final controller = gameEngine.createTrackedController(
      id: animationId,
      duration: const Duration(milliseconds: 500),
    );

    gameEngine.animation.createAnimation(
      id: 'productFade',
      controllerId: animationId,
      curve: Curves.easeIn,
      begin: 0.0,
      end: 1.0,
    );

    controller.forward();
  }

  @override
  void exit() {
    final SugarGuessEngine gameEngine = engine as SugarGuessEngine;

    gameEngine.safelyDisposeController(animationId);

    _sugarCubeControllers.forEach((round, controllers) {
      for (var controller in controllers) {
        try {
          if (controller.isAnimating) {
            controller.stop();
          }
          controller.dispose();
        } catch (e) {}
      }
    });
    _sugarCubeControllers.clear();
  }

  @override
  void update(Duration deltaTime) {}

  @override
  Widget render() {
    final SugarGuessEngine gameEngine = engine as SugarGuessEngine;
    final Animation<double>? fadeAnimation =
        gameEngine.animation.getAnimation('productFade');

    if (gameEngine.currentProduct == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ValueListenableBuilder<int>(
                      valueListenable: gameEngine.scoreNotifier,
                      builder: (context, score, _) {
                        return Text(
                          'Score: $score',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        );
                      }),
                  ValueListenableBuilder<int>(
                      valueListenable: gameEngine.roundsPlayedNotifier,
                      builder: (context, roundsPlayed, _) {
                        return Text(
                          'Round: ${roundsPlayed + 1}/${gameEngine.totalRounds}',
                          style: const TextStyle(fontSize: 18),
                        );
                      }),
                  ValueListenableBuilder<int>(
                      valueListenable: gameEngine.timeRemainingNotifier,
                      builder: (context, timeRemaining, _) {
                        return Text(
                          'Time: ${timeRemaining}s',
                          style: TextStyle(
                            fontSize: 18,
                            color:
                                timeRemaining < 5 ? Colors.red : Colors.black,
                            fontWeight: timeRemaining < 5
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        );
                      }),
                ],
              ),
              const SizedBox(height: 30),
              FadeTransition(
                opacity: fadeAnimation ?? const AlwaysStoppedAnimation(1.0),
                child: ValueListenableBuilder<Product?>(
                    valueListenable: gameEngine.currentProductNotifier,
                    builder: (context, currentProduct, _) {
                      if (currentProduct == null) {
                        return const SizedBox.shrink();
                      }

                      return Column(
                        children: <Widget>[
                          SmoothImage(
                              width: 200,
                              height: 200,
                              fit: BoxFit.contain,
                              imageProvider:
                                  NetworkImage(currentProduct.imageFrontUrl!)),
                          const SizedBox(height: 20),
                          Text(
                            currentProduct.productName ?? 'Unknown Product',
                            style: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      );
                    }),
              ),
              const SizedBox(height: 40),
              ValueListenableBuilder<bool>(
                  valueListenable: gameEngine.hasGuessedNotifier,
                  builder: (context, hasGuessed, _) {
                    return hasGuessed
                        ? _buildResultDisplay(gameEngine)
                        : _buildGuessInput(gameEngine);
                  }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuessInput(SugarGuessEngine gameEngine) {
    return Column(
      children: [
        const Text(
          'How many sugar cubes?',
          style: TextStyle(fontSize: 20),
        ),
        const SizedBox(height: 15),
        ValueListenableBuilder<int>(
            valueListenable: gameEngine.userGuessNotifier,
            builder: (context, sliderValue, _) {
              return Column(
                children: [
                  Text(
                    sliderValue.toString(),
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  Slider(
                    value: sliderValue.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: sliderValue.toString(),
                    onChanged: (value) {
                      gameEngine.userGuess = value.toInt();
                    },
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      gameEngine.submitGuess(sliderValue);
                    },
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      child: Text('Guess!', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ],
              );
            }),
      ],
    );
  }

  Widget _buildResultDisplay(SugarGuessEngine gameEngine) {
    if (gameEngine.currentProduct == null) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<int>(
        valueListenable: gameEngine.userGuessNotifier,
        builder: (context, userGuess, _) {
          final double? sugarGrams = gameEngine.currentProduct!.nutriments
              ?.getValue(Nutrient.sugars, PerSize.oneHundredGrams);
          final int sugarCubes =
              sugarGrams != null ? (sugarGrams / 4).round() : 0;
          int difference = (userGuess - sugarCubes).abs();
          int pointsThisRound = max(10 - difference, 0) * 10;

          String resultText;
          Color resultColor;

          if (difference == 0) {
            resultText = 'Perfect! +${pointsThisRound} points';
            resultColor = Colors.green;
          } else if (difference <= 2) {
            resultText = 'Close! +${pointsThisRound} points';
            resultColor = Colors.blue;
          } else {
            resultText = 'Not quite. +${pointsThisRound} points';
            resultColor = Colors.orange;
          }

          return Column(
            children: [
              Text(
                'Your guess: $userGuess',
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(height: 10),
              Text(
                'Actual sugar cubes: $sugarCubes',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),
              Text(
                resultText,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: resultColor),
              ),
              const SizedBox(height: 20),
              ValueListenableBuilder<bool>(
                  valueListenable: gameEngine.showingAnimationNotifier,
                  builder: (context, showingAnimation, _) {
                    return showingAnimation
                        ? SizedBox(
                            height: 120,
                            child: _buildSugarCubeAnimation(
                                gameEngine, sugarCubes),
                          )
                        : const SizedBox.shrink();
                  }),
            ],
          );
        });
  }

  Widget _buildSugarCubeAnimation(SugarGuessEngine gameEngine, int sugarCubes) {
    final int currentRound = gameEngine.roundsPlayed;

    if (!_sugarCubeControllers.containsKey(currentRound)) {
      final controllers = <AnimationController>[];

      for (int i = 0; i < min(sugarCubes, 10); i++) {
        try {
          final controller = AnimationController(
            duration: Duration(milliseconds: 800 + (i * 100)),
            vsync: gameEngine.vsync,
          );

          controllers.add(controller);
          controller.forward();
        } catch (e) {}
      }

      _sugarCubeControllers[currentRound] = controllers;
    }

    final controllers = _sugarCubeControllers[currentRound] ?? [];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        min(sugarCubes, 8),
        (index) {
          if (index >= controllers.length) {
            return const SizedBox.shrink();
          }

          return AnimatedBuilder(
            animation: controllers[index],
            builder: (context, child) {
              return Padding(
                padding: const EdgeInsets.all(3.0),
                child: Transform.translate(
                  offset: Offset(
                    0,
                    (1 - controllers[index].value) * 400,
                  ),
                  child: Opacity(
                    opacity: controllers[index].value,
                    child: Image(
                        width: 30,
                        height: 30,
                        image: gameEngine.asset.getAsset(
                            'https://www.kindpng.com/picc/m/604-6041708_sugar-cube-png-cartoon-transparent-png.png')),
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

class GameOverState extends GameState {
  GameOverState(SugarGuessEngine engine) : super(engine);

  static const String animationId = 'gameOver';

  @override
  void enter() {
    final SugarGuessEngine gameEngine = engine as SugarGuessEngine;

    final controller = gameEngine.createTrackedController(
      id: animationId,
      duration: const Duration(milliseconds: 800),
    );

    gameEngine.animation.createAnimation(
      id: 'gameOverScale',
      controllerId: animationId,
      curve: Curves.elasticOut,
      begin: 0.2,
      end: 1.0,
    );

    controller.forward();

    gameEngine.score.saveScores();

    gameEngine.onGameComplete(gameEngine.getCurrentScore());
  }

  @override
  void exit() {
    final SugarGuessEngine gameEngine = engine as SugarGuessEngine;

    gameEngine.safelyDisposeController(animationId);
  }

  @override
  void update(Duration deltaTime) {}

  @override
  Widget render() {
    final SugarGuessEngine gameEngine = engine as SugarGuessEngine;
    final Animation<double>? scaleAnimation =
        gameEngine.animation.getAnimation('gameOverScale');

    return Center(
      child: ScaleTransition(
        scale: scaleAnimation ?? const AlwaysStoppedAnimation(1.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Game Over!',
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            ValueListenableBuilder<int>(
                valueListenable: gameEngine.scoreNotifier,
                builder: (context, score, _) {
                  return Text(
                    'Final Score: $score',
                    style: const TextStyle(fontSize: 28),
                  );
                }),
            const SizedBox(height: 50),
            ElevatedButton(
              onPressed: () {
                gameEngine.reset();
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Text('Play Again', style: TextStyle(fontSize: 20)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
