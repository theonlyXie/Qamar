import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../widgets/account_sheet.dart';
import '../widgets/common.dart';
import '../widgets/living_orb.dart';
import '../widgets/welcome_dishes.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 56, 24, 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // First thing on the first screen: someone who does not read Arabic
          // must be able to switch before the conversation starts.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: QLangToggle(lang: state.lang, onChanged: state.setLang, large: true),
            ),
          ),
          Expanded(
            child: Center(
              child: LayoutBuilder(builder: (context, box) {
                // Was a fixed 300px Stack with the pills hung off its edges at
                // left:-4 / right:-6. Stack clips by default, so on a narrower
                // phone — or once the real Arabic font loads and the labels get
                // wider than a fallback's tofu boxes — the pills were cut off
                // at the sides. Size to the screen and let them overhang.
                final side = math.min(box.maxWidth - 24, 320.0);
                return SizedBox(
                width: side,
                height: side,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    LivingOrb(size: 132, wander: true, wanderDuration: const Duration(milliseconds: 9000), haloDuration: const Duration(milliseconds: 7000)),
                    Positioned(
                      top: 14,
                      left: -4,
                      child: _FloatingPill(
                        label: t.chatDirect,
                        sub: t.chatDirectSub,
                        dot: QColors.violet,
                        // Something real before the first question (O5): a
                        // dish first. A consultation left part-way carries on.
                        onTap: () => state.consultationPaused ? state.startOnboarding() : WelcomeDishes.show(context, state),
                        emphasis: true,
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      right: -6,
                      child: _FloatingPill(
                        label: t.scanInbody,
                        dot: null,
                        onTap: state.openScan,
                        emphasis: false,
                      ),
                    ),
                  ],
                ),
              );
              }),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.brand, style: QText.display(size: 40, height: 48, color: QColors.textPrimary)),
              const SizedBox(height: 8),
              Text(t.promise, style: QText.body(size: 16, height: 24, color: QColors.textMid)),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: Divider(color: QColors.borderFaint, height: 1)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(t.continueWith, style: QText.body(size: 12, color: QColors.textMuted)),
                  ),
                  const Expanded(child: Divider(color: QColors.borderFaint, height: 1)),
                ],
              ),
              const SizedBox(height: 12),
              // One tap, no typing. These are real linkIdentity/signInWithOAuth
              // calls — they used to be three buttons that went straight to
              // onboarding without signing anybody in.
              const ProviderRow(),
              const SizedBox(height: 10),
              _ProviderButton(
                label: state.isAr ? 'كمّل بالإيميل' : 'Continue with email',
                icon: Icons.mail_outline,
                onTap: state.openLinkAccount,
              ),
              if (state.authError != null) ...[
                const SizedBox(height: 8),
                Text(state.authError!,
                    textAlign: TextAlign.center,
                    style: QText.body(size: 12, height: 18, color: QColors.amberSoft)),
              ],
              const SizedBox(height: 4),
              TextButton(
                onPressed: state.openSignIn,
                child: Text(t.haveAccount, style: QText.body(size: 14, weight: FontWeight.w500, color: QColors.textMuted)),
              ),
              // The friend's side of the referral loop: a code from someone
              // who is already here. Their name is the first thing shown.
              TextButton(
                onPressed: state.invitationBusy ? null : () => _askInvitationCode(context, state),
                child: Text(state.isAr ? 'عندك دعوة؟' : 'Have an invitation?',
                    style: QText.body(size: 13, weight: FontWeight.w500, color: QColors.violetSoft)),
              ),
              if (state.invitationNotice != null) ...[
                Text(state.invitationNotice!,
                    textAlign: TextAlign.center,
                    style: QText.body(size: 12, height: 18, color: state.invitedBy != null ? QColors.cyan : QColors.amberSoft)),
                const SizedBox(height: 6),
              ],
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Text(
                    t.boundary,
                    textAlign: TextAlign.center,
                    style: QText.body(size: 11, height: 17, color: QColors.textMuted),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _askInvitationCode(BuildContext context, AppState state) async {
  final controller = TextEditingController(text: state.pendingInvitationCode ?? '');
  final isAr = state.isAr;
  final code = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: QColors.cardDeep,
      title: Text(isAr ? 'كود الدعوة' : 'Invitation code', style: QText.body(size: 16, weight: FontWeight.w600, color: QColors.textHigh)),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        textDirection: TextDirection.ltr,
        style: QText.number(size: 18, color: QColors.textHigh),
        decoration: InputDecoration(hintText: 'QMR-XXXXX', hintStyle: QText.number(size: 18, color: QColors.textMuted)),
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(isAr ? 'إلغاء' : 'Cancel', style: QText.body(size: 14, color: QColors.textMuted))),
        TextButton(onPressed: () => Navigator.of(ctx).pop(controller.text), child: Text(isAr ? 'تفعيل' : 'Redeem', style: QText.body(size: 14, weight: FontWeight.w600, color: QColors.violetSoft))),
      ],
    ),
  );
  controller.dispose();
  if (code != null && code.trim().isNotEmpty) await state.redeemInvitation(code);
}

class _FloatingPill extends StatelessWidget {
  final String label;

  /// What the pill opens, in a line under its label. Null: the label alone.
  final String? sub;
  final Color? dot;
  final VoidCallback onTap;
  final bool emphasis;
  const _FloatingPill({required this.label, this.sub, required this.dot, required this.onTap, required this.emphasis});

  @override
  Widget build(BuildContext context) {
    // Never wider than the screen less a margin, so a long label shortens
    // instead of running off the edge.
    final maxWidth = MediaQuery.of(context).size.width - 40;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          height: sub == null ? 52 : 60,
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: QColors.glass,
            border: Border.all(color: emphasis ? QColors.violet.withOpacity(0.5) : QColors.borderSoft),
            // Lifted by its lighter fill and edge, not by a shadow: a black
            // shadow on a near-black ground drew a hard slab under the pill.
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot != null) ...[
                Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: dot)),
                const SizedBox(width: 9),
              ] else ...[
                Container(width: 12, height: 12, decoration: BoxDecoration(border: Border.all(color: QColors.cyan, width: 2), borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 9),
              ],
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.textHigh)),
                    if (sub != null)
                      Text(sub!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: QText.body(size: 12, height: 16, color: QColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _ProviderButton({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: QColors.borderSoft),
          backgroundColor: QColors.cardDeep,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: QColors.textMid),
            const SizedBox(width: 8),
            Text(label, style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.textHigh)),
          ],
        ),
      ),
    );
  }
}
