/// A player as stored in the public `players` table. Cards are NOT here — a
/// player's hand lives in the private `player_hands` table.
class Player {
  final String id;
  final String roomId;
  final String userId;
  final String nickname;
  final int team;
  final int seatIndex;
  final int handCount;
  final bool connected;
  final DateTime? lastSeen;

  const Player({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.nickname,
    required this.team,
    required this.seatIndex,
    required this.handCount,
    required this.connected,
    required this.lastSeen,
  });

  /// Considered online if seen within the last 25s (heartbeat pings every ~8s).
  bool get isOnline {
    final seen = lastSeen;
    if (seen == null) return false;
    return DateTime.now().toUtc().difference(seen.toUtc()).inSeconds < 25;
  }

  factory Player.fromMap(Map<String, dynamic> m) => Player(
        id: m['id'] as String,
        roomId: m['room_id'] as String,
        userId: m['user_id'] as String,
        nickname: m['nickname'] as String,
        team: m['team'] as int,
        seatIndex: m['seat_index'] as int,
        handCount: (m['hand_count'] as int?) ?? 0,
        connected: (m['connected'] as bool?) ?? true,
        lastSeen: m['last_seen'] == null
            ? null
            : DateTime.tryParse(m['last_seen'] as String),
      );
}
