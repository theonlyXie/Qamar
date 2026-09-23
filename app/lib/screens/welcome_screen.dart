import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';
import '../widgets/living_orb.dart';
import '../widgets/welcome_dishes.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const boundaryKey = ValueKey('welcome-boundary');
  static const chatPillKey = ValueKey('welcome-chat');
  static const scanPillKey = ValueKey('welcome-scan');
  static const moonKey = ValueKey('welcome-moon');
  static const guestNoteKey = ValueKey('welcome-guest-note');
  static const noticeKey = ValueKey('welcome-notice');

  /// The two ways in and the room around them, with no moon: 20 off the
  /// language toggle, the 60-point pill, 14, the 52-point pill, 20 off the
  /// name. The pills are always drawn whole at this size; only the moon
  /// between them gives way.
  static const heroFloor = 20.0 + 60 + 14 + 52 + 20;

  /// The hero in [room] points: the moon, the clearance above the first
  /// pill and the gap either side of the moon. The moon takes what the
  /// pills and their room leave, up to its full 132. Where that would be
  /// under 64, a moon no longer worth the name, the room gives first: the
  /// gaps close to 8 and the clearance under the toggle, whose own touch
  /// band already stands clear of its pill, to 8. Only a room too short
  /// even for that shows the two ways in alone. The 20 above the name
  /// never gives.
  static ({double moon, double top, double gap}) heroFor(double room) {
    const pills = 60.0 + 52, below = 20.0;
    final spare = room - pills - below;
    if (spare - (20 + 2 * 14) >= 64) return (moon: (spare - 48).clamp(64.0, 132.0), top: 20.0, gap: 14.0);
    if (spare - (8 + 2 * 8) < 64) return (moon: 0.0, top: 20.0, gap: 14.0);
    // Between the two, the room shares what the 64-point moon leaves, in
    // the same proportion as at full size.
    final t = (spare - 64 - 24) / (48 - 24);
    return (moon: 64.0, top: 8 + 12 * t, gap: 8 + 6 * t);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;
    final isAr = state.isAr;
    final link = QText.body(size: 14, weight: FontWeight.w500, color: QColors.violetSoft);

    // One page, top to bottom: the language, the two ways in around the
    // moon, the name and its promise, the guest line, the way back in, the
    // invitation and its notice, the fine print. The moon takes what height
    // the rest leaves; nothing else ever shrinks. When even a moonless page
    // is taller than the phone (a landscape phone, a split screen, large
    // text), it scrolls, where the hero used to be scaled down as a picture.
    return LayoutBuilder(builder: (context, viewport) {
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: viewport.maxHeight),
          child: IntrinsicHeight(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // First thing on the first screen: someone who does not read
                  // Arabic must be able to switch before the conversation
                  // starts. Its edge is the pills' edge.
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: QLangToggle(lang: state.lang, onChanged: state.setLang, large: true),
                    ),
                  ),
                  Expanded(
                    child: _HeroRoom(
                      floor: heroFloor,
                      child: LayoutBuilder(builder: (context, box) {
                        final (:moon, :top, :gap) = heroFor(box.maxHeight);
                        return Padding(
                          padding: EdgeInsets.only(top: top, bottom: 20),
                          child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: _FloatingPill(
                                  key: WelcomeScreen.chatPillKey,
                                  label: t.chatDirect,
                                  sub: t.chatDirectSub,
                                  dot: QColors.violet,
                                  // Something real before the first question (O5):
                                  // a dish first. A consultation left part-way
                                  // carries on.
                                  onTap: () => state.consultationPaused ? state.startOnboarding() : WelcomeDishes.show(context, state),
                                  emphasis: true,
                                ),
                              ),
                              SizedBox(height: gap),
                              if (moon > 0) ...[
                                SizedBox(
                                  height: moon,
                                  child: Center(child: LivingOrb(key: WelcomeScreen.moonKey, size: moon, wander: true, wanderDuration: const Duration(milliseconds: 9000), haloDuration: const Duration(milliseconds: 7000))),
                                ),
                                SizedBox(height: gap),
                              ],
                              Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: _FloatingPill(
                                  key: WelcomeScreen.scanPillKey,
                                  label: t.scanInbody,
                                  dot: null,
                                  onTap: state.openScan,
                                  emphasis: false,
                                ),
                              ),
                            ],
                          ),
                          ),
                        );
                      }),
                    ),
                  ),
                  // One axis from here down: the name, the promise, the ways
                  // back in and the fine print all hang from the centre line.
                  Text(t.brand, textAlign: TextAlign.center, style: QText.display(size: 40, ar: QText.arabic(t.brand), color: QColors.textPrimary)),
                  const SizedBox(height: 8),
                  QBalancedText(t.promise, style: QText.body(size: 17, height: 25, color: QColors.textMid)),
                  const SizedBox(height: 16),
                  // Where "or sign up with" and three providers stood: the
                  // conversation needs no account, and saving is offered once
                  // there is something to save.
                  QBalancedText(t.guestNote, textKey: WelcomeScreen.guestNoteKey, style: QText.body(size: 13, height: 19, color: QColors.textMuted)),
                  const SizedBox(height: 4),
                  // The one way back in. The sheet it opens carries all four
                  // ways: Google, Apple, Facebook and email.
                  TextButton(
                    onPressed: state.openSignIn,
                    // Both ways back in read as links, in the one link colour.
                    child: Text(t.haveAccount, style: link),
                  ),
                  // The friend's side of the referral loop: a code from someone
                  // who is already here. Their name is the first thing shown.
                  TextButton(
                    onPressed: state.invitationBusy ? null : () => _askInvitationCode(context, state),
                    child: Text(isAr ? 'عندك دعوة؟' : 'Have an invitation?', style: link),
                  ),
                  // The notice's own tone (seat 1's invitationNoticeGood): good
                  // news in cyan, the inviter named or not; anything that did not
                  // happen in amber, whoever invited before.
                  if (state.invitationNotice != null) ...[
                    QBalancedText(state.invitationNotice!,
                        textKey: WelcomeScreen.noticeKey,
                        maxWidth: 320,
                        style: QText.body(size: 12, height: 18, color: state.invitationNoticeGood ? QColors.cyan : QColors.amberSoft)),
                    const SizedBox(height: 12),
                  ],
                  QBalancedText(t.boundary, textKey: WelcomeScreen.boundaryKey, maxWidth: 320, style: QText.body(size: 11, height: 17, color: QColors.textMuted)),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// The hero's room in the page's column. It asks for the pills' own height
