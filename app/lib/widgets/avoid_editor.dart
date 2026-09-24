import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/icons.dart';
import '../theme/text_styles.dart';
import 'account_sheet.dart';
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

  /// The row's name on Me, and the sheet's title.
  static String title({required bool isAr}) => isAr ? 'اللي بتتجنبه' : 'What to avoid';

  static Future<void> show(BuildContext context, AppState state) => SheetPanel.open(context, (_) => AvoidEditor(state: state));

  @override
  State<AvoidEditor> createState() => _AvoidEditorState();
}

class _AvoidEditorState extends State<AvoidEditor> {
  late final Set<String> _picked = {...widget.state.profile.prefs};

  /// A save from this sheet has failed: its notice is shown here. A notice
  /// from an earlier change belongs to Me, not to this sheet.
  bool _failed = false;

  void _toggle(String value) => setState(() {
        _failed = false;
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
      SheetPanel.close(context);
    } else {
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final isAr = state.isAr;
        final step = AppState.avoidStep;
        return SheetPanel(
          title: AvoidEditor.title(isAr: isAr),
          onClose: () => SheetPanel.close(context),
          primary: QPrimaryButton(
            key: AvoidEditor.saveKey,
            label: state.avoidBusy ? (isAr ? 'بحفظ…' : 'Saving…') : (isAr ? 'احفظ' : 'Save'),
            onTap: state.avoidBusy ? null : _save,
          ),
          children: [
            Text(step.ask(isAr), style: QText.body(size: 17, color: QColors.inkSecondary)),
            const SizedBox(height: QSpace.lg),
            Wrap(
              spacing: QSpace.sm,
              runSpacing: QSpace.sm,
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
              const SizedBox(height: QSpace.lg),
              QStateLine(line: state.avoidNotice!, icon: QIcons.offline),
            ],
          ],
        );
      },
    );
  }
}
