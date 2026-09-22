enum ObKind { q, u, target, save, dish, trialOffer }

class ObMessage {
  final ObKind kind;
  final String ar;
  final String en;
  const ObMessage.q({required this.ar, required this.en}) : kind = ObKind.q;
  const ObMessage.u({required this.ar, required this.en}) : kind = ObKind.u;
  const ObMessage.target()
      : kind = ObKind.target,
        ar = '',
        en = '';
  const ObMessage.save()
      : kind = ObKind.save,
        ar = '',
        en = '';

  /// The first moment of value: one real dish, costed against the new
  /// target (AppState.revealDish).
  const ObMessage.dish()
      : kind = ObKind.dish,
        ar = '',
        en = '';

  /// The free week, offered once after the plan reveal — never before it.
  const ObMessage.trialOffer()
      : kind = ObKind.trialOffer,
        ar = '',
        en = '';

  String text(bool isAr) => isAr ? ar : en;
}

enum ChatWho { q, u }

class ChatTurn {
  final ChatWho who;
  final String text;
  final String? sub;
  final String? action;
  /// The action button opens the wallet (buy another photo with Su) instead of Plan.
  final bool openWallet;

  /// The action button opens Qamar+ — the fourth question of the day.
  final bool openPlus;

  /// The photo the person sent with these words — a menu, a label, a plate.
  /// Shown in their bubble; never kept anywhere but this device.
  final String? photoPath;
  const ChatTurn({required this.who, required this.text, this.sub, this.action, this.openWallet = false, this.openPlus = false, this.photoPath});
}
