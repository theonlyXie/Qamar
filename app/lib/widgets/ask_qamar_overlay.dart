import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/meal.dart';
import '../models/messages.dart';
import '../services/photos.dart';
import '../models/problem.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/icons.dart';
import '../theme/motion.dart';
import '../theme/layout.dart';
import '../theme/text_styles.dart';
import 'common.dart';
import 'glass.dart';

/// S18 — Ask Qamar, the way a conversation with an assistant already looks
/// on the phone (the liquid-glass skill's chat pattern).
///
/// A black page. The assistant's words are plain text across the page; the
/// person's own sit in a grey bubble on their side. At the foot, one glass
/// field: a "+" for a photo, the words, and one white button that is the
/// microphone while the field is empty and the send arrow once there is
/// something to send. Nothing else: no orb docked to the side, no beam, no
/// colour.
///
/// Motion is short and critically damped (QSpring), and falls back to a plain
/// cross-fade under the platform's reduce-motion setting.
const _ground = QColors.canvas;

/// The person's own words: the raised grey, a step above the page.
const _userBubble = QColors.surfaceHigh;

bool _stillness(BuildContext context) => MediaQuery.disableAnimationsOf(context);

class AskQamarOverlay extends StatefulWidget {
  const AskQamarOverlay({super.key});

  /// The conversation, drawn from the bottom up (O10).
  static const transcriptKey = ValueKey('chat-transcript');

  /// The suggestion row's end fade.
  static const suggestionFadeKey = ValueKey('chat-suggestion-fade');

  /// The empty conversation's one line, for tests.
  static const emptyKey = ValueKey('chat-empty');

  /// The line under the composer saying the answers come from AI.
  static const disclosureKey = ValueKey('chat-disclosure');

  /// The copy action under the latest reply.
  static const copyKey = ValueKey('chat-copy');

  /// The conversation's ground at its top and bottom edges, for the shell
  /// to carry into the status bar and the home indicator's strips.
  static Color get groundTop => _ground;
  static Color get groundBottom => _ground;
  @override
  State<AskQamarOverlay> createState() => _AskQamarOverlayState();
}

class _AskQamarOverlayState extends State<AskQamarOverlay> with SingleTickerProviderStateMixin {
  final _chat = ChatScroller();
  final _ctrl = TextEditingController();

