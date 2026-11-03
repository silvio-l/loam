import 'dart:convert';

import 'package:unused_exports_fixture/dynamic_members.dart';

/// Uses [DynamicHost] as a type only, so the class is referenced.
String encodeHost(DynamicHost host) => jsonEncode(host);
