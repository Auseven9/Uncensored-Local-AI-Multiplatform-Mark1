import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../theme/app_colors.dart';
import '../core/research/research_records.dart';
import '../services/llm_service.dart';
import '../services/research_service.dart';
import '../services/search_service.dart';

/// The research chat page — the second chat, to the left of the main one.
///
/// Unlike the normal chat, this is a procurement console: pick a turn budget
/// (1–100), give the agent a goal, and it goes to the web, summarizes what it
/// finds (behind the rogue-prompt guard), and files it into a local corpus you
/// can browse. No model / no search key → it refuses with a clear reason
/// rather than inventing anything.
class ResearchScreen extends StatefulWidget {
  const ResearchScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<ResearchScreen> createState() => _ResearchScreenState();
}

class _ResearchScreenState extends State<ResearchScreen> {
  final _research = Get.find<ResearchService>();
  final _llm = Get.find<LlmService>();
  SearchService get _search => Get.find<SearchService>();

  final _goalCtrl = TextEditingController();
  final _activityScroll = ScrollController();
  Worker? _activityWorker;

  List<ResearchTopic> _topics = const [];

  @override
  void initState() {
    super.initState();
    _reloadTopics();
    // Keep the activity log pinned to the newest line as it streams.
    _activityWorker =
        ever(_research.activity, (_) => _scrollActivityToEnd());
  }

  @override
  void dispose() {
    _activityWorker?.dispose();
    _goalCtrl.dispose();
    _activityScroll.dispose();
    super.dispose();
  }

  Future<void> _reloadTopics() async {
    try {
      final t = await _research.topics();
      if (mounted) setState(() => _topics = t);
    } catch (_) {
      // Store not ready yet (e.g. hot reload before splash init) — leave empty.
    }
  }

