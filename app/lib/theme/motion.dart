/// Animation timings ported from the prototype's @keyframes (qbreath, qhalo,
/// qfloat, qorbit…). Kept centralized so the orb's "alive" feel stays
/// consistent everywhere it appears (welcome hero, nav orb, chat, tree).
class QMotion {
  QMotion._();

  static const breath = Duration(milliseconds: 4600);
  static const breathChat = Duration(milliseconds: 5500);
  static const breathTree = Duration(milliseconds: 4600);
  static const halo = Duration(milliseconds: 5200);
  static const haloWelcome = Duration(milliseconds: 7000);
  static const float = Duration(milliseconds: 11000);
  static const floatWelcomeOrb = Duration(milliseconds: 9000);
  static const floatChatPill = Duration(milliseconds: 11000);
  static const floatScanPill = Duration(milliseconds: 13000);
  static const orbit = Duration(milliseconds: 7000);
  static const orbit2 = Duration(milliseconds: 5400);
  static const orbit3 = Duration(milliseconds: 9500);
  static const ring = Duration(milliseconds: 2400);
  static const trail = Duration(milliseconds: 3600);
  static const branch = Duration(milliseconds: 3400);
  static const sway = Duration(milliseconds: 3600);
  static const nodeBob = Duration(milliseconds: 5400);
  static const pulse = Duration(milliseconds: 1000);
  static const twinkle = Duration(milliseconds: 2400);

  static const fadeIn = Duration(milliseconds: 240);
  static const riseIn = Duration(milliseconds: 340);
  static const growIn = Duration(milliseconds: 280);

  static const typingDelay = Duration(milliseconds: 600);
  static const qamarSayDelay = Duration(milliseconds: 550);
  static const answerDelay = Duration(milliseconds: 260);
  static const targetDelay = Duration(milliseconds: 900);
  static const chatThinkDelay = Duration(milliseconds: 1100);
  static const listenDelay = Duration(milliseconds: 1500);
  static const scanReadDelay = Duration(milliseconds: 1700);
  static const analyzeDelay = Duration(milliseconds: 1900);
}
