// Forbidden: core depends on features.
import '../features/home.dart';
import 'base.dart';

Home leak() => Home(Base());
