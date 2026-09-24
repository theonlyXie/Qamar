import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/trial_words.dart';
import '../l10n/words.dart';
import '../models/billing.dart';
import '../models/invitation.dart';
import '../models/su_economy.dart';
import '../services/config.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/icons.dart';
import '../theme/layout.dart';
import '../theme/text_styles.dart';
import '../widgets/account_sheet.dart';
import '../widgets/avoid_editor.dart';
import '../widgets/common.dart';
import '../widgets/kit.dart';
import '../widgets/orb_gesture_guide.dart';

/// Me, the kit's Settings page: the profile card, then one card to a group,
/// a row to a thing, its value at the end and a chevron where it goes
/// somewhere, switches (burgundy when on) on their own rows. What people
/// come here for is at the top — who they are, Qamar+, their food, their
/// points — and the rare and the technical at the foot: the nutritionists'
/// codes, privacy, the version. Anything with more to it than a row opens a
/// sheet over the page.
class YouScreen extends StatelessWidget {
  const YouScreen({super.key});

  /// The "Points and streaks" switch (O4) and its row, found by tests.
  static const scoreSwitchKey = ValueKey('points-and-streaks');
  static const scoreRowKey = ValueKey('points-and-streaks-row');

  /// The professional's code, or the way to one, in its sheet.
  static const proCodeKey = ValueKey('affiliate-code');

  /// The choice of how many questions Qamar asks a day, [n] a day.
  static ValueKey<String> nudgeKey(int n) => ValueKey('nudges-$n');

  /// The Western digits, as the Arabic digits choice shows them: the one
  /// place an Arabic screen draws Latin digits on purpose.
  static const westernDigits = '123';

  /// How many things Qamar remembers, counted the way each language counts:
  /// "1 item" and "2 items"; in Arabic one, two (the dual), three to ten
  /// (the plural) and eleven on (the singular), where both used to say the
  /// plural for every number ("1 items", "١ عناصر"). The app's one count
  /// rule ([Counted]).
  static String itemsLine(int n, {required bool isAr, required String Function(String) iso}) => Counted.item.of(n, ar: isAr, iso: iso);

  /// What to avoid, in the consultation's own names for its choices and
  /// in their order: "No red meat · Lactose", "مش باكل لحوم · لاكتوز", and
  /// its "Nothing" / "مفيش" when there is none, where the read-out said a
  /// bare count ("2") and "None". A value the choices do not name is said
  /// as it is stored, after them.
  static String avoidLine(List<String> prefs, {required bool isAr}) {
    final options = AppState.avoidStep.options;
    if (prefs.isEmpty) {
      final none = options.firstWhere((o) => o.value == 'none');
      return isAr ? none.ar : none.en;
    }
    final known = {for (final o in options) o.value};
    return [
      for (final o in options)
        if (o.value != 'none' && prefs.contains(o.value)) isAr ? o.ar : o.en,
      for (final p in prefs)
        if (!known.contains(p)) p,
    ].join(' · ');
  }

  /// The food group: the target, what to avoid, and what Qamar remembers.
  static const readOutKey = ValueKey('you-read-out');

  /// What to avoid, the row that changes it (gap 4).
  static const avoidEntryKey = ValueKey('you-avoid-entry');

  /// The wallet's group, and its row: the one way to the wallet on Me.
  static const walletCardKey = ValueKey('you-wallet');
  static const walletRowKey = ValueKey('you-wallet-row');

  /// The other rows that go somewhere, for tests.
  static const saveProgressKey = ValueKey('you-save-progress');
  static const plusRowKey = ValueKey('you-plus');
  static const inviteRowKey = ValueKey('you-invite');
  static const helpRowKey = ValueKey('you-help');
  static const proCodeRowKey = ValueKey('you-pro-code');
  static const programmeRowKey = ValueKey('you-programme');
  static const ramadanRowKey = ValueKey('you-ramadan');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;
    final isAr = state.isAr;
    final tg = state.target();
    final remembered = state.rememberedCount();
    final until = state.plusUntil?.toLocal();
    final member = state.plusActive;

