import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/meal.dart';
import '../models/messages.dart';
import '../services/photos.dart';
import '../models/problem.dart';
import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import 'common.dart';

/// S18 — Ask Qamar, read as a conversation and nothing else.
///
/// The earlier version staged a performance around the words: a 78px orb docked
/// to the side, a violet beam running down the page, a gradient on every line
/// the user typed. It was the loudest surface in the app and the hardest to
/// read. This is the same conversation with the staging removed — a translucent
/// sheet over the page, the assistant as plain text, the user in one quiet
/// bubble, controls small enough to stop competing with the answer.
///
/// Motion follows the same rule: short, critically damped, never decorative.
/// Everything here honours the platform's reduce-motion setting by falling back
/// to a plain cross-fade.
const _scrimTop = Color(0xF20A0F1C);
const _scrimBottom = Color(0xFA060A14);

/// The composer and the user's own words sit on the one surface that is a step
/// lighter than the sheet — enough to separate, not enough to shout.
const _raised = Color(0xE60E1526);
const _userBubble = Color(0xF21B2440);

/// How long anything in this overlay is allowed to take.
const _enter = Duration(milliseconds: 240);
const _press = Duration(milliseconds: 90);

bool _stillness(BuildContext context) => MediaQuery.disableAnimationsOf(context);

class AskQamarOverlay extends StatefulWidget {
  const AskQamarOverlay({super.key});
  @override
  State<AskQamarOverlay> createState() => _AskQamarOverlayState();
}

class _AskQamarOverlayState extends State<AskQamarOverlay> with SingleTickerProviderStateMixin {
  final _chat = ChatScroller();
  final _ctrl = TextEditingController();
  late final AnimationController _in = AnimationController(vsync: this, duration: _enter)..forward();

