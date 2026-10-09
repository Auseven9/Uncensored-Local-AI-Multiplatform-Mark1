import 'package:flutter_test/flutter_test.dart';

import 'package:portable_ai_flutter/services/llm_service.dart';

/// [LlmService.scrubReply] is the single shared cleanup applied to every
/// generated turn — the chat screen AND the debate room both route their final
/// text through it, so a reply produced off the main chat is cleaned identically
/// ("there is never a difference"). These tests lock that behaviour.
void main() {
  group('LlmService.scrubReply', () {
    test('strips common stop / end-of-turn control tokens', () {
      expect(LlmService.scrubReply('Hello<|end|>'), 'Hello');
      expect(LlmService.scrubReply('Hi<|eot_id|>'), 'Hi');
      expect(LlmService.scrubReply('Yo<|im_end|>'), 'Yo');
      expect(LlmService.scrubReply('Done<end_of_turn>'), 'Done');
      expect(LlmService.scrubReply('End</s>'), 'End');
      expect(LlmService.scrubReply('[INST]ignored'), 'ignored');
    });

    test('strips role markers a model may emit at the end of a turn', () {
      expect(LlmService.scrubReply('Answer.<|user|>'), 'Answer.');
      expect(LlmService.scrubReply('Reply.<|assistant|>'), 'Reply.');
      // The bracket token is removed; any bare word the template split off
      // remains, exactly as the chat's cleanup always behaved.
      expect(LlmService.scrubReply('Reply.<start_of_turn>'), 'Reply.');
    });

    test('strips stray structural HTML a template can bleed in', () {
      expect(
        LlmService.scrubReply('A point.</blockquote>'),
        'A point.',
      );
      expect(LlmService.scrubReply('<p>Para</p>'), 'Para');
      expect(LlmService.scrubReply('line<br/>two'), 'linetwo');
    });

    test('trims surrounding whitespace left after stripping', () {
      expect(LlmService.scrubReply('  spaced  '), 'spaced');
      expect(LlmService.scrubReply('text<|end|>  '), 'text');
    });

    test('leaves clean prose untouched', () {
      const clean = 'The user\'s name is Dylon. Alesis remembers it.';
      expect(LlmService.scrubReply(clean), clean);
    });
  });
}
