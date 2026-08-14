import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import 'common.dart';

/// Linking an email to the guest account, or signing back in on a new device.
///
/// This is a real Supabase flow — a six-digit code lands in the user's inbox
/// and the session it verifies is a real one. It replaced three provider
/// buttons that looked like sign-in and went straight to onboarding.
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
            child: Container(
              color: const Color(0xC7050810),
              alignment: Alignment.bottomCenter,
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(20, 18, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xF7141C2E), Color(0xFF0A0F1A)]),
                    border: Border(top: BorderSide(color: QColors.borderStrong)),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
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
        Text(title, style: QText.display(size: 24, height: 30, color: const Color(0xFFF5F7FF))),
        const SizedBox(height: 10),
        Text(state.authDone!, style: QText.body(size: 14, height: 22, color: QColors.textHigh)),
        const SizedBox(height: 16),
        QPrimaryButton(label: isAr ? 'تمام' : 'Done', onTap: state.closeAuth, height: 50),
      ];
    }

    return [
      Row(
        children: [
          Expanded(child: Text(title, style: QText.display(size: 24, height: 30, color: const Color(0xFFF5F7FF)))),
          QRoundIconButton(icon: Icons.close, onTap: state.closeAuth, size: 34),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        state.authLinking
            ? (isAr
                ? 'كل حاجة سجلتها هتفضل زي ما هي — الإيميل بيخليها ترجعلك لو غيّرت الموبايل.'
                : 'Everything you have logged stays exactly as it is — the email is what brings it back if you change phone.')
            : (isAr
                ? 'هنبعتلك كود ٦ أرقام على الإيميل.'
                : 'We will email you a six-digit code.'),
        style: QText.body(size: 13, height: 20, color: QColors.textMuted),
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
            borderRadius: BorderRadius.circular(12),
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
        hintStyle: QText.body(size: 14, color: QColors.textFaint),
        filled: true,
        fillColor: QColors.cardNavy,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: QColors.borderSoft)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: QColors.borderSoft)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: QColors.violet)),
      ),
    );
  }
}