  @override
  void dispose() {
    _in.dispose();
    _chat.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;
    final still = _stillness(context);

    _chat.sync(state.chat.length * 3 + state.chatState.index);
    if (_ctrl.text != state.chatDraft) {
      _ctrl.value = TextEditingValue(text: state.chatDraft, selection: TextSelection.collapsed(offset: state.chatDraft.length));
    }

    final showSuggestions = state.chatDraft.isEmpty && state.chatState != ChatState.thinking;

    // Sized by the shell, not by a Stack: the overlay is handed a full-screen
    // box so it can fade in and out inside a switcher.
    return SizedBox.expand(
      child: ClipRect(
        child: BackdropFilter(
          // The page stays visible behind the conversation: the sheet is a
          // material over the app, not a new screen the app jumped to.
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: FadeTransition(
            opacity: CurvedAnimation(parent: _in, curve: Curves.easeOut),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_scrimTop, _scrimBottom]),
              ),
              child: AnimatedBuilder(
                animation: _in,
                builder: (context, child) {
                  if (still) return child!;
                  final v = Curves.easeOutCubic.transform(_in.value);
                  return Transform.translate(offset: Offset(0, 10 * (1 - v)), child: child);
                },
                child: Column(
                  children: [
                    _Header(state: state),
                    Expanded(
                      child: ListView(
                        controller: _chat.controller,
                        // Dragging the conversation puts the keyboard away, the
                        // way every messaging app on the phone already does.
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                        children: [
                          for (final c in state.chat) _ChatBubble(turn: c),
                          if (state.chatState == ChatState.thinking) const _Thinking(),
                          // What the assistant read off the meal, waiting to be
                          // confirmed. Nothing is written until it is.
                          if (state.hasProposal) const _ProposalCard(),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 22),
                      // A fade where the conversation meets the composer, in
                      // place of a rule across the screen.
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00060A14), Color(0xE6060A14)]),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showSuggestions) ...[
                            SizedBox(
                              height: 34,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                children: [
                                  for (final sug in state.chatSuggestions())
                                    Padding(
                                      padding: const EdgeInsetsDirectional.only(end: 8),
                                      child: _Chip(label: sug, onTap: () => state.chatSuggestionTap(sug)),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          // Proof the camera actually fired: the shot the user
                          // just took, attached to the message about to be sent.
                          if (state.lastMealPhotoPath != null && !kIsWeb)
                            _Attachment(path: state.lastMealPhotoPath!, label: state.isAr ? 'صورة الوجبة' : 'Meal photo'),
                          // A menu photographed at the table, waiting to go with
                          // the next words — or with none: "what do I order
                          // here?" is implied.
                          if (state.chatPhotoPath != null && !kIsWeb)
                            _Attachment(path: state.chatPhotoPath!, label: state.isAr ? 'صورة المنيو' : 'Menu photo', onRemove: state.detachChatPhoto),
                          _Composer(state: state, ctrl: _ctrl, placeholder: state.chatPhotoPath != null
                              ? (state.isAr ? 'اسأل عن المنيو، أو ابعت الصورة بس' : 'Ask about the menu, or just send the photo')
                              : t.chatPlaceholder),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Name, one line of state, one way out. The quota takes the status line when
/// there is no status to report, so the header never carries two pills at once.
class _Header extends StatelessWidget {
  final AppState state;
  const _Header({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = state.t;
    final heard = state.dictationError ??
        switch (state.chatState) {
          ChatState.listening => state.heard.isEmpty ? t.sListening : state.heard,
          ChatState.thinking => t.sThinking,
          ChatState.idle => '',
        };
    // One thing at a time: a dictation error, then what was heard (or
    // Listening / Thinking), then the quota only near the limit, then
    // nothing (O8). The full count lives in Me.
    final quota = state.quotaLine;
    final line = heard.isNotEmpty ? heard : quota;
    final colour = state.dictationError != null
        ? QColors.red
        : heard.isNotEmpty
            ? QColors.textMid
            : QColors.textFaint;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      child: Row(
        children: [
          const SizedBox(width: 40),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Large text reads too loose at its default tracking; the brand
                // is the one place in this overlay that needs tightening.
                Text(t.brand, style: QText.display(size: 19, height: 23, weight: FontWeight.w400, letterSpacing: -0.3, color: QColors.textBrand)),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: line.isEmpty
                      ? const SizedBox(key: ValueKey('quiet'), height: 0, width: 0)
                      : Padding(
                          key: ValueKey(line),
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(line,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: QText.body(size: 11.5, height: 15, color: colour)),
                        ),
                ),
              ],
            ),
          ),
          _IconButton(icon: Icons.close_rounded, onTap: state.closeChat, glyph: 19),
        ],
      ),
    );
  }
}

/// The assistant is plain text on the page; only the user gets a bubble. That
/// is the whole reason this reads like a conversation rather than a feed of
/// cards.
class _ChatBubble extends StatelessWidget {
  final ChatTurn turn;
  const _ChatBubble({required this.turn});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    if (turn.who == ChatWho.u) {
      return _Appear(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _userBubble,
                border: Border.all(color: QColors.borderSoft),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (turn.photoPath != null && !kIsWeb) ...[
                    ClipRRect(borderRadius: BorderRadius.circular(14), child: _photoThumb(turn.photoPath!, 132)),
                    const SizedBox(height: 8),
                  ],
                  Text(turn.text, style: QText.body(size: 15.5, height: 23, color: QColors.textPrimary)),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return _Appear(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(turn.text, style: QText.body(size: 15.5, height: 25, color: QColors.textHigh)),
            if (turn.sub != null && turn.sub!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(turn.sub!, style: QText.body(size: 13, height: 21, color: QColors.textMuted)),
            ],
            // A problem's next step, and another way on when there is one
            // (O10); otherwise the turn's one action, as before.
            if (turn.problem != null) ...[
              const SizedBox(height: 6),
              _ProblemActions(problem: turn.problem!),
            ] else if (turn.action != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: _Chip(label: turn.action!, onTap: state.chatActionTap, emphasis: true),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Three dots, the size of a full stop, in the text colour. Under reduce-motion
/// they stop moving and the word says it instead.
class _Thinking extends StatelessWidget {
  const _Thinking();
  @override
  Widget build(BuildContext context) {
    if (_stillness(context)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Text(context.read<AppState>().t.sThinking, style: QText.body(size: 15.5, height: 25, color: QColors.textMuted)),
      );
    }
    return const Padding(
      padding: EdgeInsets.only(bottom: 18, top: 2),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Row(mainAxisSize: MainAxisSize.min, children: [_TDot(0), SizedBox(width: 5), _TDot(1), SizedBox(width: 5), _TDot(2)]),
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
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
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
        final phase = (_c.value + widget.i * 0.18) % 1.0;
        final wave = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
        return Opacity(
          opacity: (0.25 + 0.6 * wave).clamp(0.25, 0.85),
          child: Container(width: 5, height: 5, decoration: const BoxDecoration(shape: BoxShape.circle, color: QColors.textMid)),
        );
      },
    );
  }
}

/// One line of the conversation arriving: a short fade with 8px of travel, so
/// the eye is told where the new text is without being pulled to it.
class _Appear extends StatefulWidget {
  final Widget child;
  const _Appear({required this.child});
  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: _enter)..forward();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = _stillness(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final v = Curves.easeOutCubic.transform(_c.value);
        final faded = Opacity(opacity: v, child: child);
        return still ? faded : Transform.translate(offset: Offset(0, 8 * (1 - v)), child: faded);
      },
      child: widget.child,
    );
  }
}

/// The composer: a field, and the three things you can do with it. The icons
/// are bare glyphs at reading size inside a 40pt target — small on the screen,
/// still a thumb's worth of tappable.
class _Composer extends StatelessWidget {
  final AppState state;
  final TextEditingController ctrl;
  final String placeholder;
  const _Composer({required this.state, required this.ctrl, required this.placeholder});

  @override
  Widget build(BuildContext context) {
    final ready = state.chatDraft.trim().isNotEmpty || state.chatPhotoPath != null;
    return Container(
      padding: const EdgeInsetsDirectional.only(start: 16, end: 4, top: 3, bottom: 3),
      decoration: BoxDecoration(
        color: _raised,
        border: Border.all(color: QColors.borderSoft),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: TextField(
                controller: ctrl,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onChanged: state.onChatDraftChanged,
                onSubmitted: (_) => state.sendChat(),
                style: QText.body(size: 15.5, height: 21, color: QColors.textPrimary),
                decoration: InputDecoration(
                  hintText: placeholder,
                  hintStyle: QText.body(size: 15.5, height: 21, color: QColors.textFaint),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          if (!kIsWeb) _IconButton(icon: Icons.photo_camera_outlined, onTap: () => _photographMenu(context, state)),
          _IconButton(
            icon: Icons.mic_none_rounded,
            onTap: state.tapOrbListen,
            tint: state.chatState == ChatState.listening ? QColors.violetSoft : null,
          ),
          _IconButton(icon: Icons.arrow_upward_rounded, onTap: state.sendChat, filled: true, dim: !ready, glyph: 17),
        ],
      ),
    );
  }
}

/// A 40pt target with an 18pt glyph in it, which answers on the press rather
/// than on the release.
class _IconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  final bool dim;
  final double glyph;
  final Color? tint;
  const _IconButton({required this.icon, required this.onTap, this.filled = false, this.dim = false, this.glyph = 18, this.tint});
  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final still = _stillness(context);
    final Widget glyph = widget.filled
        ? Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(shape: BoxShape.circle, color: QColors.textMuted.withOpacity(widget.dim ? 0.28 : 1)),
            child: Icon(widget.icon, size: widget.glyph, color: widget.dim ? QColors.textMid : QColors.cardNavy),
          )
        : Icon(widget.icon, size: widget.glyph, color: widget.tint ?? QColors.textMuted);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: still
              ? Opacity(opacity: _down ? 0.6 : 1, child: glyph)
              : AnimatedScale(
                  scale: _down ? 0.9 : 1,
                  duration: _press,
                  curve: Curves.easeOut,
                  child: glyph,
                ),
        ),
      ),
    );
  }
}