/// when the page is measured, and lays the moon out in whatever it is given
/// beyond that. Measuring it never asks the moon, which takes its size from
/// the room and so has none of its own.
class _HeroRoom extends SingleChildRenderObjectWidget {
  final double floor;
  const _HeroRoom({required this.floor, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHeroRoom(floor);

  @override
  void updateRenderObject(BuildContext context, _RenderHeroRoom renderObject) => renderObject.floor = floor;
}

class _RenderHeroRoom extends RenderProxyBox {
  _RenderHeroRoom(this._floor);

  double _floor;
  set floor(double v) {
    if (v == _floor) return;
    _floor = v;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicHeight(double width) => _floor;
  @override
  double computeMaxIntrinsicHeight(double width) => _floor;
  @override
  double computeMinIntrinsicWidth(double height) => 0;
  @override
  double computeMaxIntrinsicWidth(double height) => 0;
  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(Size(constraints.maxWidth, _floor));
}

Future<void> _askInvitationCode(BuildContext context, AppState state) async {
  final controller = TextEditingController(text: state.pendingInvitationCode ?? '');
  final isAr = state.isAr;
  final code = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: QColors.cardDeep,
      title: Text(isAr ? 'كود الدعوة' : 'Invitation code', style: QText.body(size: 17, weight: FontWeight.w600, color: QColors.textHigh)),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        textDirection: TextDirection.ltr,
        style: QText.number(size: 17, color: QColors.textHigh),
        decoration: InputDecoration(hintText: 'QMR-XXXXX', hintStyle: QText.number(size: 17, color: QColors.textMuted)),
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
  const _FloatingPill({super.key, required this.label, this.sub, required this.dot, required this.onTap, required this.emphasis});

  @override
  Widget build(BuildContext context) {
    // Never wider than the screen less a margin, so a long label shortens
    // instead of running off the edge.
    final maxWidth = MediaQuery.of(context).size.width - 40;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(QRadii.pill),
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
            borderRadius: BorderRadius.circular(QRadii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot != null) ...[
                Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: dot)),
                const SizedBox(width: 9),
              ] else ...[
                const Icon(Icons.crop_free, size: 14, color: QColors.cyan), // a viewfinder, for the scan
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
