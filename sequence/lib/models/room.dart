/// A game room as stored in the `rooms` table (public columns).
class Room {
  final String id;
  final String code;
  final String hostId;
  final String status; // 'lobby' | 'playing' | 'finished'
  final int numTeams;
  final int sequencesToWin;
  final List<List<int?>> board; // 10x10 of team index | null
  final List<List<int>> locked; // [[r,c], ...] sequence chips
  final List<String> turnOrder; // player ids by seat
  final String? currentTurn; // player id whose turn it is
  final int? winnerTeam;
  final DateTime? lastMoveAt; // changes every move (used as a turn key)

  const Room({
    required this.id,
    required this.code,
    required this.hostId,
    required this.status,
    required this.numTeams,
    required this.sequencesToWin,
    required this.board,
    required this.locked,
    required this.turnOrder,
    required this.currentTurn,
    required this.winnerTeam,
    required this.lastMoveAt,
  });

  /// A value that changes each time the turn advances; used to fire per-turn UI.
  String get turnKey => '$currentTurn@${lastMoveAt?.microsecondsSinceEpoch}';

  bool get isLobby => status == 'lobby';
  bool get isPlaying => status == 'playing';
  bool get isFinished => status == 'finished';

  factory Room.fromMap(Map<String, dynamic> m) {
    final rawBoard = (m['board'] as List?) ?? const [];
    final board = rawBoard
        .map<List<int?>>((row) =>
            (row as List).map<int?>((v) => v == null ? null : v as int).toList())
        .toList();

    final rawLocked = (m['locked'] as List?) ?? const [];
    final locked = rawLocked
        .map<List<int>>((c) => (c as List).map<int>((v) => v as int).toList())
        .toList();

    final rawOrder = (m['turn_order'] as List?) ?? const [];

    return Room(
      id: m['id'] as String,
      code: m['code'] as String,
      hostId: m['host_id'] as String,
      status: m['status'] as String,
      numTeams: m['num_teams'] as int,
      sequencesToWin: m['sequences_to_win'] as int,
      board: board,
      locked: locked,
      turnOrder: rawOrder.map((e) => e as String).toList(),
      currentTurn: m['current_turn'] as String?,
      winnerTeam: m['winner_team'] as int?,
      lastMoveAt: m['last_move_at'] == null
          ? null
          : DateTime.tryParse(m['last_move_at'] as String),
    );
  }
}
