import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/icons.dart';
import '../theme/motion.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';
import '../widgets/living_orb.dart';

/// The first screen (S03): the moon, the name, and one way in.
///
/// Its one job is to start, in your language. "Chat with Qamar" is the one
/// white button, and it goes straight into the conversation, with nothing in
/// between: one tap from here to the first question. A report is the other
/// way in, an outline under it. Then the guest line (no sign-up, and how
/// long it takes), the way back in and the invitation, and the fine print.
/// The language switch is the first thing on the page, so someone who does
/// not read Arabic can switch before anything is asked.
///
/// Centred, as only the welcome and an empty state are (the liquid-glass
/// skill). The moon takes what height the rest leaves; nothing else is ever
/// scaled, and a page that cannot fit even without the moon scrolls.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const boundaryKey = ValueKey('welcome-boundary');
  static const chatPillKey = ValueKey('welcome-chat');
  static const scanPillKey = ValueKey('welcome-scan');
  static const moonKey = ValueKey('welcome-moon');
  static const guestNoteKey = ValueKey('welcome-guest-note');
  static const noticeKey = ValueKey('welcome-notice');

  /// The invitation's link, which the words beside it name ("Have an
  /// invitation?").
  static String invitationLabel(bool ar) => ar ? 'عندك دعوة؟' : 'Have an invitation?';

  /// The moon at its largest, and the smallest still worth drawing.
  static const moonMax = 168.0, moonMin = 72.0;

  /// The air the moon keeps: above it, and between it and the name.
  static const moonAbove = 16.0, moonBelow = 24.0;

  /// The moon in a room [room] points tall: as large as the room allows, up
  /// to [moonMax], with its air; none at all where that would be under
  /// [moonMin].
  static double moonFor(double room) {
    final m = math.min(moonMax, room - moonAbove - moonBelow);
    return m >= moonMin ? m : 0;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;
    final isAr = state.isAr;
    final notice = state.invitationNotice;

    return LayoutBuilder(builder: (context, viewport) {
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: viewport.maxHeight),
          child: IntrinsicHeight(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(QSpace.page, QSpace.sm, QSpace.page, QSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: QLangToggle(lang: state.lang, onChanged: state.setLang, large: true),
                  ),
                  // The moon, in the room the rest of the page leaves; it
                  // sits on the name, and the room's spare sky is above it.
                  Expanded(
                    flex: 3,
                    child: _HeroRoom(
                      child: LayoutBuilder(builder: (context, box) {
                        final moon = moonFor(box.maxHeight);
                        if (moon == 0) return const SizedBox.shrink();
                        return Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(padding: const EdgeInsets.only(bottom: moonBelow), child: _Moon(size: moon)),
                        );
                      }),
                    ),
                  ),
                  Text(t.brand, textAlign: TextAlign.center, style: QText.display(size: 34, ar: QText.arabic(t.brand))),
                  const SizedBox(height: QSpace.sm),
                  QBalancedText(t.promise, maxWidth: 320, style: QText.body(size: 17, color: QColors.inkSecondary)),
                  // Room before the ways in: a share of the spare height, and
                  // never less than this.
                  const Expanded(child: SizedBox(height: QSpace.xxl)),
                  // The one thing to do. A consultation left part-way is
                  // carried on, and the button says so.
                  QPrimaryButton(
                    key: chatPillKey,
                    label: state.consultationPaused ? t.next : t.chatDirect,
                    onTap: state.startOnboarding,
                  ),
                  const SizedBox(height: QSpace.sm),
                  QOutlineButton(key: scanPillKey, label: t.scanInbody, icon: QIcons.scan, onTap: state.openScan),
                  const SizedBox(height: QSpace.md),
                  QBalancedText(t.guestNote, textKey: guestNoteKey, style: QText.body(size: 13, color: QColors.inkTertiary)),
                  const SizedBox(height: QSpace.xs),
                  // The way back in (the sheet it opens has Google, Apple,
                  // Facebook and email) and a friend's invitation: two quiet
                  // links on one line, alike.
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: QSpace.sm,
                    children: [
                      _Link(label: t.haveAccount, onTap: state.openSignIn),
                      _Link(
                        label: invitationLabel(isAr),
                        onTap: state.invitationBusy ? null : () => _askInvitationCode(context, state),
                      ),
                    ],
                  ),
                  // What happened to an invitation: in the first ink when it
                  // is good news, the inviter named or not; in the second when
                  // it did not happen. The words say which.
                  if (notice != null) ...[
                    QBalancedText(
                      notice,
                      textKey: noticeKey,
                      maxWidth: 320,
                      style: QText.body(size: 13, color: state.invitationNoticeGood ? QColors.ink : QColors.inkSecondary),
                    ),
                    const SizedBox(height: QSpace.md),
                  ] else
                    const SizedBox(height: QSpace.xs),
                  QBalancedText(t.boundary, textKey: boundaryKey, maxWidth: 320, style: QText.body(size: 11, height: 16, color: QColors.inkTertiary)),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// The welcome's moon: the orb at rest, arriving by growing out of the dark.
/// With reduce-motion on it arrives by a fade and then holds still: its
/// breath, halo and drift are paused, not merely slowed.
class _Moon extends StatelessWidget {
  final double size;
  const _Moon({required this.size});

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      width: size,
      height: size,
      child: ExcludeSemantics(
        child: QSpringIn(
          arrive: QArrive.grow,
          child: TickerMode(
            enabled: !still,
            child: LivingOrb(
              key: WelcomeScreen.moonKey,
              size: size,
              wander: true,
              wanderDuration: QMotion.floatWelcomeOrb,
              haloDuration: QMotion.haloWelcome,
            ),
          ),
        ),
      ),
    );
  }
}

