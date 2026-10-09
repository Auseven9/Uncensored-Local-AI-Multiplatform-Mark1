import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/memory/event_records.dart';
import '../../core/memory/memory_records.dart';
import '../../core/memory/memory_service.dart';
import '../../theme/app_colors.dart';
import 'memory_panel_controller.dart';

/// View and edit every stored memory (semantic facts + episodic log) and watch
/// the live feed of remember/recall/consolidate calls.
class MemoryPanelScreen extends StatelessWidget {
  const MemoryPanelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<MemoryPanelController>();
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: context.bg,
        appBar: AppBar(
          title: const Text('Memory'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: c.refreshAll,
            ),
            IconButton(
              tooltip: 'Clear all memory',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => _confirmClear(context, c),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Facts'),
              Tab(text: 'Episodic'),
              Tab(text: 'Events'),
              Tab(text: 'Activity'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _FactsTab(c: c),
            _EpisodicTab(c: c),
            _EventsTab(c: c),
            _ActivityTab(c: c),
          ],
        ),
      ),
    );
  }
}

// ── Facts tab ────────────────────────────────────────────────
class _FactsTab extends StatelessWidget {
  final MemoryPanelController c;
  const _FactsTab({required this.c});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SearchBar(onSubmit: c.search),
        Expanded(
          child: Obx(() {
            if (c.loading.value) {
              return const Center(child: CircularProgressIndicator());
            }
            if (c.facts.isEmpty) {
              return _empty(context, Icons.lightbulb_outline,
                  'No long-term facts yet.\nThey appear after consolidation runs.');
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: c.facts.length,
              itemBuilder: (ctx, i) => _factCard(ctx, c, c.facts[i]),
            );
          }),
        ),
      ],
    );
  }
}

Widget _factCard(BuildContext context, MemoryPanelController c, SemanticFact f) {
  final color = _catColor(f.category);
  return Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      onTap: () => _editFact(context, c, f),
      title: Text(f.text, style: const TextStyle(fontSize: 14)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            _chip(f.category.name, color),
            _chip('conf ${f.confidence.toStringAsFixed(2)}', context.textM),
            _chip(f.createdUtc.toLocal().toString().split('.').first,
                context.textD),
          ],
        ),
      ),
      trailing: IconButton(
        icon: Icon(Icons.delete_outline_rounded, color: AppColors.red, size: 20),
        onPressed: () => _confirmDelete(
          context,
          'Delete this fact?',
          () => c.deleteFact(f),
        ),
      ),
    ),
  );
}

// ── Episodic tab ─────────────────────────────────────────────
class _EpisodicTab extends StatelessWidget {
  final MemoryPanelController c;
  const _EpisodicTab({required this.c});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SearchBar(onSubmit: c.search),
        Expanded(
          child: Obx(() {
            if (c.loading.value) {
              return const Center(child: CircularProgressIndicator());
            }
            if (c.episodic.isEmpty) {
              return _empty(context, Icons.inbox_outlined,
                  'No episodic entries yet.');
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: c.episodic.length,
              itemBuilder: (ctx, i) => _episodicCard(ctx, c, c.episodic[i]),
            );
          }),
        ),
      ],
    );
  }
}

Widget _episodicCard(
    BuildContext context, MemoryPanelController c, EpisodicEntry e) {
  return Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      onTap: () => _editEpisodic(context, c, e),
      title: Text(e.content,
          maxLines: 4, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            _chip(e.role, AppColors.accent),
            _chip(e.kind.name, context.textM),
            if (e.consolidated) _chip('consolidated', AppColors.green),
            _chip(e.timestampUtc.toLocal().toString().split('.').first,
                context.textD),
          ],
        ),
      ),
      trailing: IconButton(
        icon: Icon(Icons.delete_outline_rounded, color: AppColors.red, size: 20),
        onPressed: () => _confirmDelete(
          context,
          'Delete this entry?',
          () => c.deleteEpisodic(e),
        ),
      ),
    ),
  );
}