    return ListView(
      padding: const EdgeInsets.fromLTRB(QSpace.page, QLayout.pageTop, QSpace.page, QLayout.pageBottom),
      children: [
        // A tab's page: its name, and no way back (the tab bar is the way).
        QPageTitle(title: t.you, isAr: isAr),
        const SizedBox(height: QSpace.lg),

        // Who this is: the one hero on Me, the moon beside the name. Saving
        // the account is offered only while it really is a guest one.
        _Group(
          rows: [
            _ProfileRow(state: state),
            if (!state.hasAccount) _Row(key: YouScreen.saveProgressKey, icon: QIcons.account, label: t.saveProgress, onTap: state.openLinkAccount),
          ],
          footer: state.hasAccount ? null : t.saveProgressSub,
        ),
        const SizedBox(height: QSpace.lg),

        // Qamar+, and what it brings with it. The day's allowance in full is
        // said here; the conversation's header says only "Last question
        // today" near the limit (O8).
        _Group(
          rows: [
            _Row(
              key: YouScreen.plusRowKey,
              icon: QIcons.plus,
              label: 'Qamar+',
              labelDirection: TextDirection.ltr,
              value: member ? (isAr ? 'مفعّل' : 'Active') : null,
              sub: member
                  ? (state.plusIsTrial && until != null
                      ? (isAr ? 'الأسبوع المجاني · لحد ${state.iso('${until.day}/${until.month}')}' : 'Free week · until ${until.day}/${until.month}')
                      : (isAr ? 'شكراً إنك معانا' : 'Thanks for supporting Qamar'))
                  : state.trialWaiting
                      // "Not now" at the reveal leaves the free week here.
                      ? TrialWords.waitingInMe(AppState.trialOfferDays, ar: isAr, iso: state.iso)
                      : (isAr ? 'خطة بكرة، وصور وأسئلة أكتر' : 'Tomorrow’s plan, more photos and questions'),
              onTap: state.openSubscription,
            ),
            _Row(
              key: YouScreen.inviteRowKey,
              icon: QIcons.gift,
              label: isAr ? 'ادعي صحابك' : 'Invite friends',
              value: member ? (isAr ? 'باقي ${state.iso('${state.invitationsLeft}')} من ${state.iso('${state.invitations.limit}')}' : '${state.invitationsLeft} of ${state.invitations.limit} left') : null,
              sub: member ? null : (isAr ? 'لأعضاء قمر+' : 'For Qamar+ members'),
              onTap: () => _InvitationsSheet.open(context),
            ),
          ],
          footer: state.quotaSummary.isEmpty ? null : state.quotaSummary,
        ),
        const SizedBox(height: QSpace.lg),

        // The food: what Qamar plans around. What to avoid changes here, with
        // the consultation's own question, so a new allergy reaches every
        // plan; the target and the memory are read-outs, drawn without a
        // chevron, so nothing pretends to be a control.
        _Group(
          header: isAr ? 'الأكل' : 'Food',
          cardKey: YouScreen.readOutKey,
          rows: [
            _Row(
              icon: QIcons.flame,
              label: isAr ? 'هدفك اليومي' : 'Daily target',
              // On general guidance Qamar sets no target (Today shows none).
              value: state.generalGuidance ? (isAr ? 'مفيش هدف' : 'No target') : (isAr ? '${state.iso('${tg.kcal}')} سعر' : '${tg.kcal} kcal'),
            ),
            _Row(
              key: YouScreen.avoidEntryKey,
              icon: QIcons.shield,
              label: AvoidEditor.title(isAr: isAr),
              // The name whole, the value in what it leaves, on one line: a
              // long list of things to avoid ends on an ellipsis.
              value: YouScreen.avoidLine(state.profile.prefs, isAr: isAr),
              onTap: () => AvoidEditor.show(context, state),
            ),
            _Row(
              icon: QIcons.moon,
              label: isAr ? 'قمر فاكر' : 'Qamar remembers',
              value: remembered == 0 ? (isAr ? 'لسه ولا حاجة' : 'Nothing yet') : YouScreen.itemsLine(remembered, isAr: isAr, iso: state.iso),
            ),
            // In the season, Ramadan: fasting days, suhoor and iftar.
            if (state.seasonVisible)
              _Row(key: YouScreen.ramadanRowKey, icon: QIcons.moonFull, label: isAr ? 'رمضان' : 'Ramadan', onTap: () => state.go(AppScreen.ramadan)),
          ],
          footer: state.avoidNotice,
        ),
        const SizedBox(height: QSpace.lg),

        // Su Points: the one way to the wallet on Me, and under it, in the
        // same card, what "Points and streaks" hides (O4). Off hides
        // everything on screen that keeps score, and only hides it.
        _Group(
          cardKey: YouScreen.walletCardKey,
          rows: [
            _Row(
              key: YouScreen.walletRowKey,
              leading: const SuCoinIcon(size: 20),
              label: t.walletTitle,
              value: state.formatSu(state.suAvailable),
              semanticsLabel: '${t.walletTitle}, ${isAr ? '${state.iso(state.formatSu(state.suAvailable))} متاح' : '${state.formatSu(state.suAvailable)} available'}',
              onTap: state.openWallet,
            ),
            _SwitchRow(
              key: YouScreen.scoreRowKey,
              switchKey: YouScreen.scoreSwitchKey,
              icon: QIcons.star,
              label: isAr ? 'النقاط والسلسلة' : 'Points and streaks',
              value: state.showScore,
              onChanged: state.setShowScore,
            ),
          ],
          footer: isAr
              ? 'نقاط Su ومستواك والسلسلة ومهمة اليوم. لو قفلتها بتستخبى بس: النقاط بتتحسب زي ما هي، ورصيدك فاضل في المحفظة.'
              : 'Su, your level, the streak and the day’s quest. Off only hides them: you still earn, and your balance stays in the wallet.',
        ),
        const SizedBox(height: QSpace.lg),

        _Group(
          header: isAr ? 'التطبيق' : 'App',
          rows: [
            // How many questions Qamar asks a day: a choice of three, on the
            // row itself, each named for what it sets.
            _Row(
              icon: QIcons.bell,
              label: isAr ? 'أسئلة قمر' : 'Qamar’s questions',
              sub: state.nudgesPerDay > 0 && state.nudgePromptDone && !state.nudgesAllowed
                  ? (isAr ? 'مقفولة من إعدادات الموبايل — افتحها من هناك.' : 'Off in the phone’s settings — turn them on there.')
                  : (isAr ? 'كام مرة في اليوم، في مواعيد أكلك' : 'How many a day, at your meal times'),
              below: Wrap(
                spacing: QSpace.sm,
                runSpacing: QSpace.sm,
                children: [
                  for (final n in const [0, 1, 2])
                    Semantics(
                      key: YouScreen.nudgeKey(n),
                      selected: state.nudgesPerDay == n,
                      child: QPillChip(
                        label: switch (n) {
                          0 => isAr ? 'مقفولة' : 'Off',
                          1 => isAr ? 'مرة' : 'Once',
                          _ => isAr ? 'مرتين' : 'Twice',
                        },
                        selected: state.nudgesPerDay == n,
                        onTap: () => state.setNudgesPerDay(n),
                      ),
                    ),
                ],
              ),
            ),
            _Row(icon: QIcons.language, label: isAr ? 'اللغة' : 'Language', control: QLangToggle(lang: state.lang, onChanged: state.setLang)),
            // Which digits Arabic draws: each choice shown in its own digits.
            if (isAr)
              _Row(
                label: 'الأرقام',
                control: Row(mainAxisSize: MainAxisSize.min, children: [
                  QPillChip(label: '١٢٣', selected: state.easternDigits, onTap: () => state.setEasternDigits(true)),
                  const SizedBox(width: QSpace.sm),
                  QPillChip(label: YouScreen.westernDigits, selected: !state.easternDigits, onTap: () => state.setEasternDigits(false)),
                ]),
              ),
            // The moon's gestures for good (the tutorial on Today can be put
            // away), and how to reach Qamar without opening the app.
            _Row(key: YouScreen.helpRowKey, icon: QIcons.gesture, label: isAr ? 'الحركات والاختصارات' : 'Gestures and shortcuts', onTap: () => _HelpSheet.open(context)),
          ],
        ),
        const SizedBox(height: QSpace.lg),

        // The professional programme, both sides of it (O12): a client's
        // code, and a nutritionist's own.
        _Group(
          header: isAr ? 'الأخصائي' : 'Nutritionist',
          rows: [
            _Row(
              key: YouScreen.proCodeRowKey,
              icon: QIcons.code,
              label: isAr ? 'كود الأخصائي' : 'Nutritionist’s code',
              value: state.proName,
              onTap: state.proName == null ? () => _ProCodeSheet.open(context) : null,
            ),
            _Row(key: YouScreen.programmeRowKey, icon: QIcons.card, label: isAr ? 'لو إنت أخصائي أو مدرّب' : 'For nutritionists and coaches', onTap: () => _ProgrammeSheet.open(context)),
          ],
          footer: state.proName != null
              ? (isAr
                  ? 'كود ${state.proName} على حسابك. السعر زي ما هو، وبياخد نصيبه لما تشترك.'
                  : '${state.proName}’s code is on your account. Your price is the same, and they get their share when you subscribe.')
              : (isAr ? 'لو أخصائي أو مدرّب بعتك، ضيف الكود بتاعه. السعر مش بيتغير.' : 'If a nutritionist or coach sent you, add their code. Your price does not change.'),
        ),
        const SizedBox(height: QSpace.lg),

        // The consents given in the consultation, changeable here, and the
        // pages the stores require. Off means off: the analytics SDK stops
        // and nothing is sent again.
        _Group(
          header: isAr ? 'الخصوصية' : 'Privacy',
          rows: [
            _SwitchRow(
              icon: QIcons.trend,
              label: isAr ? 'تحسين الخدمة' : 'Service improvement',
              sub: isAr ? 'استخدام مجهول، من غير أكلك ولا جسمك ولا صورك' : 'Anonymous usage, never your food, body or photos',
              value: state.improve,
              onChanged: (v) => state.setImprove(v),
            ),
            // The professional programme's one condition: the client's yes.
            _SwitchRow(
              icon: QIcons.friends,
              label: isAr ? 'شارك أسبوعي' : 'Share my week',
              sub: isAr ? 'أيام التسجيل ومتوسطك بس، لأخصائيك وبس' : 'Days logged and your average, only to your nutritionist',
              value: state.adherenceShare,
              onChanged: (v) => state.setAdherenceShare(v),
            ),
            // Store requirements, and the second a legal obligation: pages
            // that really open, in the browser.
            _Row(icon: QIcons.locked, label: isAr ? 'سياسة الخصوصية' : 'Privacy policy', external: true, onTap: () => _openPage(QamarConfig.privacyUrl)),
            _Row(icon: QIcons.document, label: isAr ? 'الشروط' : 'Terms', external: true, onTap: () => _openPage(QamarConfig.termsUrl)),
            _Row(icon: QIcons.share, label: isAr ? 'صدّر أو امسح بياناتي' : 'Export or delete my data', external: true, onTap: () => _openPage(QamarConfig.deleteDataUrl)),
          ],
        ),
        const SizedBox(height: QSpace.xl),

        // The version and the consents agreed to, in the language's digits.
        Column(children: [
          Text('${t.brand} ${state.iso(QamarConfig.buildLabel)}', style: QText.number(size: 13, color: QColors.inkTertiary)),
          Text(isAr ? 'الموافقات: الإصدار ${state.digits(QamarConfig.consentVersion)}' : 'Consents: version ${QamarConfig.consentVersion}', style: QText.body(size: 13, color: QColors.inkTertiary)),
        ]),
      ],
    );
  }
}

