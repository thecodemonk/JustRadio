class NowPlaying {
  final String title;
  final String artist;
  final String rawMetadata;
  final DateTime timestamp;

  NowPlaying({
    required this.title,
    required this.artist,
    required this.rawMetadata,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory NowPlaying.fromIcyMetadata(String? metadata) {
    if (metadata == null || metadata.isEmpty) {
      return NowPlaying.empty();
    }

    String artist = '';
    String title = '';

    // Parse StreamTitle from ICY metadata
    final streamTitleMatch =
        RegExp(r"StreamTitle='([^']*)'").firstMatch(metadata);
    if (streamTitleMatch != null) {
      final streamTitle = streamTitleMatch.group(1) ?? '';

      // Common formats: "Artist - Title" or "Title - Artist" or just "Title"
      if (streamTitle.contains(' - ')) {
        final parts = streamTitle.split(' - ');
        artist = parts[0].trim();
        title = parts.sublist(1).join(' - ').trim();
      } else {
        title = streamTitle.trim();
      }
    }

    return NowPlaying(
      title: title,
      artist: artist,
      rawMetadata: metadata,
    );
  }

  factory NowPlaying.empty() {
    return NowPlaying(
      title: '',
      artist: '',
      rawMetadata: '',
    );
  }

  bool get isEmpty => title.isEmpty && artist.isEmpty;
  bool get isNotEmpty => !isEmpty;

  String get displayText {
    if (isEmpty) return '';
    if (artist.isEmpty) return title;
    if (title.isEmpty) return artist;
    return '$artist - $title';
  }

  @override
  String toString() => 'NowPlaying(artist: $artist, title: $title)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NowPlaying &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          artist == other.artist;

  @override
  int get hashCode => title.hashCode ^ artist.hashCode;
}
