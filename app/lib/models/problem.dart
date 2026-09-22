/// Something that did not work, said so the person can act on it (O10).
///
/// Every problem names what happened in one line, why when it is known, and
/// the next step from where the person is — never a raw exception, and never
/// a dead end. `QStateCard` (widgets/common.dart) renders one on a screen;
/// the conversation renders one as Qamar's line with its actions under it.
class Problem {
  /// What happened, in one line. Always visible.
  final String what;

  /// Why, when it is known.
  final String? why;

  /// The next step from here.
  final ProblemAction action;

  /// Another way on, when there is one — usually the way that keeps what
  /// the person was trying to do ("Type it instead").
  final ProblemAction? secondary;

  final ProblemKind kind;

  const Problem({required this.what, this.why, required this.action, this.secondary, this.kind = ProblemKind.error});
}

/// A button's words and what it does.
class ProblemAction {
  final String label;
  final void Function() onTap;
  const ProblemAction(this.label, this.onTap);
}

/// What sort of problem it is. Seat 6 gives each its glyph; the words are
/// the same component either way.
enum ProblemKind {
  /// Nothing here yet.
  empty,

  /// Something failed on our side.
  error,

  /// No connection, or one too slow to answer.
  offline,

  /// The phone has not allowed something the step needs, like the camera.
  permission,

  /// A daily allowance used up — the questions, the photos, the plan's
  /// rewrites. Nothing broke; it comes back tomorrow.
  limit,
}