/// A public page, in the browser, where the address can be seen.
Future<void> _openPage(String url) async {
  final uri = Uri.parse(url);
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    await launchUrl(uri);
  }
}

/// One group (the kit's): its name over it when it needs one, its rows on
/// one card with no lines between them, and a line of small print under it.
class _Group extends StatelessWidget {
  final String? header;
  final List<Widget> rows;
  final String? footer;
  final Key? cardKey;
  const _Group({required this.rows, this.header, this.footer, this.cardKey});

  @override
  Widget build(BuildContext context) {
    final isAr = Directionality.of(context) == TextDirection.rtl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(QSpace.xs, QSpace.sm, QSpace.lg, QSpace.sm),
            child: Semantics(header: true, child: Text(QText.eyebrowText(header!, ar: isAr), style: QText.eyebrow(ar: isAr))),
          ),
        Container(
          key: cardKey,
          clipBehavior: Clip.antiAlias,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: QDecor.card(),
          child: Column(children: rows),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(QSpace.xs, QSpace.sm, QSpace.lg, 0),
            child: Text(footer!, style: QText.body(size: 13, height: 18, color: QColors.inkSecondary)),
          ),
      ],
    );
  }
}

/// A settings row, 56 points at least: a 20-point glyph, the name, and at the
/// end its value, a control, or a chevron when it goes somewhere (an arrow out
/// when that is a page in the browser). A row that does something takes the
/// whole row as its touch and answers on the press; a read-out is drawn the
/// same way, with no chevron and no touch, so it never looks like a control.
class _Row extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String label;
  final TextDirection? labelDirection;
  final String? sub;
  final String? value;
  final Widget? control;
  final Widget? below;
  final VoidCallback? onTap;
  final bool external;
  final String? semanticsLabel;

  const _Row({
    super.key,
    required this.label,
    this.icon,
    this.leading,
    this.labelDirection,
    this.sub,
    this.value,
    this.control,
    this.below,
    this.onTap,
    this.external = false,
    this.semanticsLabel,
  });

  /// Where the words start, from the card's edge.
  static const wordsInset = QSpace.xl + 22 + 14;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return _drawn(false);
    return QTapArea(
      onTap: onTap,
      link: external,
      label: semanticsLabel,
      builder: (context, pressed) => semanticsLabel == null ? _drawn(pressed) : ExcludeSemantics(child: _drawn(pressed)),
    );
  }

  Widget _drawn(bool pressed) {
    final lead = leading ?? (icon == null ? null : QIcon(icon!, size: 22, color: QColors.ink));
    final name = Text(label, textDirection: labelDirection, style: QText.body(size: 16, color: QColors.ink));
    final words = sub == null
        ? name
        : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            name,
            const SizedBox(height: 2),
            Text(sub!, style: QText.body(size: 13, height: 18, color: QColors.inkSecondary)),
          ]);
    final shown = value == null
        ? null
        : Text(value!, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end, style: QText.number(size: 15, weight: FontWeight.w400, color: QColors.inkSecondary));
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      color: pressed ? QColors.surfaceRaised : Colors.transparent,
      constraints: const BoxConstraints(minHeight: 56),
      alignment: AlignmentDirectional.centerStart,
      padding: const EdgeInsetsDirectional.fromSTEB(QSpace.xl, QSpace.sm, QSpace.lg, QSpace.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            SizedBox(width: 22, child: lead == null ? null : Center(child: lead)),
            const SizedBox(width: 14),
            if (shown != null && sub == null) ...[
              // The name whole, and the value in what it leaves; at a large
              // text size the name wraps before it can push the value off.
              ConstrainedBox(constraints: const BoxConstraints(maxWidth: 200), child: name),
              const SizedBox(width: QSpace.lg),
              Expanded(child: shown),
            ] else ...[
              Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: words)),
              if (shown != null) ...[const SizedBox(width: QSpace.md), shown],
            ],
            if (control != null) ...[const SizedBox(width: QSpace.md), control!],
            if (onTap != null) ...[
              const SizedBox(width: QSpace.sm),
              QIcon(external ? QIcons.external : QIcons.forward, size: 20, color: QColors.ink),
            ],
          ]),
          if (below != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: _Row.wordsInset - QSpace.lg, top: QSpace.sm, bottom: QSpace.xs),
              child: Align(alignment: AlignmentDirectional.centerStart, child: below),
            ),
        ],
      ),
    );
  }
}

