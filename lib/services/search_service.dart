import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import 'chat_storage_service.dart';
import 'log_service.dart';

/// Pluggable web-search for the LLM — provider-agnostic.
///
/// There is ONE generic request builder; a "provider" is just a bundle of
/// config (endpoint, HTTP method, auth header, the query field name, extra
/// body/query params, and where the results live in the response). Linkup
/// ships as the pre-filled preset ([SearchConfig.linkup]); the `custom` preset
/// lets the user point it at ANY search API with ANY key. Nothing provider-
/// specific is hard-coded in the request path, so adding an engine is a config
/// change, not a code change.
///
/// Real HTTP only (`package:http`) — no mocks, no simulated results. On any
/// failure it returns a [SearchResponse] with `ok: false` and a plain-language
/// error; it never throws to the caller.
class SearchService extends GetxService {
  final http.Client _client;
  SearchService({http.Client? client}) : _client = client ?? http.Client();

  ChatStorageService? get _storage {
    try {
      return Get.find<ChatStorageService>();
    } catch (_) {
      return null;
    }
  }

  LogService? get _log {
    try {
      return Get.find<LogService>();
    } catch (_) {
      return null;
    }
  }

  /// The most recent error (for the Settings test button / status strip).
  final lastError = RxnString();

  /// The active configuration, from the `search_config` setting, defaulting to
  /// the Linkup preset (with an empty key until the user sets one).
  SearchConfig config() {
    final raw = _storage?.searchConfigJson ?? '';
    if (raw.trim().isEmpty) return SearchConfig.linkup;
    try {
      return SearchConfig.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return SearchConfig.linkup;
    }
  }

  bool get isConfigured => config().apiKey.trim().isNotEmpty;

  /// Run a real web search for [query]. Never throws.
  Future<SearchResponse> search(String query, {int maxResults = 6}) async {
    final q = query.trim();
    if (q.isEmpty) return SearchResponse.fail('Empty query.');
    final cfg = config();
    if (cfg.apiKey.trim().isEmpty) {
      final msg = 'No search API key — set one in Settings → Web Search.';
      lastError.value = msg;
      return SearchResponse.fail(msg);
    }

    try {
      final headers = <String, String>{};
      if (cfg.authHeader.isNotEmpty) {
        headers[cfg.authHeader] = '${cfg.authPrefix}${cfg.apiKey}';
      }

      final http.Response resp;
      if (cfg.method.toUpperCase() == 'GET') {
        final params = <String, String>{
          cfg.queryField: q,
          for (final e in cfg.extraParams.entries) e.key: '${e.value}',
        };
        final uri = Uri.parse(cfg.endpoint).replace(queryParameters: params);
        resp = await _client.get(uri, headers: headers);
      } else {
        headers['Content-Type'] = 'application/json';
        final body = jsonEncode({cfg.queryField: q, ...cfg.extraParams});
        resp = await _client.post(Uri.parse(cfg.endpoint),
            headers: headers, body: body);
      }

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        final msg = 'Search HTTP ${resp.statusCode}: ${_short(resp.body)}';
        lastError.value = msg;
        _log?.warn(msg, source: 'Search');
        return SearchResponse.fail(msg);
      }

      final decoded = jsonDecode(resp.body);
      final results = parseResults(decoded, cfg, max: maxResults);
      lastError.value = null;
      _log?.info('search "${_short(q, 60)}" → ${results.length} results '
          '(${cfg.provider})', source: 'Search');
      return SearchResponse.ok(results);
    } catch (e) {
      final msg = 'Search failed: $e';
      lastError.value = msg;
      _log?.error(msg, source: 'Search');
      return SearchResponse.fail(msg);
    }
  }

  // ── Pure parsing (unit-tested without a network) ────────────────

  /// Extract results from a decoded JSON response per [cfg]. Tolerant: a
  /// missing path or wrong shape yields an empty list rather than throwing.
  static List<SearchResult> parseResults(dynamic decoded, SearchConfig cfg,
      {int max = 10}) {
    final node = dig(decoded, cfg.resultsPath);
    if (node is! List) return const [];
    final out = <SearchResult>[];
    for (final item in node) {
      if (item is! Map) continue;
      final m = item.cast<String, dynamic>();
      final title = (m[cfg.titleField] ?? '').toString().trim();
      final url = (m[cfg.urlField] ?? '').toString().trim();
      final snippet = (m[cfg.snippetField] ?? '').toString().trim();
      if (url.isEmpty && title.isEmpty && snippet.isEmpty) continue;
      out.add(SearchResult(title: title, url: url, snippet: snippet));
      if (out.length >= max) break;
    }
    return out;
  }

  /// Walk a dot-path (e.g. `data.results`) into a decoded JSON tree. Empty path
  /// returns the root. Returns null if any segment is missing.
  static dynamic dig(dynamic json, String dotPath) {
    if (dotPath.isEmpty) return json;
    dynamic cur = json;
    for (final key in dotPath.split('.')) {
      if (cur is Map && cur.containsKey(key)) {
        cur = cur[key];
      } else {
        return null;
      }
    }
    return cur;
  }

  static String _short(String s, [int n = 160]) {
    final t = s.replaceAll('\n', ' ').trim();
    return t.length <= n ? t : '${t.substring(0, n)}…';
  }
}

