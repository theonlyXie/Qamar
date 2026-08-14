import 'dart:ui';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/meal.dart';
import '../models/messages.dart';
import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import 'living_orb.dart';
import 'common.dart';

/// S18 — Ask Qamar as a companion overlay: the page behind fades/blurs, the
/// orb docks to the side, and messages emerge from it along a moonbeam.
class AskQamarOverlay extends StatefulWidget {
  const AskQamarOverlay({super.key});
  @override
  State<AskQamarOverlay> createState() => _AskQamarOverlayState();
}

class _AskQamarOverlayState extends State<AskQamarOverlay> {
  final _chat = ChatScroller();
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _chat.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;

    _chat.sync(state.chat.length * 3 + state.chatState.index);
    if (_ctrl.text != state.chatDraft) {
      _ctrl.value = TextEditingValue(text: state.chatDraft, selection: TextSelection.collapsed(offset: state.chatDraft.length));
    }

    final orbActive = state.chatState == ChatState.listening || state.chatState == ChatState.thinking;
    // While dictating, show the words as the recogniser hears them — that is
    // the difference between the microphone obviously working and the user
    // wondering whether it is on. Falls back to the status label before the
    // first word lands, and surfaces a real failure instead of hiding it.
    final orbStateLabel = state.dictationError ??
        switch (state.chatState) {
          ChatState.listening => state.heard.isEmpty ? t.sListening : state.heard,
          ChatState.thinking => t.sThinking,
          ChatState.idle => t.sIdle,
        };
    final showSuggestions = state.chatDraft.isEmpty && state.chatState != ChatState.thinking;