/// A row with a switch on it: the whole row is the control, not only the
/// switch, and a screen reader hears the two as one.
class _SwitchRow extends StatelessWidget {
  final Key? switchKey;
  final IconData icon;
  final String label;
  final String? sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({super.key, this.switchKey, required this.icon, required this.label, this.sub, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: () {
            HapticFeedback.selectionClick();
            onChanged(!value);
          },
          child: _Row(icon: icon, label: label, sub: sub, control: Switch.adaptive(key: switchKey, value: value, onChanged: onChanged)),
        ),
      );
}

/// The person (the kit's profile card): the first letter of their name on
/// its lavender circle, the name, and where their progress is kept.
class _ProfileRow extends StatelessWidget {
  final AppState state;
  const _ProfileRow({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final name = state.profile.name.isNotEmpty ? state.profile.name : (isAr ? 'يا صاحبي' : 'friend');
    final initial = state.profile.name.trim().isEmpty ? '' : state.profile.name.trim().characters.first.toUpperCase();
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(QSpace.xl, QSpace.md, QSpace.lg, QSpace.md),
      child: Row(children: [
        ExcludeSemantics(
          child: Container(
            width: 54,
            height: 54,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: QColors.lavender),
            child: Center(
              child: initial.isEmpty
                  ? const QIcon(QIcons.me, size: 26, color: QColors.onPastel)
                  : Text(initial, style: QText.display(size: 24, ar: QText.arabic(initial), color: QColors.onPastel)),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: QText.body(size: 17, weight: FontWeight.w600, color: QColors.ink)),
            const SizedBox(height: 2),
            Text(state.accountEmail ?? state.t.guestAccount, style: QText.body(size: 13, color: QColors.inkSecondary)),
          ]),
        ),
      ]),
    );
  }
}

