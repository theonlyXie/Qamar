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
import 'common.dart';
import 'moon.dart';

/// Ask Qamar — a familiar AI chat sheet.
///
/// Idle / thinking: header + message list + composer (ChatGPT-style).
/// Listening: full-bleed voice mode with a centered speaking orb.
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
    final listening = state.chatState == ChatState.listening;

    _chat.sync(state.chat.length * 3 + state.chatState.index);
    if (_ctrl.text != state.chatDraft) {
      _ctrl.value = TextEditingValue(
        text: state.chatDraft,
        selection: TextSelection.collapsed(offset: state.chatDraft.length),
      );
    }

    final statusLabel = state.dictationError ??
        switch (state.chatState) {
          ChatState.listening => state.heard.isEmpty ? t.sListening : state.heard,
          ChatState.thinking => t.sThinking,
          ChatState.idle => t.online,
        };

    return Positioned.fill(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xF00B1324), Color(0xF805070E)],
              ),
            ),
            child: SafeArea(
              child: listening
                  ? _VoiceMode(
                      status: statusLabel,
                      typeInstead: t.typeInstead,
                      tapHint: t.voiceTapHint,
                      onStop: state.tapOrbListen,
                      onClose: () async {
                        await state.cancelListen();
                        state.closeChat();
                      },
                      onTypeInstead: state.cancelListen,
                    )
                  : Column(
                      children: [
                        _ChatHeader(
                          brand: t.brand,
                          status: statusLabel,
                          onClose: state.closeChat,
                        ),
                        Expanded(
                          child: ListView(
                            controller: _chat.controller,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            children: [
                              for (final c in state.chat) _ChatBubble(turn: c),
                              if (state.chatState == ChatState.thinking) const _ThinkingBubble(),
                              if (state.hasProposal) const _ProposalCard(),
                            ],
                          ),
                        ),
                        _Composer(
                          ctrl: _ctrl,
                          placeholder: t.chatPlaceholder,
                          showSuggestions: state.chatDraft.isEmpty &&
                              state.chatState != ChatState.thinking,
                          suggestions: state.chatSuggestions(),
                          photoPath: state.lastMealPhotoPath,
                          photoLabel: state.isAr ? 'صورة الوجبة' : 'Meal photo',
                          onDraft: state.onChatDraftChanged,
                          onSend: state.sendChat,
                          onListen: state.tapOrbListen,
                          onSuggestion: state.chatSuggestionTap,
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  final String brand;
  final String status;
  final VoidCallback onClose;
  const _ChatHeader({required this.brand, required this.status, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(
        children: [
          const QamarMoon(size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(brand, style: QText.display(size: 18, height: 22, color: QColors.textBrand)),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: QText.body(size: 12, color: QColors.textMuted),
                ),
              ],
            ),
          ),
          Material(
            color: const Color(0xB3111827),
            shape: const CircleBorder(side: BorderSide(color: QColors.borderStrong)),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onClose,
              child: const SizedBox(
                width: 36,
                height: 36,
                child: Icon(Icons.close, size: 18, color: QColors.textMid),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ChatGPT-style voice mode: one speaking orb in the middle, status under it.
class _VoiceMode extends StatelessWidget {
  final String status;
  final String typeInstead;
  final String tapHint;
  final VoidCallback onStop;
  final VoidCallback onClose;
  final VoidCallback onTypeInstead;
  const _VoiceMode({
    required this.status,
    required this.typeInstead,
    required this.tapHint,
    required this.onStop,
    required this.onClose,
    required this.onTypeInstead,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Material(
              color: const Color(0xB3111827),
              shape: const CircleBorder(side: BorderSide(color: QColors.borderStrong)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onClose,
                child: const SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(Icons.close, size: 18, color: QColors.textMid),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SpeakingOrb(onTap: onStop),
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    status,
                    textAlign: TextAlign.center,
                    style: QText.body(size: 16, height: 24, color: QColors.textMid),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Column(
            children: [
              TextButton(
                onPressed: onTypeInstead,
                child: Text(
                  typeInstead,
                  style: QText.body(size: 14, weight: FontWeight.w500, color: QColors.textMuted),
                ),
              ),
              const SizedBox(height: 4),
              Text(tapHint, style: QText.body(size: 12, color: QColors.textFaint)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Soft pulsing disc — ChatGPT Advanced Voice energy, with Qamar's moon inside.
class _SpeakingOrb extends StatefulWidget {
  final VoidCallback onTap;
  const _SpeakingOrb({required this.onTap});

  @override
  State<_SpeakingOrb> createState() => _SpeakingOrbState();
}

class _SpeakingOrbState extends State<_SpeakingOrb> with TickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
  late final AnimationController _ring =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const moonSize = 96.0;
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: 220,
        height: 220,
        child: AnimatedBuilder(
          animation: Listenable.merge([_pulse, _ring]),
          builder: (context, _) {
            final breathe = 1.0 + 0.06 * _pulse.value;
            return Stack(
              alignment: Alignment.center,
              children: [
                for (var i = 0; i < 3; i++)
                  Opacity(
                    opacity: ((1 - ((_ring.value + i / 3) % 1.0)) * 0.45).clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: 0.55 + 0.7 * ((_ring.value + i / 3) % 1.0),
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: i.isEven ? QColors.moonlight.withOpacity(0.55) : QColors.violet.withOpacity(0.4),
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                Transform.scale(
                  scale: breathe,
                  child: Container(
                    width: moonSize + 28,
                    height: moonSize + 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          QColors.moonlight.withOpacity(0.22),
                          QColors.violet.withOpacity(0.08),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.55, 1.0],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const QamarMoon(size: moonSize),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController ctrl;
  final String placeholder;
  final bool showSuggestions;
  final List<String> suggestions;
  final String? photoPath;
  final String photoLabel;
  final ValueChanged<String> onDraft;
  final VoidCallback onSend;
  final VoidCallback onListen;
  final ValueChanged<String> onSuggestion;

  const _Composer({
    required this.ctrl,
    required this.placeholder,
    required this.showSuggestions,
    required this.suggestions,
    required this.photoPath,
    required this.photoLabel,
    required this.onDraft,
    required this.onSend,
    required this.onListen,
    required this.onSuggestion,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: QColors.borderFaint)),
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
                  for (final sug in suggestions)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => onSuggestion(sug),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            decoration: BoxDecoration(
                              color: const Color(0xB3141C2E),
                              border: Border.all(color: QColors.textMuted.withOpacity(0.24)),
                              borderRadius: BorderRadius.circular(999),
                            ),
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
          if (photoPath != null && !kIsWeb) ...[
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
                      child: Image.file(File(photoPath!), width: 44, height: 44, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 10),
                    Text(photoLabel, style: QText.body(size: 12, color: QColors.textMuted)),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ],
          Container(
            padding: const EdgeInsetsDirectional.only(start: 16, end: 5, top: 5, bottom: 5),
            decoration: BoxDecoration(
              color: const Color(0xE5111827),
              border: Border.all(color: QColors.borderStrong),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: ctrl,
                    onChanged: onDraft,
                    onSubmitted: (_) => onSend(),
                    style: QText.body(size: 15, color: QColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: placeholder,
                      hintStyle: QText.body(size: 15, color: QColors.textFaint),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                QRoundIcon(icon: Icons.mic_none_rounded, size: 40, onTap: onListen, filled: false),
                const SizedBox(width: 6),
                QRoundIcon(icon: Icons.arrow_upward, size: 40, onTap: onSend, filled: true),
              ],
            ),
          ),
        ],
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
            child: Icon(icon, size: size * 0.42, color: filled ? Colors.white : QColors.textMuted),
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
    final maxW = MediaQuery.of(context).size.width * 0.78;

    if (turn.who == ChatWho.u) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Container(
            constraints: BoxConstraints(maxWidth: maxW),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFF2A3550),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(turn.text, style: QText.body(size: 15, height: 22, color: Colors.white)),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: QamarMoon(size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxW),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        turn.text,
                        style: QText.body(size: 15, height: 23, color: const Color(0xFFF5F7FF)),
                      ),
                      if (turn.sub != null && turn.sub!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(turn.sub!, style: QText.body(size: 13, height: 20, color: QColors.textMuted)),
                      ],
                    ],
                  ),
                ),
                if (turn.action != null) ...[
                  const SizedBox(height: 10),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: state.chatActionTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        decoration: BoxDecoration(
                          color: QColors.violet.withOpacity(0.14),
                          border: Border.all(color: QColors.violet.withOpacity(0.45)),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          turn.action!,
                          style: QText.body(size: 13, weight: FontWeight.w500, color: const Color(0xFFE9ECFF)),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
        color: const Color(0xF2111827),
        border: Border.all(color: QColors.violet.withOpacity(0.45)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.nothingWrites, style: QText.body(size: 12, color: QColors.textMuted)),
          const SizedBox(height: 10),
          for (var i = 0; i < items.length; i++) ...[
            Opacity(
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
                              Text(
                                isAr ? items[i].def.ar : items[i].def.en,
                                style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.textPrimary),
                              ),
                              Text(
                                isAr ? items[i].def.portionAr : items[i].def.portionEn,
                                style: QText.body(size: 12, color: QColors.textMuted),
                              ),
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
                        SizedBox(
                          width: 40,
                          child: Text(
                            '${items[i].q}×',
                            textAlign: TextAlign.center,
                            style: QText.number(size: 14, weight: FontWeight.w600, color: QColors.textMid),
                          ),
                        ),
                        QRoundIconButton(icon: Icons.add, onTap: () => state.incQty(i), size: 28),
                        const Spacer(),
                        Text(
                          '${items[i].def.kcal * items[i].q} kcal',
                          style: QText.number(size: 14, weight: FontWeight.w600, color: QColors.cyan),
                        ),
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
                child: Text(
                  '${totals.kcal} kcal · P ${totals.p} · C ${totals.c} · F ${totals.f}',
                  textAlign: TextAlign.end,
                  style: QText.number(size: 14, weight: FontWeight.w600, color: QColors.textPrimary),
                ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          const QamarMoon(size: 22),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xE5141C2E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [_TDot(0), SizedBox(width: 5), _TDot(1), SizedBox(width: 5), _TDot(2)],
            ),
          ),
        ],
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
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();
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
        return Opacity(
          opacity: opacity.clamp(0.3, 1.0),
          child: Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: QColors.moonlight),
          ),
        );
      },
    );
  }
}
