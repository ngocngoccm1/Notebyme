class Note {
  const Note({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
    this.deleted = false,
    this.dirty = false,
    this.revision = 0,
  });
  final String id, title, body, updatedAt;
  final bool deleted, dirty;
  final int revision;

  factory Note.fromRow(Map<String, Object?> row) => Note(
    id: row['id'] as String,
    title: row['title'] as String,
    body: row['body'] as String,
    updatedAt: row['updated_at'] as String,
    deleted: row['deleted'] == 1 || row['deleted'] == true,
    dirty: row['dirty'] == 1 || row['dirty'] == true,
    revision: (row['revision'] as num?)?.toInt() ?? 0,
  );

  Map<String, Object?> toRemote() => {
    'id': id,
    'title': title,
    'body': body,
    'updated_at': updatedAt,
    'deleted': deleted,
  };
  Map<String, Object?> toLocal(String userId) => {
    ...toRemote(),
    'user_id': userId,
    'deleted': deleted ? 1 : 0,
    'dirty': dirty ? 1 : 0,
    'revision': revision,
  };
  Note edit({String? title, String? body, bool? deleted}) => Note(
    id: id,
    title: title ?? this.title,
    body: body ?? this.body,
    deleted: deleted ?? this.deleted,
    updatedAt: DateTime.now().toUtc().toIso8601String(),
    dirty: true,
    revision: revision + 1,
  );
}

class NoteSummary {
  const NoteSummary({
    required this.id,
    required this.title,
    required this.preview,
    required this.updatedAt,
    required this.dirty,
  });
  final String id, title, preview, updatedAt;
  final bool dirty;
  factory NoteSummary.fromRow(Map<String, Object?> row) => NoteSummary(
    id: row['id'] as String,
    title: row['title'] as String,
    preview: row['preview'] as String,
    updatedAt: row['updated_at'] as String,
    dirty: row['dirty'] == 1,
  );
}

class Session {
  const Session(this.userId, this.token);
  final String userId, token;
  Map<String, Object?> toJson() => {'userId': userId, 'token': token};
  factory Session.fromJson(Map<String, dynamic> value) =>
      Session(value['userId'] as String, value['token'] as String);
}
