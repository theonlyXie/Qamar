import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/icons.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';
import '../widgets/kit.dart';
import '../widgets/mascot.dart';

/// The first screen (S03), the Nutri AI kit's onboarding page: the whole
/// screen lavender, the moon waving, the name, the promise, and at the foot
/// the kit's round black button in its white bump.
///
/// Its one job is to start, in your language. "Chat with Qamar" is that one
/// round button, and it goes straight into the conversation, with nothing in
/// between: one tap from here to the first question. A report is the other
/// way in, a white capsule above it. Then the guest line (no sign-up, and
/// how long it takes), the way back in and the invitation, and the fine
/// print. The language switch is the first thing on the page, so someone
/// who does not read Arabic can switch before anything is asked.
///
/// Centred, as only the welcome and an empty state are (the qamar-design
/// skill). The moon takes what height the rest leaves; nothing else is ever
/// scaled, and a page that cannot fit even without the moon scrolls. The
/// lavender and the bump are drawn under the phone's own bars by
/// [WelcomeBackdrop], in the shell.
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

  /// The moon at its largest, and the smallest still worth drawing: its
  /// height, the mascot standing with its sparkles.
  static const moonMax = 280.0, moonMin = 96.0;

  /// The air the moon keeps: above it, and between it and the name.
  static const moonAbove = 8.0, moonBelow = 20.0;

  /// The moon in a room [room] points tall: as large as the room allows, up
  /// to [moonMax], with its air; none at all where that would be under
  /// [moonMin].
  static double moonFor(double room) {
    final m = math.min(moonMax, room - moonAbove - moonBelow);
    return m >= moonMin ? m : 0;
  }

  /// The round button and the bump it sits in: the button's size, the
  /// bump's width and how far its top rises over the foot of the page.
  static const startSize = 88.0, bumpWidth = 128.0, bumpRise = 120.0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;
    final isAr = state.isAr;
    final notice = state.invitationNotice;

    // Black words and the phone's own bar in dark ink, on the lavender.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: LayoutBuilder(builder: (context, viewport) {
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: viewport.maxHeight),
          child: IntrinsicHeight(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(QSpace.page, QSpace.sm, QSpace.page, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: QLangToggle(lang: state.lang, onChanged: state.setLang, large: true),
                  ),
                  // The moon, in the room the rest of the page leaves; it
                  // stands over the name, and the room's spare sky is above.
                  Expanded(
                    flex: 3,
                    child: _HeroRoom(
                      child: LayoutBuilder(builder: (context, box) {
                        final moon = moonFor(box.maxHeight);
                        if (moon == 0) return const SizedBox.shrink();
                        return Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(padding: const EdgeInsets.only(bottom: moonBelow), child: _Moon(height: moon)),
                        );
                      }),
                    ),
                  ),
                  Text(t.brand, textAlign: TextAlign.center, style: QText.display(size: 34, ar: QText.arabic(t.brand), color: QColors.onPastel)),
                  const SizedBox(height: QSpace.xs),
                  QBalancedText(t.promise, maxWidth: 320, style: QText.body(size: 17, color: QColors.onPastelSecondary)),
                  // Room before the ways in: a share of the spare height, and
                  // never less than this.
                  const Expanded(child: SizedBox(height: QSpace.xl)),
                  Center(child: QPastelButton(key: scanPillKey, label: t.scanInbody, icon: QIcons.scan, light: true, height: 44, onTap: state.openScan)),
                  const SizedBox(height: QSpace.sm),
                  QBalancedText(t.guestNote, textKey: guestNoteKey, style: QText.body(size: 13, color: QColors.onPastelSecondary)),
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
                      style: QText.body(size: 13, weight: FontWeight.w500, color: state.invitationNoticeGood ? QColors.onPastel : QColors.onPastelSecondary),
                    ),
                    const SizedBox(height: QSpace.sm),
                  ],
                  QBalancedText(t.boundary, textKey: boundaryKey, maxWidth: 320, style: QText.body(size: 12, height: 16, color: QColors.onPastelSecondary)),
                  const SizedBox(height: QSpace.sm),
                  // The one thing to do, in its bump, which the backdrop runs on
                  // under the home indicator. A consultation left part-way is
                  // carried on, and the button says so.
                  Center(
                    child: Container(
                      width: bumpWidth,
                      height: bumpRise,
                      alignment: const Alignment(0, 0.35),
                      decoration: const BoxDecoration(
                        color: QColors.white,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(QRadii.pill)),
                      ),
                      child: _Start(
                        key: chatPillKey,
                        label: state.consultationPaused ? t.next : t.chatDirect,
                        onTap: state.startOnboarding,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }),
    );
  }
}