  void _scrollActivityToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_activityScroll.hasClients) {
        _activityScroll.jumpTo(_activityScroll.position.maxScrollExtent);
      }
    });
  }

  void _procure() {
    FocusScope.of(context).unfocus();
    _research
        .procure(goal: _goalCtrl.text, turns: _research.turnsBudget.value)
        .then((_) {
      if (mounted) _reloadTopics();
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);
    if (widget.embedded) return SafeArea(bottom: false, child: body);
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bgPanel,
        title: const Text('Research', style: TextStyle(fontSize: 16)),
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(child: body),
    );
  }

  Widget _buildBody(BuildContext context) {
    return Column(
      children: [
        _header(context),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _readinessBanners(context),
              _turnSelector(context),
              const SizedBox(height: 14),
              _goalInput(context),
              const SizedBox(height: 10),
              _runButton(context),
              const SizedBox(height: 14),
              _statusAndActivity(context),
              const SizedBox(height: 22),
              _libraryHeader(context),
              const SizedBox(height: 8),
              ..._topics.map((t) => _topicTile(context, t)),
              if (_topics.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'Nothing procured yet.\nGive the agent a goal above.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.textD, fontSize: 13),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: context.bg,
        border: Border(bottom: BorderSide(color: context.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.travel_explore_rounded,
                size: 19, color: AppColors.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Research',
                    style: TextStyle(
                        color: context.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                Text('Send the agent to the web → local library',
                    style: TextStyle(color: context.textD, fontSize: 11.5)),
              ],
            ),
          ),
          Obx(() => Text(
                '${_research.findingsCount.value > 0 ? '${_research.findingsCount.value} this run' : ''}',
                style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              )),
        ],
      ),
    );
  }

  Widget _readinessBanners(BuildContext context) {
    return Obx(() {
      final noModel = !_llm.isLoaded.value;
      // isConfigured reads the saved key; recompute cheaply on build.
      final noKey = !_search.isConfigured;
      if (!noModel && !noKey) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          children: [
            if (noModel)
              _banner(context, Icons.smart_toy_outlined,
                  'No model loaded — research uses your on-device LLM.', null),
            if (noModel && noKey) const SizedBox(height: 8),
            if (noKey)
              _banner(context, Icons.key_outlined,
                  'No search key set. Tap to configure web search.',
                  () => Get.toNamed('/web-search')),
          ],
        ),
      );
    });
  }

  Widget _banner(BuildContext context, IconData icon, String text,
      VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.orange.withValues(alpha: 0.10),
          border: Border.all(color: AppColors.orange.withValues(alpha: 0.30)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: TextStyle(color: context.text, fontSize: 12.5)),
            ),
            if (onTap != null)
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 12, color: context.textD),
          ],
        ),
      ),
    );
  }

  Widget _turnSelector(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: context.bgPanel,
        border: Border.all(color: context.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Obx(() {
        final turns = _research.turnsBudget.value;
        final running = _research.isRunning.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Turns',
                    style: TextStyle(
                        color: context.textM,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$turns',
                      style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            Slider(
              value: turns.clamp(1, 100).toDouble(),
              min: 1,
              max: 100,
              divisions: 99,
              activeColor: AppColors.accent,
              label: '$turns',
              onChanged: running
                  ? null
                  : (v) => _research.setTurns(v.round()),
            ),
            Text(
              'How many search→summarize→store cycles the agent gets (1–100).',
              style: TextStyle(color: context.textD, fontSize: 11),
            ),
          ],
        );
      }),
    );
  }

  Widget _goalInput(BuildContext context) {
    return TextField(
      controller: _goalCtrl,
      minLines: 2,
      maxLines: 5,
      style: TextStyle(color: context.text, fontSize: 14, height: 1.4),
      decoration: InputDecoration(
        hintText: 'What should I go research?\n'
            'e.g. "the current state of on-device LLM inference on Android"',
        hintStyle: TextStyle(color: context.textD, fontSize: 13),
        filled: true,
        fillColor: context.bgInput,
        contentPadding: const EdgeInsets.all(14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
      ),
    );
  }

  Widget _runButton(BuildContext context) {
    return Obx(() {
      final running = _research.isRunning.value;
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: running ? _research.stop : _procure,
          icon: Icon(
              running ? Icons.stop_rounded : Icons.rocket_launch_rounded,
              size: 18),
          label: Text(running ? 'Stop' : 'Procure data'),
          style: ElevatedButton.styleFrom(
            backgroundColor: running ? AppColors.red : AppColors.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    });
  }

  Widget _statusAndActivity(BuildContext context) {
    return Obx(() {
      final status = _research.statusLine.value;
      final running = _research.isRunning.value;
      final turn = _research.currentTurn.value;
      final budget = _research.turnsBudget.value;
      final log = _research.activity.toList();
      if (status.isEmpty && log.isEmpty) return const SizedBox.shrink();
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.bgPanel,
          border: Border.all(color: context.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (running)
                  const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation(AppColors.accent)),
                  )
                else
                  const Icon(Icons.check_circle_outline_rounded,
                      size: 15, color: AppColors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status.isEmpty ? 'Idle' : status,
                    style: TextStyle(color: context.text, fontSize: 12.5),
                  ),
                ),
                if (running && turn > 0)
                  Text('turn $turn/$budget',
                      style:
                          TextStyle(color: context.textM, fontSize: 11)),
              ],
            ),
            if (log.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                constraints: const BoxConstraints(maxHeight: 170),
                decoration: BoxDecoration(
                  color: context.bgInput,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  controller: _activityScroll,
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(10),
                  itemCount: log.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      log[i],
                      style: TextStyle(
                          color: context.textM,
                          fontSize: 11.5,
                          height: 1.35),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    });
  }

  Widget _libraryHeader(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.auto_stories_outlined, size: 16, color: context.textM),
        const SizedBox(width: 6),
        Text('Library',
            style: TextStyle(
                color: context.textM,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3)),
        const Spacer(),
        IconButton(
          icon: Icon(Icons.refresh_rounded, size: 18, color: context.textM),
          onPressed: _reloadTopics,
          tooltip: 'Refresh',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _topicTile(BuildContext context, ResearchTopic t) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.bgPanel,
        border: Border.all(color: context.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        title: Text(t.name,
            style: TextStyle(
                color: context.text,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        subtitle: t.summary.trim().isEmpty
            ? Text('Tap to open findings',
                style: TextStyle(color: context.textD, fontSize: 12))
            : Text(
                t.summary.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.textM, fontSize: 12, height: 1.3),
              ),
        trailing: Icon(Icons.arrow_forward_ios_rounded,
            size: 14, color: context.textD),
        onTap: () => _openTopic(context, t),
      ),
    );
  }

  Future<void> _openTopic(BuildContext context, ResearchTopic t) async {
    final findings = await _research.findings(t.id!);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.bgPanel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, scroll) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(t.name,
                        style: TextStyle(
                            color: context.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                  ),
                  Text('${findings.length} finding(s)',
                      style:
                          TextStyle(color: context.textM, fontSize: 12)),
                ],
              ),
            ),
            if (t.summary.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(t.summary.trim(),
                    style: TextStyle(
                        color: context.textM, fontSize: 12.5, height: 1.4)),
              ),
            const Divider(height: 1),
            Expanded(
              child: findings.isEmpty
                  ? Center(
                      child: Text('No findings stored.',
                          style:
                              TextStyle(color: context.textD, fontSize: 13)))
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: findings.length,
                      itemBuilder: (_, i) => _findingTile(context, findings[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _findingTile(BuildContext context, ResearchFinding f) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.bgInput,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Text(f.title,
              style: TextStyle(
                  color: context.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600)),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(f.content,
                  style: TextStyle(
                      color: context.textM, fontSize: 12.5, height: 1.45)),
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<ResearchSource>>(
              future: _research.sources(f.id!),
              builder: (_, snap) {
                final sources = snap.data ?? const [];
                if (sources.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sources',
                        style: TextStyle(
                            color: context.textD,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    ...sources.map((s) => Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            '• ${s.title.isEmpty ? s.url : s.title}\n  ${s.url}',
                            style: TextStyle(
                                color: context.textD,
                                fontSize: 11,
                                height: 1.35),
                          ),
                        )),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
