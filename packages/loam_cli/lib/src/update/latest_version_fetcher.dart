import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

/// Interface for fetching the latest published version from pub.dev.
///
/// Implementations are injected into [UpdateChecker] so that the network
/// call can be replaced by a [FakeLatestVersionFetcher] in tests.
abstract interface class LatestVersionFetcher {
  /// Fetches the latest stable version for the given [packageName].
  ///
  /// Returns `null` on any error (network, timeout, malformed JSON, non-2xx).
  Future<Version?> fetchLatest(String packageName);
}

/// Parses the pub.dev JSON response body and returns the `latest.version`.
///
/// Extracted as a top-level function so that JSON→Version parsing is testable
/// without any network call (acceptance criterion: parse separated from HTTP).
///
/// Returns `null` if [json] is malformed or missing the expected fields.
Version? parsePubDevVersion(String json) {
  try {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final latest = decoded['latest'] as Map<String, dynamic>?;
    final versionStr = latest?['version'] as String?;
    if (versionStr == null) return null;
    return Version.parse(versionStr);
  } catch (_) {
    return null;
  }
}

/// Default [LatestVersionFetcher] that queries `https://pub.dev/api/packages/`.
///
/// Uses `dart:io` [HttpClient] with a hard 2-second timeout. Any error
/// (timeout, connection refused, non-2xx, malformed JSON) is silently
/// swallowed and `null` is returned.
class PubDevLatestVersionFetcher implements LatestVersionFetcher {
  /// Creates a [PubDevLatestVersionFetcher].
  const PubDevLatestVersionFetcher();

  @override
  Future<Version?> fetchLatest(String packageName) async {
    final client = HttpClient();
    try {
      client.connectionTimeout = const Duration(seconds: 2);
      final uri = Uri.parse('https://pub.dev/api/packages/$packageName');
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 2));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 2),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        return null;
      }

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 2));
      return parsePubDevVersion(body);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
