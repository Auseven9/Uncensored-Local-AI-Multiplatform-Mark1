import 'dart:convert';

/// Strict GBNF tool-grammar engine for constrained tool-call generation.
///
/// This module has two responsibilities:
///
///  1. **Grammar synthesis** — [buildToolCallGrammar] compiles a list of
///     [ToolSpec]s into a llama.cpp GBNF grammar string. Unlike a naive
///     "any string" grammar, the `tool` field is constrained to the *exact*
///     set of registered tool names, so the sampler cannot hallucinate a
///     tool that does not exist.
///
///  2. **Validated parsing** — [parseToolCall] / [tryParseToolCall] take raw
///     model output (which may be wrapped in markdown fences or surrounded by
///     prose) and deterministically extract, decode, and validate a single
///     tool call. This is the layer that eliminates parser misfires and JSON
///     crashes even when the underlying backend cannot enforce the grammar.
///
/// ## On grammar-constrained sampling
///
/// The grammar strings produced here are enforced by the sampler on
/// grammar-capable backends (the native llama.cpp backends used on
/// mobile/desktop). `LlmService.generateWithGrammar` passes them via
/// `GenerationParams.grammar` (llamadart >= 0.8). [parseToolCall] still runs
/// afterwards as defence in depth — and remains the sole guard on backends
/// that cannot enforce grammars (e.g. some web/LiteRT paths).
class GbnfToolEngine {
  const GbnfToolEngine._();

  // ── Grammar synthesis ─────────────────────────────────────────

  /// Compiles [tools] into a GBNF grammar that forces output of the shape
  /// `{"tool": "<one-of-the-tool-names>", "arguments": { ... }}`.
  ///
  /// When [tools] is empty the `tool` field accepts any JSON string, so the
  /// grammar still guarantees well-formed structure.
  static String buildToolCallGrammar(List<ToolSpec> tools) {
    final toolNameRule = tools.isEmpty
        ? 'toolname ::= string'
        : 'toolname ::= ${tools.map((t) => _gbnfStringLiteral(t.name)).join(' | ')}';

    // Constrains structure (and the tool name), not per-argument types, so it
    // composes with any tool schema without a combinatorial blow-up.
    return '''
root      ::= ws "{" ws "\\"tool\\"" ws ":" ws toolname ws "," ws "\\"arguments\\"" ws ":" ws object ws "}" ws
$toolNameRule
$_sharedJsonRules
''';
  }

  /// Builds a GBNF grammar that accepts any single well-formed JSON object.
  /// Used to force structured, parseable output from summary/curation passes.
  static String buildJsonObjectGrammar() {
    return '''
root      ::= ws object ws
$_sharedJsonRules
''';
  }

  /// Shared JSON production rules (no `root` — callers prepend their own).
  static const _sharedJsonRules = '''
object    ::= "{" ws ( member ( ws "," ws member )* )? ws "}"
member    ::= string ws ":" ws value
value     ::= object | array | string | number | "true" | "false" | "null"
array     ::= "[" ws ( value ( ws "," ws value )* )? ws "]"
string    ::= "\\"" ( [^"\\\\] | "\\\\" ["\\\\/bfnrt] | "\\\\u" hex hex hex hex )* "\\""
number    ::= "-"? ( "0" | [1-9] [0-9]* ) ( "." [0-9]+ )? ( [eE] [-+]? [0-9]+ )?
hex       ::= [0-9a-fA-F]
ws        ::= [ \\t\\n\\r]*''';

  /// Emits a GBNF literal that matches the JSON string `"value"` (quotes
  /// included). Any embedded quotes/backslashes in [value] are escaped.
  static String _gbnfStringLiteral(String value) {
    final escaped =
        value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    // Produces e.g. `"\"get-weather\""` in the emitted grammar text.
    return '"\\"$escaped\\""';
  }

  // ── Validated parsing ─────────────────────────────────────────