/// A single web-search hit, normalized across providers.
class SearchResult {
  final String title;
  final String url;
  final String snippet;
  const SearchResult(
      {required this.title, required this.url, required this.snippet});

  @override
  String toString() => '$title <$url>';
}

/// The outcome of a search: results, or a plain-language error. Never throws.
class SearchResponse {
  final bool ok;
  final List<SearchResult> results;
  final String? error;
  const SearchResponse(this.ok, this.results, this.error);

  factory SearchResponse.ok(List<SearchResult> results) =>
      SearchResponse(true, List.unmodifiable(results), null);
  factory SearchResponse.fail(String error) =>
      SearchResponse(false, const [], error);
}

/// Provider-agnostic search configuration. A "provider" is just a named bundle
/// of these fields; presets pre-fill them. Persisted as JSON under the
/// `search_config` setting.
class SearchConfig {
  final String provider; // 'linkup' | 'custom' | …
  final String endpoint;
  final String apiKey;
  final String method; // 'POST' | 'GET'
  final String authHeader; // e.g. 'Authorization' ('' = no auth header)
  final String authPrefix; // e.g. 'Bearer '
  final String queryField; // the request field holding the search term
  final Map<String, dynamic> extraParams; // provider knobs (depth, etc.)
  final String resultsPath; // dot-path to the results array in the response
  final String titleField;
  final String urlField;
  final String snippetField;

  const SearchConfig({
    required this.provider,
    required this.endpoint,
    required this.apiKey,
    this.method = 'POST',
    this.authHeader = 'Authorization',
    this.authPrefix = 'Bearer ',
    this.queryField = 'q',
    this.extraParams = const {},
    this.resultsPath = 'results',
    this.titleField = 'name',
    this.urlField = 'url',
    this.snippetField = 'content',
  });

  /// Linkup (api.linkup.so) — the default preset. `q` + depth/outputType in the
  /// POST body, `Authorization: Bearer <key>`, results under `results` with
  /// `name`/`url`/`content` fields.
  static const SearchConfig linkup = SearchConfig(
    provider: 'linkup',
    endpoint: 'https://api.linkup.so/v1/search',
    apiKey: '',
    method: 'POST',
    authHeader: 'Authorization',
    authPrefix: 'Bearer ',
    queryField: 'q',
    extraParams: {'depth': 'standard', 'outputType': 'searchResults'},
    resultsPath: 'results',
    titleField: 'name',
    urlField: 'url',
    snippetField: 'content',
  );

  SearchConfig copyWith({String? provider, String? endpoint, String? apiKey}) =>
      SearchConfig(
        provider: provider ?? this.provider,
        endpoint: endpoint ?? this.endpoint,
        apiKey: apiKey ?? this.apiKey,
        method: method,
        authHeader: authHeader,
        authPrefix: authPrefix,
        queryField: queryField,
        extraParams: extraParams,
        resultsPath: resultsPath,
        titleField: titleField,
        urlField: urlField,
        snippetField: snippetField,
      );

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'endpoint': endpoint,
        'apiKey': apiKey,
        'method': method,
        'authHeader': authHeader,
        'authPrefix': authPrefix,
        'queryField': queryField,
        'extraParams': extraParams,
        'resultsPath': resultsPath,
        'titleField': titleField,
        'urlField': urlField,
        'snippetField': snippetField,
      };

  factory SearchConfig.fromJson(Map<String, dynamic> j) {
    String s(String k, String d) => (j[k] ?? d).toString();
    return SearchConfig(
      provider: s('provider', 'custom'),
      endpoint: s('endpoint', ''),
      apiKey: s('apiKey', ''),
      method: s('method', 'POST'),
      authHeader: s('authHeader', 'Authorization'),
      authPrefix: s('authPrefix', 'Bearer '),
      queryField: s('queryField', 'q'),
      extraParams: (j['extraParams'] is Map)
          ? (j['extraParams'] as Map).cast<String, dynamic>()
          : const {},
      resultsPath: s('resultsPath', 'results'),
      titleField: s('titleField', 'name'),
      urlField: s('urlField', 'url'),
      snippetField: s('snippetField', 'content'),
    );
  }
}