/// An eyebrow inside a sheet, over what it names.
class _Eyebrow extends StatelessWidget {
  final String text;
  const _Eyebrow(this.text);

  @override
  Widget build(BuildContext context) {
    final isAr = Directionality.of(context) == TextDirection.rtl;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: QSpace.sm),
      child: Text(QText.eyebrowText(text, ar: isAr), style: QText.eyebrow(ar: isAr)),
    );
  }
}

/// The moon's three gestures, for good, and the ways to reach Qamar without
/// opening the app.
class _HelpSheet extends StatelessWidget {
  const _HelpSheet();

  static Future<void> open(BuildContext context) => SheetPanel.open(context, (_) => const _HelpSheet());

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;
    final ways = <(String, String)>[
      isAr
          ? ('آيفون', 'الإعدادات ← تسهيلات الاستخدام ← لمس ← الضغط على الخلف، واختار «Ask Qamar» أو «Log a meal with Qamar».')
          : ('iPhone', 'Settings → Accessibility → Touch → Back Tap, then pick “Ask Qamar” or “Log a meal with Qamar”.'),
      isAr
          ? ('أندرويد', 'اضغط مطوّلاً على أيقونة قمر واختار اسأل أو سجّل وجبة. على Pixel: الإيماءات ← Quick Tap ← افتح قمر.')
          : ('Android', 'Long-press the Qamar icon and choose Ask or Log a meal. On a Pixel: Gestures → Quick Tap → open Qamar.'),
      isAr ? ('سيري', 'قول «Ask Qamar» أو «Log a meal with Qamar».') : ('Siri', 'Say “Ask Qamar” or “Log a meal with Qamar”.'),
    ];
    return SheetPanel(
      title: isAr ? 'الحركات والاختصارات' : 'Gestures and shortcuts',
      onClose: () => SheetPanel.close(context),
      children: [
        OrbGestureGuide(state: state, dismissible: false),
        const SizedBox(height: QSpace.xxl),
        _Eyebrow(isAr ? 'من غير ما تفتح التطبيق' : 'Without opening the app'),
        Container(
          decoration: QDecor.card(color: QColors.surfaceRaised, border: QColors.surfaceRaised),
          child: Column(children: [
            for (final (i, (where, how)) in ways.indexed) ...[
              if (i > 0) const Divider(height: 1, thickness: 1, indent: QSpace.lg, color: QColors.hairlineStrong),
              Padding(
                padding: const EdgeInsets.all(QSpace.lg),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(where, style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.ink)),
                  const SizedBox(height: 2),
                  Text(how, style: QText.body(size: 15, color: QColors.inkSecondary)),
                ]),
              ),
            ],
          ]),
        ),
        const SizedBox(height: QSpace.sm),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: QSpace.lg),
          child: Text(
            isAr
                ? 'تسجيل الوجبة من الاختصار ببلاش ومش بيتعد. سؤال قمر بيتعد من أسئلة اليوم.'
                : 'Logging a meal from a shortcut is free and never counted. Asking Qamar counts toward the day’s questions.',
            style: QText.body(size: 13, height: 18, color: QColors.inkSecondary),
          ),
        ),
      ],
    );
  }
}

