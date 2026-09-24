import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

/// Every glyph the app draws, by what it means (the qamar-design skill: one
/// icon family). All of them are Iconsax, the Nutri AI kit's family (vuesax):
/// linear at rest, and bold only for a chosen or "on" state — the tab the
/// person is on, a done mark — the way the kit fills its active tab.
///
/// No `Icons.` (Material) or Cupertino glyph is drawn anywhere (icons_test.dart),
/// and a screen names its glyph here rather than reaching into the family, so
/// the family can be changed in one place.
abstract final class QIcons {
  static const _linear = 'IconsaxPlusLinear';
  static const _pkg = 'iconsax_plus';

  // Navigation. Back and forward point the way the reading goes, so they
  // mirror in Arabic, where back points right (the family's arrow_left_1 and
  // arrow_right_3, the chevrons, with matchTextDirection).
  static const back = IconData(0xe930, fontFamily: _linear, fontPackage: _pkg, matchTextDirection: true);
  static const forward = IconData(0xe936, fontFamily: _linear, fontPackage: _pkg, matchTextDirection: true);

  /// Close: Iconsax draws no plain ×, so the mark is the family's "add"
  /// turned an eighth of a turn, which [QIcon] does. It is its own constant
  /// (the add glyph set to mirror, which a cross does not show), so it is
  /// never taken for [add]; icons_test.dart holds that every close is drawn
  /// through [QIcon].
  static const close = IconData(0xe907, fontFamily: _linear, fontPackage: _pkg, matchTextDirection: true);
  static const down = IconsaxPlusLinear.arrow_down;
  static const up = IconsaxPlusLinear.arrow_up_1;
  static const more = IconsaxPlusLinear.more;
  static const external = IconsaxPlusLinear.export_3;

  // The conversation.
  static const send = IconsaxPlusLinear.arrow_up;
  static const mic = IconsaxPlusLinear.microphone_2;
  static const micOff = IconsaxPlusLinear.microphone_slash_1;
  static const voice = IconsaxPlusLinear.voice_cricle;
  static const stop = IconsaxPlusBold.stop;
  static const attach = IconsaxPlusLinear.add;
  static const camera = IconsaxPlusLinear.camera;
  static const photo = IconsaxPlusLinear.gallery;
  static const keyboard = IconsaxPlusLinear.keyboard;
  static const copy = IconsaxPlusLinear.copy;
  static const ask = IconsaxPlusLinear.magic_star;

  // Actions.
  static const add = IconsaxPlusLinear.add;
  static const remove = IconsaxPlusLinear.minus;
  static const check = IconsaxPlusLinear.tick_circle;
  static const done = IconsaxPlusBold.tick_circle;
  static const edit = IconsaxPlusLinear.edit_2;
  static const repeat = IconsaxPlusLinear.repeat;
  static const share = IconsaxPlusLinear.export;
  static const swap = IconsaxPlusLinear.refresh_2;
  static const scan = IconsaxPlusLinear.scan;
  static const barcode = IconsaxPlusLinear.scan_barcode;

  // The torch, over the camera: bold while it is on.
  static const torch = IconsaxPlusLinear.flash_1;
  static const torchOn = IconsaxPlusBold.flash_1;

  // The tabs and the day. A tab's glyph is linear at rest and bold when it
  // is the page the person is on ([onFor]).
  static const today = IconsaxPlusLinear.home;
  static const log = IconsaxPlusLinear.note_2;
  static const plan = IconsaxPlusLinear.reserve;
  static const review = IconsaxPlusLinear.activity;
  static const me = IconsaxPlusLinear.profile;
  static const water = IconsaxPlusLinear.drop;
  static const waterFull = IconsaxPlusBold.drop;
  static const moon = IconsaxPlusLinear.moon;
  static const moonFull = IconsaxPlusBold.moon;
  static const flame = IconsaxPlusLinear.flash;
  static const glass = IconsaxPlusLinear.drop;
  static const bottle = IconsaxPlusLinear.milk;
  static const tea = IconsaxPlusLinear.coffee;
  static const shop = IconsaxPlusLinear.shopping_cart;

  /// The macros, on their cards: carbs a sheaf of grain in the kit, drawn
  /// here as the family's cake (bread and sweets); protein the egg-and-yolk
  /// shape the kit uses, the family's "record"; fat a drop.
  static const calories = IconsaxPlusLinear.flash;
  static const protein = IconsaxPlusLinear.record_circle;
  static const carbs = IconsaxPlusLinear.cake;
  static const fat = IconsaxPlusLinear.drop;

  // Movement.
  static const walk = IconsaxPlusLinear.routing;
  static const run = IconsaxPlusLinear.flash;
  static const football = IconsaxPlusLinear.cup;
  static const gym = IconsaxPlusLinear.weight_1;
  static const other = IconsaxPlusLinear.more_circle;

