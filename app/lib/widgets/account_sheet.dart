import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import 'common.dart';

/// One-tap sign-in with Google, Apple or Facebook.
///
/// Laid out as a row of three so signing up is one tap and no typing — which
/// is the whole point of offering them. Apple sits alongside the other two
/// rather than being optional: App Store review requires it wherever another
/// third-party login is offered.
///
/// These call `linkIdentity` for a guest, so everything logged before signing
/// in keeps the same user id and survives.
class ProviderRow extends StatelessWidget {
  const ProviderRow({super.key});

  static const _providers = <(OAuthChoice, String, Widget)>[
    (OAuthChoice.google, 'Google', GoogleMark(size: 18)),
    (OAuthChoice.apple, 'Apple', Icon(Icons.apple, size: 20, color: QColors.textHigh)),
    (OAuthChoice.facebook, 'Facebook', Icon(Icons.facebook, size: 20, color: QColors.textHigh)),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Row(
      children: [
        for (final (choice, label, mark) in _providers) ...[
          if (choice != _providers.first.$1) const SizedBox(width: 10),
          Expanded(
            child: _ProviderButton(
              label: label,
              mark: mark,
              // Only the provider actually being used shows the wait; the
              // other two grey out rather than all three spinning at once.
              busy: state.authBusy && state.authProvider == choice,
              enabled: !state.authBusy,
              onTap: () => state.signInWith(choice),
            ),
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
    (QColors.googleRed, Path()
      ..moveTo(24, 9.5)
      ..cubicTo(27.54, 9.5, 30.71, 10.72, 33.21, 13.1)
      ..lineTo(40.06, 6.25)
      ..cubicTo(35.9, 2.38, 30.47, 0, 24, 0)
      ..cubicTo(14.62, 0, 6.51, 5.38, 2.56, 13.22)
      ..lineTo(10.54, 19.41)
      ..cubicTo(12.43, 13.72, 17.74, 9.5, 24, 9.5)
      ..close()),
    (QColors.googleBlue, Path()
      ..moveTo(46.98, 24.55)
      ..cubicTo(46.98, 22.98, 46.83, 21.46, 46.6, 20)
      ..lineTo(24, 20)
      ..lineTo(24, 29.02)
      ..lineTo(36.94, 29.02)
      ..cubicTo(36.36, 31.98, 34.68, 34.5, 32.16, 36.2)
      ..lineTo(39.89, 42.2)
      ..cubicTo(44.4, 38.02, 46.98, 31.84, 46.98, 24.55)
      ..close()),
    (QColors.googleYellow, Path()
      ..moveTo(10.53, 28.59)
      ..cubicTo(10.05, 27.14, 9.77, 25.6, 9.77, 24)
      ..cubicTo(9.77, 22.4, 10.04, 20.86, 10.53, 19.41)
      ..lineTo(2.55, 13.22)
      ..cubicTo(0.92, 16.46, 0, 20.12, 0, 24)
      ..cubicTo(0, 27.88, 0.92, 31.54, 2.56, 34.78)
      ..lineTo(10.53, 28.59)
      ..close()),
    (QColors.googleGreen, Path()
      ..moveTo(24, 48)
      ..cubicTo(30.48, 48, 35.93, 45.87, 39.89, 42.19)
      ..lineTo(32.16, 36.19)
      ..cubicTo(30.01, 37.64, 27.24, 38.49, 24, 38.49)
      ..cubicTo(17.74, 38.49, 12.43, 34.27, 10.53, 28.58)
      ..lineTo(2.55, 34.77)
      ..cubicTo(6.51, 42.62, 14.62, 48, 24, 48)
      ..close()),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48, size.height / 48);
    for (final (color, path) in _parts) {
      canvas.drawPath(path, Paint()..color = color..isAntiAlias = true);
    }
  }

  @override
  bool shouldRepaint(_GooglePainter oldDelegate) => false;
}

class _ProviderButton extends StatelessWidget {
  final String label;
  final Widget mark;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;
  const _ProviderButton({
    required this.label,
    required this.mark,
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: enabled ? onTap : null,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: QColors.borderSoft),
          backgroundColor: QColors.cardDeep,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(QRadii.control)),
        ),
        child: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: QColors.textMid),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Opacity(opacity: enabled ? 1 : 0.4, child: mark),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: QText.body(size: 13, weight: FontWeight.w600, color: enabled ? QColors.textHigh : QColors.textDisabled),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Linking an email to the guest account, or signing back in on a new device.
///
/// This is a real Supabase flow — a six-digit code lands in the user's inbox
/// and the session it verifies is a real one. Providers sit above it, because
/// tapping a logo beats typing an address and waiting for a code.
class AccountSheet extends StatefulWidget {
  const AccountSheet({super.key});

  @override
  State<AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<AccountSheet> {
  final _email = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;

    return Positioned.fill(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: GestureDetector(
            onTap: state.closeAuth,
            child: QSheetScrim(
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(20, 18, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
                  decoration: const BoxDecoration(
                    gradient: QColors.sheet,
                    border: Border(top: BorderSide(color: QColors.borderStrong)),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(QRadii.sheet)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _body(context, state, isAr),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, AppState state, bool isAr) {
    final title = state.authLinking
        ? (isAr ? 'اربط حسابك' : 'Link your account')
        : (isAr ? 'ادخل بحسابك' : 'Sign in');

    if (state.authDone != null) {
      return [
        Text(title, style: QText.display(size: 24, ar: QText.arabic(title), color: QColors.textPrimary)),
        const SizedBox(height: 10),
        Text(state.authDone!, style: QText.body(size: 14, height: 22, color: QColors.textHigh)),
        const SizedBox(height: 16),
        QPrimaryButton(label: isAr ? 'تمام' : 'Done', onTap: state.closeAuth, height: 50),
      ];
    }

    return [
      Row(
        children: [
          Expanded(child: Text(title, style: QText.display(size: 24, ar: QText.arabic(title), color: QColors.textPrimary))),
          QRoundIconButton(icon: Icons.close, onTap: state.closeAuth, size: 34, label: state.isAr ? 'اقفل' : 'Close'),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        state.authLinking
            ? (isAr
                ? 'كل حاجة سجلتها هتفضل زي ما هي — ده بس اللي هيرجّعهالك لو غيّرت الموبايل.'
                : 'Everything you have logged stays exactly as it is — this is only what brings it back if you change phone.')
            : (isAr
                ? 'ادخل بنفس الطريقة اللي سجلت بيها.'
                : 'Use whichever way you signed up with.'),
        style: QText.body(size: 13, height: 20, color: QColors.textMuted),
      ),
      const SizedBox(height: 14),
      // One tap first, typing second — most people will never reach the field
      // below, which is the point of offering the providers at all.
      const ProviderRow(),
      const SizedBox(height: 14),
      Row(
        children: [
          const Expanded(child: Divider(color: QColors.borderFaint, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(isAr ? 'أو بالإيميل' : 'or with email',
                style: QText.body(size: 12, color: QColors.textMuted)),
          ),
          const Expanded(child: Divider(color: QColors.borderFaint, height: 1)),
        ],
      ),
      const SizedBox(height: 14),
      _Field(
        controller: _email,
        hint: isAr ? 'الإيميل' : 'Email address',
        enabled: !state.authCodeSent && !state.authBusy,
        keyboardType: TextInputType.emailAddress,
        onChanged: state.onAuthEmailChanged,
      ),
      if (state.authCodeSent) ...[
        const SizedBox(height: 10),
        _Field(
          controller: _code,
          hint: isAr ? 'الكود' : 'Six-digit code',
          enabled: !state.authBusy,
          keyboardType: TextInputType.number,
          formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          onChanged: state.onAuthCodeChanged,
        ),
      ],
      if (state.authError != null) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: QColors.amber.withValues(alpha: 0.1),
            border: Border.all(color: QColors.amber.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(QRadii.control),
          ),
          child: Text(state.authError!, style: QText.body(size: 12, height: 18, color: QColors.amberSoft)),
        ),
      ],
      const SizedBox(height: 14),
      QPrimaryButton(
        label: state.authBusy
            ? (isAr ? 'ثانية…' : 'One moment…')
            : state.authCodeSent
                ? (isAr ? 'أكّد الكود' : 'Confirm code')
                : (isAr ? 'ابعت الكود' : 'Send code'),
        onTap: state.authBusy ? null : (state.authCodeSent ? state.verifyAuthCode : state.sendAuthCode),
        height: 50,
      ),
      if (state.authCodeSent) ...[
        Center(
          child: TextButton(
            onPressed: state.authBusy ? null : state.sendAuthCode,
            child: Text(isAr ? 'ابعت الكود تاني' : 'Send it again',
                style: QText.body(size: 13, weight: FontWeight.w500, color: QColors.textMuted)),
          ),
        ),
      ],
    ];
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? formatters;
  final ValueChanged<String> onChanged;
  const _Field({
    required this.controller,
    required this.hint,
    required this.enabled,
    required this.keyboardType,
    required this.onChanged,
    this.formatters,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      textDirection: TextDirection.ltr,
      onChanged: onChanged,
      style: QText.number(size: 15, color: QColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: QText.body(size: 14, color: QColors.textMuted),
        filled: true,
        fillColor: QColors.cardNavy,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(QRadii.control), borderSide: const BorderSide(color: QColors.borderSoft)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(QRadii.control), borderSide: const BorderSide(color: QColors.borderSoft)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(QRadii.control), borderSide: const BorderSide(color: QColors.violet)),
      ),
    );
  }
}
