/// Plezy+ extensions shared by the server backends.
library;

/// [MediaItem.raw] key of the crew (director, writer, producer): a list of
/// maps with `id`, `tag` (name), `thumb` (photo) and `job` (`director`,
/// `writer`, `producer`). Filled by the Plex and Jellyfin/Emby mappers.
const String mediaCrewRawKey = 'plezyCrew';

/// A client that can refresh the metadata of a single item (film, show,
/// season, episode) from the server's agents/providers. Servers refuse it
/// for users without the right to manage the library.
abstract interface class ItemMetadataRefreshClient {
  /// Queue a metadata refresh of [itemId] (and, for a show or season, its
  /// children). The server works in the background; failures throw.
  Future<void> refreshItemMetadata(String itemId);
}

/// A client that can gather a show's crew from its episodes.
abstract interface class ShowCrewClient {
  /// Crew of a show, gathered from its episodes (a show itself carries
  /// none): the [mediaCrewRawKey] list format, most frequent people first,
  /// at most [limit] people.
  Future<List<Map<String, Object?>>> fetchShowCrew(String showId, {int limit = 20});
}

/// A client whose person filmography ([MediaServerClient.fetchPersonMediaPage])
/// lists the acting roles first and the crew roles after them.
abstract interface class PersonRoleSplitClient {
  /// Number of acting roles at the start of the list for [personId], or null
  /// when the list is not split (not loaded yet, or the split failed).
  int? personCastCount(String personId);
}

/// One crew credit of an episode: name, job (`director`, `writer`,
/// `producer`) and, where the server sends them, person id and photo.
typedef EpisodeCrewCredit = ({String name, String job, String? id, String? thumb});

/// A show's crew from the credits of its episodes (one list per episode), in
/// the [mediaCrewRawKey] format: each person once per job, the most frequent
/// people first (ties by name), at most [limit] people. People are told apart
/// by id, or by name where the server sends none.
List<Map<String, Object?>> showCrewFromEpisodes(Iterable<Iterable<EpisodeCrewCredit>> episodes, {int limit = 20}) {
  const jobOrder = ['director', 'writer', 'producer'];
  final counts = <String, int>{};
  final best = <String, EpisodeCrewCredit>{};
  final jobs = <String, Set<String>>{};
  for (final credits in episodes) {
    for (final credit in credits) {
      final name = credit.name.trim();
      if (name.isEmpty) continue;
      final key = credit.id ?? name;
      counts[key] = (counts[key] ?? 0) + 1;
      final known = best[key];
      if (known == null || (known.thumb == null && credit.thumb != null)) best[key] = credit;
      (jobs[key] ??= <String>{}).add(credit.job);
    }
  }
  final keys = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : best[a]!.name.trim().compareTo(best[b]!.name.trim());
    });
  if (keys.length > limit) keys.removeRange(limit, keys.length);
  return [
    for (final key in keys)
      for (final job in jobOrder)
        if (jobs[key]!.contains(job))
          {'id': best[key]!.id, 'tag': best[key]!.name.trim(), 'thumb': best[key]!.thumb, 'job': job},
  ];
}