  /// The composer's focus, taken when the state asks ("Type it instead").
  final _focus = FocusNode();
  int? _focusAsked;

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
    _focus.dispose();
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
    // A request made since the conversation opened takes the keyboard,
    // including one made as it opened ("Log a meal", Type on the moon); the
    // count already there before it opened is not a request.
    if ((_focusAsked ?? state.composerFocusAtOpen) != state.composerFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
    _focusAsked = state.composerFocus;

    // Questions to ask are not offered while Qamar waits to hear a meal, or
    // for one to be confirmed: the one thing to do then is answer.
    final showSuggestions = state.chatDraft.isEmpty && state.chatState != ChatState.thinking && !state.loggingMeal && !state.hasProposal;
    final empty = state.chat.isEmpty && !state.hasProposal && state.chatState != ChatState.thinking;

    // Sized by the shell, not by a Stack: the overlay is handed a full-screen
    // box so it can fade in and out inside a switcher.
    return SizedBox.expand(
      child: FadeTransition(
        opacity: _shown,
        child: ColoredBox(
          color: _ground,
          child: AnimatedBuilder(
            animation: _in,
            builder: (context, child) {
              if (still) return child!;
              return Transform.translate(offset: Offset(0, 8 * (1 - _shown.value)), child: child);
            },
            child: Column(
              children: [
                _Header(state: state),
                Expanded(
                  child: empty
                      ? Center(
                          key: AskQamarOverlay.emptyKey,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              state.isAr ? 'أساعدك في إيه؟' : 'What can I help with?',
                              textAlign: TextAlign.center,
                              style: QText.display(size: 28, ar: state.isAr, weight: FontWeight.w600),
                            ),
                          ),
                        )
                      // Drawn from the bottom up (O10): a fresh conversation's
                      // first line sits on the field, where the eye is.
                      : _TopFade(
                          child: ListView(
                            key: AskQamarOverlay.transcriptKey,
                            controller: _chat.controller,
                            reverse: true,
                            // Dragging the conversation puts the keyboard away,
                            // the way every messaging app on the phone does.
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.fromLTRB(QSpace.page, 16, QSpace.page, 16),
                            children: [
                              // Newest first. What the assistant read off the
                              // meal, waiting to be confirmed: nothing is
                              // written until it is.
                              if (state.hasProposal) const _ProposalCard(),
                              if (state.chatState == ChatState.thinking) const _Thinking(),
                              // Keyed by place in the conversation, oldest
                              // first, so a new message is a new child that
                              // arrives, and the ones above keep their state
                              // (unkeyed, the newest slot took the new words
                              // and nothing animated in).
                              for (final (i, c) in state.chat.reversed.indexed)
                                _ChatTurn(key: ValueKey('turn-${state.chat.length - 1 - i}'), turn: c, latest: i == 0),
                            ],
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showSuggestions) ...[
                        SizedBox(
                          height: QLayout.minTap,
                          // The row fades out at its end, where it runs on
                          // past the screen: "more this way", not "broken".
                          child: _EndFade(
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
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
                        const SizedBox(height: 6),
                      ],
                      // Proof the camera actually fired: the shot the user just
                      // took, attached to the message about to be sent.
                      if (state.lastMealPhotoPath != null && !kIsWeb)
                        _Attachment(path: state.lastMealPhotoPath!, label: state.isAr ? 'صورة الوجبة' : 'Meal photo'),
                      // A menu photographed at the table, waiting to go with
                      // the next words — or with none: "what do I order here?"
                      // is implied.
                      if (state.chatPhotoPath != null && !kIsWeb)
                        _Attachment(path: state.chatPhotoPath!, label: state.isAr ? 'صورة المنيو' : 'Menu photo', onRemove: state.detachChatPhoto),
                      // The field's hint says what it takes now: a menu's
                      // question, a meal being logged (an example, never a
                      // question's words: a meal read spends none), or a
                      // question for Qamar.
                      _Composer(
                        state: state,
                        ctrl: _ctrl,
                        focus: _focus,
                        placeholder: state.chatPhotoPath != null
                            ? (state.isAr ? 'اسأل عن المنيو، أو ابعت الصورة بس' : 'Ask about the menu, or just send the photo')
                            : state.loggingMeal
                                ? t.mealPlaceholder
                                : t.chatPlaceholder,
                      ),
                      // Said once and always there, quietly: the answers
                      // come from AI and can be wrong (the HIG's generative
                      // AI rules), and a health question is a doctor's.
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          state.isAr ? 'قمر ممكن يغلط. أي حاجة طبية راجعها مع دكتور.' : 'Qamar can make mistakes. Check anything medical with a doctor.',
                          key: AskQamarOverlay.disclosureKey,
                          textAlign: TextAlign.center,
                          style: QText.body(size: 11, color: QColors.inkTertiary),
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

/// The conversation header's measures (O8), for the header and its tests.
abstract final class ChatHeader {
  /// The status line's type size.
  static const double lineSize = 12;

  /// The line's reserved height: its top gap and one 16pt line, kept when
  /// the line is empty.
  static const double lineHeight = 18;

  static const lineKey = ValueKey('chat-header-line');
}

/// One way out, the name, and one line of state. The quota takes the status
/// line when there is no status to report, so the header never carries two
/// things at once (O8).
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
    final line = heard.isNotEmpty ? heard : state.quotaLine;
    final colour = heard.isNotEmpty ? QColors.inkSecondary : QColors.inkTertiary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Row(
        children: [
          _GlassIcon(icon: QIcons.close, onTap: state.closeChat, label: state.isAr ? 'اقفل المحادثة' : 'Close the conversation'),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t.brand, style: QText.body(size: 17, weight: FontWeight.w600, color: QColors.ink)),
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
          // As wide as the close button, so the name is centred on the screen.
          const SizedBox(width: QLayout.minTap),
        ],
      ),
    );
  }
}

/// The transcript's top edge fades under the header instead of stopping at
/// a rule: what scrolls away goes behind, the way content does under a bar.
class _TopFade extends StatelessWidget {
  final Widget child;
  const _TopFade({required this.child});

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Colors.transparent, QColors.canvas, QColors.canvas],
          stops: [0, 24 / r.height.clamp(24, double.infinity), 1],
        ).createShader(r),
        child: child,
      );
}

/// A turn of the conversation. The assistant is plain text on the page; only
/// the person gets a bubble. That is the whole reason this reads like a
/// conversation rather than a feed of cards.
class _ChatTurn extends StatelessWidget {
  final ChatTurn turn;

  /// The newest turn: a reply here carries the copy action under it.
  final bool latest;
  const _ChatTurn({super.key, required this.turn, this.latest = false});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    if (turn.who == ChatWho.u) {
      return _Appear(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 20, top: 4),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(color: _userBubble, borderRadius: BorderRadius.circular(QRadii.card)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (turn.photoPath != null && !kIsWeb) ...[
                    ClipRRect(borderRadius: BorderRadius.circular(QRadii.inset), child: _photoThumb(turn.photoPath!, 140)),
                    const SizedBox(height: 8),
                  ],
                  Text(turn.text, style: QText.body(size: 17, height: 24, color: QColors.ink)),
                ],
              ),
            ),
          ),
        ),
      );
    }
    // The newest answer's copy row is its own space below it. Qamar's own
    // lines (a greeting, a question, a notice) are not answers to copy.
    final copy = latest && turn.answer && turn.problem == null;
    return _Appear(
      child: Padding(
        padding: EdgeInsets.only(bottom: copy ? 8 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(turn.text, style: QText.body(size: 17, height: 26, color: QColors.ink)),
            if (turn.sub != null && turn.sub!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(turn.sub!, style: QText.body(size: 15, height: 22, color: QColors.inkSecondary)),
            ],
            // A problem's next step, and another way on when there is one
            // (O10); otherwise the turn's one action.
            if (turn.problem != null) ...[
              const SizedBox(height: 8),
              _ProblemActions(problem: turn.problem!),
            ] else if (turn.action != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: _Chip(label: turn.action!, onTap: state.chatActionTap, emphasis: true),
              ),
            ],
            // Under the newest answer, the one thing people do with an
            // answer they like: copy it.
            if (copy) _CopyReply(text: [turn.text, if (turn.sub != null && turn.sub!.isNotEmpty) turn.sub!].join('\n')),
          ],
        ),
      ),
    );
  }
}