// ── Activity tab ─────────────────────────────────────────────
class _ActivityTab extends StatelessWidget {
  final MemoryPanelController c;
  const _ActivityTab({required this.c});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final calls = c.calls.toList();
      if (calls.isEmpty) {
        return _empty(context, Icons.timeline_outlined,
            'No memory calls yet.\nEvery recall/remember/consolidate shows here.');
      }
      return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: calls.length,
        itemBuilder: (ctx, i) {
          final call = calls[i];
          final t = call.at;
          final time = '${t.hour.toString().padLeft(2, '0')}:'
              '${t.minute.toString().padLeft(2, '0')}:'
              '${t.second.toString().padLeft(2, '0')}';
          return ListTile(
            dense: true,
            leading: Icon(_callIcon(call.type), color: _callColor(call.type)),
            title: Text(_callLabel(call.type),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _callColor(call.type))),
            subtitle: Text(call.summary,
                style: TextStyle(fontSize: 12, color: ctx.textM)),
            trailing: Text(time,
                style: TextStyle(
                    fontSize: 10, color: ctx.textD, fontFamily: 'monospace')),
          );
        },
      );
    });
  }
}

// ── Events tab (append-only grounded log) ────────────────────
class _EventsTab extends StatelessWidget {
  final MemoryPanelController c;
  const _EventsTab({required this.c});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (c.loading.value) {
        return const Center(child: CircularProgressIndicator());
      }
      if (c.events.isEmpty) {
        return _empty(context, Icons.event_note_outlined,
            'No events yet.\nEvery launch, message and consolidation is\nrecorded here with a time anchor.');
      }
      return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: c.events.length,
        itemBuilder: (ctx, i) => _eventCard(ctx, c.events[i]),
      );
    });
  }
}

Widget _eventCard(BuildContext context, AppEvent e) {
  final color = _eventColor(e.source);
  final a = e.anchor;
  final local = e.timestampUtc.toLocal().toString().split('.').first;
  final preview = e.payload['preview']?.toString();
  final skew = a.clockSkewMs;
  // A large wall-vs-monotonic divergence means real time passed the process
  // didn't see (sleep/suspend) — surface it as a "gap" chip.
  final gapLabel = (skew != null && skew.abs() >= 2000)
      ? 'gap ${(skew / 1000).toStringAsFixed(0)}s'
      : null;
  return Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: Icon(_eventIcon(e.source), color: color),
      title: Text('${e.source} · ${e.type}',
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: color)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (preview != null && preview.isNotEmpty)
              Text(preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: context.textM)),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _chip(local, context.textD),
                  _chip('t+${(a.monotonicMs / 1000).toStringAsFixed(0)}s',
                      context.textM),
                  _chip('sess ${_shortSession(a.sessionId)}', AppColors.standard),
                  if (e.parentEventIds.isNotEmpty)
                    _chip('←#${e.parentEventIds.first}', context.textD),
                  if (gapLabel != null) _chip(gapLabel, AppColors.orange),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String _shortSession(String id) =>
    id.length <= 6 ? id : id.substring(id.length - 6);

IconData _eventIcon(String source) {
  switch (source) {
    case 'user':
      return Icons.person_outline_rounded;
    case 'assistant':
      return Icons.smart_toy_outlined;
    case 'memory':
      return Icons.auto_awesome_outlined;
    case 'system':
    default:
      return Icons.bolt_rounded;
  }
}

Color _eventColor(String source) {
  switch (source) {
    case 'user':
      return AppColors.accent;
    case 'assistant':
      return AppColors.standard;
    case 'memory':
      return AppColors.orange;
    case 'system':
    default:
      return AppColors.custom;
  }
}

// ── Shared widgets & helpers ─────────────────────────────────
class _SearchBar extends StatelessWidget {
  final ValueChanged<String> onSubmit;
  const _SearchBar({required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: TextField(
        onSubmitted: onSubmit,
        style: TextStyle(color: context.text, fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search memories… (enter)',
          hintStyle: TextStyle(color: context.textD),
          prefixIcon: Icon(Icons.search_rounded, color: context.textM),
          filled: true,
          fillColor: context.bgInput,
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
    );
  }
}

Widget _chip(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );

Widget _empty(BuildContext context, IconData icon, String text) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: context.textD),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.textD, fontSize: 14)),
          ],
        ),
      ),
    );

