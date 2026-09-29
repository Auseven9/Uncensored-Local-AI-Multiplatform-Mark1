import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../theme/app_colors.dart';
import 'introspection_controller.dart';

/// Introspection Dojo: gated, on-demand memory consolidation. The model stays
/// idle until there is real work to do.
class IntrospectionScreen extends StatelessWidget {
  const IntrospectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<IntrospectionController>();

    return Scaffold(
      backgroundColor: context.bg,
      body: Column(
        children: [
          // ── Top bar ──────────────────────────────────
          Container(
            padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top, left: 4, right: 4),
            decoration: BoxDecoration(
              color: context.bg,
              border:
                  Border(bottom: BorderSide(color: context.border, width: 0.5)),
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
                    'Introspection Dojo',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: context.text,
                    ),
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Pending work
                Obx(() => _StatCard(
                      icon: Icons.inbox_outlined,
                      label: 'Episodic entries awaiting consolidation',
                      value: '${controller.pendingCount.value}',
                    )),
                const SizedBox(height: 12),

                // Last run summary
                Obx(() => _StatCard(
                      icon: Icons.history_rounded,
                      label: 'Last consolidation',
                      value: controller.lastSummary.value.isEmpty
                          ? 'Not run yet'
                          : controller.lastSummary.value,
                    )),
                const SizedBox(height: 20),

                // Run now
                Obx(() => SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: controller.isRunning.value
                            ? null
                            : () => controller.runOnce(),
                        icon: controller.isRunning.value
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation(Colors.white),
                                ),
                              )
                            : const Icon(Icons.psychology_rounded, size: 18),
                        label: Text(controller.isRunning.value
                            ? 'Consolidating…'
                            : 'Consolidate memory now'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    )),
                const SizedBox(height: 16),

                // Background scheduling toggle
                Obx(() => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: context.bgPanel,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: context.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Background consolidation',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: context.text,
                                  ),
                                ),
                                Text(
                                  'Checks every 10 min; wakes the model only '
                                  'when entries are pending.',
                                  style: TextStyle(
                                      fontSize: 11, color: context.textD),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: controller.scheduledEnabled.value,
                            activeColor: AppColors.accent,
                            onChanged: (on) => on
                                ? controller.enableScheduled()
                                : controller.disableScheduled(),
                          ),
                        ],
                      ),
                    )),

                const SizedBox(height: 20),
                Text(
                  'Consolidation summarises recent activity and stores only '
                  'durable facts, preferences, and rules — discarding noise so '
                  'long-term memory stays clean.',
                  style: TextStyle(
                      fontSize: 12, color: context.textD, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.bgPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: context.textM),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.text,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
