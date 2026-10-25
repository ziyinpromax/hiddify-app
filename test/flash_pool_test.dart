import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/flash_pool.dart';

void main() {
  group('parsePoolJson', () {
    test('parses node and subscription entries, skips empty keys', () {
      final entries = parsePoolJson(jsonEncode({
        'ok': true,
        'entries': [
          {'id': 'a', 'name': 'SG', 'country': '🇸🇬', 'key': 'vless://u@h:443', 'kind': 'node'},
          {'id': 'b', 'name': 'Sub', 'key': 'https://sub.example.com/list', 'kind': 'subscription'},
          {'id': 'c', 'name': 'Bad', 'key': ''},
        ],
      }));
      expect(entries.length, 2);
      expect(entries[0].kind, 'node');
      expect(entries[1].isSubscription, isTrue);
    });

    test('malformed bodies return empty, never throw', () {
      expect(parsePoolJson('not json'), isEmpty);
      expect(parsePoolJson('{"ok":true}'), isEmpty);
      expect(parsePoolJson('[]'), isEmpty);
    });
  });

  group('extractPublishableLinks', () {
    test('extracts links from a list, dedupes, keeps order', () {
      const text = 'vless://u@a:443#One\ntrojan://p@b:443#Two\nvless://u@a:443#One';
      expect(extractPublishableLinks(text), ['vless://u@a:443#One', 'trojan://p@b:443#Two']);
    });

    test('extracts links embedded in JSON text', () {
      const text = '{"outbounds":[{"protocol":"vless","address":"x"}]} vless://u@a:443';
      expect(extractPublishableLinks(text), ['vless://u@a:443']);
    });

    test('decodes a base64 blob containing links', () {
      final blob = base64Encode(utf8.encode('vmess://abc@h:443'));
      expect(extractPublishableLinks(blob), ['vmess://abc@h:443']);
    });

    test('ignores unknown schemes and vendor-locked formats', () {
      expect(extractPublishableLinks('nm-abc123\nzivpn://xyz\nhttps://example.com'), isEmpty);
    });
  });

  group('normalizePoolUrl', () {
    test('trims and drops trailing slashes', () {
      expect(normalizePoolUrl('  https://pool.example.com/  '), 'https://pool.example.com');
      expect(normalizePoolUrl('https://pool.example.com'), 'https://pool.example.com');
    });
  });

  group('FlashPoolClient against a local server', () {
    late HttpServer server;
    late String base;
    final stored = <Map<String, dynamic>>[];

    setUp(() async {
      stored.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      server.listen((request) async {
        if (request.uri.path == '/pool' && request.method == 'GET') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'ok': true, 'entries': stored}));
        } else if (request.uri.path == '/publish' && request.method == 'POST') {
          final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
          if (body['password'] != 'pw') {
            request.response.statusCode = 401;
            request.response.write(jsonEncode({'ok': false, 'error': 'bad_password'}));
          } else {
            stored.add({'id': '1', 'name': body['name'], 'key': body['key'], 'kind': 'node'});
            request.response.write(jsonEncode({'ok': true, 'id': '1'}));
          }
        } else {
          request.response.statusCode = 404;
          request.response.write('not found');
        }
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('fetch returns published entries, bad password surfaces verbatim', () async {
      final client = FlashPoolClient();
      expect(await client.fetchPool(base), isEmpty);
      final bad = await client.publishEntry(poolUrl: base, password: 'no', name: 'A', key: 'vless://u@h:443');
      expect(bad.ok, isFalse);
      expect(bad.error, 'bad_password');
      final good = await client.publishEntry(poolUrl: base, password: 'pw', name: 'A', key: 'vless://u@h:443');
      expect(good.ok, isTrue);
      final entries = await client.fetchPool(base);
      expect(entries.length, 1);
      expect(entries.first.key, 'vless://u@h:443');
    });
  });
}
