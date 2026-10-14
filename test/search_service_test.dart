import 'package:flutter_test/flutter_test.dart';
import 'package:portable_ai_flutter/services/search_service.dart';

void main() {
  group('SearchConfig', () {
    test('linkup preset has the expected shape', () {
      const c = SearchConfig.linkup;
      expect(c.provider, 'linkup');
      expect(c.endpoint, 'https://api.linkup.so/v1/search');
      expect(c.method, 'POST');
      expect(c.authHeader, 'Authorization');
      expect(c.authPrefix, 'Bearer ');
      expect(c.queryField, 'q');
      expect(c.resultsPath, 'results');
      expect(c.titleField, 'name');
      expect(c.snippetField, 'content');
      expect(c.extraParams['outputType'], 'searchResults');
    });

    test('toJson/fromJson round-trips, including the key and extraParams', () {
      final c = SearchConfig.linkup.copyWith(apiKey: 'secret-123');
      final back = SearchConfig.fromJson(c.toJson());
      expect(back.apiKey, 'secret-123');
      expect(back.provider, 'linkup');
      expect(back.queryField, 'q');
      expect(back.extraParams['depth'], 'standard');
      expect(back.urlField, 'url');
    });

    test('fromJson tolerates a sparse custom blob', () {
      final c = SearchConfig.fromJson({
        'provider': 'custom',
        'endpoint': 'https://api.example.com/search',
        'apiKey': 'k',
        'method': 'GET',
        'queryField': 'query',
        'resultsPath': 'data.items',
        'titleField': 'title',
        'urlField': 'link',
        'snippetField': 'desc',
      });
      expect(c.method, 'GET');
      expect(c.resultsPath, 'data.items');
      expect(c.titleField, 'title');
      expect(c.extraParams, isEmpty);
    });
  });

  group('SearchService.dig', () {
    test('walks a dot-path and returns null on a missing segment', () {
      final tree = {
        'data': {
          'items': [1, 2, 3]
        }
      };
      expect(SearchService.dig(tree, 'data.items'), [1, 2, 3]);
      expect(SearchService.dig(tree, ''), tree);
      expect(SearchService.dig(tree, 'data.missing'), isNull);
      expect(SearchService.dig(tree, 'nope.at.all'), isNull);
    });
  });

  group('SearchService.parseResults', () {
    test('parses a Linkup-shaped payload', () {
      final decoded = {
        'results': [
          {
            'type': 'text',
            'name': 'Dart language',
            'url': 'https://dart.dev',
            'content': 'Dart is a client-optimized language.'
          },
          {
            'type': 'text',
            'name': 'Flutter',
            'url': 'https://flutter.dev',
            'content': 'Flutter builds cross-platform apps.'
          },
        ]
      };
      final out = SearchService.parseResults(decoded, SearchConfig.linkup);
      expect(out.length, 2);
      expect(out.first.title, 'Dart language');
      expect(out.first.url, 'https://dart.dev');
      expect(out.first.snippet, contains('client-optimized'));
    });

    test('parses a custom nested path with remapped fields', () {
      final cfg = SearchConfig.fromJson({
        'provider': 'custom',
        'endpoint': 'x',
        'apiKey': 'k',
        'resultsPath': 'data.items',
        'titleField': 'title',
        'urlField': 'link',
        'snippetField': 'desc',
      });
      final decoded = {
        'data': {
          'items': [
            {'title': 'A', 'link': 'https://a.com', 'desc': 'alpha'},
            {'title': 'B', 'link': 'https://b.com', 'desc': 'beta'},
          ]
        }
      };
      final out = SearchService.parseResults(decoded, cfg);
      expect(out.length, 2);
      expect(out[1].title, 'B');
      expect(out[1].url, 'https://b.com');
      expect(out[1].snippet, 'beta');
    });

    test('respects the max cap', () {
      final decoded = {
        'results': [
          for (var i = 0; i < 20; i++)
            {'name': 'r$i', 'url': 'https://e/$i', 'content': 'c$i'}
        ]
      };
      final out =
          SearchService.parseResults(decoded, SearchConfig.linkup, max: 5);
      expect(out.length, 5);
    });

    test('missing path or wrong shape yields empty, never throws', () {
      expect(SearchService.parseResults({'nope': 1}, SearchConfig.linkup),
          isEmpty);
      expect(SearchService.parseResults({'results': 'not-a-list'},
          SearchConfig.linkup), isEmpty);
      expect(SearchService.parseResults(42, SearchConfig.linkup), isEmpty);
    });

    test('skips entirely-empty items', () {
      final decoded = {
        'results': [
          {'name': '', 'url': '', 'content': ''},
          {'name': 'Real', 'url': 'https://real', 'content': 'x'},
        ]
      };
      final out = SearchService.parseResults(decoded, SearchConfig.linkup);
      expect(out.length, 1);
      expect(out.first.title, 'Real');
    });
  });
}
