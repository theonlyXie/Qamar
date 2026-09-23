/// Shared layout constants that more than one screen has to agree on.
abstract final class QLayout {
  /// Height of the band at the bottom of the screen where the orb rests
  /// (O1). Screens that show the orb pad their scroll views by this much, so
  /// nothing the person needs ever sits under it.
  ///
  /// Seat 6 owns this value and builds the band itself (the stops, the snap
  /// and the edge fade); it may retune it now that the orb's Su pill is only a
  /// passing receipt.
  static const double orbBand = 72;

  /// Where an orb screen's list ends: the band, and a gap above it, so the
  /// last thing on the page comes to rest above the orb (O1). Content that
  /// is still scrolling passes under the band's soft fade.
  static const double pageBottom = orbBand + 24;

  /// Where a page starts under the status bar: close, as a large title sits
  /// under a phone's own bar. It was 56, which spent a band of empty sky
  /// above every page and pushed Today's slot below the fold (O15).
  static const double pageTop = 16;

  /// The smallest touch any control takes, each way (O11). 48 rather than
  /// Apple's 44: most phones in Egypt run Android, whose guideline is 48dp,
  /// and 48 clears 44 as well.
  static const double minTap = 48;
}
