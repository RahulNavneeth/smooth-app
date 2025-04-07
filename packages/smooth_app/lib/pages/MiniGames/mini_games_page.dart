import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:smooth_app/pages/MiniGames/how_much_sugar/how_much_sugar.dart';

class MiniGamesPage extends StatefulWidget {
  const MiniGamesPage({Key? key}) : super(key: key);

  @override
  State<MiniGamesPage> createState() => _MiniGamesPageState();
}

class _MiniGamesPageState extends State<MiniGamesPage> {
  int highScore = 0;
  Key gameKey = UniqueKey();

  void _onGameComplete(int score) {
    setState(() {
      if (score > highScore) {
        highScore = score;
      }
      gameKey = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: HowMuchSugarGame(
        key: gameKey,
        onGameComplete: _onGameComplete,
        gameArgs: {'high_score': highScore},
      ),
    );
  }
}
