import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../theme/app_colors.dart';
import '../../services/llm_service.dart';
import 'arena_controller.dart';

/// Dual-Agent Arena: run a debate between two personas and watch it stream.
class ArenaScreen extends StatefulWidget {
  const ArenaScreen({super.key});

  @override
  State<ArenaScreen> createState() => _ArenaScreenState();
}

class _ArenaScreenState extends State<ArenaScreen> {
  final _topicCtrl = TextEditingController();
  final _controller = Get.find<ArenaController>();
  final _llm = Get.find<LlmService>();

  @override
  void dispose() {
    _topicCtrl.dispose();
    super.dispose();
  }

  void _start() {
    final topic = _topicCtrl.text.trim();
    if (topic.isEmpty) {
      Get.snackbar('Topic required', 'Enter a topic for the debate.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    if (!_llm.isLoaded.value) {
      Get.snackbar('No model loaded', 'Load a model before starting a debate.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    FocusScope.of(context).unfocus();
    _controller.runDebate(
      sessionId: 'arena-${DateTime.now().millisecondsSinceEpoch}',
      topic: topic,
      rounds: 3,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      body: Column(
        children: [
          _TopBar(),
          _InputBar(topicCtrl: _topicCtrl, onStart: _start, controller: _controller),
          Expanded(
            child: Obx(() {
              final turns = _controller.transcript.toList();
              final live = _controller.liveText.value;
              final agent = _controller.currentAgent.value;
              final running = _controller.isRunning.value;

              if (turns.isEmpty && !running) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.forum_outlined, size: 48, color: context.textD),
                        const SizedBox(height: 16),
                        Text(
                          'Enter a topic and start a debate between two AI personas.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.textD, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  for (final turn in turns)
                    _TurnCard(agent: turn.agent, round: turn.round, text: turn.text),
                  if (running && live.isNotEmpty)
                    _TurnCard(agent: agent, round: _controller.currentRound.value, text: live, live: true),
                ],
              );
            }),
          ),
          _StatusBar(controller: _controller),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top, left: 4, right: 4),
      decoration: BoxDecoration(
        color: context.bg,
        border: Border(bottom: BorderSide(color: context.border, width: 0.5)),
      ),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: context.text),
              onPressed: () => Get.back<void>(),
            ),
            Text(
              'Debate Arena',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: context.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController topicCtrl;
  final VoidCallback onStart;
  final ArenaController controller;
  const _InputBar({
    required this.topicCtrl,
    required this.onStart,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: topicCtrl,
              style: TextStyle(color: context.text, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Debate topic…',
                hintStyle: TextStyle(color: context.textD),
                filled: true,
                fillColor: context.bgInput,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.border),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Obx(() {
            final running = controller.isRunning.value;
            return ElevatedButton(
              onPressed: running ? controller.stop : onStart,
              style: ElevatedButton.styleFrom(
                backgroundColor: running ? AppColors.red : AppColors.accent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(running ? 'Stop' : 'Start'),
            );
          }),
        ],
      ),
    );
  }
}

class _TurnCard extends StatelessWidget {
  final String agent;
  final int round;
  final String text;
  final bool live;
  const _TurnCard({
    required this.agent,
    required this.round,
    required this.text,
    this.live = false,
  });

  @override
  Widget build(BuildContext context) {
    final isA = agent == 'Agent A';
    final color = isA ? AppColors.accent : AppColors.custom;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$agent · round $round',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              if (live) ...[
                const SizedBox(width: 8),
                Text('typing…',
                    style: TextStyle(fontSize: 11, color: context.textD)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: TextStyle(fontSize: 14, color: context.text, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final ArenaController controller;
  const _StatusBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final msg = controller.statusMessage.value;
      if (msg.isEmpty) return const SizedBox.shrink();
      return Container(
        width: double.infinity,
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 10,
          bottom: MediaQuery.of(context).padding.bottom + 10,
        ),
        decoration: BoxDecoration(
          color: context.bgPanel,
          border: Border(top: BorderSide(color: context.border, width: 0.5)),
        ),
        child: Text(
          msg,
          style: TextStyle(fontSize: 12, color: context.textM),
        ),
      );
    });
  }
}