/// One pill, used both for the suggestions under the field and for the single
/// action an answer may offer. Same shape, same weight — nothing here is a
/// call to action loud enough to pull the eye off the text.
class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool emphasis;
  const _Chip({required this.label, required this.onTap, this.emphasis = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: emphasis ? const Color(0x1AA78BFA) : _raised,
            border: Border.all(color: emphasis ? QColors.violetSoft.withOpacity(0.4) : QColors.borderSoft),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label, style: QText.body(size: 12.5, weight: emphasis ? FontWeight.w500 : FontWeight.w400, color: emphasis ? QColors.textHigh : QColors.textMid)),
        ),
      ),
    );
  }
}

/// A photo riding along with the next message, shown at the size of a stamp:
/// the point is that it is attached, not what is in it.
class _Attachment extends StatelessWidget {
  final String path;
  final String label;
  final VoidCallback? onRemove;
  const _Attachment({required this.path, required this.label, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 10, 4),
        decoration: BoxDecoration(
          color: _raised,
          border: Border.all(color: QColors.borderSoft),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(10), child: _photoThumb(path, 36)),
            const SizedBox(width: 10),
            Text(label, style: QText.body(size: 12, color: QColors.textMuted)),
            if (onRemove != null) ...[
              const SizedBox(width: 2),
              _IconButton(icon: Icons.close_rounded, onTap: onRemove!, glyph: 15),
            ],
          ],
        ),
      ),
    );
  }
}

