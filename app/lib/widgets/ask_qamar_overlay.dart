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
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/motion.dart';
import '../theme/layout.dart';
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
final _scrimTop = QColors.cardDeep.withValues(alpha: 0.95);
final _scrimBottom = QColors.bgBottom.withValues(alpha: 0.98);

/// The composer and the user's own words sit on the one surface that is a step
/// lighter than the sheet — enough to separate, not enough to shout.
final _raised = QColors.cardDeep.withValues(alpha: 0.9);
const _userBubble = QColors.glassHigh;

/// How long a press takes to show. Arrivals are on the settle spring
/// (QSpring): past half-way in 100ms, at rest in about 400.
const _press = Duration(milliseconds: 90);

bool _stillness(BuildContext context) => MediaQuery.disableAnimationsOf(context);

class AskQamarOverlay extends StatefulWidget {
  const AskQamarOverlay({super.key});

  /// The conversation, drawn from the bottom up (O10).
  static const transcriptKey = ValueKey('chat-transcript');

  /// The suggestion row's end fade.
  static const suggestionFadeKey = ValueKey('chat-suggestion-fade');

  /// The conversation's ground at its top and bottom edges, for the shell
  /// to carry into the status bar and the home indicator's strips.
  static Color get groundTop => _scrimTop;
  static Color get groundBottom => _scrimBottom;
  @override
  State<AskQamarOverlay> createState() => _AskQamarOverlayState();
}