/// The welcome's ground, drawn by the shell under the phone's own bars: the
/// lavender to every edge, and under the home indicator the foot of the
/// white bump the page draws, so the bump runs on to the screen's edge.
class WelcomeBackdrop extends StatelessWidget {
  const WelcomeBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ColoredBox(
      color: QColors.lavender,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(width: WelcomeScreen.bumpWidth, height: bottom, child: const ColoredBox(color: QColors.white)),
      ),
    );
  }
}

/// The kit's round black button: the words and an arrow the way the
/// reading goes.
class _Start extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _Start({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => QTapArea(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        label: label,
        builder: (context, pressed) => qPressed(
          context,
          pressed: pressed,
          child: Container(
            width: WelcomeScreen.startSize,
            height: WelcomeScreen.startSize,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(shape: BoxShape.circle, color: pressed ? QColors.surface : QColors.canvas),
            child: ExcludeSemantics(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(label, textAlign: TextAlign.center, maxLines: 2, style: QText.body(size: 13, height: 16, weight: FontWeight.w600, color: QColors.ink)),
                const SizedBox(height: 2),
                const QIcon(QIcons.forward, size: 18, color: QColors.ink),
              ]),
            ),
          ),
        ),
      );
}

/// The welcome's moon: the mascot, waving, arriving by growing a little into
/// place. With reduce-motion on it arrives by a fade.
class _Moon extends StatelessWidget {
  final double height;
  const _Moon({required this.height});

  @override
  Widget build(BuildContext context) {
    final width = height / MoonMascot.heightFor(1, full: true);
    return SizedBox(
      width: width,
      height: height,
      child: QSpringIn(
        arrive: QArrive.grow,
        child: MoonMascot(key: WelcomeScreen.moonKey, size: width, full: true),
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

/// A quiet action on the lavender: black words, a whole touch, a step
/// lighter under the finger. With nothing to do, the second ink.
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
              weight: FontWeight.w600,
              color: onTap == null || pressed ? QColors.onPastelSecondary : QColors.onPastel,
            ).copyWith(decoration: TextDecoration.underline, decorationColor: QColors.onPastelSecondary),
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
    // The sheet draws its own frosted glass (QSheetSurface).
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
    return Padding(
      // Above the keyboard, which the field opens with.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: QSheetSurface(
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(QSpace.page, QSpace.md, QSpace.page, QSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: QSheetGrabber()),
                const SizedBox(height: QSpace.sm),
                Row(
                  children: [
                    QRoundIconButton(icon: QIcons.close, onTap: () => Navigator.of(context).pop(), label: ar ? 'اقفل' : 'Close'),
                    const SizedBox(width: QSpace.xs),
                    Expanded(child: Text(ar ? 'كود الدعوة' : 'Invitation code', style: QText.display(size: 24, ar: ar))),
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
                  style: QText.number(size: 17),
                  // The kit's field (the theme's): the ground in a grey edge.
                  decoration: InputDecoration(
                    hintText: 'QMR-XXXXX',
                    hintTextDirection: TextDirection.ltr,
                    hintStyle: QText.number(size: 17, color: QColors.inkTertiary),
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
