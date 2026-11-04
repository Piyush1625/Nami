class Playlist {
  Playlist({
    required this.id,
    required this.name,
    List<int>? trackIds,
    DateTime? createdAt,
  })  : trackIds = trackIds ?? <int>[],
        createdAt = createdAt ?? DateTime.now();

  final String id;
  String name;
  final List<int> trackIds;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'trackIds': trackIds,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id'] as String,
        name: j['name'] as String,
        trackIds: (j['trackIds'] as List).map((e) => e as int).toList(),
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(j['createdAt'] as int),
      );
}

class HistoryEntry {
  const HistoryEntry({required this.trackId, required this.playedAt});

  final int trackId;
  final DateTime playedAt;

  Map<String, dynamic> toJson() =>
      {'t': trackId, 'at': playedAt.millisecondsSinceEpoch};

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        trackId: j['t'] as int,
        playedAt: DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
      );
}