/// Copy an answer: a quiet glyph at the answer's start, which turns into a
/// tick for a moment once the words are on the clipboard.
class _CopyReply extends StatefulWidget {
  final String text;
  const _CopyReply({required this.text});

  @override
  State<_CopyReply> createState() => _CopyReplyState();
}

class _CopyReplyState extends State<_CopyReply> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    HapticFeedback.selectionClick();
    if (!mounted) return;
    setState(() => _copied = true);
    await Future.delayed(const Duration(milliseconds: 1600));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final ar = context.read<AppState>().isAr;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: QTapArea(
        key: AskQamarOverlay.copyKey,
        onTap: _copy,
        label: _copied ? (ar ? 'اتنسخ' : 'Copied') : (ar ? 'انسخ الرد' : 'Copy the answer'),
        builder: (context, pressed) => qPressed(
          context,
          pressed: pressed,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: Icon(_copied ? QIcons.check : QIcons.copy, key: ValueKey(_copied), size: 18, color: QColors.inkTertiary),
          ),
        ),
      ),
    );
  }
}

/// Qamar is thinking: one white dot, breathing, where the answer will start.
/// Under reduce-motion it holds still and the word says it instead.
class _Thinking extends StatefulWidget {
  const _Thinking();
  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_stillness(context)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Text(context.read<AppState>().t.sThinking, style: QText.body(size: 17, height: 26, color: QColors.inkTertiary)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 24, top: 6),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final v = Curves.easeInOut.transform(_c.value);
            return Transform.scale(
              scale: 0.72 + 0.28 * v,
              child: Opacity(
                opacity: 0.55 + 0.45 * v,
                child: Container(width: 14, height: 14, decoration: const BoxDecoration(shape: BoxShape.circle, color: QColors.ink)),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One line of the conversation arriving: a short fade with 8 points of
/// travel, so the eye is told where the new text is without being pulled.
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
        colors: const [QColors.canvas, QColors.canvas, Colors.transparent],
        stops: [0, 1 - fade / r.width, 1],
      ).createShader(r),
      child: child,
    );
  }
}

/// The composer: one glass field, the way an assistant's is. A "+" for a
/// photo at the start; the words; and at the end one white button that is
/// the microphone while there is nothing to send and the send arrow once
/// there is. While Qamar is listening the button is the stop square.
class _Composer extends StatelessWidget {
  final AppState state;
  final TextEditingController ctrl;
  final FocusNode focus;
  final String placeholder;
  const _Composer({required this.state, required this.ctrl, required this.focus, required this.placeholder});

