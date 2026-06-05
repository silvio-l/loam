import 'package:unused_exports_fixture/members.dart';

/// Consumer that references specific members from members.dart so they are
/// NOT reported as unused by the rule.
class MembersConsumer {
  final _host = MemberHost();

  /// Uses [AppLoggerLike] at the class level (so it is not reported as an unused
  /// class) but deliberately NEVER calls its `fatal` — that member stays unused.
  final _appLogger = AppLoggerLike();

  /// A different type whose `fatal` IS called — proves that calling
  /// `SdkStyleLogger.fatal` must not suppress `AppLoggerLike.fatal`.
  /// (Plain backticks, not doc references, so these comments are not usages.)
  final _sdkLogger = SdkStyleLogger();

  /// References `AppLoggerLike.note` only (NOT its `fatal`).
  String logNote() => _appLogger.note('hello');

  /// References `SdkStyleLogger.fatal` — the colliding name on the other type.
  Future<void> logFatal() => _sdkLogger.fatal('boom');

  /// References [MemberHost.usedMethod].
  String callUsedMethod() => _host.usedMethod();

  /// References [MemberHost.usedField].
  String readUsedField() => _host.usedField;

  /// References [MemberHost.usedMemberGetter].
  int readUsedGetter() => _host.usedMemberGetter;

  /// References [MemberHost.usedMemberSetter].
  void writeUsedSetter(int v) => _host.usedMemberSetter = v;

  /// References [MemberEnum.usedEnumMethod].
  String callEnumMethod() => MemberEnum.alpha.usedEnumMethod();

  /// References [StaticFieldHolder.usedStaticField] via ClassName.field access.
  String readStaticField() => StaticFieldHolder.usedStaticField;

  /// References [StaticFieldHolder.usedStaticMap] via ClassName.field index access.
  String? readStaticMap(String k) => StaticFieldHolder.usedStaticMap[k];

  /// References [StaticFieldHolder.usedStaticMethod] via ClassName.method() call.
  String callStaticMethod() => StaticFieldHolder.usedStaticMethod();

  /// References [StaticFieldHolder.usedStaticGetter] via ClassName.getter read.
  int readStaticGetter() => StaticFieldHolder.usedStaticGetter;
}
