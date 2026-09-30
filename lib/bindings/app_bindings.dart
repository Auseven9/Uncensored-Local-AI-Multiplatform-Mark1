import 'package:get/get.dart';

import '../services/llm_service.dart';
import '../services/embedding_service.dart';
import '../services/model_manager.dart';
import '../services/chat_storage_service.dart';
import '../services/local_api_server_service.dart';
import '../services/wakelock_service.dart';
import '../services/log_service.dart';
import '../services/system_health_monitor.dart';
import '../core/params/parameters_service.dart';
import '../controllers/chat_controller.dart';
import '../controllers/model_controller.dart';
import '../controllers/theme_controller.dart';
import '../core/engine/inference_worker.dart';
import '../core/memory/eidetic_memory_engine.dart';
import '../core/memory/memory_manager.dart';
import '../core/memory/memory_service.dart';
import '../features/rooms/arena_controller.dart';
import '../features/rooms/introspection_controller.dart';
import '../features/memory/memory_panel_controller.dart';

/// Initial bindings — registers all services and controllers with GetX DI.
class AppBindings extends Bindings {
  @override
  void dependencies() {
    // ── Services (async init happens in splash) ──────────────────
    Get.lazyPut(() => LlmService(), fenix: true);
    Get.lazyPut(() => EmbeddingService(), fenix: true);
    Get.lazyPut(() => ModelManager(), fenix: true);
    Get.lazyPut(() => ChatStorageService(), fenix: true);
    Get.lazyPut(() => LocalApiServerService(), fenix: true);
    Get.lazyPut(() => WakelockService(), fenix: true);
    Get.lazyPut(() => LogService(), fenix: true);
    Get.lazyPut(() => SystemHealthMonitor(), fenix: true);
    Get.lazyPut(() => ParametersService(), fenix: true);

    // ── Eidetic Dojo engine ──────────────────────────────────────
    Get.lazyPut(() => InferenceWorker(), fenix: true);
    Get.lazyPut(() => EideticMemoryEngine(), fenix: true);
    Get.lazyPut(
      () => MemoryManager(
        memory: Get.find<EideticMemoryEngine>(),
        worker: Get.find<InferenceWorker>(),
      ),
      fenix: true,
    );
    Get.lazyPut(
      () => MemoryService(
        memory: Get.find<EideticMemoryEngine>(),
        manager: Get.find<MemoryManager>(),
      ),
      fenix: true,
    );

    // ── Controllers ──────────────────────────────────────────────
    Get.put(
      ThemeController(),
    ); // Put instead of lazyPut since we need theme immediately
    Get.lazyPut(() => ChatController(), fenix: true);
    Get.lazyPut(() => ModelController(), fenix: true);
    Get.lazyPut(() => ArenaController(), fenix: true);
    Get.lazyPut(() => IntrospectionController(), fenix: true);
    Get.lazyPut(() => MemoryPanelController(), fenix: true);
  }
}