  @override
  Widget build(BuildContext context) {
    final ready = state.chatDraft.trim().isNotEmpty || state.chatPhotoPath != null;
    final listening = state.chatState == ChatState.listening;
    final isAr = state.isAr;
    return QGlass(
      shape: QGlassShape.rounded,
      radius: 26,
      padding: const EdgeInsetsDirectional.only(start: 4, end: 4, top: 2, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!kIsWeb) _PlainIcon(icon: QIcons.attach, onTap: () => _photographMenu(context, state), label: isAr ? 'صوّر' : 'Take a photo'),
          Expanded(
            // The field itself is the touch, [QLayout.minTap] tall (O11).
            child: TextField(
              controller: ctrl,
              focusNode: focus,
              minLines: 1,
              maxLines: 6,
              textInputAction: TextInputAction.send,
              onChanged: state.onChatDraftChanged,
              onSubmitted: (_) => state.sendChat(),
              cursorColor: QColors.accentInk,
              style: QText.body(size: 17, height: 22, color: QColors.ink),
              decoration: InputDecoration(
                // Listening, the field says so where the words will appear.
                hintText: listening ? state.t.sListening : placeholder,
                hintStyle: QText.body(size: 17, height: 22, color: QColors.inkTertiary),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsetsDirectional.only(start: kIsWeb ? 12 : 2, end: 4, top: (QLayout.minTap - 22) / 2 + 0.5, bottom: (QLayout.minTap - 22) / 2 + 0.5),
              ),
            ),
          ),
          if (ready)
            _InkCircle(icon: QIcons.send, onTap: state.sendChat, label: isAr ? 'ابعت' : 'Send', accent: true)
          else
            _InkCircle(
              icon: listening ? QIcons.stop : QIcons.mic,
              onTap: state.tapOrbListen,
              label: listening ? (isAr ? 'وقّف' : 'Stop') : (isAr ? 'اتكلم' : 'Speak'),
            ),
        ],
      ),
    );
  }
}

/// A bare glyph in a whole touch ([QLayout.minTap]), answering on the press.
class _PlainIcon extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String label;
  final double glyph;
  const _PlainIcon({required this.icon, required this.onTap, required this.label, this.glyph = 22});
  @override
  State<_PlainIcon> createState() => _PlainIconState();
}

class _PlainIconState extends State<_PlainIcon> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
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
          child: Center(child: qPressed(context, pressed: _down, child: Icon(widget.icon, size: widget.glyph, color: enabled ? QColors.ink : QDisabled.label))),
        ),
      ),
    );
  }
}

/// The composer's one filled button: a white circle, a black glyph.
class _InkCircle extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String label;

  /// Burgundy: the composer's one action, sending what is written. The
  /// microphone beside an empty field is clear glass, so the screen's one
  /// burgundy thing stays the thing to do.
  final bool accent;
  const _InkCircle({required this.icon, required this.onTap, required this.label, this.accent = false});
  @override
  State<_InkCircle> createState() => _InkCircleState();
}