class _AskQamarOverlayState extends State<AskQamarOverlay> with SingleTickerProviderStateMixin {
  final _chat = ChatScroller();
  final _ctrl = TextEditingController();
  /// The entrance, on the settle spring (QSpring): quick, and at rest
  /// without passing its mark. Under reduce-motion a plain fade.
  late final AnimationController _in = AnimationController.unbounded(vsync: this);
  late final Animation<double> _shown = _in.drive(_Clamp01());
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    QSpring.drive(_in, 1, still: _stillness(context));
  }

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
            opacity: _shown,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_scrimTop, _scrimBottom]),
              ),
              child: AnimatedBuilder(
                animation: _in,
                builder: (context, child) {
                  if (still) return child!;
                  return Transform.translate(offset: Offset(0, 10 * (1 - _shown.value)), child: child);
                },
                child: Column(
                  children: [
                    _Header(state: state),
                    // Drawn from the bottom up (O10): a fresh conversation's
                    // first line sits on the field, where the eye is, and the
                    // space above it is sky instead of a gap under it.
                    Expanded(
                      child: ListView(
                        key: AskQamarOverlay.transcriptKey,
                        controller: _chat.controller,
                        reverse: true,
                        // Dragging the conversation puts the keyboard away, the
                        // way every messaging app on the phone already does.
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                        children: [
                          // Newest first.
                          // What the assistant read off the meal, waiting to be
                          // confirmed. Nothing is written until it is.
                          if (state.hasProposal) const _ProposalCard(),
                          if (state.chatState == ChatState.thinking) const _Thinking(),
                          for (final c in state.chat.reversed) _ChatBubble(turn: c),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 22),
                      // A fade where the conversation meets the composer, in
                      // place of a rule across the screen.
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [QColors.bgBottom.withValues(alpha: 0), QColors.bgBottom.withValues(alpha: 0.9)]),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showSuggestions) ...[
                            SizedBox(
                              height: QLayout.minTap,
                              // The row fades out at its end, where it runs
                              // on past the screen: a clipped chip read as
                              // broken; a fading one reads as "more this way".
                              child: _EndFade(
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
                            ),
                            const SizedBox(height: 4),
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
/// The conversation header's measures (O8), for the header and its tests.
abstract final class ChatHeader {
  /// The status line's type size.
  static const double lineSize = 12;

  /// The line's reserved height: its top gap and one 16pt line, kept when
  /// the line is empty.
  static const double lineHeight = 18;

  static const lineKey = ValueKey('chat-header-line');
}

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
    // The quota is read, not glanced past: textMuted passes AA on the
    // conversation's ground where the old faint grey did not (O8).
    final colour = state.dictationError != null
        ? QColors.red
        : heard.isNotEmpty
            ? QColors.textMid
            : QColors.textMuted;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      child: Row(
        children: [
          // As wide as the close button, so the name is centred on the screen.
          const SizedBox(width: QLayout.minTap),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Large text reads too loose at its default tracking; the brand
                // is the one place in this overlay that needs tightening.
                Text(t.brand, style: QText.display(size: 20, ar: QText.arabic(t.brand), weight: FontWeight.w400, color: QColors.textPrimary)),
                // The line keeps its height when it has nothing to say, so
                // the name never jumps as a status comes and goes (O8).
                SizedBox(
                  key: ChatHeader.lineKey,
                  height: ChatHeader.lineHeight,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: line.isEmpty
                        ? const SizedBox.shrink(key: ValueKey('quiet'))
                        : Padding(
                            key: ValueKey(line),
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(line,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: QText.body(size: ChatHeader.lineSize, height: 16, color: colour)),
                          ),
                  ),
                ),
              ],
            ),
          ),
          _IconButton(icon: Icons.close_rounded, onTap: state.closeChat, glyph: 19, label: state.isAr ? 'اقفل المحادثة' : 'Close the conversation'),
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
                borderRadius: BorderRadius.circular(QRadii.card),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (turn.photoPath != null && !kIsWeb) ...[
                    ClipRRect(borderRadius: BorderRadius.circular(QRadii.control), child: _photoThumb(turn.photoPath!, 132)),
                    const SizedBox(height: 8),
                  ],
                  Text(turn.text, style: QText.body(size: 15, height: 23, color: QColors.textPrimary)),
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
            Text(turn.text, style: QText.body(size: 15, height: 25, color: QColors.textHigh)),
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
        child: Text(context.read<AppState>().t.sThinking, style: QText.body(size: 15, height: 25, color: QColors.textMuted)),
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
  late final AnimationController _c = AnimationController.unbounded(vsync: this);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    QSpring.drive(_c, 1, still: _stillness(context));
  }

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
        final v = _c.value.clamp(0.0, 1.0);
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
/// Fades its child out towards the end edge (the right in English, the left
/// in Arabic): a row that runs on past the screen says so.
class _EndFade extends StatelessWidget {
  final Widget child;
  const _EndFade({required this.child});

  static const fade = 28.0;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return ShaderMask(
      key: AskQamarOverlay.suggestionFadeKey,
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) => LinearGradient(
        begin: rtl ? Alignment.centerRight : Alignment.centerLeft,
        end: rtl ? Alignment.centerLeft : Alignment.centerRight,
        // Only a dstIn mask's alpha counts: whole, whole, gone.
        colors: const [QColors.bgBottom, QColors.bgBottom, Colors.transparent],
        stops: [0, 1 - fade / r.width, 1],
      ).createShader(r),
      child: child,
    );
  }
}

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
        borderRadius: BorderRadius.circular(QRadii.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            // The field itself is the touch, [QLayout.minTap] tall (O11):
            // the padding that used to sit around it is inside it now.
            child: TextField(
                controller: ctrl,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onChanged: state.onChatDraftChanged,
                onSubmitted: (_) => state.sendChat(),
                style: QText.body(size: 15, height: 21, color: QColors.textPrimary),
                decoration: InputDecoration(
                  hintText: placeholder,
                  hintStyle: QText.body(size: 15, height: 21, color: QColors.textMuted),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: (QLayout.minTap - 21) / 2 + 0.5),
                ),
              ),
          ),
          if (!kIsWeb) _IconButton(icon: Icons.photo_camera_outlined, onTap: () => _photographMenu(context, state), label: state.isAr ? 'صوّر' : 'Take a photo'),
          _IconButton(
            icon: Icons.mic_none_rounded,
            onTap: state.tapOrbListen,
            label: state.isAr ? 'اتكلم' : 'Speak',
            tint: state.chatState == ChatState.listening ? QColors.violetSoft : null,
          ),
          _IconButton(icon: Icons.arrow_upward_rounded, onTap: ready ? state.sendChat : null, filled: true, glyph: 17, label: state.isAr ? 'ابعت' : 'Send'),
        ],
      ),
    );
  }
}

