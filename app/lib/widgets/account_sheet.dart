import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/icons.dart';
import '../theme/motion.dart';
import '../theme/text_styles.dart';
import 'common.dart';

/// A sheet's panel, drawn the one way every sheet from Me is (the mono-glass
/// sheet): the surface with 32-point top corners under a strong top edge, a
/// grabber, the close on the leading side beside the title, what the sheet
/// holds — scrolling when it is taller than the room — and at most one
/// primary at its foot, with [footer] (a quiet action) under it.
///
/// The account sheet is hosted by the shell; the sheets Me opens are pushed
/// with [open], which puts them above everything, the orb included.
class SheetPanel extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  final List<Widget> children;
  final Widget? primary;
  final Widget? footer;

  const SheetPanel({super.key, required this.title, required this.onClose, required this.children, this.primary, this.footer});

  static const closeKey = ValueKey('sheet-close');

  /// Opens the sheet [builder] draws over everything on the root navigator,
  /// on the kit's own sheet ([QSheetScrim]): it rises on the settle spring,
  /// follows a drag, and leaves the way it came, whether its close, the scrim,
  /// a drag or the phone's back sent it away. [SheetPanel.close] from inside
  /// it does the same.
  static Future<void> open(BuildContext context, WidgetBuilder builder) => Navigator.of(context).push(_SheetRoute(builder));

  /// Sends the sheet [context] is in away, the way it came.
  static void close(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route != null && route.isCurrent) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isAr = Directionality.of(context) == TextDirection.rtl;
    // The keyboard, when it is up, or the home indicator: whichever is taller.
    final bottom = math.max(mq.viewInsets.bottom, mq.padding.bottom);
    // A sheet pushed over the page has no page under it to print its fields
    // on: this transparent material is theirs.
    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: math.max(0, mq.size.height - mq.padding.top - QSpace.xxl)),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: QColors.surface,
            border: Border(top: BorderSide(color: QColors.hairlineStrong)),
            borderRadius: BorderRadius.vertical(top: Radius.circular(QRadii.sheet)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(QSpace.page, QSpace.sm, QSpace.page, QSpace.lg + bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The grabber: where a finger takes the sheet down.
                Center(
                  child: Container(
                    width: 36,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: QSpace.md),
                    decoration: const BoxDecoration(color: QColors.hairlineStrong, borderRadius: BorderRadius.all(Radius.circular(QRadii.pill))),
                  ),
                ),
                Row(children: [
                  QRoundIconButton(key: closeKey, icon: QIcons.close, onTap: onClose, size: 34, label: isAr ? 'إغلاق' : 'Close'),
                  const SizedBox(width: QSpace.sm),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(title, style: QText.display(size: 22, ar: QText.arabic(title))),
                    ),
                  ),
                ]),
                const SizedBox(height: QSpace.lg),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
                  ),
                ),
                if (primary != null) ...[
                  const SizedBox(height: QSpace.xl),
                  primary!,
                ],
                if (footer != null) footer!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The route behind [SheetPanel.open]: nothing of its own to draw or animate.
/// The kit's sheet does the rising and the leaving; this holds it on screen
/// until it has left ([QSheetSlot]), and tells it when it is being sent away.
class _SheetRoute extends PopupRoute<void> {
  final WidgetBuilder builder;
  _SheetRoute(this.builder);

  final _open = ValueNotifier<bool>(true);

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => Duration.zero;

  /// Long enough for the settle spring to take the sheet off screen.
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 420);

  @override
  bool didPop(void result) {
    _open.value = false;
    return super.didPop(result);
  }

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    return ValueListenableBuilder<bool>(
      valueListenable: _open,
      child: Builder(builder: builder),
      builder: (context, open, sheet) => Stack(children: [
        QSheetSlot(
          open: open,
          child: Positioned.fill(
            child: QSheetScrim(
              blur: 8,
              onDismiss: () {
                if (isCurrent) navigator?.pop();
              },
              child: sheet!,
            ),
          ),
        ),
      ]),
    );
  }
}

/// A small light that breathes while something is on its way (the skill's
/// waiting: 2.4 s, full to half and back), and holds still under reduce
/// motion. Never a spinner alone: it always sits beside words.
class BreathingDot extends StatefulWidget {
  final Color color;
  final double size;
  const BreathingDot({super.key, this.color = QColors.ink, this.size = 8});

  @override
  State<BreathingDot> createState() => _BreathingDotState();
}

class _BreathingDotState extends State<BreathingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: QMotion.ring);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Opacity(
            opacity: _c.isAnimating ? 0.75 + 0.25 * math.cos(2 * math.pi * _c.value) : 1,
            child: Container(width: widget.size, height: widget.size, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color)),
          ),
        ),
      );
}

