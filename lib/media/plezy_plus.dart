/// Plezy+ extensions shared by the server backends.
library;

/// [MediaItem.raw] key of the crew (director, writer, producer): a list of
/// maps with `id`, `tag` (name), `thumb` (photo) and `job` (`director`,
/// `writer`, `producer`). Filled by the Plex and Jellyfin/Emby mappers.
const String mediaCrewRawKey = 'plezyCrew';

/// A client whose person filmography ([MediaServerClient.fetchPersonMediaPage])
/// lists the acting roles first and the crew roles after them.
abstract interface class PersonRoleSplitClient {
  /// Number of acting roles at the start of the list for [personId], or null
  /// when the list is not split (not loaded yet, or the split failed).
  int? personCastCount(String personId);
}
