import 'package:unused_exports_fixture/used_class.dart';

/// A lib-level class that uses UsedClass — this cross-file reference
/// proves that UsedClass should NOT be reported as unused.
class Consumer {
  final UsedClass _used = UsedClass();

  String consume() => _used.name;
}