/// One-tap sign-in with Google, Apple or Facebook, one under the other: a
/// tap and no typing, which is the whole point of offering them. Apple sits
/// with the other two rather than being optional: App Store review requires
/// it wherever another third-party login is offered.
///
/// These call `linkIdentity` for a guest, so everything logged before signing
/// in keeps the same user id and survives.
class ProviderRow extends StatelessWidget {
  const ProviderRow({super.key});

  /// Each provider's button, for tests.
  static Key buttonKey(OAuthChoice choice) => ValueKey('provider-${choice.name}');

  static const _providers = <(OAuthChoice, String)>[
    (OAuthChoice.google, 'Google'),
    (OAuthChoice.apple, 'Apple'),
    (OAuthChoice.facebook, 'Facebook'),
  ];

  /// The mark each provider is drawn with: Google's "G" in its own four
  /// colours, the one place colour is allowed; Apple's and Facebook's in ink.
  static Widget mark(OAuthChoice choice, {required bool enabled}) => switch (choice) {
        OAuthChoice.google => Opacity(opacity: enabled ? 1 : 0.4, child: const GoogleMark(size: 20)),
        OAuthChoice.apple => Icon(QIcons.appleMark, size: 22, color: enabled ? QColors.ink : QDisabled.label),
        OAuthChoice.facebook => Icon(QIcons.facebookMark, size: 22, color: enabled ? QColors.ink : QDisabled.label),
      };

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, (choice, name)) in _providers.indexed) ...[
          if (i > 0) const SizedBox(height: QSpace.sm),
          _ProviderButton(
            key: buttonKey(choice),
            choice: choice,
            label: isAr ? 'كمّل بـ $name' : 'Continue with $name',
            busyLabel: isAr ? 'بنفتح $name…' : 'Opening $name…',
            // Only the provider being used shows the wait; the other two
            // rest until it is done.
            busy: state.authBusy && state.authProvider == choice,
            enabled: !state.authBusy,
            onTap: () => state.signInWith(choice),
          ),
        ],
      ],
    );
  }
}

/// Google's "G", drawn from its published 48-unit artwork, in its four
/// colours.
class GoogleMark extends StatelessWidget {
  final double size;
  const GoogleMark({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) => SizedBox.square(dimension: size, child: const CustomPaint(painter: _GooglePainter()));
}

class _GooglePainter extends CustomPainter {
  const _GooglePainter();

  static final _parts = <(Color, Path)>[
    (
      QBrandMarks.googleRed,
      Path()
        ..moveTo(24, 9.5)
        ..cubicTo(27.54, 9.5, 30.71, 10.72, 33.21, 13.1)
        ..lineTo(40.06, 6.25)
        ..cubicTo(35.9, 2.38, 30.47, 0, 24, 0)
        ..cubicTo(14.62, 0, 6.51, 5.38, 2.56, 13.22)
        ..lineTo(10.54, 19.41)
        ..cubicTo(12.43, 13.72, 17.74, 9.5, 24, 9.5)
        ..close()
    ),
    (
      QBrandMarks.googleBlue,
      Path()
        ..moveTo(46.98, 24.55)
        ..cubicTo(46.98, 22.98, 46.83, 21.46, 46.6, 20)
        ..lineTo(24, 20)
        ..lineTo(24, 29.02)
        ..lineTo(36.94, 29.02)
        ..cubicTo(36.36, 31.98, 34.68, 34.5, 32.16, 36.2)
        ..lineTo(39.89, 42.2)
        ..cubicTo(44.4, 38.02, 46.98, 31.84, 46.98, 24.55)
        ..close()
    ),
    (
      QBrandMarks.googleYellow,
      Path()
        ..moveTo(10.53, 28.59)
        ..cubicTo(10.05, 27.14, 9.77, 25.6, 9.77, 24)
        ..cubicTo(9.77, 22.4, 10.04, 20.86, 10.53, 19.41)
        ..lineTo(2.55, 13.22)
        ..cubicTo(0.92, 16.46, 0, 20.12, 0, 24)
        ..cubicTo(0, 27.88, 0.92, 31.54, 2.56, 34.78)
        ..lineTo(10.53, 28.59)
        ..close()
    ),
    (
      QBrandMarks.googleGreen,
      Path()
        ..moveTo(24, 48)
        ..cubicTo(30.48, 48, 35.93, 45.87, 39.89, 42.19)
        ..lineTo(32.16, 36.19)
        ..cubicTo(30.01, 37.64, 27.24, 38.49, 24, 38.49)
        ..cubicTo(17.74, 38.49, 12.43, 34.27, 10.53, 28.58)
        ..lineTo(2.55, 34.77)
        ..cubicTo(6.51, 42.62, 14.62, 48, 24, 48)
        ..close()
    ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48, size.height / 48);
    for (final (color, path) in _parts) {
      canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..isAntiAlias = true);
    }
  }

