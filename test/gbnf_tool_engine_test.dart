import 'package:flutter_test/flutter_test.dart';
import 'package:portable_ai_flutter/core/tools/gbnf_tool_engine.dart';

void main() {
  const tools = [
    ToolSpec(
      name: 'get-weather',
      description: 'Get the weather',
      parameters: [ToolParameter(name: 'city', required: true)],
    ),
    ToolSpec(name: 'search'),
  ];

  group('buildToolCallGrammar', () {
    test('constrains the tool field to registered names', () {
      final grammar = GbnfToolEngine.buildToolCallGrammar(tools);
      expect(grammar, contains(r'"\"get-weather\""'));
      expect(grammar, contains(r'"\"search\""'));
      expect(grammar, contains('toolname ::='));
      expect(grammar, contains('arguments'));
    });

    test('falls back to any string when no tools are given', () {
      final grammar = GbnfToolEngine.buildToolCallGrammar(const []);
      expect(grammar, contains('toolname ::= string'));
    });

    test('buildJsonObjectGrammar accepts a single object', () {
      final grammar = GbnfToolEngine.buildJsonObjectGrammar();
      expect(grammar, contains('ws object ws'));
      expect(grammar, contains('"true" | "false" | "null"'));
      expect(grammar, isNot(contains('toolname')));
    });
  });

  group('extractJsonObject', () {
    test('extracts a bare object', () {
      expect(GbnfToolEngine.extractJsonObject('{"a":1}'), '{"a":1}');
    });

    test('strips markdown fences', () {
      const raw = '```json\n{"tool":"search","arguments":{}}\n```';
      expect(GbnfToolEngine.extractJsonObject(raw),
          '{"tool":"search","arguments":{}}');
    });

    test('ignores prose around the object', () {
      const raw = 'Sure! Here you go: {"tool":"search","arguments":{}} — done.';
      expect(GbnfToolEngine.extractJsonObject(raw),
          '{"tool":"search","arguments":{}}');
    });

    test('honours braces inside strings', () {
      const raw = '{"tool":"search","arguments":{"q":"a } b"}}';
      expect(GbnfToolEngine.extractJsonObject(raw), raw);
    });

    test('returns null when unbalanced', () {
      expect(GbnfToolEngine.extractJsonObject('{"a":1'), isNull);
    });
  });

  group('parseToolCall', () {
    test('parses a valid, fenced call', () {
      const raw = '```json\n{"tool":"get-weather","arguments":{"city":"Paris"}}\n```';
      final call = GbnfToolEngine.parseToolCall(raw, tools: tools);
      expect(call.tool, 'get-weather');
      expect(call.arguments['city'], 'Paris');
    });

    test('defaults arguments to an empty map', () {
      final call = GbnfToolEngine.parseToolCall('{"tool":"search"}', tools: tools);
      expect(call.tool, 'search');
      expect(call.arguments, isEmpty);
    });

    test('rejects an unknown tool', () {
      expect(
        () => GbnfToolEngine.parseToolCall('{"tool":"nope","arguments":{}}',
            tools: tools),
        throwsA(isA<ToolCallParseException>()),
      );
    });

    test('rejects a missing required argument', () {
      expect(
        () => GbnfToolEngine.parseToolCall(
            '{"tool":"get-weather","arguments":{}}',
            tools: tools),
        throwsA(isA<ToolCallParseException>()),
      );
    });

    test('rejects output with no JSON', () {
      expect(
        () => GbnfToolEngine.parseToolCall('I cannot do that.', tools: tools),
        throwsA(isA<ToolCallParseException>()),
      );
    });

    test('tryParseToolCall returns null instead of throwing', () {
      expect(GbnfToolEngine.tryParseToolCall('garbage', tools: tools), isNull);
    });
  });
}
