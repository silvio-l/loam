import 'package:unused_exports_fixture/all_kinds.dart';

/// Consumer that references one symbol of each declaration kind from
/// all_kinds.dart and all_kinds_part.dart, so those symbols are not reported
/// as unused by the rule.
class KindsConsumer with UsedMixin {
  /// References [usedFunction].
  String callFunction() => usedFunction();

  /// References [usedGetter].
  int readGetter() => usedGetter;

  /// References [usedSetter].
  void writeSetter(int v) => usedSetter = v;

  /// References [UsedEnum].
  UsedEnum pickEnum() => UsedEnum.alpha;

  /// References [UsedExtension] (via call on a String literal).
  String callExtension() => 'hello'.exclaimed;

  /// References [UsedTypedef].
  UsedTypedef buildTypedef() =>
      (n) => n.toString();

  /// References [usedVariable].
  String readVariable() => usedVariable;

  /// References [UsedPartClass] (declared in all_kinds_part.dart).
  UsedPartClass makePartClass() => UsedPartClass();
}
