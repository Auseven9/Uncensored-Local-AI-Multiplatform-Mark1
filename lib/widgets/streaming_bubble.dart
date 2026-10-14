import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../theme/app_colors.dart';
import '../controllers/chat_controller.dart';

/// The in-progress assistant reply, rendered as a smooth left-to-right
/// typewriter rather than popping in token chunks.
///
/// The model streams tokens into [ChatController.streamedResponse] at an uneven,
/// chunky cadence. This widget DECOUPLES the display from that: a 60fps ticker
/// reveals the buffered text a few characters at a time so letters flow like
/// someone typing, catching up (never falling seconds behind) when a big chunk
/// lands, and parking a blinking caret when it has caught up and is waiting for
/// more. Plain text only — markdown is parsed once when the turn finishes and
/// the bubble becomes a [ChatBubble] — so there is no per-token re-parse jank.
class StreamingBubble extends StatefulWidget {
  const StreamingBubble({super.key});

  @override
  State<StreamingBubble> createState() => _StreamingBubbleState();
}

class _StreamingBubbleState extends State<StreamingBubble> {
  final _chat = Get.find<ChatController>();
  Timer? _reveal;
  Timer? _blink;
  int _shown = 0;
  bool _caretOn = true;

  @override
  void initState() {
    super.initState();
    _reveal =
        Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
    _blink = Timer.periodic(const Duration(milliseconds: 530), (_) {
      if (mounted) setState(() => _caretOn = !_caretOn);
    });
  }

  void _tick() {
    if (!mounted) return;
    final target = _chat.streamedResponse.value.length;
    if (_shown == target) return;
    if (_shown > target) {
      // Buffer reset (new turn) — snap back.
      setState(() => _shown = target);
      return;
    }
    // Reveal a few chars per frame; accelerate when far behind so we stay near
    // real time, but still move letter-by-letter when close.
    final remaining = target - _shown;
    final step = remaining > 240
        ? (remaining ~/ 24)
        : remaining > 24
            ? 3
            : 1;
    final next = _shown + step;
    setState(() => _shown = next > target ? target : next);
  }

  @override
  void dispose() {
    _reveal?.cancel();
    _blink?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 600;
    final hPad = isSmall ? 16.0 : 24.0;
    final full = _chat.streamedResponse.value;
    final shown = _shown > full.length ? full.length : _shown;
    final text = full.substring(0, shown);

    return Container(
      width: double.infinity,
      color: context.bgMsgAi,
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.bolt_rounded, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: text),
                    // Caret: a steady block that blinks when the reveal has
                    // caught up (i.e. she's "thinking" / waiting for tokens).
                    TextSpan(
                      text: '▋',
                      style: TextStyle(
                        color: AppColors.accent.withValues(
                            alpha: _caretOn ? 1.0 : 0.0),
                      ),
                    ),
                  ],
                ),
                style: TextStyle(fontSize: 15, color: context.text, height: 1.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
