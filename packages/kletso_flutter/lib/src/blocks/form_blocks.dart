import 'package:flutter/material.dart';
import 'package:kletso_core/kletso_core.dart';

import '../registry/build_context.dart';
import '../theme/kletso_theme.dart';
import 'support.dart';

/// `confirm`: approve/deny a paused tool call.
Widget buildConfirmBlock(KletsoBuildContext ctx, KletsoNode node) {
  final t = ctx.theme;
  final toolCallId = node.string('toolCallId');
  KletsoAction confirmAction({required bool approve}) =>
      node.actions
          .whereType<KletsoConfirmAction>()
          .where((a) => a.approve == approve)
          .firstOrNull ??
      KletsoConfirmAction(
        id: approve ? 'yes' : 'no',
        toolCallId: toolCallId,
        approve: approve,
      );
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: t.warningSoft,
      borderRadius: t.borderRadiusLg,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.warning_amber_outlined, color: t.text, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                node.string('title', fallback: 'Please confirm'),
                style: t.title.copyWith(fontSize: 16),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(node.string('message'), style: t.body),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final cancel = KletsoButton(
              label: node.string('cancelLabel', fallback: 'Cancel'),
              variant: 'secondary',
              expanded: true,
              onPressed: () => ctx.execute(confirmAction(approve: false)),
            );
            final confirm = KletsoButton(
              label: node.string('confirmLabel', fallback: 'Confirm'),
              expanded: true,
              onPressed: () => ctx.execute(confirmAction(approve: true)),
            );
            if (constraints.maxWidth < 360) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[confirm, const SizedBox(height: 8), cancel],
              );
            }
            return Row(
              children: <Widget>[
                Expanded(child: cancel),
                const SizedBox(width: 8),
                Expanded(child: confirm),
              ],
            );
          },
        ),
      ],
    ),
  );
}

/// `form`: fields with validation; submit fires the node's `submit` action
/// with `{formId, values}`.
Widget buildFormBlock(KletsoBuildContext ctx, KletsoNode node) =>
    KletsoFormBlock(ctx: ctx, node: node);

/// `input`: one field; enter/submit fires the node's first action with
/// `{name: value}` as args.
Widget buildInputBlock(KletsoBuildContext ctx, KletsoNode node) =>
    KletsoFormBlock(
      ctx: ctx,
      node: node,
      fields: <JsonMap>[
        <String, Object?>{
          'name': node.string('name', fallback: 'value'),
          'kind': node.string('kind', fallback: 'text'),
          'label': node.string('label'),
          'placeholder': node.stringOrNull('placeholder'),
        },
      ],
      single: true,
    );

/// `select`: one select field.
Widget buildSelectBlock(KletsoBuildContext ctx, KletsoNode node) =>
    KletsoFormBlock(
      ctx: ctx,
      node: node,
      fields: <JsonMap>[
        <String, Object?>{
          'name': node.string('name', fallback: 'value'),
          'kind': 'select',
          'label': node.string('label'),
          'options': node.list('options'),
          'multiple': node.boolean('multiple'),
        },
      ],
      single: true,
    );

/// Stateful form used by `form`, `input` and `select`.
final class KletsoFormBlock extends StatefulWidget {
  /// Creates the form for [node]; [fields] overrides `props.fields`.
  const KletsoFormBlock({
    required this.ctx,
    required this.node,
    super.key,
    this.fields,
    this.single = false,
  });

  /// Build context of the surface.
  final KletsoBuildContext ctx;

  /// The form node.
  final KletsoNode node;

  /// Field definitions (defaults to `props.fields`).
  final List<JsonMap>? fields;

  /// `true` for `input`/`select` (no title, compact submit).
  final bool single;

  @override
  State<KletsoFormBlock> createState() => _KletsoFormBlockState();
}

final class _KletsoFormBlockState extends State<KletsoFormBlock> {
  final Map<String, Object?> _values = <String, Object?>{};
  final Map<String, String> _errors = <String, String>{};
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  bool _submitted = false;

  List<JsonMap> get _fields => widget.fields ?? widget.node.mapList('fields');