/// Opens the camera for a menu, a label or a plate and attaches the shot to
/// the next message. Sized for reading print, not for keeping (see photos.dart).
///
/// When the camera will not open, Qamar says so (O10), with choosing a photo
/// already on the phone as the way on, and Settings where the phone allows.
Future<void> _photographMenu(BuildContext context, AppState state) async {
  try {
    final shot = await pickCompressedPhoto(ImageSource.camera);
    if (!context.mounted || shot == null) return;
    state.attachChatPhoto(shot.path);
  } on Exception catch (e) {
    if (!context.mounted) return;
    state.cameraFailedInChat(
      e,
      instead: ProblemAction(state.isAr ? 'اختار صورة من الاستوديو' : 'Choose a photo instead', () => _chooseMenuPhoto(state)),
    );
  }
}

/// The library instead of the camera: the same photo, taken earlier. It
/// needs no camera permission.
Future<void> _chooseMenuPhoto(AppState state) async {
  try {
    final shot = await pickCompressedPhoto(ImageSource.gallery);
    if (shot != null) state.attachChatPhoto(shot.path);
  } on Exception {
    // Nothing chosen and nothing broken: the conversation stays as it was.
  }
}

/// A problem's buttons under Qamar's line: the next step, and another way
/// on when there is one. The chat's chip look, with a touch area of the full
/// 48 points.
class _ProblemActions extends StatelessWidget {
  final Problem problem;
  const _ProblemActions({required this.problem});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        _TallChip(action: problem.action, emphasis: true),
        if (problem.secondary != null) _TallChip(action: problem.secondary!),
        if (problem.also != null) _TallChip(action: problem.also!),
      ],
    );
  }
}

class _TallChip extends StatelessWidget {
  final ProblemAction action;
  final bool emphasis;
  const _TallChip({required this.action, this.emphasis = false});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: action.onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Align(
              widthFactor: 1,
              heightFactor: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: emphasis ? const Color(0x1AA78BFA) : _raised,
                  border: Border.all(color: emphasis ? QColors.violetSoft.withOpacity(0.4) : QColors.borderSoft),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(action.label,
                    style: QText.body(size: 12.5, weight: emphasis ? FontWeight.w500 : FontWeight.w400, color: emphasis ? QColors.textHigh : QColors.textMid)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _photoThumb(String path, double size) {
  return Image.file(
    File(path),
    width: size,
    height: size,
    fit: BoxFit.cover,
    errorBuilder: (_, __, ___) => SizedBox(
      width: size,
      height: size,
      child: const DecoratedBox(
        decoration: BoxDecoration(color: Color(0xFF182137)),
        child: Icon(Icons.photo_camera_outlined, size: 16, color: QColors.textMuted),
      ),
    ),
  );
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

    return _Appear(
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: _raised,
          border: Border.all(color: QColors.borderStrong),
          borderRadius: BorderRadius.circular(20),
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
                          Text(isAr ? '${state.iso('${items[i].def.kcal * items[i].q}')} سعر' : '${items[i].def.kcal * items[i].q} kcal',
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
      ),
    );
  }
}
