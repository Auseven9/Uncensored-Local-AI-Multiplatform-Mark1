import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/params/param_spec.dart';
import '../../core/params/parameters_service.dart';
import '../../theme/app_colors.dart';

/// Every AETHER parameter, adjustable. Rendered from [aetherParamRegistry], so
/// new knobs appear here automatically.
class ParametersScreen extends StatefulWidget {
  const ParametersScreen({super.key});

  @override
  State<ParametersScreen> createState() => _ParametersScreenState();
}

class _ParametersScreenState extends State<ParametersScreen> {
  final ParametersService _svc = Get.find<ParametersService>();
  String _q = '';

  bool _matches(ParamSpec p) {
    if (_q.isEmpty) return true;
    final q = _q.toLowerCase();
    return p.label.toLowerCase().contains(q) ||
        p.key.toLowerCase().contains(q) ||
        p.group.toLowerCase().contains(q);
  }

  Future<void> _confirmResetAll() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset all parameters?'),
        content: const Text('Every parameter returns to its default value.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () {
              Navigator.of(ctx).pop();
              _svc.resetAll();
            },
            child: const Text('Reset all'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        title: const Text('Parameters'),
        actions: [
          IconButton(
            tooltip: 'Reset all',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: _confirmResetAll,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              style: TextStyle(color: context.text, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search parameters…',
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
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Some parameters take effect as their subsystem ships (see phases).',
              style: TextStyle(color: context.textD, fontSize: 11),
            ),
          ),
          Expanded(
            child: Obx(() {
              // Touch the map so the list rebuilds on any change.
              final _ = _svc.values.length;
              final items = <Widget>[];
              for (final g in _svc.groups) {
                final params = aetherParamRegistry
                    .where((p) => p.group == g && _matches(p))
                    .toList();
                if (params.isEmpty) continue;
                items.add(_GroupHeader(title: g));
                for (final p in params) {
                  items.add(_ParamRow(spec: p, svc: _svc));
                }
              }
              if (items.isEmpty) {
                return Center(
                  child: Text('No matching parameters',
                      style: TextStyle(color: context.textD)),
                );
              }
              return ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: items,
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String title;
  const _GroupHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: AppColors.accent,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ParamRow extends StatefulWidget {
  final ParamSpec spec;
  final ParametersService svc;
  const _ParamRow({required this.spec, required this.svc});

  @override
  State<_ParamRow> createState() => _ParamRowState();
}

class _ParamRowState extends State<_ParamRow> {
  double? _dragging;
  TextEditingController? _strCtrl;

  @override
  void initState() {
    super.initState();
    if (widget.spec.type == ParamType.stringType) {
      _strCtrl =
          TextEditingController(text: widget.svc.getString(widget.spec.key));
    }
  }

  @override
  void dispose() {
    _strCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.spec;
    final svc = widget.svc;
    final overridden = svc.isOverridden(s.key);

    final trailing = <Widget>[];
    if (s.type == ParamType.boolType) {
      trailing.add(Switch(
        value: svc.getBool(s.key),
        activeColor: AppColors.accent,
        onChanged: (v) => svc.set(s.key, v),
      ));
    }
    if (overridden) {
      trailing.add(IconButton(
        tooltip: 'Reset to default',
        icon: Icon(Icons.undo_rounded, size: 18, color: context.textM),
        onPressed: () {
          svc.reset(s.key);
          if (s.type == ParamType.stringType) {
            _strCtrl?.text = svc.getString(s.key);
          }
          setState(() {});
        },
      ));
    }

    final children = <Widget>[
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.label,
                    style: TextStyle(
                        color: context.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
                if (s.help != null)
                  Text(s.help!,
                      style: TextStyle(color: context.textD, fontSize: 11)),
              ],
            ),
          ),
          ...trailing,
        ],
      ),
    ];

    if (s.type == ParamType.doubleType || s.type == ParamType.intType) {
      children.add(_slider(context, s, svc));
    } else if (s.type == ParamType.stringType) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: TextField(
          controller: _strCtrl,
          style: TextStyle(color: context.text, fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: context.bgInput,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: context.border),
            ),
          ),
          onSubmitted: (v) => svc.set(s.key, v),
        ),
      ));
    }

    children.add(Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text('key: ${s.key}',
          style: TextStyle(
              color: context.textD, fontSize: 10, fontFamily: 'monospace')),
    ));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...children,
          Divider(color: context.borderFaint, height: 18),
        ],
      ),
    );
  }

  Widget _slider(BuildContext context, ParamSpec s, ParametersService svc) {
    final isInt = s.type == ParamType.intType;
    final min = s.min ?? 0.0;
    final max = s.max ?? 1.0;
    final current = _dragging ??
        (isInt ? svc.getInt(s.key).toDouble() : svc.getDouble(s.key));
    final value = current.clamp(min, max).toDouble();
    final divisions =
        isInt ? (max - min).round().clamp(1, 1000) : null;
    final display = isInt ? value.round().toString() : value.toStringAsFixed(2);

    return Row(
      children: [
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: display,
            activeColor: AppColors.accent,
            onChanged: (v) => setState(() => _dragging = v),
            onChangeEnd: (v) {
              svc.set(s.key,
                  isInt ? v.round() : double.parse(v.toStringAsFixed(3)));
              setState(() => _dragging = null);
            },
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(display,
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: context.text,
                  fontSize: 13,
                  fontFamily: 'monospace')),
        ),
      ],
    );
  }
}