  // States: a glyph says what a colour used to.
  static const info = IconsaxPlusLinear.info_circle;
  static const warning = IconsaxPlusLinear.warning_2;
  static const error = IconsaxPlusLinear.danger;
  static const offline = IconsaxPlusLinear.cloud_cross;
  static const locked = IconsaxPlusLinear.lock;
  static const limit = IconsaxPlusLinear.timer_1;
  static const empty = IconsaxPlusLinear.moon;
  static const good = IconsaxPlusLinear.tick_circle;
  static const gift = IconsaxPlusLinear.gift;
  static const plus = IconsaxPlusLinear.crown;
  static const safety = IconsaxPlusLinear.heart;
  static const time = IconsaxPlusLinear.clock;
  static const gesture = IconsaxPlusLinear.finger_cricle;
  static const trend = IconsaxPlusLinear.trend_up;
  static const idea = IconsaxPlusLinear.lamp_on;
  static const shield = IconsaxPlusLinear.shield_tick;
  static const star = IconsaxPlusLinear.star;
  static const thumbsUp = IconsaxPlusLinear.like_1;
  static const thumbsDown = IconsaxPlusLinear.dislike;

  // Choosing: a round mark for one of several, the way a list picks one.
  static const chosen = IconsaxPlusBold.record_circle;
  static const unchosen = IconsaxPlusLinear.record;

  // The orb's gestures, as the gestures guide names them.
  static const tap = IconsaxPlusLinear.finger_cricle;
  static const move = IconsaxPlusLinear.arrow_2;

  // Things and places.
  static const calendar = IconsaxPlusLinear.calendar_1;
  static const basket = IconsaxPlusLinear.bag_2;
  static const gallery = IconsaxPlusLinear.gallery;
  static const settings = IconsaxPlusLinear.setting_2;
  static const bell = IconsaxPlusLinear.notification;
  static const bellOff = IconsaxPlusLinear.notification_bing;
  static const language = IconsaxPlusLinear.language_square;
  static const trash = IconsaxPlusLinear.trash;
  static const friends = IconsaxPlusLinear.profile_2user;
  static const account = IconsaxPlusLinear.profile_circle;
  static const link = IconsaxPlusLinear.link_2;
  static const mail = IconsaxPlusLinear.sms;
  static const document = IconsaxPlusLinear.document_text;
  static const card = IconsaxPlusLinear.card;
  static const code = IconsaxPlusLinear.scan_barcode;
  static const shown = IconsaxPlusLinear.eye;
  static const hidden = IconsaxPlusLinear.eye_slash;
  static const refresh = IconsaxPlusLinear.refresh_2;
  static const sunrise = IconsaxPlusLinear.sun_fog;
  static const sunset = IconsaxPlusLinear.sun;
  static const search = IconsaxPlusLinear.search_normal_1;
  static const unlocked = IconsaxPlusLinear.unlock;

  /// Leaving (sign out): the arrow points out of the box the way the
  /// reading goes, so it mirrors in Arabic.
  static const signOut = IconData(0xeadf, fontFamily: _linear, fontPackage: _pkg, matchTextDirection: true);

  /// The bold form of a tab's glyph, for the tab the person is on.
  static IconData onFor(IconData g) => switch (g) {
        IconsaxPlusLinear.home => IconsaxPlusBold.home,
        IconsaxPlusLinear.reserve => IconsaxPlusBold.reserve,
        IconsaxPlusLinear.activity => IconsaxPlusBold.activity,
        IconsaxPlusLinear.profile => IconsaxPlusBold.profile,
        IconsaxPlusLinear.moon => IconsaxPlusBold.moon,
        _ => g,
      };

  // Other people's marks, in their owners' own drawing and in one ink: the
  // sign-in buttons' Apple and Facebook. Neither is in Iconsax, and neither is
  // ours to redraw; like Google's G (QBrandMarks) they are the one exception
  // to the family, and they are named here and nowhere else.
  static const appleMark = Icons.apple;
  static const facebookMark = Icons.facebook;
}

/// An icon as the app draws it: the glyph, turned where the family draws the
/// mark on its side ([QIcons.close]). Every control that takes a glyph draws
/// it through here, so the close mark is never the add mark by mistake.
class QIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color? color;
  final String? semanticLabel;
  const QIcon(this.icon, {super.key, this.size = 24, this.color, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final glyph = Icon(icon, size: size, color: color, semanticLabel: semanticLabel);
    if (icon != QIcons.close) return glyph;
    // The add glyph's arms are two thirds of its box; turned, a fifth larger,
    // so the cross spans what the family's other marks do.
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.rotationZ(math.pi / 4)..scaleByDouble(1.2, 1.2, 1, 1),
      child: glyph,
    );
  }
}