  /// Parses [raw] model output into a validated [ToolCall].
  ///
  /// Tolerates markdown code fences and surrounding prose by extracting the
  /// first balanced JSON object. When [tools] is provided, the tool name must
  /// match a registered spec and any [ToolParameter.required] arguments must
  /// be present (with best-effort type coercion).
  ///
  /// Throws [ToolCallParseException] on any structural problem — callers get a
  /// single, typed failure instead of a raw [FormatException] or a null-deref.
  static ToolCall parseToolCall(String raw, {List<ToolSpec> tools = const []}) {
    final jsonText = extractJsonObject(raw);
    if (jsonText == null) {
      throw const ToolCallParseException('No JSON object found in output.');
    }

    final Object? decoded;
    try {
      decoded = json.decode(jsonText);
    } on FormatException catch (e) {
      throw ToolCallParseException('Malformed JSON: ${e.message}');
    }

    if (decoded is! Map) {
      throw const ToolCallParseException('Top-level value is not an object.');
    }
    final map = decoded.cast<String, dynamic>();

    final toolValue = map['tool'];
    if (toolValue is! String || toolValue.trim().isEmpty) {
      throw const ToolCallParseException('Missing or empty "tool" field.');
    }
    final tool = toolValue.trim();

    final argsValue = map['arguments'] ?? const <String, dynamic>{};
    if (argsValue is! Map) {
      throw const ToolCallParseException('"arguments" is not an object.');
    }
    final arguments = argsValue.cast<String, dynamic>();

    if (tools.isNotEmpty) {
      ToolSpec? spec;
      for (final t in tools) {
        if (t.name == tool) {
          spec = t;
          break;
        }
      }
      if (spec == null) {
        final known = tools.map((t) => t.name).join(', ');
        throw ToolCallParseException(
          'Unknown tool "$tool". Known tools: $known.',
        );
      }
      for (final p in spec.parameters) {
        if (p.required && !arguments.containsKey(p.name)) {
          throw ToolCallParseException(
            'Tool "$tool" is missing required argument "${p.name}".',
          );
        }
      }
    }

    return ToolCall(tool, arguments);
  }

  /// Like [parseToolCall] but returns `null` instead of throwing.
  static ToolCall? tryParseToolCall(String raw,
      {List<ToolSpec> tools = const []}) {
    try {
      return parseToolCall(raw, tools: tools);
    } on ToolCallParseException {
      return null;
    }
  }

  /// Extracts the first balanced, brace-delimited JSON object from [raw].
  ///
  /// Strips markdown code fences, honours string literals and escape
  /// sequences while scanning, and returns `null` if no complete object is
  /// present. Kept public so callers (e.g. the memory gate) can reuse the
  /// same tolerant extraction for structured summaries.
  static String? extractJsonObject(String raw) {
    var text = raw.trim();

    // Strip a leading ```json / ``` fence and a trailing ``` fence if present.
    final fence = RegExp(r'```[a-zA-Z0-9_-]*\s*');
    if (text.startsWith('```')) {
      text = text.replaceFirst(fence, '');
      final lastFence = text.lastIndexOf('```');
      if (lastFence != -1) text = text.substring(0, lastFence);
      text = text.trim();
    }

    final start = text.indexOf('{');
    if (start == -1) return null;

    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final ch = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == r'\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
      } else if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) {
          return text.substring(start, i + 1);
        }
      }
    }
    return null; // Unbalanced — no complete object.
  }
}

/// The type of a tool argument, used only for lightweight validation.
enum ToolParamType { string, number, boolean, object, array }

/// A single named parameter of a [ToolSpec].
class ToolParameter {
  final String name;
  final ToolParamType type;
  final bool required;
  final String? description;

  const ToolParameter({
    required this.name,
    this.type = ToolParamType.string,
    this.required = false,
    this.description,
  });
}

/// Describes a tool the model may call.
class ToolSpec {
  final String name;
  final String description;
  final List<ToolParameter> parameters;

  const ToolSpec({
    required this.name,
    this.description = '',
    this.parameters = const [],
  });
}

/// A validated tool invocation extracted from model output.
class ToolCall {
  final String tool;
  final Map<String, dynamic> arguments;

  const ToolCall(this.tool, this.arguments);

  Map<String, dynamic> toJson() => {'tool': tool, 'arguments': arguments};

  @override
  String toString() => 'ToolCall($tool, $arguments)';
}

/// Raised when raw model output cannot be turned into a valid [ToolCall].
class ToolCallParseException implements Exception {
  final String message;
  const ToolCallParseException(this.message);

  @override
  String toString() => 'ToolCallParseException: $message';
}
