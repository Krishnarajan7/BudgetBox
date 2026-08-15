import '../api_client.dart';
import 'wire.dart';

/// The loose paper in the box. There is no delete: a note is archived, because
/// the one thing worse than clutter is losing something on purpose.
class NotesApi {
  const NotesApi(this._c);

  final BbxClient _c;

  Future<List<NoteOut>> list({bool includeArchived = false}) async => wireList(
    await _c.get('/v1/notes', {'include_archived': includeArchived}),
    NoteOut.fromJson,
  );

  Future<NoteOut> upsert(String id, NoteIn body) async => NoteOut.fromJson(
    wireObject(await _c.put('/v1/notes/$id', body.toJson())),
  );

  Future<NoteOut> patch(String id, NotePatch body) async => NoteOut.fromJson(
    wireObject(await _c.patch('/v1/notes/$id', body.toJson())),
  );
}

class NoteOut {
  const NoteOut({
    required this.id,
    required this.title,
    required this.body,
    required this.pinned,
    required this.remindAt,
    required this.completed,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String body;
  final bool pinned;
  final DateTime? remindAt;
  final bool completed;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory NoteOut.fromJson(Map<String, dynamic> json) => NoteOut(
    id: json.text('id'),
    title: json.text('title'),
    body: json.text('body'),
    pinned: json.flag('pinned'),
    remindAt: json.instantOrNull('remind_at'),
    completed: json.flag('completed'),
    archived: json.flag('archived'),
    createdAt: json.instant('created_at'),
    updatedAt: json.instant('updated_at'),
  );
}

/// An empty title and an empty body are both fine — a note can be one line
/// with no name.
class NoteIn {
  const NoteIn({
    this.title = '',
    this.body = '',
    this.pinned = false,
    this.remindAt,
    this.completed = false,
  });

  final String title;
  final String body;
  final bool pinned;
  final DateTime? remindAt;
  final bool completed;

  Map<String, dynamic> toJson() => {
    'title': title,
    'body': body,
    'pinned': pinned,
    'remind_at': remindAt?.toUtc().toIso8601String(),
    'completed': completed,
  };
}

/// Every column here is `NOT NULL`, so a null simply means "leave it alone".
class NotePatch {
  const NotePatch({
    this.title,
    this.body,
    this.pinned,
    this.remindAt,
    this.completed,
    this.archived,
  });

  final String? title;
  final String? body;
  final bool? pinned;
  final DateTime? remindAt;
  final bool? completed;
  final bool? archived;

  Map<String, dynamic> toJson() =>
      (WireBody()
            ..maybe('title', title)
            ..maybe('body', body)
            ..maybe('pinned', pinned)
            ..maybe('remind_at', remindAt?.toUtc().toIso8601String())
            ..maybe('completed', completed)
            ..maybe('archived', archived))
          .build();
}