Color _catColor(SemanticCategory c) {
  switch (c) {
    case SemanticCategory.fact:
      return AppColors.accent;
    case SemanticCategory.preference:
      return AppColors.custom;
    case SemanticCategory.rule:
      return AppColors.orange;
    case SemanticCategory.summary:
      return AppColors.standard;
  }
}

IconData _callIcon(MemoryCallType t) {
  switch (t) {
    case MemoryCallType.recall:
      return Icons.psychology_alt_outlined;
    case MemoryCallType.remember:
      return Icons.save_alt_rounded;
    case MemoryCallType.consolidate:
      return Icons.auto_awesome_outlined;
  }
}

Color _callColor(MemoryCallType t) {
  switch (t) {
    case MemoryCallType.recall:
      return AppColors.standard;
    case MemoryCallType.remember:
      return AppColors.accent;
    case MemoryCallType.consolidate:
      return AppColors.orange;
  }
}

String _callLabel(MemoryCallType t) {
  switch (t) {
    case MemoryCallType.recall:
      return 'REMEMBERING (recall)';
    case MemoryCallType.remember:
      return 'REMEMBER (store)';
    case MemoryCallType.consolidate:
      return 'CONSOLIDATE';
  }
}

Future<void> _editFact(
    BuildContext context, MemoryPanelController c, SemanticFact f) async {
  final textCtrl = TextEditingController(text: f.text);
  var category = f.category;
  var confidence = f.confidence;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Edit fact'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: textCtrl,
                maxLines: null,
                decoration: const InputDecoration(labelText: 'Text'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Category'),
                  const SizedBox(width: 12),
                  DropdownButton<SemanticCategory>(
                    value: category,
                    items: SemanticCategory.values
                        .map((v) => DropdownMenuItem(
                            value: v, child: Text(v.name)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setLocal(() => category = v);
                    },
                  ),
                ],
              ),
              Row(
                children: [
                  const Text('Confidence'),
                  Expanded(
                    child: Slider(
                      value: confidence,
                      divisions: 20,
                      label: confidence.toStringAsFixed(2),
                      onChanged: (v) => setLocal(() => confidence = v),
                    ),
                  ),
                  Text(confidence.toStringAsFixed(2)),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final t = textCtrl.text.trim();
              if (t.isEmpty) return;
              Navigator.of(ctx).pop();
              try {
                await c.saveFact(f,
                    text: t, category: category, confidence: confidence);
              } catch (e) {
                Get.snackbar('Save failed', '$e',
                    snackPosition: SnackPosition.BOTTOM);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  textCtrl.dispose();
}

Future<void> _editEpisodic(
    BuildContext context, MemoryPanelController c, EpisodicEntry e) async {
  final textCtrl = TextEditingController(text: e.content);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Edit ${e.role} entry'),
      content: SingleChildScrollView(
        child: TextField(
          controller: textCtrl,
          maxLines: null,
          decoration: const InputDecoration(labelText: 'Content'),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () async {
            final t = textCtrl.text.trim();
            if (t.isEmpty) return;
            Navigator.of(ctx).pop();
            try {
              await c.saveEpisodic(e, t);
            } catch (err) {
              Get.snackbar('Save failed', '$err',
                  snackPosition: SnackPosition.BOTTOM);
            }
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  textCtrl.dispose();
}

Future<void> _confirmDelete(
    BuildContext context, String message, Future<void> Function() onConfirm) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Confirm'),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
          onPressed: () async {
            Navigator.of(ctx).pop();
            await onConfirm();
          },
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}

Future<void> _confirmClear(BuildContext context, MemoryPanelController c) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Clear all memory?'),
      content: const Text(
          'This permanently deletes every episodic entry and semantic fact. '
          'This cannot be undone.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
          onPressed: () async {
            Navigator.of(ctx).pop();
            await c.clearAll();
          },
          child: const Text('Clear all'),
        ),
      ],
    ),
  );
}