/// A client's side of the professional programme: the code a nutritionist or
/// coach gave them (O12). It puts the professional on the account, so their
/// share reaches them at the first payment with no code typed at checkout,
/// and starts the free trial while the account's one trial is unused. The
/// length is the server's; this sheet never states a number the server can
/// change, and the answer says the days actually given.
class _ProCodeSheet extends StatefulWidget {
  const _ProCodeSheet();

  static const fieldKey = ValueKey('pro-code-field');
  static const useKey = ValueKey('pro-code-use');

  static Future<void> open(BuildContext context) => SheetPanel.open(context, (_) => const _ProCodeSheet());

  @override
  State<_ProCodeSheet> createState() => _ProCodeSheetState();
}

class _ProCodeSheetState extends State<_ProCodeSheet> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _use(AppState state) async {
    await state.enterProCode(_code.text);
    if (mounted && state.proName != null) _code.clear();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;
    final who = state.proName;
    return SheetPanel(
      title: isAr ? 'كود الأخصائي' : 'Nutritionist’s code',
      onClose: () => SheetPanel.close(context),
      primary: who != null
          ? QPrimaryButton(label: isAr ? 'تمام' : 'Done', onTap: () => SheetPanel.close(context))
          : QPrimaryButton(
              key: _ProCodeSheet.useKey,
              label: state.proBusy ? (isAr ? 'بتأكد من الكود…' : 'Checking the code…') : (isAr ? 'استخدم الكود' : 'Use the code'),
              onTap: state.proBusy ? null : () => _use(state),
            ),
      children: [
        if (who == null) ...[
          Text(
            isAr
                ? 'لو أخصائي تغذية أو مدرّب بعتك، اكتب الكود بتاعه. لو لسه ما خدتش التجربة المجانية، بتبدأ دلوقتي، وهو بياخد نصيبه لما تشترك. السعر مش بيتغير.'
                : 'If a nutritionist or coach sent you, enter their code. If you have not had your free trial yet, it starts now, and they get their share when you subscribe. Your price does not change.',
            style: QText.body(size: 15, color: QColors.inkSecondary),
          ),
          const SizedBox(height: QSpace.lg),
          SheetField(
            key: _ProCodeSheet.fieldKey,
            controller: _code,
            hint: 'QMR…',
            enabled: !state.proBusy,
            characters: true,
            action: TextInputAction.done,
            onSubmitted: (_) => _use(state),
          ),
        ] else
          Text(
            isAr ? 'كود $who على حسابك. السعر زي ما هو، وبياخد نصيبه لما تشترك.' : '$who’s code is on your account. Your price is the same, and they get their share when you subscribe.',
            style: QText.body(size: 17, color: QColors.ink),
          ),
        if (state.proNotice != null) ...[
          const SizedBox(height: QSpace.md),
          QStateLine(line: state.proNotice!, icon: who != null ? QIcons.good : QIcons.info),
        ],
      ],
    );
  }
}

/// The professional's side (O12): the code to give clients, what it has
/// earned, the payout, and each client who said yes, with their week as
/// numbers. No meals, no photos, no weight.
class _ProgrammeSheet extends StatefulWidget {
  const _ProgrammeSheet();

  static Future<void> open(BuildContext context) => SheetPanel.open(context, (_) => const _ProgrammeSheet());

  @override
  State<_ProgrammeSheet> createState() => _ProgrammeSheetState();
}

