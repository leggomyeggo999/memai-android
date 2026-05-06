class MemNoteListItem {
  MemNoteListItem({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.collectionIds,
    this.snippet,
    this.content,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> collectionIds;
  final String? snippet;
  final String? content;
}

class MemNoteFull {
  MemNoteFull({
    required this.id,
    required this.title,
    required this.content,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    required this.collectionIds,
    this.trashedAt,
  });

  final String id;
  final String title;
  final String content;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> collectionIds;
  final DateTime? trashedAt;
}

class MemCollectionItem {
  MemCollectionItem({
    required this.id,
    required this.title,
    required this.description,
    required this.noteCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String? description;
  final int noteCount;
  final DateTime createdAt;
  final DateTime updatedAt;
}