    return Positioned.fill(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xA8060A14), Color(0xF0060A14)],
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 18, 18, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Material(
                        color: const Color(0xB3111827),
                        shape: const CircleBorder(side: BorderSide(color: QColors.borderStrong)),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: state.closeChat,
                          child: const SizedBox(width: 34, height: 34, child: Icon(Icons.close, size: 18, color: QColors.textMid)),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      ListView(
                        controller: _chat.controller,
                        padding: const EdgeInsetsDirectional.fromSTEB(110, 4, 18, 150),
                        children: [
                          for (final c in state.chat) _ChatBubble(turn: c),
                          if (state.chatState == ChatState.thinking) const _ThinkingBubble(),
                          // What the assistant read off the meal, waiting to be
                          // confirmed. Nothing is written until it is.
                          if (state.hasProposal) const _ProposalCard(),
                        ],
                      ),
                      PositionedDirectional(
                        top: 6,
                        start: 14,
                        child: Column(
                          children: [
                            LivingOrb(
                              size: 78,
                              activeRings: orbActive,
                              breathDuration: const Duration(milliseconds: 5500),
                              haloDuration: const Duration(milliseconds: 5400),
                              onTap: state.tapOrbListen,
                            ),
                            const SizedBox(height: 7),
                            Text(t.brand, style: QText.display(size: 15, height: 20, color: const Color(0xFFE9ECFF))),
                            Text(orbStateLabel.toUpperCase(), textAlign: TextAlign.center, style: QText.number(size: 9, weight: FontWeight.w500, color: QColors.violet, letterSpacing: 1.4)),
                          ],
                        ),
                      ),
                      PositionedDirectional(
                        top: 104,
                        bottom: 0,
                        start: 55,
                        child: Container(
                          width: 1,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x807B6CFF), Color(0x0F7B6CFF), Colors.transparent],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 26),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xEB060A14)]),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showSuggestions) ...[
                        SizedBox(
                          height: 38,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final sug in state.chatSuggestions())
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(end: 8),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(999),
                                      onTap: () => state.chatSuggestionTap(sug),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                                        decoration: BoxDecoration(color: const Color(0xB3141C2E), border: Border.all(color: QColors.textMuted.withOpacity(0.24)), borderRadius: BorderRadius.circular(999)),
                                        child: Text(sug, style: QText.body(size: 12, color: QColors.textMuted)),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      // Proof the camera actually fired: the shot the user just
                      // took, attached to the message they are about to send.
                      if (state.lastMealPhotoPath != null && !kIsWeb) ...[
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: const Color(0xE5111827),
                              border: Border.all(color: QColors.borderStrong),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.file(File(state.lastMealPhotoPath!), width: 44, height: 44, fit: BoxFit.cover),
                                ),
                                const SizedBox(width: 10),
                                Text(state.isAr ? 'صورة الوجبة' : 'Meal photo',
                                    style: QText.body(size: 12, color: QColors.textMuted)),
                                const SizedBox(width: 8),
                              ],
                            ),
                          ),
                        ),
                      ],
                      Container(
                        padding: const EdgeInsetsDirectional.only(start: 16, end: 5, top: 5, bottom: 5),
                        decoration: BoxDecoration(color: const Color(0xE5111827), border: Border.all(color: QColors.borderStrong), borderRadius: BorderRadius.circular(999)),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _ctrl,
                                onChanged: state.onChatDraftChanged,
                                onSubmitted: (_) => state.sendChat(),
                                style: QText.body(size: 15, color: QColors.textPrimary),
                                decoration: InputDecoration(
                                  hintText: t.chatPlaceholder,
                                  hintStyle: QText.body(size: 15, color: QColors.textFaint),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                              ),
                            ),
                            QRoundIcon(icon: Icons.circle, size: 40, onTap: state.tapOrbListen, filled: false),
                            const SizedBox(width: 6),
                            QRoundIcon(icon: Icons.arrow_upward, size: 40, onTap: state.sendChat, filled: true),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class QRoundIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final bool filled;
  const QRoundIcon({super.key, required this.icon, required this.size, required this.onTap, required this.filled});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: filled
              ? const BoxDecoration(shape: BoxShape.circle, gradient: QColors.brandGradient)
              : BoxDecoration(shape: BoxShape.circle, border: Border.all(color: QColors.borderStrong)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Icon(icon, size: size * 0.4, color: filled ? Colors.white : QColors.textMuted),
          ),
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatTurn turn;
  const _ChatBubble({required this.turn});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    if (turn.who == ChatWho.u) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.96),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
            decoration: BoxDecoration(gradient: QColors.brandGradient, borderRadius: BorderRadius.circular(18)),
            child: Text(turn.text, style: QText.body(size: 15, height: 23, color: Colors.white)),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xF2182137), Color(0xF2111827)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              border: Border.all(color: QColors.borderStrong),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(turn.text, style: QText.body(size: 15, weight: FontWeight.w500, height: 23, color: const Color(0xFFF5F7FF))),
                if (turn.sub != null && turn.sub!.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(turn.sub!, style: QText.body(size: 13, height: 21, color: QColors.textMuted)),
                ],
              ],
            ),
          ),
          if (turn.action != null) ...[
            const SizedBox(height: 8),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: state.chatActionTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(color: QColors.violet.withOpacity(0.14), border: Border.all(color: QColors.violet.withOpacity(0.55)), borderRadius: BorderRadius.circular(999)),
                  child: Text(turn.action!, style: QText.body(size: 13, weight: FontWeight.w500, color: const Color(0xFFE9ECFF))),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The meal the assistant read, offered for confirmation inside the
/// conversation. This is the whole confirm step — there is no confirm page —
/// and the meal reaches the day's totals only when the button is pressed.
class _ProposalCard extends StatelessWidget {
  const _ProposalCard();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;
    final isAr = state.isAr;
    final items = state.proposalItems();
    final totals = state.proposalTotals();

    String confLabel(Confidence c) => switch (c) {
          Confidence.high => isAr ? 'ثقة عالية' : 'High confidence',
          Confidence.med => isAr ? 'ثقة متوسطة' : 'Medium confidence',
          Confidence.low => isAr ? 'تقدير' : 'Estimate',
        };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xF2182137), Color(0xF2111827)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        border: Border.all(color: QColors.violet.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.nothingWrites, style: QText.body(size: 12, color: QColors.textMuted)),
          const SizedBox(height: 10),
          for (var i = 0; i < items.length; i++) ...[
            Opacity(
              // A dropped item stays visible: the reading is still what the
              // assistant saw, it just is not going in the log.
              opacity: items[i].q == 0 ? 0.4 : 1,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(isAr ? items[i].def.ar : items[i].def.en,
                                  style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.textPrimary)),
                              Text(isAr ? items[i].def.portionAr : items[i].def.portionEn,
                                  style: QText.body(size: 12, color: QColors.textMuted)),
                            ],
                          ),
                        ),
                        ConfidenceBadge(high: items[i].def.conf == Confidence.high, label: confLabel(items[i].def.conf)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        QRoundIconButton(icon: Icons.remove, onTap: () => state.decQty(i), size: 28),
                        SizedBox(width: 40, child: Text('${items[i].q}×', textAlign: TextAlign.center, style: QText.number(size: 14, weight: FontWeight.w600, color: QColors.textMid))),
                        QRoundIconButton(icon: Icons.add, onTap: () => state.incQty(i), size: 28),
                        const Spacer(),
                        Text('${items[i].def.kcal * items[i].q} kcal',
                            style: QText.number(size: 14, weight: FontWeight.w600, color: QColors.cyan)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(t.approx, style: QText.number(size: 14, weight: FontWeight.w500, color: QColors.textMuted)),
              Flexible(
                child: Text('${totals.kcal} kcal · P ${totals.p} · C ${totals.c} · F ${totals.f}',
                    textAlign: TextAlign.end,
                    style: QText.number(size: 14, weight: FontWeight.w600, color: QColors.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          QPrimaryButton(label: t.confirmAndLog, onTap: state.confirmProposal, height: 48),
          Center(
            child: TextButton(
              onPressed: state.discardProposal,
              child: Text(t.cancel, style: QText.body(size: 13, weight: FontWeight.w500, color: QColors.textMuted)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: const Color(0xE5141C2E), border: Border.all(color: QColors.borderSoft), borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisSize: MainAxisSize.min, children: const [_TDot(0), SizedBox(width: 5), _TDot(1), SizedBox(width: 5), _TDot(2)]),
      ),
    );
  }
}

class _TDot extends StatefulWidget {
  final int i;
  const _TDot(this.i);
  @override
  State<_TDot> createState() => _TDotState();
}

class _TDotState extends State<_TDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final phase = (_c.value + widget.i * 0.2) % 1.0;
        final opacity = 0.3 + 0.7 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
        return Opacity(opacity: opacity.clamp(0.3, 1.0), child: Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: QColors.violet)));
      },
    );
  }
}
