import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import 'common.dart';

/// What to avoid, changed from Me (gap 4): the consultation's own question
/// and choices, with the current ones picked, and Save. The account's copy
/// is saved before anything changes on the phone ([AppState.saveAvoid]); if
/// that fails the sheet stays open and says so.
class AvoidEditor extends StatefulWidget {
  final AppState state;
  const AvoidEditor({super.key, required this.state});

  static const saveKey = ValueKey('avoid-save');
  static Key chipKey(String value) => ValueKey('avoid-$value');

  static Future<void> show(BuildContext context, AppState state) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: QColors.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(QRadii.sheet))),
        builder: (_) => AvoidEditor(state: state),
      );

  @override
  State<AvoidEditor> createState() => _AvoidEditorState();
}

class _AvoidEditorState extends State<AvoidEditor> {
  late final Set<String> _picked = {...widget.state.profile.prefs};

  /// A save from this sheet has failed: its notice is shown here. A notice
  /// from an earlier change belongs to Me, not to this sheet.
  bool _failed = false;

  void _toggle(String value) => setState(() {
        if (value == 'none') {
          _picked.clear();
        } else if (!_picked.remove(value)) {
          _picked.add(value);
        }
      });

  Future<void> _save() async {
    final saved = await widget.state.saveAvoid(_picked);
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
    } else {
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final isAr = state.isAr;
        final step = AppState.avoidStep;
        return Directionality(
          textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(step.ask(isAr), style: QText.body(size: 15, height: 22, color: QColors.ink)),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final o in step.options)
                        QPillChip(
                          key: AvoidEditor.chipKey(o.value as String),
                          label: isAr ? o.ar : o.en,
                          selected: o.value == 'none' ? _picked.isEmpty : _picked.contains(o.value),
                          onTap: () => _toggle(o.value as String),
                        ),
                    ],
                  ),
                  if (_failed && !state.avoidBusy && state.avoidNotice != null) ...[
                    const SizedBox(height: 12),
                    Text(state.avoidNotice!, style: QText.body(size: 13, height: 20, color: QColors.inkSecondary)),
                  ],
                  const SizedBox(height: 16),
                  QPrimaryButton(
                    key: AvoidEditor.saveKey,
                    label: isAr ? 'احفظ' : 'Save',
                    onTap: state.avoidBusy ? null : _save,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
