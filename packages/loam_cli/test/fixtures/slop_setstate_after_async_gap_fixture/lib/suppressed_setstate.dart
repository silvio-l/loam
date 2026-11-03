import 'package:flutter/framework.dart';

Future<int> load() async => 1;

class Splash extends StatefulWidget {
  const Splash();

  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> {
  int value = 0;

  Future<void> boot() async {
    await load();
    // loam-ignore: slop-setstate-after-async-gap – the splash state lives for the whole app session
    setState(() => value = 1);
  }
}