class _InkCircleState extends State<_InkCircle> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
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
        onTap: enabled
            ? () {
                HapticFeedback.lightImpact();
                widget.onTap!();
              }
            : null,
        child: SizedBox(
          width: QLayout.minTap,
          height: QLayout.minTap,
          child: Center(
            child: qPressed(
              context,
              pressed: _down,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                transitionBuilder: (child, a) => ScaleTransition(scale: Tween(begin: 0.8, end: 1.0).animate(a), child: FadeTransition(opacity: a, child: child)),
                // Burgundy glass to send; clear glass to speak.
                child: enabled
                    ? QGlass(
                        key: ValueKey(widget.icon),
                        shape: QGlassShape.circle,
                        tint: widget.accent ? QColors.accent : null,
                        pressed: _down,
                        blur: 0,
                        width: 36,
                        height: 36,
                        child: Center(child: Icon(widget.icon, size: 18, color: widget.accent ? QColors.onAccent : QColors.ink)),
                      )
                    : Container(
                        key: ValueKey(widget.icon),
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: QDisabled.fill),
                        child: Icon(widget.icon, size: 18, color: QDisabled.label),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A floating glass circle with a glyph: the header's way out.
class _GlassIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String label;
  const _GlassIcon({required this.icon, required this.onTap, required this.label});

  @override
  Widget build(BuildContext context) => QTapArea(
        onTap: onTap,
        label: label,
        builder: (context, pressed) => qPressed(
          context,
          pressed: pressed,
          child: QGlass(
            shape: QGlassShape.circle,
            pressed: pressed,
            width: 40,
            height: 40,
            child: Center(child: Icon(icon, size: 18, color: QColors.ink)),
          ),
        ),
      );
}

/// One chip for the conversation: the suggestions over the field, a turn's
/// action, and a problem's ways on (O10). A capsule of clear glass drawn
/// about 36 points tall that takes a whole touch ([QLayout.minTap]) (O11).
/// The emphasised one, a turn's next step, says it in burgundy words: an
/// action, but not the screen's one burgundy fill, which a conversation
/// keeps for sending (and a reading's "Confirm and log").
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
        child: qPressed(
          context,
          pressed: pressed,
          child: QGlass(
            pressed: pressed,
            blur: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Text(label, style: QText.body(size: 15, weight: emphasis ? FontWeight.w600 : FontWeight.w500, color: emphasis ? QColors.accentInk : QColors.ink)),
          ),
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
        margin: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
        padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 6, 4),
        decoration: QDecor.card(color: QColors.surfaceRaised, radius: QRadii.control),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(QRadii.inset), child: _photoThumb(path, 40)),
            const SizedBox(width: 10),
            Text(label, style: QText.body(size: 13, color: QColors.inkSecondary)),
            if (onRemove != null) _PlainIcon(icon: QIcons.close, onTap: onRemove!, glyph: 15, label: context.read<AppState>().isAr ? 'شيل الصورة' : 'Remove the photo'),
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
/// on when there is one.
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
        decoration: BoxDecoration(color: QColors.surfaceRaised),
        child: Icon(QIcons.photo, size: 16, color: QColors.inkTertiary),
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

    // How sure the reading is, said only where it matters and in plain
    // words: a sure item says nothing, a guess says so, and a weak one asks
    // to be looked at. Never a score.
    String? doubt(Confidence c) => switch (c) {
          Confidence.high => null,
          Confidence.med => isAr ? 'تقريبي' : 'Best guess',
          Confidence.low => isAr ? 'اتأكد منها' : 'Check this',
        };

    return _Appear(
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        decoration: QDecor.card(border: QColors.hairlineStrong),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.nothingWrites, style: QText.body(size: 13, color: QColors.inkTertiary)),
            const SizedBox(height: 12),
            for (var i = 0; i < items.length; i++) ...[
              Opacity(
                // A dropped item stays visible: the reading is still what the
                // assistant saw, it just is not going in the log.
                opacity: items[i].q == 0 ? 0.4 : 1,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
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
                                Text(isAr ? items[i].def.ar : items[i].def.en, style: QText.body(size: 17, weight: FontWeight.w600, color: QColors.ink)),
                                Text(isAr ? items[i].def.portionAr : items[i].def.portionEn, style: QText.body(size: 13, color: QColors.inkTertiary)),
                              ],
                            ),
                          ),
                          if (doubt(items[i].def.conf) case final d?) ConfidenceBadge(check: items[i].def.conf == Confidence.low, label: d),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          QRoundIconButton(icon: QIcons.remove, onTap: () => state.decQty(i), size: 32, label: isAr ? 'أقل' : 'Fewer'),
                          SizedBox(width: 40, child: Text(isAr ? state.iso('${items[i].q}×') : '${items[i].q}×', textAlign: TextAlign.center, style: QText.number(size: 15, weight: FontWeight.w600, color: QColors.ink))),
                          QRoundIconButton(icon: QIcons.add, onTap: () => state.incQty(i), size: 32, label: isAr ? 'أكتر' : 'More'),
                          const Spacer(),
                          Text(isAr ? '${state.iso('${items[i].def.kcal * items[i].q}')} سعر' : '${items[i].def.kcal * items[i].q} kcal',
                              style: QText.number(size: 15, weight: FontWeight.w600, color: QColors.ink)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const Divider(height: 1, color: QColors.hairline),
            const SizedBox(height: 12),
            // The one number the meal comes to; the macros are Today's.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(isAr ? 'الإجمالي' : 'Total', style: QText.body(size: 15, weight: FontWeight.w500, color: QColors.inkSecondary)),
                Flexible(
                  child: Text(isAr ? 'حوالي ${state.iso('${totals.kcal}')} سعر' : 'About ${totals.kcal} kcal',
                      textAlign: TextAlign.end, style: QText.number(size: 17, weight: FontWeight.w600, color: QColors.ink, ar: isAr)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            QPrimaryButton(label: t.confirmAndLog, onTap: state.confirmProposal, height: 50),
            Center(
              child: TextButton(
                onPressed: state.discardProposal,
                style: TextButton.styleFrom(minimumSize: const Size(QLayout.minTap, QLayout.minTap), foregroundColor: QColors.inkSecondary),
                child: Text(t.cancel, style: QText.body(size: 15, weight: FontWeight.w500, color: QColors.inkSecondary)),
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