/// A whole touch ([QLayout.minTap]) with an 18pt glyph in it, which answers
/// on the press rather than on the release. With nothing to do ([onTap]
/// null) it takes no touch and says so: the filled one dims, and a screen
/// reader hears it as not enabled.
class _IconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;
  final double glyph;
  final Color? tint;

  /// What it does, for a screen reader: the glyph has no words.
  final String label;
  const _IconButton({required this.icon, required this.onTap, required this.label, this.filled = false, this.glyph = 18, this.tint});
  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final still = _stillness(context);
    final enabled = widget.onTap != null;
    final Widget glyph = widget.filled
        ? Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(shape: BoxShape.circle, color: enabled ? QColors.textMuted : QDisabled.edge),
            child: Icon(widget.icon, size: widget.glyph, color: enabled ? QColors.cardDeep : QDisabled.label),
          )
        : Icon(widget.icon, size: widget.glyph, color: enabled ? (widget.tint ?? QColors.textMuted) : QDisabled.label);

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onTap,
        child: SizedBox(
          width: QLayout.minTap,
          height: QLayout.minTap,
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
      ),
    );
  }
}

/// One chip for the conversation: the suggestions under the field, a
/// turn's action, and a problem's ways on (O10). Drawn about 34 points tall,
/// it takes a whole touch ([QLayout.minTap]) (O11).
class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool emphasis;
  const _Chip({required this.label, required this.onTap, this.emphasis = false});

  @override
  Widget build(BuildContext context) {
    return QTapArea(
      onTap: onTap,
      // Centred in its band: a row of chips hands each one the band's full
      // height, and the chip is drawn at its own.
      builder: (context, pressed) => Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: pressed ? QColors.cardMid : (emphasis ? QColors.violetSoft.withValues(alpha: 0.1) : _raised),
          border: Border.all(color: emphasis ? QColors.violetSoft.withValues(alpha: 0.4) : QColors.borderSoft),
          borderRadius: BorderRadius.circular(QRadii.pill),
        ),
        child: Text(label, style: QText.body(size: 13, weight: emphasis ? FontWeight.w500 : FontWeight.w400, color: emphasis ? QColors.textHigh : QColors.textMid)),
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
          borderRadius: BorderRadius.circular(QRadii.control),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(QRadii.inset), child: _photoThumb(path, 36)),
            const SizedBox(width: 10),
            Text(label, style: QText.body(size: 12, color: QColors.textMuted)),
            if (onRemove != null) ...[
              const SizedBox(width: 2),
              _IconButton(icon: Icons.close_rounded, onTap: onRemove!, glyph: 15, label: context.read<AppState>().isAr ? 'شيل الصورة' : 'Remove the photo'),
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
        _Chip(label: problem.action.label, onTap: problem.action.onTap, emphasis: true),
        if (problem.secondary != null) _Chip(label: problem.secondary!.label, onTap: problem.secondary!.onTap),
        if (problem.also != null) _Chip(label: problem.also!.label, onTap: problem.also!.onTap),
      ],
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
        decoration: BoxDecoration(color: QColors.cardMid),
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
          borderRadius: BorderRadius.circular(QRadii.card),
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
                          QRoundIconButton(icon: Icons.remove, onTap: () => state.decQty(i), size: 28, label: isAr ? 'أقل' : 'Fewer'),
                          SizedBox(width: 40, child: Text(isAr ? state.iso('${items[i].q}×') : '${items[i].q}×', textAlign: TextAlign.center, style: QText.number(size: 14, weight: FontWeight.w600, color: QColors.textMid))),
                          QRoundIconButton(icon: Icons.add, onTap: () => state.incQty(i), size: 28, label: isAr ? 'أكتر' : 'More'),
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

/// 0 to 1, whatever the spring's last digits do.
class _Clamp01 extends Animatable<double> {
  @override
  double transform(double t) => t.clamp(0.0, 1.0);
}
