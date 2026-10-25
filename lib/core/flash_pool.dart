// Flâsh fork only: client for the NEW Flâsh Hiddify pool (v0.2).
//
// The pool is a plain Cloudflare Worker + KV (see flash-pool-worker/).
// It is SEPARATE from Flâsh VPN's pool: different Worker, KV and secret.
// Published links are PUBLIC by definition — anyone who knows the pool
// URL can fetch and use them. Never publish a private subscription URL
// unless you intend it to become public.
//
// Security notes: the publish password is stored in the app's
// preferences (not secure storage, same as the app's other preferences).
// It is NEVER logged, and NEVER exported with a profile. Pool links
// themselves are public once published, so they are not treated as
// secrets in the UI — but the password always is.
import 'dart:convert';
import 'dart:io';

/// One pool entry. [kind] is "node" (a single proxy link) or
/// "subscription" (a subscription URL, labelled as such in the UI).
class FlashPoolEntry {
  const FlashPoolEntry({
    required this.id,
    required this.name,
    required this.country,
    required this.key,
    required this.kind,
  });

  final String id;
  final String name;
  final String country;
  final String key;
  final String kind;

  bool get isSubscription => kind == 'subscription';

  factory FlashPoolEntry.fromJson(Map<String, dynamic> json) {
    final key = (json['key'] as String?) ?? '';
    var kind = (json['kind'] as String?) ?? '';
    if (kind != 'node' && kind != 'subscription') {
      kind = key.startsWith('http://') || key.startsWith('https://') ? 'subscription' : 'node';
    }
    return FlashPoolEntry(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      country: (json['country'] as String?) ?? '',
      key: key,
      kind: kind,
    );
  }
}

/// Parse a GET /pool body. Malformed bodies return an empty list — a
/// garbage pool response must never crash the app or wipe local data.
List<FlashPoolEntry> parsePoolJson(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return [];
    final entries = decoded['entries'];
    if (entries is! List) return [];
    final out = <FlashPoolEntry>[];
    for (final e in entries) {
      if (e is Map<String, dynamic> && (e['key'] as String? ?? '').isNotEmpty) {
        out.add(FlashPoolEntry.fromJson(e));
      }
    }
    return out;
  } catch (_) {
    return [];
  }
}

/// Proxy-link schemes the pool accepts for single nodes.
const flashPoolNodeSchemes = <String>{
  'vless',
  'vmess',
  'trojan',
  'ss',
  'hysteria2',
  'hy2',
  'tuic',
  'wireguard',
};

final _linkPattern = RegExp(
  r'\b(?:vless|vmess|trojan|ss|hysteria2|hy2|tuic|wireguard)://[^\s<>]+',
);

String _cleanLink(String raw) {
  var link = raw.trim();
  // Trim trailing punctuation that is not part of a link (JSON/CSV edges).
  while (link.isNotEmpty && ',;"\\\''.contains(link[link.length - 1])) {
    link = link.substring(0, link.length - 1);
  }
  return link;
}

/// Extract individual publishable proxy links from a profile's raw config
/// text (a local profile's content, or any link list). Lines/JSON blobs
/// containing links are scanned; if the whole text is one base64 blob it
/// is decoded once and scanned again. Returns de-duplicated links in
/// first-seen order. Never invents links: anything without a recognised
/// scheme is ignored.
List<String> extractPublishableLinks(String rawConfig) {
  final seen = <String>{};
  final out = <String>[];
  void scan(String text) {
    for (final m in _linkPattern.allMatches(text)) {
      final link = _cleanLink(m.group(0)!);
      if (link.isNotEmpty && seen.add(link)) out.add(link);
    }
  }

  scan(rawConfig);
  if (out.isEmpty) {
    final trimmed = rawConfig.trim();
    if (trimmed.isNotEmpty && !trimmed.contains(' ') && !trimmed.contains('\n')) {
      try {
        final decoded = utf8.decode(base64Decode(trimmed));
        scan(decoded);
      } catch (_) {
        // Not base64 — no links, return empty (not an error to fake).
      }
    }
  }
  return out;
}

/// Normalise a pool URL entered by the user: trim, drop a trailing slash.
String normalizePoolUrl(String raw) {
  var url = raw.trim();
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

class FlashPoolResult {
  const FlashPoolResult({required this.ok, this.error = '', this.id = ''});

  final bool ok;
  final String error;
  final String id;
}

/// Minimal HTTP client for the pool. Uses dart:io directly (no extra
/// dependency) so it is unit-testable against a local HttpServer.
class FlashPoolClient {
  FlashPoolClient({HttpClient? httpClient}) : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;

  Future<List<FlashPoolEntry>> fetchPool(String poolUrl) async {
    final base = normalizePoolUrl(poolUrl);
    if (base.isEmpty) throw const FormatException('Pool URL empty');
    final request = await _httpClient.getUrl(Uri.parse('$base/pool')).timeout(const Duration(seconds: 20));
    final response = await request.close().timeout(const Duration(seconds: 20));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Pool fetch failed (HTTP ${response.statusCode})');
    }
    return parsePoolJson(body);
  }

  Future<FlashPoolResult> publishEntry({
    required String poolUrl,
    required String password,
    required String name,
    required String key,
    String country = '',
  }) async {
    final base = normalizePoolUrl(poolUrl);
    if (base.isEmpty) return const FlashPoolResult(ok: false, error: 'Pool URL empty');
    try {
      final request = await _httpClient.postUrl(Uri.parse('$base/publish')).timeout(const Duration(seconds: 20));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'name': name, 'country': country, 'key': key, 'password': password}));
      final response = await request.close().timeout(const Duration(seconds: 20));
      final body = await response.transform(utf8.decoder).join();
      String error = 'HTTP ${response.statusCode}';
      String id = '';
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          error = (decoded['error'] as String?) ?? error;
          id = (decoded['id'] as String?) ?? '';
        }
      } catch (_) {
        // Keep the HTTP error text.
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return FlashPoolResult(ok: false, error: error);
      }
      return FlashPoolResult(ok: true, id: id);
    } catch (e) {
      return FlashPoolResult(ok: false, error: e.toString());
    }
  }
}
