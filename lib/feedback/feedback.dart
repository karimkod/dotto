/// A single playtest feedback entry for a level.
class FeedbackEntry {
  const FeedbackEntry({
    required this.level,
    required this.status, // 'ok' | 'ko'
    required this.comment,
    required this.timestamp, // ISO-8601 UTC
  });

  final int level;
  final String status;
  final String comment;
  final String timestamp;

  Map<String, dynamic> toJson() => {
        'level': level,
        'status': status,
        'comment': comment,
        'timestamp': timestamp,
      };

  factory FeedbackEntry.fromJson(Map<String, dynamic> j) => FeedbackEntry(
        level: (j['level'] as num).toInt(),
        status: (j['status'] ?? '') as String,
        comment: (j['comment'] ?? '') as String,
        timestamp: (j['timestamp'] ?? '') as String,
      );
}
