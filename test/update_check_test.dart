import 'package:flutter_test/flutter_test.dart';
import 'package:labscale/core/app_links.dart';
import 'package:labscale/core/update_check.dart';

void main() {
  group('isNewerVersion', () {
    test('only a strictly newer release counts', () {
      expect(isNewerVersion('v2.1.0', '2.0.0'), isTrue);
      expect(isNewerVersion('2.0.1', '2.0.0'), isTrue);
      expect(isNewerVersion('2.0.0', '2.0.0'), isFalse);
      expect(isNewerVersion('1.9.9', '2.0.0'), isFalse);
      expect(isNewerVersion('2.10.0', '2.9.0'), isTrue,
          reason: 'dibandingkan sebagai angka, bukan teks');
    });

    test('anything unreadable never offers an update', () {
      expect(isNewerVersion('latest', '2.0.0'), isFalse);
      expect(isNewerVersion('3.0.0', ''), isFalse);
    });
  });

  group('UpdateChecker.parseRelease', () {
    test('a newer tag is offered with its release page', () {
      final result = UpdateChecker.parseRelease(
        '{"tag_name":"v2.2.0","html_url":"$kRepoUrl/releases/tag/v2.2.0"}',
        '2.1.0',
      );
      expect(result.status, UpdateStatus.available);
      expect(result.update!.version, '2.2.0');
      expect(result.update!.pageUrl, '$kRepoUrl/releases/tag/v2.2.0');
    });

    test('the same version is up to date', () {
      final result =
          UpdateChecker.parseRelease('{"tag_name":"v2.1.0"}', '2.1.0');
      expect(result.status, UpdateStatus.upToDate);
    });

    test('a page outside our repository is never opened', () {
      final result = UpdateChecker.parseRelease(
        '{"tag_name":"v9.0.0","html_url":"https://example.com/evil"}',
        '2.1.0',
      );
      expect(result.update!.pageUrl, kReleasesUrl);
    });

    test('garbage is a failed check, not a crash', () {
      expect(UpdateChecker.parseRelease('<html>', '2.1.0').status,
          UpdateStatus.failed);
      expect(UpdateChecker.parseRelease('[]', '2.1.0').status,
          UpdateStatus.failed);
    });
  });
}