/// The moon's room in the page's column. It asks for no height of its own
/// when the page is measured (the moon takes its size from the room, so it
/// has none to give), and lays the moon out in whatever it is handed.
class _HeroRoom extends SingleChildRenderObjectWidget {
  const _HeroRoom({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHeroRoom();
}

class _RenderHeroRoom extends RenderProxyBox {
  @override
  double computeMinIntrinsicHeight(double width) => 0;
  @override
  double computeMaxIntrinsicHeight(double width) => 0;
  @override
  double computeMinIntrinsicWidth(double height) => 0;
  @override
  double computeMaxIntrinsicWidth(double height) => 0;
  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(Size(constraints.maxWidth, 0));
}

/// A quiet action: words in the second ink, a whole touch, brighter under
/// the finger. With nothing to do, the disabled ink.
class _Link extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _Link({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return QTapArea(
      onTap: onTap,
      builder: (context, pressed) => qPressed(
        context,
        pressed: pressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: QSpace.md),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: QText.body(
              size: 15,
              weight: FontWeight.w500,
              color: onTap == null ? QDisabled.label : (pressed ? QColors.ink : QColors.inkSecondary),
            ),
          ),
        ),
      ),
    );
  }
}

/// A friend's invitation code, asked in a sheet over the welcome: one field
/// and one button. It closes with the grabber's swipe, the scrim or its
/// close; what is typed goes to the invitation, and its notice is said on
/// the welcome under the link.
Future<void> _askInvitationCode(BuildContext context, AppState state) async {
  final code = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    // The sheet draws its own frosted glass (QSheetGlass).
    backgroundColor: Colors.transparent,
    barrierColor: QColors.scrim,
    elevation: 0,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(QRadii.sheet))),
    builder: (_) => _InvitationSheet(initial: state.pendingInvitationCode ?? '', isAr: state.isAr),
  );
  if (code != null && code.trim().isNotEmpty) await state.redeemInvitation(code);
}

class _InvitationSheet extends StatefulWidget {
  final String initial;
  final bool isAr;
  const _InvitationSheet({required this.initial, required this.isAr});

  @override
  State<_InvitationSheet> createState() => _InvitationSheetState();
}

class _InvitationSheetState extends State<_InvitationSheet> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _use() => Navigator.of(context).pop(_ctrl.text);

  @override
  Widget build(BuildContext context) {
    final ar = widget.isAr;
    OutlineInputBorder edge(Color c, [double w = 1]) => OutlineInputBorder(borderRadius: BorderRadius.circular(QRadii.control), borderSide: BorderSide(color: c, width: w));
    return Padding(
      // Above the keyboard, which the field opens with.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: QSheetGlass(
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(QSpace.page, QSpace.md, QSpace.page, QSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 5,
                    decoration: BoxDecoration(color: QColors.hairlineStrong, borderRadius: BorderRadius.circular(QRadii.pill)),
                  ),
                ),
                const SizedBox(height: QSpace.sm),
                Row(
                  children: [
                    QRoundIconButton(icon: QIcons.close, onTap: () => Navigator.of(context).pop(), label: ar ? 'اقفل' : 'Close'),
                    const SizedBox(width: QSpace.xs),
                    Expanded(child: Text(ar ? 'كود الدعوة' : 'Invitation code', style: QText.display(size: 22, ar: ar))),
                  ],
                ),
                const SizedBox(height: QSpace.lg),
                TextField(
                  controller: _ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  textDirection: TextDirection.ltr,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _use(),
                  cursorColor: QColors.accentInk,
                  style: QText.number(size: 17),
                  decoration: InputDecoration(
                    hintText: 'QMR-XXXXX',
                    hintTextDirection: TextDirection.ltr,
                    hintStyle: QText.number(size: 17, color: QColors.inkTertiary),
                    filled: true,
                    fillColor: QColors.surfaceRaised,
                    contentPadding: const EdgeInsets.symmetric(horizontal: QSpace.lg, vertical: 15),
                    border: edge(QColors.hairline),
                    enabledBorder: edge(QColors.hairline),
                    focusedBorder: edge(QColors.hairlineStrong, 1.5),
                  ),
                ),
                const SizedBox(height: QSpace.lg),
                QPrimaryButton(label: ar ? 'استخدم الكود' : 'Use code', onTap: _use),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