  @override
  bool shouldRepaint(_GooglePainter oldDelegate) => false;
}

/// A provider as an outline capsule the width of the sheet: its mark, then
/// "Continue with …". While its browser tab is open it breathes and says so.
class _ProviderButton extends StatelessWidget {
  final OAuthChoice choice;
  final String label;
  final String busyLabel;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;
  const _ProviderButton({
    super.key,
    required this.choice,
    required this.label,
    required this.busyLabel,
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final lit = enabled || busy;
    return QTapArea(
      onTap: enabled ? onTap : null,
      builder: (context, pressed) => qPressed(
        context,
        pressed: pressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: QSpace.xl),
          decoration: QDecor.capsule(
            edge: lit ? QColors.hairlineStrong : QDisabled.edge,
            fill: pressed ? QColors.surfaceRaised : Colors.transparent,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox.square(
                dimension: 22,
                child: Center(child: busy ? const BreathingDot() : ProviderRow.mark(choice, enabled: enabled)),
              ),
              const SizedBox(width: QSpace.md),
              Flexible(
                child: Text(
                  busy ? busyLabel : label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: QText.body(size: 17, weight: FontWeight.w500, color: lit ? QColors.ink : QDisabled.label),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Saving progress to an account, or signing back in on a new phone.
///
/// A real Supabase flow: a six-digit code lands in the inbox and the session
/// it verifies is a real one. The providers come first, because tapping a
/// mark beats typing an address and waiting for a code. The code checks
/// itself once its sixth digit is in; "Confirm the code" is still there.
class AccountSheet extends StatefulWidget {
  const AccountSheet({super.key});

  /// The email and code fields, for tests.
  static const emailKey = ValueKey('account-email');
  static const codeKey = ValueKey('account-code');

  @override
  State<AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<AccountSheet> {
  // What was typed the last time the sheet was open is what the next code
  // would be sent to, so the field starts with it.
  late final _email = TextEditingController(text: context.read<AppState>().authEmail);
  final _code = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  void _codeChanged(AppState state, String v) {
    state.onAuthCodeChanged(v);
    if (v.trim().length == 6 && !state.authBusy) state.verifyAuthCode();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Positioned.fill(
      child: QSheetScrim(
        onDismiss: state.closeAuth,
        blur: 8,
        child: state.authDone != null ? _done(state) : _form(state),
      ),
    );
  }

  String _title(AppState state) {
    final isAr = state.isAr;
    return state.authLinking ? (isAr ? 'احفظ تقدمك' : 'Save your progress') : (isAr ? 'ادخل بحسابك' : 'Sign in');
  }

  Widget _done(AppState state) => SheetPanel(
        title: _title(state),
        onClose: state.closeAuth,
        primary: QPrimaryButton(label: state.isAr ? 'تمام' : 'Done', onTap: state.closeAuth),
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 1), child: Icon(QIcons.good, size: 20, color: QColors.ink)),
            const SizedBox(width: QSpace.md),
            Expanded(child: Text(state.authDone!, style: QText.body(size: 17, color: QColors.ink))),
          ]),
        ],
      );

  Widget _form(AppState state) {
    final isAr = state.isAr;
    final sent = state.authCodeSent;
    final busy = state.authBusy;
    final emailBusy = busy && state.authProvider == null;
    return SheetPanel(
      title: _title(state),
      onClose: state.closeAuth,
      primary: QPrimaryButton(
        label: emailBusy
            ? (sent ? (isAr ? 'بتأكد من الكود…' : 'Checking the code…') : (isAr ? 'بابعت الكود…' : 'Sending the code…'))
            : sent
                ? (isAr ? 'أكّد الكود' : 'Confirm the code')
                : (isAr ? 'ابعتلي كود' : 'Send me a code'),
        onTap: busy ? null : (sent ? state.verifyAuthCode : state.sendAuthCode),
      ),
      footer: sent
          ? Center(
              child: QTapArea(
                onTap: busy ? null : state.sendAuthCode,
                builder: (context, pressed) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: QSpace.md),
                  child: Text(isAr ? 'ابعت الكود تاني' : 'Send it again',
                      style: QText.body(size: 15, weight: FontWeight.w500, color: busy ? QDisabled.label : (pressed ? QColors.ink : QColors.inkSecondary))),
                ),
              ),
            )
          : null,
      children: [
        Text(
          state.authLinking
              ? (isAr ? 'كل اللي سجلته هيفضل زي ما هو. ده بس اللي هيرجّعه لو غيّرت الموبايل.' : 'Everything you’ve logged stays as it is. This only brings it back if you change phones.')
              : (isAr ? 'ادخل بنفس الطريقة اللي سجلت بيها.' : 'Use the same way you signed up with.'),
          style: QText.body(size: 15, color: QColors.inkSecondary),
        ),
        const SizedBox(height: QSpace.xl),
        const ProviderRow(),
        const SizedBox(height: QSpace.xl),
        Row(children: [
          const Expanded(child: Divider(color: QColors.hairline, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: QSpace.md),
            child: Text(isAr ? 'أو بالإيميل' : 'or with email', style: QText.body(size: 13, color: QColors.inkTertiary)),
          ),
          const Expanded(child: Divider(color: QColors.hairline, height: 1)),
        ]),
        const SizedBox(height: QSpace.xl),
        SheetField(
          key: AccountSheet.emailKey,
          controller: _email,
          hint: isAr ? 'الإيميل' : 'Email address',
          enabled: !sent && !busy,
          keyboardType: TextInputType.emailAddress,
          autofill: AutofillHints.email,
          action: TextInputAction.send,
          // One request at a time, whichever key or button sent it.
          onSubmitted: (_) => state.authBusy ? null : state.sendAuthCode(),
          onChanged: state.onAuthEmailChanged,
        ),
        if (sent) ...[
          const SizedBox(height: QSpace.md),
          Text(isAr ? 'شوف الإيميل: هتلاقي فيه كود من ٦ أرقام.' : 'Check your inbox for a six-digit code.', style: QText.body(size: 13, color: QColors.inkTertiary)),
          const SizedBox(height: QSpace.sm),
          SheetField(
            key: AccountSheet.codeKey,
            controller: _code,
            hint: isAr ? 'الكود' : 'Six-digit code',
            enabled: !busy,
            keyboardType: TextInputType.number,
            autofill: AutofillHints.oneTimeCode,
            action: TextInputAction.done,
            number: true,
            formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            onSubmitted: (_) => state.authBusy ? null : state.verifyAuthCode(),
            onChanged: (v) => _codeChanged(state, v),
          ),
        ],
        if (state.authError != null) ...[
          const SizedBox(height: QSpace.md),
          QStateLine(line: state.authError!, icon: QIcons.warning),
        ],
      ],
    );
  }
}

/// A field on a sheet, the kit's way: the raised surface, the control
/// corner, 52 tall, a placeholder in the third ink, and a strong edge while
/// it has the focus. Always left to right: it holds an address or a code.
class SheetField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? formatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? action;
  final String? autofill;
  final bool number;
  final bool characters;
  const SheetField({
    super.key,
    required this.controller,
    required this.hint,
    this.enabled = true,
    this.keyboardType = TextInputType.text,
    this.onChanged,
    this.onSubmitted,
    this.formatters,
    this.action,
    this.autofill,
    this.number = false,
    this.characters = false,
  });

