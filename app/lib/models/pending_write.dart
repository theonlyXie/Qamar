/// The offline logging queue.
///
/// A meal, a glass or a walk is logged on the phone the instant it is tapped;
/// the server's copy follows. When the write fails — a lift, a metro, a bad
/// signal on 3G — the entry is kept here, on the phone, and replayed when
/// the app comes back to the foreground, when the next write succeeds, or on
/// the next start. Only writes that stand alone are kept: their payload is
/// everything the repository needs, so a restart can replay them without the
/// objects that were on screen.
library;

import 'dart:convert';

enum PendingKind { meal, water, activity }

class PendingWrite {
  final PendingKind kind;
  final Map<String, dynamic> payload;
  final DateTime at;
  final int attempts;

  const PendingWrite({required this.kind, required this.payload, required this.at, this.attempts = 0});

  PendingWrite copyWith({int? attempts}) => PendingWrite(kind: kind, payload: payload, at: at, attempts: attempts ?? this.attempts);

  Map<String, dynamic> toJson() => {'kind': kind.name, 'payload': payload, 'at': at.toIso8601String(), 'attempts': attempts};

  static PendingWrite? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = PendingKind.values.asNameMap()[raw['kind']?.toString()];
    final payload = raw['payload'];
    final at = raw['at'] is String ? DateTime.tryParse(raw['at'] as String) : null;
    if (kind == null || payload is! Map || at == null) return null;
    return PendingWrite(
      kind: kind,
      payload: payload.cast<String, dynamic>(),
      at: at,
      attempts: raw['attempts'] is num ? (raw['attempts'] as num).toInt() : 0,
    );
  }

  /// The queue as it is kept in the phone's preferences.
  static String encode(List<PendingWrite> writes) => jsonEncode([for (final w in writes) w.toJson()]);

  static List<PendingWrite> decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list.map(PendingWrite.fromJson).whereType<PendingWrite>().toList();
    } catch (_) {
      return [];
    }
  }
}
