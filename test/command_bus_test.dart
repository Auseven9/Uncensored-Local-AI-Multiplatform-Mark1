import 'package:flutter_test/flutter_test.dart';
import 'package:portable_ai_flutter/core/agent/command_bus.dart';

void main() {
  group('CommandBus — validated execution path', () {
    late CommandBus bus;

    setUp(() {
      bus = CommandBus()
        ..register(CommandSpec(
          name: 'echo',
          description: 'echoes its text back',
          requiredArgs: const ['text'],
          handler: (c) async => CommandResult.ok(c.args['text']),
        ))
        ..register(CommandSpec(
          name: 'boom',
          description: 'always throws',
          handler: (c) async => throw StateError('kaboom'),
        ));
    });

    test('dispatches a valid command', () async {
      final r = await bus.dispatch(const AppCommand('echo', {'text': 'hi'}));
      expect(r.ok, isTrue);
      expect(r.value, 'hi');
    });

    test('unknown command fails instead of throwing', () async {
      final r = await bus.dispatch(const AppCommand('nope'));
      expect(r.ok, isFalse);
      expect(r.error, contains('unknown command'));
    });

    test('missing required arg fails', () async {
      final r = await bus.dispatch(const AppCommand('echo'));
      expect(r.ok, isFalse);
      expect(r.error, contains('missing required arg'));
    });

    test('a null required arg also fails', () async {
      final r = await bus.dispatch(const AppCommand('echo', {'text': null}));
      expect(r.ok, isFalse);
    });

    test('a throwing handler is caught and returned as failure', () async {
      final r = await bus.dispatch(const AppCommand('boom'));
      expect(r.ok, isFalse);
      expect(r.error, contains('kaboom'));
    });

    test('toolCatalog lists registered commands with their metadata', () {
      final cat = bus.toolCatalog();
      expect(cat.map((e) => e['name']), containsAll(['echo', 'boom']));
      final echo = cat.firstWhere((e) => e['name'] == 'echo');
      expect(echo['required_args'], contains('text'));
      expect(echo['read_only'], isTrue);
    });
  });
}
