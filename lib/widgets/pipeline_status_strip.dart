import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/pipeline_status_service.dart';
import '../theme/app_colors.dart';

/// A live, always-current readout of what the system is doing right now:
/// phase, a ticking elapsed timer, a progress bar (determinate for model-load %
/// and generation budget, indeterminate otherwise), and — during generation —
/// the running token count and rate. On a slow on-device model this turns the
/// wait into a stream of information instead of a blank pause.
///
/// It self-refreshes on a short timer (so the elapsed clock advances even when
/// no event fires) and reads the [PipelineStatusService] each frame, so it also
/// picks up phase/detail changes within one tick. Hidden while idle.
class PipelineStatusStrip extends StatefulWidget {
  const PipelineStatusStrip({super.key});

  @override
  State<PipelineStatusStrip> createState() => _PipelineStatusStripState();
}

class _PipelineStatusStripState extends State<PipelineStatusStrip> {
  Timer? _ticker;

  PipelineStatusService? get _svc {
    try {
      return Get.find<PipelineStatusService>();
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    // A gentle heartbeat so the elapsed timer advances and phase/detail changes
    // are reflected promptly. 250ms is imperceptible latency and near-free.
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  IconData _iconFor(PipelinePhase p) {
    switch (p) {
      case PipelinePhase.arming:
        return Icons.bolt_outlined;
      case PipelinePhase.loading:
        return Icons.downloading_rounded;
      case PipelinePhase.recalling:
        return Icons.search_rounded;
      case PipelinePhase.embedding:
        return Icons.bubble_chart_outlined;
      case PipelinePhase.prompting:
        return Icons.settings_ethernet_rounded;
      case PipelinePhase.generating:
        return Icons.auto_awesome_rounded;
      case PipelinePhase.consolidating:
        return Icons.hub_outlined;
      case PipelinePhase.error:
        return Icons.error_outline_rounded;
      case PipelinePhase.idle:
        return Icons.circle_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = _svc;
    if (svc == null) return const SizedBox.shrink();

    final phase = svc.phase.value;
    if (phase == PipelinePhase.idle) return const SizedBox.shrink();

    final isError = phase == PipelinePhase.error;
    final tint = isError ? AppColors.red : AppColors.accent;

    final since = svc.activeSinceMs.value;
    final elapsed = since == 0
        ? Duration.zero
        : Duration(
            milliseconds: DateTime.now().millisecondsSinceEpoch - since);

    final detail = svc.detail.value;
    final progress = svc.progress.value; // null ⇒ indeterminate
    final tokens = svc.tokens.value;
    final tps = svc.tps.value;
    final generating = phase == PipelinePhase.generating;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      decoration: BoxDecoration(
        color: context.bgPanel,
        border: Border(top: BorderSide(color: context.border, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(_iconFor(phase), size: 14, color: tint),
              const SizedBox(width: 6),
              Text(
                phase.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: tint,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 8),
              // Live elapsed clock.
              if (!isError)
                Text(
                  formatElapsed(elapsed),
                  style: TextStyle(fontSize: 11, color: context.textM),
                ),
              const Spacer(),
              // Token count + rate while generating.
              if (generating)
                Text(
                  '$tokens tok · ${tps.toStringAsFixed(tps >= 1 ? 1 : 2)} t/s',
                  style: TextStyle(
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: context.textM,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Progress bar: determinate when we have a fraction, else a moving
          // indeterminate bar so it's clearly alive.
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: isError ? 1.0 : progress,
              minHeight: 3,
              backgroundColor: context.border.withValues(alpha: 0.4),
              valueColor: AlwaysStoppedAnimation<Color>(tint),
            ),
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: isError ? AppColors.red : context.textM,
                height: 1.25,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
