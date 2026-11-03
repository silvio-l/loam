import 'package:loam/src/model/project_path.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('projectRelativePosixPath', () {
    test('Windows paths come out with forward slashes', () {
      expect(
        projectRelativePosixPath(
          r'C:\proj\lib\widgets\wp_tabs.dart',
          r'C:\proj',
          context: p.windows,
        ),
        'lib/widgets/wp_tabs.dart',
      );
    });

    test('POSIX paths stay unchanged', () {
      expect(
        projectRelativePosixPath(
          '/proj/lib/widgets/wp_tabs.dart',
          '/proj',
          context: p.posix,
        ),
        'lib/widgets/wp_tabs.dart',
      );
    });
  });
}
