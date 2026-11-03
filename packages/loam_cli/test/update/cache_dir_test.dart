import 'package:loam/src/update/update_state.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  String? dir(Map<String, String> env, {bool mac = false, bool win = false}) =>
      FileUpdateStateStore.cacheDirFor(env, isMacOS: mac, isWindows: win);

  test('missing or empty variables mean no store, never a relative path', () {
    expect(dir({}), isNull);
    expect(dir({'HOME': ''}), isNull);
    expect(dir({}, mac: true), isNull);
    expect(dir({'LOCALAPPDATA': ''}, win: true), isNull);
  });

  test('resolves per platform', () {
    expect(dir({'HOME': '/h'}), p.join('/h', '.cache', 'loam'));
    expect(dir({'HOME': '/h', 'XDG_CACHE_HOME': '/x'}), p.join('/x', 'loam'));
    expect(
      dir({'HOME': '/h'}, mac: true),
      p.join('/h', 'Library', 'Caches', 'loam'),
    );
    expect(
      dir({
        'LOCALAPPDATA': '/l',
        'HOME': '/h',
        'XDG_CACHE_HOME': '/x',
      }, win: true),
      p.join('/l', 'loam'),
    );
  });
}
