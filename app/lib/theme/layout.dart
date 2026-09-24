/// Shared layout constants that more than one screen has to agree on.
abstract final class QLayout {
  /// The tab bar's pill (the kit's floating bar): its height, and the gap
  /// under it to the bottom of the safe area.
  static const double tabBar = 66;
  static const double tabBarGap = 12;

  /// Height of the band at the bottom of a tab page that the tab bar floats
  /// in (O1): the bar and the gap under it. The tab pages pad their scroll
  /// views by this much, so nothing the person needs ever sits under it.
  static const double tabBand = tabBar + tabBarGap;

  /// Where a tab page's list ends: the band, and a gap above it, so the last
  /// thing on the page comes to rest above the bar. Content that is still
  /// scrolling passes under the bar's soft fade.
  static const double pageBottom = tabBand + 24;

  /// Where a page starts under the status bar: close, as a large title sits
  /// under a phone's own bar (O15).
  static const double pageTop = 16;

  /// The smallest touch any control takes, each way (O11). 48 rather than
  /// Apple's 44: most phones in Egypt run Android, whose guideline is 48dp,
  /// and 48 clears 44 as well.
  static const double minTap = 48;
}
