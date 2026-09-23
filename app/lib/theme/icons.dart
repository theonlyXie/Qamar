import 'package:flutter/cupertino.dart';

/// Every glyph the app draws, by what it means (the mono-glass skill: one
/// icon family). All of them are Cupertino icons — the open drawing of Apple's
/// SF Symbols that ships with Flutter — at one weight, so a page never mixes
/// a filled Material glyph with an outlined one again. Filled forms are used
/// only for a selected or "on" state, the way SF Symbols uses them.
///
/// No `Icons.` (Material) glyph is drawn anywhere (icons_test.dart), and a
/// screen names its glyph here rather than reaching into the family, so the
/// family can be changed in one place.
abstract final class QIcons {
  static const _font = CupertinoIcons.iconFont;
  static const _package = CupertinoIcons.iconFontPackage;

  // Navigation. Back and forward point the way the reading goes: they mirror
  // in Arabic, where back points right.
  static const back = IconData(0xf3cf, fontFamily: _font, fontPackage: _package, matchTextDirection: true);
  static const forward = IconData(0xf3d1, fontFamily: _font, fontPackage: _package, matchTextDirection: true);
  static const close = CupertinoIcons.xmark;
  static const down = CupertinoIcons.chevron_down;
  static const more = CupertinoIcons.ellipsis;
  static const external = CupertinoIcons.arrow_up_right;

  // The conversation.
  static const send = CupertinoIcons.arrow_up;
  static const mic = CupertinoIcons.mic;
  static const micOff = CupertinoIcons.mic_slash;
  static const voice = CupertinoIcons.waveform;
  static const stop = CupertinoIcons.stop_fill;
  static const attach = CupertinoIcons.plus;
  static const camera = CupertinoIcons.camera;
  static const photo = CupertinoIcons.photo;
  static const keyboard = CupertinoIcons.keyboard;
  static const copy = CupertinoIcons.doc_on_doc;

  // Actions.
  static const add = CupertinoIcons.plus;
  static const remove = CupertinoIcons.minus;
  static const check = CupertinoIcons.checkmark;
  static const done = CupertinoIcons.checkmark_circle_fill;
  static const edit = CupertinoIcons.pencil;
  static const repeat = CupertinoIcons.arrow_counterclockwise;
  static const share = CupertinoIcons.square_arrow_up;
  static const swap = CupertinoIcons.arrow_2_circlepath;
  static const scan = CupertinoIcons.viewfinder;

  // The tree and the day.
  static const log = CupertinoIcons.square_pencil;
  static const plan = CupertinoIcons.square_list;
  static const water = CupertinoIcons.drop;
  static const waterFull = CupertinoIcons.drop_fill;
  static const review = CupertinoIcons.chart_bar;
  static const me = CupertinoIcons.person;
  static const moon = CupertinoIcons.moon;
  static const moonFull = CupertinoIcons.moon_fill;
  static const flame = CupertinoIcons.flame;
  static const glass = CupertinoIcons.drop;
  static const bottle = CupertinoIcons.drop_fill;
  static const tea = CupertinoIcons.flame;
  static const shop = CupertinoIcons.cart;

  // Movement.
  static const walk = CupertinoIcons.person;
  static const run = CupertinoIcons.hare;
  static const football = CupertinoIcons.sportscourt;
  static const gym = CupertinoIcons.bolt;
  static const other = CupertinoIcons.ellipsis_circle;

  // States: a glyph says what a colour used to.
  static const info = CupertinoIcons.info_circle;
  static const warning = CupertinoIcons.exclamationmark_circle;
  static const error = CupertinoIcons.exclamationmark_triangle;
  static const offline = CupertinoIcons.wifi_slash;
  static const locked = CupertinoIcons.lock;
  static const limit = CupertinoIcons.hourglass;
  static const empty = CupertinoIcons.moon_stars;
  static const good = CupertinoIcons.checkmark_circle;
  static const gift = CupertinoIcons.gift;
  static const plus = CupertinoIcons.sparkles;
  static const safety = CupertinoIcons.heart;
  static const time = CupertinoIcons.clock;
  static const gesture = CupertinoIcons.hand_draw;
  static const trend = CupertinoIcons.graph_square;
}