  @override
  Widget build(BuildContext context) {
    const shape = BorderRadius.all(Radius.circular(QRadii.control));
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      textInputAction: action,
      autofillHints: autofill == null ? null : [autofill!],
      autocorrect: false,
      textCapitalization: characters ? TextCapitalization.characters : TextCapitalization.none,
      textDirection: TextDirection.ltr,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: (number ? QText.number(size: 17) : QText.body(size: 17)).copyWith(color: enabled ? QColors.ink : QColors.inkSecondary),
      decoration: InputDecoration(
        hintText: hint,
        // A Latin placeholder ("QMR…") reads left to right in Arabic too.
        hintTextDirection: QText.arabic(hint) ? null : TextDirection.ltr,
        hintStyle: QText.body(size: 17, color: QColors.inkTertiary),
        filled: true,
        fillColor: QColors.surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(horizontal: QSpace.lg, vertical: 15),
        border: const OutlineInputBorder(borderRadius: shape, borderSide: BorderSide.none),
        enabledBorder: const OutlineInputBorder(borderRadius: shape, borderSide: BorderSide.none),
        disabledBorder: const OutlineInputBorder(borderRadius: shape, borderSide: BorderSide.none),
        focusedBorder: const OutlineInputBorder(borderRadius: shape, borderSide: BorderSide(color: QColors.hairlineStrong, width: 1.5)),
      ),
    );
  }
}
