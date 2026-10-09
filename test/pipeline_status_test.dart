import 'package:flutter_test/flutter_test.dart';

import 'package:portable_ai_flutter/services/pipeline_status_service.dart';

void main() {
  group('formatElapsed', () {
    test('sub-minute shows one decimal of seconds', () {
      expect(formatElapsed(const Duration(milliseconds: 0)), '0.0s');
      expect(formatElapsed(const Duration(milliseconds: 800)), '0.8s');
      expect(formatElapsed(const Duration(seconds: 12, milliseconds: 300)),
          '12.3s');
      expect(formatElapsed(const Duration(seconds: 59, milliseconds: 900)),
          '59.9s');
    });

    test('a minute or more shows m:ss', () {
      expect(formatElapsed(const Duration(minutes: 1, seconds: 5)), '1:05');
      expect(formatElapsed(const Duration(minutes: 12, seconds: 7)), '12:07');
      expect(formatElapsed(const Duration(minutes: 1)), '1:00');
    });

    test('negative clamps to zero', () {
      expect(formatElapsed(const Duration(milliseconds: -50)), '0.0s');
    });
  });

  group('PipelineStatusService', () {
    test('begin/mark/done drive phase and breadcrumbs', () {
      final s = PipelineStatusService();
      expect(s.isActive, isFalse);
      expect(s.phase.value, PipelinePhase.idle);

      s.begin(PipelinePhase.recalling, 'searching…');
      expect(s.isActive, isTrue);
      expect(s.phase.value, PipelinePhase.recalling);
      expect(s.activeSinceMs.value, greaterThan(0));
      expect(s.steps.first.text, 'searching…');

      s.mark('recalled 3');
      expect(s.detail.value, 'recalled 3');
      expect(s.steps.first.text, 'recalled 3');

      s.done('replied');
      expect(s.phase.value, PipelinePhase.idle);
      expect(s.isActive, isFalse);
      expect(s.activeSinceMs.value, 0);
    });

    test('setGeneration maps tokens to a budget fraction', () {
      final s = PipelineStatusService();
      s.begin(PipelinePhase.generating, 'generating…', progress: 0.0);
      s.setGeneration(tokens: 128, tps: 0.3, budget: 512);
      expect(s.tokens.value, 128);
      expect(s.tps.value, 0.3);
      expect(s.progress.value, closeTo(0.25, 1e-9));
    });

    test('fail holds an error until cleared', () {
      final s = PipelineStatusService();
      s.begin(PipelinePhase.generating, 'generating…');
      s.fail('boom');
      expect(s.phase.value, PipelinePhase.error);
      expect(s.detail.value, 'boom');
      s.clearError();
      expect(s.phase.value, PipelinePhase.idle);
    });
  });
}
