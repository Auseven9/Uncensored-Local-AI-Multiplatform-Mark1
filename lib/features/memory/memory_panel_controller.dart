import 'package:get/get.dart';

import '../../core/memory/eidetic_memory_engine.dart';
import '../../core/memory/memory_records.dart';
import '../../core/memory/memory_service.dart';

/// Backs the Memory Panel: loads every stored memory, applies edits/deletes,
/// and exposes the live memory-call activity feed.
class MemoryPanelController extends GetxController {
  MemoryPanelController({EideticMemoryEngine? memory, MemoryService? service})
      : _memory = memory ?? Get.find<EideticMemoryEngine>(),
        _service = service ?? Get.find<MemoryService>();

  final EideticMemoryEngine _memory;
  final MemoryService _service;

  final facts = <SemanticFact>[].obs;
  final episodic = <EpisodicEntry>[].obs;
  final loading = false.obs;
  final persistent = true.obs;
  String _query = '';

  /// Live feed of remember/recall/consolidate calls (newest first).
  RxList<MemoryCall> get calls => _service.recentCalls;

  @override
  void onInit() {
    super.onInit();
    refreshAll();
  }

  Future<void> refreshAll() async {
    loading.value = true;
    try {
      persistent.value = _memory.isPersistent;
      final q = _query.trim();
      facts.value = q.isEmpty
          ? await _memory.recentFacts(limit: 500)
          : await _memory.recall(q, k: 200);
      final recent = await _memory.recentEpisodic(limit: 500);
      episodic.value = q.isEmpty
          ? recent
          : recent
              .where((e) => e.content.toLowerCase().contains(q.toLowerCase()))
              .toList();
    } finally {
      loading.value = false;
    }
  }

  Future<void> search(String q) async {
    _query = q;
    await refreshAll();
  }

  Future<void> saveFact(
    SemanticFact fact, {
    required String text,
    required SemanticCategory category,
    required double confidence,
  }) async {
    if (fact.id == null) return;
    await _memory.updateFact(fact.id!,
        text: text, category: category, confidence: confidence);
    await refreshAll();
  }

  Future<void> deleteFact(SemanticFact fact) async {
    if (fact.id == null) return;
    await _memory.deleteFact(fact.id!);
    await refreshAll();
  }

  Future<void> saveEpisodic(EpisodicEntry entry, String content) async {
    if (entry.id == null) return;
    await _memory.updateEpisodicContent(entry.id!, content);
    await refreshAll();
  }

  Future<void> deleteEpisodic(EpisodicEntry entry) async {
    if (entry.id == null) return;
    await _memory.deleteEpisodic(entry.id!);
    await refreshAll();
  }

  Future<void> clearAll() async {
    await _memory.clearAll();
    await refreshAll();
  }
}