class _ProgrammeSheetState extends State<_ProgrammeSheet> {
  /// The code was just copied: the button says so for a moment.
  bool _copied = false;

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;
    final wallet = state.affiliateWallet;
    final code = wallet.code;
    final clients = state.proClients;
    return SheetPanel(
      title: isAr ? 'لو إنت أخصائي أو مدرّب' : 'For nutritionists and coaches',
      onClose: () => SheetPanel.close(context),
      primary: code != null
          ? QPrimaryButton(
              label: _copied ? (isAr ? 'اتنسخ' : 'Copied') : (isAr ? 'انسخ الكود' : 'Copy the code'),
              icon: _copied ? QIcons.check : QIcons.copy,
              onTap: () => _copy(code),
            )
          // One sheet at a time: this one goes, and the account's opens.
          : QPrimaryButton(
              label: state.t.saveProgress,
              onTap: () {
                SheetPanel.close(context);
                state.openLinkAccount();
              },
            ),
      children: [
        Text(
          (isAr
                  ? 'اديلي الكود بتاعك لعميلك. يشترك بـ ٥٠٠ ج.م زي أي حد، وإنت يوصلك ١٠٠ ج.م كل شهر لمدة سنة. كاش بالجنيه، مش نقاط Su.'
                  : 'Give your code to a client. They subscribe at EGP 500 like anyone else, and you earn EGP 100 a month for a year. EGP cash, not Su Points.') +
              // The trial rides only on a code the operator has confirmed
              // (0069), and its length is the server's.
              (wallet.clientTrialDays <= 0 ? '' : TrialWords.clientDays(wallet.clientTrialDays, confirmed: wallet.professional, ar: isAr, iso: state.iso)),
          style: QText.body(size: 15, color: QColors.inkSecondary),
        ),
        const SizedBox(height: QSpace.xl),
        Container(
          padding: const EdgeInsets.all(QSpace.lg),
          decoration: QDecor.card(color: QColors.surfaceRaised, border: QColors.surfaceRaised),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Eyebrow(isAr ? 'الكود بتاعك' : 'Your code'),
            // The code is set as a code; with none yet, the way to one is an
            // instruction, not a title-sized line pretending to be one.
            code != null
                // A code reads left to right, and sits at the start like its label.
                ? Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(code, key: YouScreen.proCodeKey, textDirection: TextDirection.ltr, style: QText.number(size: 17, weight: FontWeight.w600)),
                  )
                : Text(isAr ? 'اربط حسابك عشان يطلعلك كود.' : 'Link an account to get a code.', key: YouScreen.proCodeKey, style: QText.body(size: 15, color: QColors.inkTertiary)),
            const SizedBox(height: QSpace.lg),
            const Divider(height: 1, thickness: 1, color: QColors.hairlineStrong),
            const SizedBox(height: QSpace.lg),
            _Eyebrow(isAr ? 'العمولة' : 'Your earnings'),
            Row(children: [
              Expanded(
                child: Text(
                  isAr
                      ? '${formatEgp(wallet.balancePounds, ar: true, eastern: state.easternDigits)} متاح، ${formatEgp(wallet.lifetimeEarnedCents ~/ 100, ar: true, eastern: state.easternDigits)} مكتسب'
                      : '${formatEgp(wallet.balancePounds, ar: false)} available · ${formatEgp(wallet.lifetimeEarnedCents ~/ 100, ar: false)} earned',
                  style: QText.number(size: 15, color: QColors.ink),
                ),
              ),
              const SizedBox(width: QSpace.md),
              // Below the smallest payout there is nothing to send: the
              // button says so by being off (O11).
              QOutlineButton(
                label: isAr ? 'حوّل العمولة' : 'Redeem EGP',
                height: 36,
                onTap: wallet.canRedeem ? state.requestAffiliatePayout : null,
              ),
            ]),
          ]),
        ),
        if (state.affiliateNotice != null) ...[
          const SizedBox(height: QSpace.md),
          QStateLine(line: state.affiliateNotice!, icon: QIcons.info),
        ],
        if (clients.isNotEmpty) ...[
          const SizedBox(height: QSpace.xxl),
          _Eyebrow(isAr ? 'عملاؤك، الأسبوع ده' : 'Your clients, this week'),
          Container(
            decoration: QDecor.card(color: QColors.surfaceRaised, border: QColors.surfaceRaised),
            child: Column(children: [
              for (final (i, c) in clients.indexed) ...[
                if (i > 0) const Divider(height: 1, thickness: 1, indent: QSpace.lg, color: QColors.hairlineStrong),
                Padding(
                  padding: const EdgeInsets.all(QSpace.lg),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c.name, style: QText.body(size: 17, color: QColors.ink)),
                        const SizedBox(height: 2),
                        Text(
                          c.daysLogged == 0
                              ? (isAr ? 'مفيش تسجيل الأسبوع ده' : 'Nothing logged this week')
                              : c.targetKcal == null
                                  ? (isAr ? 'متوسط ${state.iso('${c.avgKcal}')} سعر في اليوم' : 'avg ${c.avgKcal} kcal a day')
                                  : (isAr
                                      ? 'متوسط ${state.iso('${c.avgKcal}')} من ${state.iso('${c.targetKcal}')} سعر، ${TrialWords.nearTarget(c.onTargetDays, ar: true, iso: state.iso)}'
                                      : 'avg ${c.avgKcal} of ${c.targetKcal} kcal · ${TrialWords.nearTarget(c.onTargetDays, ar: false, iso: state.iso)}'),
                          style: QText.body(size: 13, height: 18, color: QColors.inkTertiary),
                        ),
                      ]),
                    ),
                    const SizedBox(width: QSpace.md),
                    Text(isAr ? '${state.iso('${c.daysLogged}')}/${state.iso('7')}' : '${c.daysLogged}/7', style: QText.number(size: 17, weight: FontWeight.w600)),
                  ]),
                ),
              ],
            ]),
          ),
          const SizedBox(height: QSpace.sm),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: QSpace.lg),
            child: Text(
              isAr ? 'اللي وافقوا على المشاركة بس. أيام التسجيل من ٧، وكام يوم منهم في حدود الهدف.' : 'Only those who said yes to sharing. Days logged out of 7, and how many landed near the target.',
              style: QText.body(size: 13, height: 18, color: QColors.inkTertiary),
            ),
          ),
        ],
      ],
    );
  }
}

/// The referral loop: three named invitations a quarter, numbered, each
/// carrying the friend's name. Members send; everyone else is told where
/// invitations come from.
class _InvitationsSheet extends StatefulWidget {
  const _InvitationsSheet();

  static Future<void> open(BuildContext context) => SheetPanel.open(context, (_) => const _InvitationsSheet());

  @override
  State<_InvitationsSheet> createState() => _InvitationsSheetState();
}

