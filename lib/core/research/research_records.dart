/// Record types for the Research Corpus — the user's on-machine knowledge store
/// procured from the web by the research-agent mode.
///
/// This is deliberately SEPARATE from ALESIS's eidetic memory: it is the user's
/// research library (web dumps, distilled), not the agent's autobiographical
/// self. High-level shape: a **topic** holds **findings** (distilled knowledge),
/// each backed by **sources** (provenance); a **run** records one procurement
/// job (a prompt + a turn budget) that produced findings under a topic.
library;

/// A high-level bucket of knowledge the user is building up.
class ResearchTopic {
  final int? id;
  final String name;
  final String slug; // normalized key for dedupe
  final String summary; // rolling high-level summary of the topic
  final String createdUtc;
  final String updatedUtc;

  const ResearchTopic({
    this.id,
    required this.name,
    required this.slug,
    this.summary = '',
    required this.createdUtc,
    required this.updatedUtc,
  });

  /// Normalize a free-text name into a stable slug for dedupe.
  static String slugify(String name) {
    final s = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return s.isEmpty ? 'topic' : s;
  }

  Map<String, Object?> toRow() => {
        'name': name,
        'slug': slug,
        'summary': summary,
        'created_utc': createdUtc,
        'updated_utc': updatedUtc,
      };

  factory ResearchTopic.fromRow(Map<String, Object?> r) => ResearchTopic(
        id: (r['id'] as num?)?.toInt(),
        name: r['name'] as String,
        slug: r['slug'] as String,
        summary: (r['summary'] as String?) ?? '',
        createdUtc: r['created_utc'] as String,
        updatedUtc: r['updated_utc'] as String,
      );
}

/// One procurement job: a prompt + a turn budget, producing findings.
class ResearchRun {
  final int? id;
  final int topicId;
  final String prompt;
  final int turnsBudget;
  final int turnsUsed;
  final String status; // running | done | stopped | error
  final String createdUtc;

  /// The capstone synthesis — the cross-finding, deeper-connections pass
  /// written once at the end of the run (empty while running / if too few
  /// findings). This is the "Findings Summary", distinct from any single
  /// finding or the topic's rolling summary.
  final String synthesis;

  const ResearchRun({
    this.id,
    required this.topicId,
    required this.prompt,
    required this.turnsBudget,
    this.turnsUsed = 0,
    this.status = 'running',
    required this.createdUtc,
    this.synthesis = '',
  });

  Map<String, Object?> toRow() => {
        'topic_id': topicId,
        'prompt': prompt,
        'turns_budget': turnsBudget,
        'turns_used': turnsUsed,
        'status': status,
        'created_utc': createdUtc,
        'synthesis': synthesis,
      };

  factory ResearchRun.fromRow(Map<String, Object?> r) => ResearchRun(
        id: (r['id'] as num?)?.toInt(),
        topicId: (r['topic_id'] as num).toInt(),
        prompt: r['prompt'] as String,
        turnsBudget: (r['turns_budget'] as num).toInt(),
        turnsUsed: (r['turns_used'] as num?)?.toInt() ?? 0,
        status: (r['status'] as String?) ?? 'running',
        createdUtc: r['created_utc'] as String,
        synthesis: (r['synthesis'] as String?) ?? '',
      );
}

/// One distilled piece of knowledge under a topic (an LLM summary of sources).
class ResearchFinding {
  final int? id;
  final int topicId;
  final int? runId;
  final String title;
  final String content; // the distilled summary
  final String createdUtc;

  const ResearchFinding({
    this.id,
    required this.topicId,
    this.runId,
    required this.title,
    required this.content,
    required this.createdUtc,
  });

  Map<String, Object?> toRow() => {
        'topic_id': topicId,
        'run_id': runId,
        'title': title,
        'content': content,
        'created_utc': createdUtc,
      };

  factory ResearchFinding.fromRow(Map<String, Object?> r) => ResearchFinding(
        id: (r['id'] as num?)?.toInt(),
        topicId: (r['topic_id'] as num).toInt(),
        runId: (r['run_id'] as num?)?.toInt(),
        title: r['title'] as String,
        content: r['content'] as String,
        createdUtc: r['created_utc'] as String,
      );
}

/// A web source backing a finding — provenance (never discarded).
class ResearchSource {
  final int? id;
  final int findingId;
  final String url;
  final String title;
  final String snippet;
  final String fetchedUtc;

  const ResearchSource({
    this.id,
    required this.findingId,
    required this.url,
    required this.title,
    required this.snippet,
    required this.fetchedUtc,
  });

  Map<String, Object?> toRow() => {
        'finding_id': findingId,
        'url': url,
        'title': title,
        'snippet': snippet,
        'fetched_utc': fetchedUtc,
      };

  factory ResearchSource.fromRow(Map<String, Object?> r) => ResearchSource(
        id: (r['id'] as num?)?.toInt(),
        findingId: (r['finding_id'] as num).toInt(),
        url: r['url'] as String,
        title: (r['title'] as String?) ?? '',
        snippet: (r['snippet'] as String?) ?? '',
        fetchedUtc: r['fetched_utc'] as String,
      );
}
