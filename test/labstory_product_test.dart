/// labstory-product.json feeds the "Spesifikasi" and "Yang baru" sections of
/// apps.labstory.id/produk/labscale (contract: labstory-platform
/// docs/API_CONTRACT.md §11). The site rejects an invalid file and keeps the
/// last good one, so a release that forgets to update it — or breaks it —
/// leaves the page silently stale. These checks run with every test pass.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final file = File('labstory-product.json');
  final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final pubspecVersion = RegExp(r'^version:\s*([^+\s]+)', multiLine: true)
      .firstMatch(File('pubspec.yaml').readAsStringSync())!
      .group(1)!;

  test('identifies itself and stays under the size limit', () {
    expect(data['schema'], 1);
    expect(data['product'], 'labscale');
    expect(file.lengthSync(), lessThanOrEqualTo(64 * 1024));
  });

  test('matches the version being released', () {
    // Bump this file together with pubspec.yaml: version, releasedAt and a
    // new changelog entry on top.
    expect(data['version'], pubspecVersion);
    checkChangelog(data, pubspecVersion);
    final top = (data['changelog'] as List).first as Map<String, dynamic>;
    expect(top['date'], data['releasedAt']);
  });

  test('has the English section the site requires, in step with Indonesian',
      () {
    // Owner rule (2026-10-14): every public page ships in ID and EN. A
    // missing or stale "en" leaves /en/produk/labscale on old defaults.
    final en = data['en'] as Map<String, dynamic>?;
    expect(en, isNotNull, reason: 'bagian "en" wajib ada');
    checkChangelog(en!, pubspecVersion);
    expect(
      (en['changelog'] as List).length,
      (data['changelog'] as List).length,
      reason: 'changelog EN dan ID harus memuat rilis yang sama',
    );
    checkRequirements(en['requirements'] as Map<String, dynamic>);
  });

  test('requirements fit the page limits', () {
    checkRequirements(data['requirements'] as Map<String, dynamic>);
  });

  test('is plain text, as the site renders it', () {
    // No HTML and no Markdown emphasis or links: shown literally on the page.
    final text = jsonEncode(data);
    expect(text, isNot(matches(RegExp(r'<[a-zA-Z/]'))));
    expect(text, isNot(contains('**')));
    expect(text, isNot(matches(RegExp(r'\]\('))));
  });
}

void checkChangelog(Map<String, dynamic> section, String version) {
  final changelog = (section['changelog'] as List).cast<Map<String, dynamic>>();
  expect(changelog.first['version'], version);
  expect(changelog.length, lessThanOrEqualTo(5));
  for (final entry in changelog) {
    expect(entry['date'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    final items = (entry['items'] as List).cast<String>();
    expect(items.length, inInclusiveRange(1, 12));
    for (final item in items) {
      expect(item.length, lessThanOrEqualTo(300), reason: item);
    }
  }
}

void checkRequirements(Map<String, dynamic> req) {
  expect((req['intro'] as String).length, lessThanOrEqualTo(500));
  final platforms = (req['platforms'] as List).cast<Map<String, dynamic>>();
  expect(platforms.length, lessThanOrEqualTo(4));
  for (final platform in platforms) {
    final rows = (platform['rows'] as List).cast<Map<String, dynamic>>();
    expect(rows.length, lessThanOrEqualTo(8));
    for (final row in rows) {
      expect((row['value'] as String).length, lessThanOrEqualTo(300));
    }
  }
  final notes = (req['notes'] as List).cast<Map<String, dynamic>>();
  expect(notes.length, lessThanOrEqualTo(9));
  for (final note in notes) {
    expect((note['title'] as String).length, lessThanOrEqualTo(60));
    expect((note['text'] as String).length, lessThanOrEqualTo(500));
  }
}
