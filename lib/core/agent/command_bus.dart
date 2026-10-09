/// The Command Bus — the agent's single validated execution path.
///
/// In the cerebrum/cerebellum split, this is the cerebellum's hands: the LLM
/// (cerebrum) *reasons* about what to do; the Command Bus *executes* it. Every
/// executable operation — from the UI, from the multi-step agent, and from the
/// Autopilot — goes through here, so there is exactly ONE place that validates
/// arguments, distinguishes read-only from state-mutating actions, and turns a
/// request into a structured result. The model never touches SQLite or device
/// state directly; it proposes a command, the bus validates and runs it. Runtime
/// owns execution (spec §1.3).
///
/// Pure and dependency-free: it only routes. Handlers (which touch memory, tools,
/// the device) are registered by the layers that own those capabilities. Unit-
/// tested; wired to real tools in the next agentic phase.
library;

/// A request to run a named operation with arguments.
class AppCommand {
  final String name;
  final Map<String, Object?> args;
  const AppCommand(this.name, [this.args = const {}]);

  @override
  String toString() => 'AppCommand($name, $args)';
}

/// The structured outcome of a command — never an exception across the boundary.
class CommandResult {
  final bool ok;
  final Object? value;
  final String? error;
  const CommandResult._(this.ok, this.value, this.error);

  factory CommandResult.ok([Object? value]) =>
      CommandResult._(true, value, null);
  factory CommandResult.fail(String error) =>
      CommandResult._(false, null, error);

  @override
  String toString() => ok ? 'ok($value)' : 'fail($error)';
}

typedef CommandHandler = Future<CommandResult> Function(AppCommand cmd);

/// The contract for one command: its [name], a [description] the agent sees when
/// choosing a tool, which [requiredArgs] must be present, whether it only reads
/// ([readOnly]) or mutates state, and the [handler] that performs it.
class CommandSpec {
  final String name;
  final String description;
  final List<String> requiredArgs;
  final bool readOnly;
  final CommandHandler handler;

  const CommandSpec({
    required this.name,
    required this.description,
    this.requiredArgs = const [],
    this.readOnly = true,
    required this.handler,
  });
}

/// Registers commands and dispatches to them with validation + error capture.
class CommandBus {
  final Map<String, CommandSpec> _specs = {};

  void register(CommandSpec spec) => _specs[spec.name] = spec;
  bool has(String name) => _specs.containsKey(name);
  CommandSpec? spec(String name) => _specs[name];
  List<CommandSpec> get specs => _specs.values.toList(growable: false);

  /// The tool catalogue the agent is shown — name, description, required args,
  /// and whether the action is read-only. This is what the reasoning step picks
  /// from; mutating tools can be gated/confirmed separately by their callers.
  List<Map<String, Object?>> toolCatalog() => [
        for (final s in _specs.values)
          {
            'name': s.name,
            'description': s.description,
            'required_args': s.requiredArgs,
            'read_only': s.readOnly,
          }
      ];

  /// Validate [cmd] against its spec and run it. An unknown command, a missing
  /// required arg, or a thrown handler all come back as a failed [CommandResult]
  /// — the bus never throws, so a bad agent action can degrade to an error
  /// observation the loop can react to, not a process crash.
  Future<CommandResult> dispatch(AppCommand cmd) async {
    final s = _specs[cmd.name];
    if (s == null) {
      return CommandResult.fail('unknown command: ${cmd.name}');
    }
    for (final k in s.requiredArgs) {
      if (!cmd.args.containsKey(k) || cmd.args[k] == null) {
        return CommandResult.fail(
            'missing required arg "$k" for ${cmd.name}');
      }
    }
    try {
      return await s.handler(cmd);
    } catch (e) {
      return CommandResult.fail('command "${cmd.name}" threw: $e');
    }
  }
}