  @override
  void initState() {
    super.initState();
    for (final f in _fields) {
      final name = f['name'] as String? ?? '';
      if (f.containsKey('default')) _values[name] = f['default'];
      if (f['kind'] == 'toggle') _values[name] ??= false;
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controller(String name) => _controllers[name] ??=
      TextEditingController(text: _values[name]?.toString() ?? '');

  bool _validate() {
    _errors.clear();
    for (final f in _fields) {
      final name = f['name'] as String? ?? '';
      final value = _values[name];
      final required = f['required'] == true;
      final empty =
          value == null ||
          (value is String && value.trim().isEmpty) ||
          (value is List && value.isEmpty);
      if (required && empty) {
        _errors[name] = 'Required';
        continue;
      }
      if (empty) continue;
      switch (f['kind']) {
        case 'email':
          if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch('$value')) {
            _errors[name] = 'Enter a valid email';
          }
        case 'number':
          final n = value is num ? value : num.tryParse('$value');
          if (n == null) {
            _errors[name] = 'Enter a number';
          } else {
            final min = f['min'];
            final max = f['max'];
            if (min is num && n < min) _errors[name] = 'Minimum $min';
            if (max is num && n > max) _errors[name] = 'Maximum $max';
          }
        default:
          break;
      }
    }
    return _errors.isEmpty;
  }

  Future<void> _submit() async {
    setState(() => _submitted = true);
    if (!_validate()) {
      setState(() {});
      return;
    }
    final values = <String, Object?>{};
    for (final f in _fields) {
      final name = f['name'] as String? ?? '';
      var v = _values[name];
      if (f['kind'] == 'number' && v is String) v = num.tryParse(v) ?? v;
      values[name] = v;
    }
    final node = widget.node;
    final action =
        node.actions.whereType<KletsoSubmitAction>().firstOrNull ??
        node.actions.where((a) => a is! KletsoUnknownAction).firstOrNull;
    if (action == null) return;
    if (action is KletsoSubmitAction) {
      await widget.ctx.execute(action, args: values);
    } else {
      await widget.ctx.execute(action, args: values);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ctx.theme;
    final node = widget.node;
    final title = widget.single ? null : node.stringOrNull('title');
    final inputDecoration = InputDecorationTheme(
      filled: true,
      fillColor: t.surface,
      border: OutlineInputBorder(
        borderRadius: t.borderRadiusSm,
        borderSide: BorderSide(color: t.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: t.borderRadiusSm,
        borderSide: BorderSide(color: t.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: t.borderRadiusSm,
        borderSide: BorderSide(color: t.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: t.borderRadiusSm,
        borderSide: BorderSide(color: t.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: t.borderRadiusSm,
        borderSide: BorderSide(color: t.error, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      labelStyle: t.caption,
      hintStyle: t.body.copyWith(color: t.textMuted),
      errorStyle: t.caption.copyWith(color: t.error),
    );
    return Theme(
      data: Theme.of(context).copyWith(inputDecorationTheme: inputDecoration),
      child: Container(
        padding: EdgeInsets.all(widget.single ? 0 : 16),
        decoration: widget.single
            ? null
            : BoxDecoration(
                color: t.surface,
                borderRadius: t.borderRadiusLg,
                border: Border.all(color: t.line),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (title != null) ...<Widget>[
              Text(title, style: t.title),
              const SizedBox(height: 12),
            ],
            for (final f in _fields) ...<Widget>[
              _field(f, t),
              const SizedBox(height: 12),
            ],
            KletsoButton(
              label: node.string(
                'submitLabel',
                fallback: widget.single ? 'Send' : 'Submit',
              ),
              expanded: !widget.single,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(JsonMap f, KletsoTheme t) {
    final name = f['name'] as String? ?? '';
    final label = f['label'] as String? ?? name;
    final kind = f['kind'] as String? ?? 'text';
    final error = _submitted ? _errors[name] : null;
    final placeholder = f['placeholder'] as String?;
    switch (kind) {
      case 'toggle':
        return MergeSemantics(
          child: Row(
            children: <Widget>[
              Expanded(child: Text(label, style: t.body)),
              Switch(
                value: _values[name] == true,
                activeThumbColor: t.primary,
                onChanged: (v) => setState(() => _values[name] = v),
              ),
            ],
          ),
        );
      case 'select':
        final options = (f['options'] as List? ?? const <Object?>[])
            .whereType<Map<Object?, Object?>>()
            .toList();
        final multiple = f['multiple'] == true;
        if (multiple) {
          final selected = (_values[name] as List?)?.toSet() ?? <Object?>{};
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(label, style: t.caption),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final o in options)
                    FilterChip(
                      label: Text('${o['label'] ?? o['value']}'),
                      selected: selected.contains(o['value']),
                      selectedColor: t.primarySoft,
                      checkmarkColor: t.primary,
                      labelStyle: t.body,
                      side: BorderSide(color: t.line),
                      onSelected: (on) => setState(() {
                        final next = <Object?>{...selected};
                        if (on) {
                          next.add(o['value']);
                        } else {
                          next.remove(o['value']);
                        }
                        _values[name] = next.toList();
                      }),
                    ),
                ],
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(error, style: t.caption.copyWith(color: t.error)),
                ),
            ],
          );
        }
        return DropdownButtonFormField<Object?>(
          initialValue: _values[name],
          decoration: InputDecoration(labelText: label, errorText: error),
          style: t.body,
          dropdownColor: t.surface,
          items: <DropdownMenuItem<Object?>>[
            for (final o in options)
              DropdownMenuItem<Object?>(
                value: o['value'],
                child: Text('${o['label'] ?? o['value']}'),
              ),
          ],
          onChanged: (v) => setState(() => _values[name] = v),
        );
      case 'date':
        final value = _values[name]?.toString();
        return InkWell(
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.tryParse(value ?? '') ?? now,
              firstDate: now.subtract(const Duration(days: 365)),
              lastDate: now.add(const Duration(days: 365 * 2)),
            );
            if (picked != null && mounted) {
              setState(
                () => _values[name] = picked.toIso8601String().substring(0, 10),
              );
            }
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              errorText: error,
              suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
            ),
            child: Text(
              value ?? (placeholder ?? 'Pick a date'),
              style: value == null
                  ? t.body.copyWith(color: t.textMuted)
                  : t.body,
            ),
          ),
        );
      default:
        return TextField(
          controller: _controller(name),
          style: t.body,
          maxLines: kind == 'textarea' ? 4 : 1,
          keyboardType: switch (kind) {
            'email' => TextInputType.emailAddress,
            'number' => const TextInputType.numberWithOptions(decimal: true),
            'textarea' => TextInputType.multiline,
            _ => TextInputType.text,
          },
          textInputAction: kind == 'textarea'
              ? TextInputAction.newline
              : TextInputAction.done,
          decoration: InputDecoration(
            labelText: label,
            hintText: placeholder,
            errorText: error,
          ),
          onChanged: (v) => _values[name] = v,
          onSubmitted: widget.single ? (_) => _submit() : null,
        );
    }
  }
}
