import 'package:flutter/framework.dart';

class Suppressed {
  // loam-ignore: slop-undisposed-resource – the controller lives for the whole process
  final _controller = TextEditingController();

  void dispose() {}
}
