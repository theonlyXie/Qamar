import '../services/config.dart';

/// Where an invitation stands: sent, the friend joined, the friend pays.
enum InvitationStatus { sent, joined, subscribed }

/// One of a member's three named invitations a quarter (the referral loop).
///
/// Scarce and numbered on purpose: the loop runs on the sender's standing,
/// not on a discount. The code is what the friend types; the link is what
/// travels in the message.
class Invitation {
  final String id;
  final int number;
  final String quarter;
  final String name;
  final String code;
  final DateTime createdAt;
  final DateTime? redeemedAt;
  final DateTime? convertedAt;

  const Invitation({
    required this.id,
    required this.number,
    required this.quarter,
    required this.name,
    required this.code,
    required this.createdAt,
    this.redeemedAt,
    this.convertedAt,
  });

  factory Invitation.fromJson(Map<String, dynamic> j) => Invitation(
        id: '${j['id']}',
        number: (j['number'] as num?)?.toInt() ?? 0,
        quarter: j['quarter'] as String? ?? '',
        name: j['name'] as String? ?? '',
        code: j['code'] as String? ?? '',
        createdAt: DateTime.tryParse('${j['created_at']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
        redeemedAt: j['redeemed_at'] == null ? null : DateTime.tryParse('${j['redeemed_at']}'),
        convertedAt: j['converted_at'] == null ? null : DateTime.tryParse('${j['converted_at']}'),
      );

  InvitationStatus get status => convertedAt != null
      ? InvitationStatus.subscribed
      : redeemedAt != null
          ? InvitationStatus.joined
          : InvitationStatus.sent;

  String get link => '${QamarConfig.site}/i/$code';

  /// The message the friend receives: their name, the sender's, what they
  /// get, what the sender gets if they pay, the code and the link. [sender]
  /// may be empty when the member never gave a name.
  ///
  /// The sender is paid in Su when the friend pays a first month, and the
  /// friend is told so in the invitation itself: a recommendation that earns
  /// the one making it says so, as the nutritionist's code already does on
  /// the paywall. [senderGets] and [friendGets] are the amounts, drawn the
  /// app's way (AppState.suAmount).
  String message({required bool ar, required String sender, required String senderGets, required String friendGets}) {
    final from = sender.trim();
    if (ar) {
      final who = from.isEmpty ? 'صاحبك' : from;
      return 'يا $name، $who بيعزمك على قمر — أخصائي التغذية اللي بيتكلم مصري. أسبوعين قمر+ ببلاش بالكود $code. '
          'ولو كمّلت ودفعت أول شهر، $who بياخد $senderGets وإنت بتاخد $friendGets.\n$link';
    }
    final who = from.isEmpty ? 'A friend' : from;
    final whoAgain = from.isEmpty ? 'your friend' : from;
    return '$name, $who invited you to Qamar — the nutritionist that speaks Egyptian. Two weeks of Qamar+, free, with the code $code. '
        'If you stay on and pay your first month, $whoAgain gets $senderGets and you get $friendGets.\n$link';
  }
}

/// A member's invitations: the quarter, the allotment, everything sent.
class InvitationBook {
  final String quarter;
  final int limit;
  final List<Invitation> invitations;

  const InvitationBook({required this.quarter, required this.limit, required this.invitations});

  static const empty = InvitationBook(quarter: '', limit: 3, invitations: []);

  factory InvitationBook.fromJson(Map<String, dynamic> j) => InvitationBook(
        quarter: j['quarter'] as String? ?? '',
        limit: (j['limit'] as num?)?.toInt() ?? 3,
        invitations: [
          for (final e in (j['invitations'] as List? ?? const [])) Invitation.fromJson(Map<String, dynamic>.from(e as Map)),
        ],
      );

  int get usedThisQuarter => invitations.where((i) => i.quarter == quarter).length;

  int get left => (limit - usedThisQuarter).clamp(0, limit);

  InvitationBook plus(Invitation i) => InvitationBook(quarter: quarter, limit: limit, invitations: [...invitations, i]);
}

/// What the friend is told the moment a code is accepted.
class InvitationRedemption {
  final String inviterName;
  final String inviteeName;
  final int trialDays;

  const InvitationRedemption({required this.inviterName, required this.inviteeName, required this.trialDays});

  factory InvitationRedemption.fromJson(Map<String, dynamic> j) => InvitationRedemption(
        inviterName: j['inviter_name'] as String? ?? '',
        inviteeName: j['invitee_name'] as String? ?? '',
        trialDays: (j['trial_days'] as num?)?.toInt() ?? 0,
      );
}

/// What redeeming a nutritionist's code returns (qamar_redeem_pro_code, 0069):
/// the professional's name, and the fortnight's days — 0 when the account's
/// one free trial was already used or it has paid, when the code still puts
/// the professional on the account for their share.
class ProCodeRedemption {
  final String professionalName;
  final int trialDays;

  const ProCodeRedemption({required this.professionalName, required this.trialDays});

  factory ProCodeRedemption.fromJson(Map<String, dynamic> j) => ProCodeRedemption(
        professionalName: j['professional_name'] as String? ?? '',
        trialDays: (j['trial_days'] as num?)?.toInt() ?? 0,
      );
}