class _InvitationsSheetState extends State<_InvitationsSheet> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _invite(AppState state) async {
    await state.issueInvitation(_name.text);
    if (mounted && state.invitationNotice == null) _name.clear();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;
    final book = state.invitations;
    final member = state.plusActive;
    final canSend = member && state.invitationsLeft > 0 && state.isBacked;

    String statusOf(Invitation i) => switch (i.status) {
          InvitationStatus.sent => isAr ? 'مبعوتة' : 'Sent',
          InvitationStatus.joined => isAr ? 'انضم' : 'Joined',
          InvitationStatus.subscribed => isAr ? 'اشترك' : 'Subscribed',
        };

    return SheetPanel(
      title: isAr ? 'ادعي صحابك' : 'Invite friends',
      onClose: () => SheetPanel.close(context),
      primary: !member
          // One sheet at a time: this one goes, and the paywall opens.
          ? QPrimaryButton(
              label: isAr ? 'شوف قمر+' : 'See Qamar+',
              onTap: () {
                SheetPanel.close(context);
                state.openSubscription();
              },
            )
          : canSend
              ? QPrimaryButton(
                  label: state.invitationBusy ? (isAr ? 'بعمل الدعوة…' : 'Making the invitation…') : (isAr ? 'ادعي' : 'Invite'),
                  onTap: state.invitationBusy ? null : () => _invite(state),
                )
              : null,
      children: [
        Text(
          isAr
              ? '${state.iso('${book.limit}')} دعوات بالاسم كل تلات شهور. صاحبك بياخد أسبوعين قمر+ ببلاش واسمك بيظهرله من أول لحظة. لما يدفع أول شهر: إنت تاخد ${state.suAmount(SuEconomy.invitationSender)} وهو ${state.suAmount(SuEconomy.invitationFriend)}.'
              : '${book.limit} named invitations a quarter. Your friend gets two weeks of Qamar+ free and sees your name from the first moment. When they pay their first month: ${state.suAmount(SuEconomy.invitationSender)} for you, ${state.suAmount(SuEconomy.invitationFriend)} for them.',
          style: QText.body(size: 15, color: QColors.inkSecondary),
        ),
        if (!member) ...[
          const SizedBox(height: QSpace.lg),
          QStateLine(line: isAr ? 'الدعوات لأعضاء قمر+.' : 'Invitations are for Qamar+ members.', icon: QIcons.locked),
        ] else ...[
          const SizedBox(height: QSpace.lg),
          Text(
            isAr ? 'باقي ${state.iso('${state.invitationsLeft}')} من ${state.iso('${book.limit}')} الربع ده' : '${state.invitationsLeft} of ${book.limit} left this quarter',
            style: QText.number(size: 15, weight: FontWeight.w600, color: QColors.ink, ar: isAr),
          ),
          if (book.invitations.isNotEmpty) ...[
            const SizedBox(height: QSpace.md),
            Container(
              decoration: QDecor.card(color: QColors.surfaceRaised, border: QColors.surfaceRaised),
              child: Column(children: [
                for (final (i, inv) in book.invitations.indexed) ...[
                  if (i > 0) const Divider(height: 1, thickness: 1, indent: QSpace.lg, color: QColors.hairlineStrong),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(QSpace.lg, QSpace.xs, QSpace.xs, QSpace.xs),
                    child: SizedBox(
                      height: QLayout.minTap,
                      child: Row(children: [
                        Text(state.iso('${inv.number}'), style: QText.number(size: 15, weight: FontWeight.w600, color: QColors.inkSecondary)),
                        const SizedBox(width: QSpace.md),
                        Expanded(child: Text(inv.name, overflow: TextOverflow.ellipsis, style: QText.body(size: 17, color: QColors.ink))),
                        Text(statusOf(inv), style: QText.body(size: 13, color: inv.status == InvitationStatus.sent ? QColors.inkTertiary : QColors.ink)),
                        if (inv.status == InvitationStatus.sent)
                          QRoundIconButton(icon: QIcons.share, size: 32, raised: true, label: isAr ? 'ابعتها تاني' : 'Share again', onTap: () => state.shareInvitation(inv))
                        else
                          const SizedBox(width: QSpace.md),
                      ]),
                    ),
                  ),
                ],
              ]),
            ),
          ],
          if (canSend) ...[
            const SizedBox(height: QSpace.lg),
            TextField(
              controller: _name,
              enabled: !state.invitationBusy,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _invite(state),
              style: QText.body(size: 17, color: QColors.ink),
              // The kit's field (the theme's): the ground in a grey edge.
              decoration: InputDecoration(
                hintText: isAr ? 'اسم صاحبك' : 'Your friend’s name',
                hintStyle: QText.body(size: 17, color: QColors.inkTertiary),
              ),
            ),
          ],
          if (!state.isBacked) ...[
            const SizedBox(height: QSpace.lg),
            QStateLine(line: isAr ? 'اربط حسابك عشان تبعت دعوات.' : 'Link your account to send invitations.', icon: QIcons.account),
          ],
        ],
        if (state.invitationNotice != null) ...[
          const SizedBox(height: QSpace.md),
          QStateLine(line: state.invitationNotice!, icon: QIcons.info),
        ],
      ],
    );
  }
}
