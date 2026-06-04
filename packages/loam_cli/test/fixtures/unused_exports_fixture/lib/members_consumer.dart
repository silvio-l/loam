import 'package:unused_exports_fixture/members.dart';

/// Consumer that references specific members from members.dart so they are
/// NOT reported as unused by the rule.
class MembersConsumer {
  final _host = MemberHost();

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
}
