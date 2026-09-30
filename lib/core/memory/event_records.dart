import 'dart:convert';

/// A grounding snapshot attached to every [AppEvent].
///
/// Phase 1 captures two *independent* clocks so the agent can never fabricate
/// temporal continuity:
///
///  * [wallClockUtc] — the OS wall clock, which the user or the network can
///    move forwards or backwards.
///  * [monotonicMs] — a monotonic process-uptime counter that only ever moves
///    forward while the app is alive, and does not advance while the process is
///    frozen (backgrounded/suspended).
///
/// Their divergence [clockSkewMs] is the ground-truth signal. Under normal
/// foreground use it stays near zero; a large positive skew means real time
/// passed that the process did not see (the device slept, or was closed and the
/// object rebuilt) or the wall clock jumped. [sessionId] marks which app launch
/// produced the event, so gaps *between* launches are visible too.
///
/// [batteryPercent], [latitude] and [longitude] are reserved for when sensor
/// grounding is switched on (the `ground.sensorsEnabled` parameter) and a
/// sensor plugin is added. They are null until then — never faked.
class SensorAnchor {
  final DateTime wallClockUtc;
  final int monotonicMs;
  final String sessionId;
  final int? clockSkewMs;
  final int? batteryPercent;
  final double? latitude;
  final double? longitude;

  const SensorAnchor({
    required this.wallClockUtc,
    required this.monotonicMs,
    required this.sessionId,
    this.clockSkewMs,
    this.batteryPercent,
    this.latitude,
    this.longitude,
  });

  Map<String, Object?> toJson() => {
        'wall_clock_utc': wallClockUtc.toUtc().toIso8601String(),
        'monotonic_ms': monotonicMs,
        'session_id': sessionId,
        if (clockSkewMs != null) 'clock_skew_ms': clockSkewMs,
        if (batteryPercent != null) 'battery_percent': batteryPercent,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      };

  static SensorAnchor fromJson(Map<String, Object?> j) => SensorAnchor(
        wallClockUtc:
            DateTime.parse(j['wall_clock_utc'] as String).toUtc(),
        monotonicMs: (j['monotonic_ms'] as num?)?.toInt() ?? 0,
        sessionId: j['session_id'] as String? ?? 'unknown',
        clockSkewMs: (j['clock_skew_ms'] as num?)?.toInt(),
        batteryPercent: (j['battery_percent'] as num?)?.toInt(),
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
      );
}

/// One immutable row of the append-only **event log** — the grounded spine of
/// the agent's history.
///
/// Unlike the episodic ledger (which is summarised and marked consolidated),
/// events are never updated or deleted in normal operation: they are the record
/// of what actually happened, each stamped with a [SensorAnchor]. The only way
/// they leave the log is the panel's explicit "clear all".
class AppEvent {
  final int? id;
  final DateTime timestampUtc;

  /// Who produced the event: 'user', 'assistant', 'system', 'memory'.
  final String source;

  /// What happened: 'app_launch', 'user_message', 'assistant_message',
  /// 'consolidate', …
  final String type;

  /// Arbitrary structured detail (kept small — full text lives in episodic).
  final Map<String, dynamic> payload;

  /// Ids of earlier events this one causally follows from.
  final List<int> parentEventIds;

  final SensorAnchor anchor;

  const AppEvent({
    this.id,
    required this.timestampUtc,
    required this.source,
    required this.type,
    this.payload = const {},
    this.parentEventIds = const [],
    required this.anchor,
  });

  Map<String, Object?> toRow() => {
        'timestamp_utc': timestampUtc.toUtc().toIso8601String(),
        'timestamp_millis': timestampUtc.toUtc().millisecondsSinceEpoch,
        'source': source,
        'type': type,
        'payload_json': payload.isEmpty ? null : json.encode(payload),
        'parent_events_json':
            parentEventIds.isEmpty ? null : json.encode(parentEventIds),
        'sensor_state_json': json.encode(anchor.toJson()),
        'session_id': anchor.sessionId,
        'monotonic_ms': anchor.monotonicMs,
      };

  static AppEvent fromRow(Map<String, Object?> row) {
    final payloadRaw = row['payload_json'] as String?;
    final parentsRaw = row['parent_events_json'] as String?;
    return AppEvent(
      id: row['id'] as int?,
      timestampUtc: DateTime.parse(row['timestamp_utc'] as String).toUtc(),
      source: row['source'] as String,
      type: row['type'] as String,
      payload: payloadRaw == null
          ? const {}
          : (json.decode(payloadRaw) as Map).cast<String, dynamic>(),
      parentEventIds: parentsRaw == null
          ? const []
          : (json.decode(parentsRaw) as List)
              .map((e) => (e as num).toInt())
              .toList(),
      anchor: SensorAnchor.fromJson(
          (json.decode(row['sensor_state_json'] as String) as Map)
              .cast<String, Object?>()),
    );
  }
}
