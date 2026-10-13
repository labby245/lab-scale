/// Checks GitHub Releases for a newer LabScale.
///
/// Deliberately does not download or install anything: an available update is
/// shown as a banner that opens the release page, and the user installs it the
/// same way they installed this copy. For an open-source app that keeps the
/// trust story simple — nothing runs that the user did not fetch themselves.
///
/// Every failure (offline, rate-limited, odd JSON) ends quietly as "unknown".
/// The app must never fail to start, or nag, because of this check.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_links.dart';

class AvailableUpdate {
  const AvailableUpdate({required this.version, required this.pageUrl});

  final String version;
  final String pageUrl;
}

enum UpdateStatus { available, upToDate, failed }

class UpdateResult {
  const UpdateResult(this.status, [this.update]);

  final UpdateStatus status;
  final AvailableUpdate? update;
}

class UpdateChecker {
  UpdateChecker({
    this.apiUrl = 'https://api.github.com/repos/$kRepo/releases/latest',
    HttpClient Function()? clientFactory,
  }) : _newClient = clientFactory ?? HttpClient.new;

  final String apiUrl;
  final HttpClient Function() _newClient;

  /// Compares the latest published release against [currentVersion].
  ///
  /// The GitHub API allows 60 unauthenticated requests per hour per IP; one
  /// call per launch is far inside that, and a refusal is just [failed].
  Future<UpdateResult> check(String currentVersion) async {
    final client = _newClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse(apiUrl));
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'LabScale');
      final response =
          await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return const UpdateResult(UpdateStatus.failed);
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 15));
      return parseRelease(body, currentVersion);
    } on Object {
      return const UpdateResult(UpdateStatus.failed);
    } finally {
      client.close(force: true);
    }
  }

  /// Reads a `releases/latest` payload. Split out so it can be tested without
  /// a network.
  static UpdateResult parseRelease(String body, String currentVersion) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return const UpdateResult(UpdateStatus.failed);
    }
    if (decoded is! Map) return const UpdateResult(UpdateStatus.failed);
    final tag = decoded['tag_name'];
    final page = decoded['html_url'];
    if (tag is! String || parseVersion(tag) == null) {
      return const UpdateResult(UpdateStatus.failed);
    }
    if (!isNewerVersion(tag, currentVersion)) {
      return const UpdateResult(UpdateStatus.upToDate);
    }
    final version = tag.startsWith('v') ? tag.substring(1) : tag;
    return UpdateResult(
      UpdateStatus.available,
      AvailableUpdate(
        version: version,
        // Only ever open our own release pages, whatever the payload says.
        pageUrl: page is String && page.startsWith('$kRepoUrl/')
            ? page
            : kReleasesUrl,
      ),
    );
  }
}

/// The numbers of "1.2.3" or "v1.2.3"; any "-beta"/"+build" part is dropped.
/// Null when the string is not a version.
List<int>? parseVersion(String raw) {
  var core = raw.trim();
  if (core.startsWith('v')) core = core.substring(1);
  core = core.split(RegExp(r'[-+]')).first;
  final parts = core.split('.');
  if (parts.isEmpty || parts.length > 4) return null;
  final numbers = <int>[];
  for (final part in parts) {
    final n = int.tryParse(part);
    if (n == null || n < 0) return null;
    numbers.add(n);
  }
  return numbers;
}

/// True only when [candidate] is strictly newer than [current]. Unreadable
/// versions compare as equal, so a parsing slip never offers a phantom
/// update — and a local build ahead of the last release is never "updated"
/// backwards.
bool isNewerVersion(String candidate, String current) {
  final a = parseVersion(candidate);
  final b = parseVersion(current);
  if (a == null || b == null) return false;
  final length = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}
