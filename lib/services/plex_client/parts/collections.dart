part of '../../plex_client.dart';

/// Plex's online metadata provider, where Plex Web reads a person's
/// biography; Plex Media Server keeps only the name and photo.
const _discoverPeopleUrl = 'https://discover.provider.plex.tv/library/people/';

mixin _PlexCollectionMethods on _PlexClientInternals {
  String? get plexAccountToken;

  _LibraryContentResult _extractLibraryContentResult(
    MediaServerResponse response, {
    int? librarySectionID,
    // ignore: unused_element_parameter
    String? librarySectionTitle,
    int? start,
    int? requestedSize,
  });

  Future<_LibraryContentResult> _getLibraryCollectionsPage(
    String sectionId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    final queryParameters = _buildPaginationParams(start, size)..['includeGuids'] = 1;
    final response = await _getWithFailover(
      '/library/sections/$sectionId/collections',
      queryParameters: queryParameters,
      abort: abort,
    );
    return _extractLibraryContentResult(
      response,
      librarySectionID: _librarySectionIdFromString(sectionId),
      start: start,
      requestedSize: size,
    );
  }

  Future<_LibraryContentResult> _getCollectionItems(
    String collectionId, {
    int? start,
    int? size,
    AbortController? abort,
    String? librarySectionID,
    String? librarySectionTitle,
  }) => _fetchPaginatedList(
    '/library/collections/$collectionId/children',
    start: start,
    size: size,
    abort: abort,
    librarySectionID: _librarySectionIdFromString(librarySectionID),
    librarySectionTitle: librarySectionTitle,
  );

  Future<_LibraryContentResult> _getPersonMedia(String personId, {int? start, int? size, AbortController? abort}) =>
      _fetchPaginatedList('/library/people/$personId/media', start: start, size: size, abort: abort);

  @override
  Future<LibraryPage<MediaItem>> fetchCollectionsPage(
    String libraryId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    final result = await _getLibraryCollectionsPage(libraryId, start: start, size: size, abort: abort);
    return LibraryPage<MediaItem>(
      items: result.items.map(PlexMappers.mediaItem).toList(),
      totalCount: result.totalSize,
      offset: start ?? 0,
    );
  }

  /// PMS caps `X-Plex-Container-Size` at 120 on
  /// `/library/collections/{id}/children`. Some servers answer a larger page
  /// with HTTP 400; the rest log that they eventually will (#2468).
  static const int _collectionChildrenMaxPageSize = 120;

  /// Serves [size] items from [start], split into requests the server
  /// accepts. A null [size] reads to the end of the collection.
  @override
  Future<LibraryPage<MediaItem>> fetchCollectionPage(
    String collectionId, {
    int? start,
    int? size,
    AbortController? abort,
    String? libraryId,
    String? libraryTitle,
  }) async {
    final offset = start ?? 0;
    final items = <PlexMetadataDto>[];
    int totalSize;
    while (true) {
      final remaining = size == null ? _collectionChildrenMaxPageSize : size - items.length;
      final result = await _getCollectionItems(
        collectionId,
        start: offset + items.length,
        size: remaining.clamp(0, _collectionChildrenMaxPageSize),
        abort: abort,
        librarySectionID: libraryId,
        librarySectionTitle: libraryTitle,
      );
      items.addAll(result.items);
      totalSize = result.totalSize;
      if (result.items.isEmpty || offset + items.length >= totalSize) break;
      if (size != null && items.length >= size) break;
    }
    return LibraryPage<MediaItem>(
      items: items.map(PlexMappers.mediaItem).toList(),
      totalCount: totalSize,
      offset: offset,
    );
  }

  /// Ids per batched `/library/metadata/{ids}` request. Plex ids are short,
  /// so 100 keeps the URL well under proxy limits.
  static const int _membershipLookupChunkSize = 100;

  /// Page size for listing a library's collections during a membership lookup.
  static const int _membershipCollectionsPageSize = 200;

  /// `collectionMode` of a collection set to "Hide collection": it never
  /// shows in the library, so it never groups downloads either.
  static const String _collectionModeHidden = '0';

  /// `collectionSort` values. Release date (`0`) is the default when absent.
  static const String _collectionSortAlphabetical = '1';
  static const String _collectionSortCustom = '2';

  /// Membership comes from the items' `Collection` tags, whose `id` is the
  /// collection's `index`. Batched detail rows carry those ids where list
  /// rows carry only the tag text, which can differ from the collection's
  /// title in case. Only a custom-ordered collection needs its children read;
  /// release and alphabetical order follow from the members' own fields.
  @override
  Future<List<CollectionMembership>> fetchCollectionMemberships(Set<String> itemIds, {AbortController? abort}) async {
    final ids = itemIds.toList()..sort();
    final membersByTag = <int, List<Map<String, dynamic>>>{};
    final tagsByLibrary = <String, Set<int>>{};
    for (var start = 0; start < ids.length; start += _membershipLookupChunkSize) {
      final end = start + _membershipLookupChunkSize < ids.length ? start + _membershipLookupChunkSize : ids.length;
      final chunk = ids.sublist(start, end);
      final response = await _getWithFailover(
        '/library/metadata/${chunk.join(',')}',
        queryParameters: _buildPaginationParams(0, chunk.length),
        abort: abort,
      );
      final rows = _getMediaContainer(response)?['Metadata'];
      if (rows is! List) continue;
      for (final row in rows.whereType<Map<String, dynamic>>()) {
        final itemId = row['ratingKey']?.toString();
        final libraryId = row['librarySectionID']?.toString();
        final tags = row['Collection'];
        if (itemId == null || !itemIds.contains(itemId) || libraryId == null || tags is! List) continue;
        for (final tag in tags.whereType<Map<String, dynamic>>()) {
          final tagId = flexibleInt(tag['id']);
          if (tagId == null) continue;
          membersByTag.putIfAbsent(tagId, () => []).add(row);
          tagsByLibrary.putIfAbsent(libraryId, () => {}).add(tagId);
        }
      }
    }

    final memberships = <CollectionMembership>[];
    for (final MapEntry(key: libraryId, value: tagIds) in tagsByLibrary.entries) {
      for (final json in await _libraryCollectionsJson(libraryId, abort: abort)) {
        final tagId = flexibleInt(json['index']);
        if (tagId == null || !tagIds.contains(tagId)) continue;
        if (flexibleBool(json['smart']) || json['collectionMode']?.toString() == _collectionModeHidden) continue;
        final collection = PlexMappers.mediaItem(
          _createTaggedMetadataWithLibrary(json, librarySectionID: int.tryParse(libraryId)),
        );
        final memberIds = await _collectionOrderedMemberIds(
          collection.id,
          json['collectionSort']?.toString(),
          membersByTag[tagId]!,
          abort: abort,
        );
        memberships.add((collection: collection, memberIds: memberIds));
      }
    }
    return memberships;
  }

  /// Every raw collection row of [libraryId], smart and hidden ones included.
  Future<List<Map<String, dynamic>>> _libraryCollectionsJson(String libraryId, {AbortController? abort}) async {
    final collections = <Map<String, dynamic>>[];
    while (true) {
      final response = await _getWithFailover(
        '/library/sections/$libraryId/collections',
        queryParameters: _buildPaginationParams(collections.length, _membershipCollectionsPageSize),
        abort: abort,
      );
      final container = _getMediaContainer(response);
      final rows = container?['Metadata'];
      final page = rows is List ? rows.whereType<Map<String, dynamic>>().toList() : const <Map<String, dynamic>>[];
      collections.addAll(page);
      final total = flexibleInt(container?['totalSize']) ?? collections.length;
      if (page.isEmpty || collections.length >= total) return collections;
    }
  }

  /// The ids of [members] in the collection's [sort] order.
  Future<List<String>> _collectionOrderedMemberIds(
    String collectionId,
    String? sort,
    List<Map<String, dynamic>> members, {
    AbortController? abort,
  }) async {
    if (sort == _collectionSortCustom) {
      final memberIds = {for (final member in members) member['ratingKey'].toString()};
      final children = await drainPages(
        (start, size) => fetchCollectionPage(collectionId, start: start, size: size, abort: abort),
        pageSize: _collectionChildrenMaxPageSize,
        abort: abort,
      );
      return [
        for (final child in children)
          if (memberIds.remove(child.id)) child.id,
      ];
    }

    String titleKey(Map<String, dynamic> row) => (row['titleSort'] ?? row['title'] ?? '').toString().toLowerCase();
    final sorted = List.of(members)
      ..sort((a, b) {
        if (sort != _collectionSortAlphabetical) {
          // Release order; undated members after dated ones.
          final aDate = a['originallyAvailableAt']?.toString() ?? '${a['year'] ?? ''}';
          final bDate = b['originallyAvailableAt']?.toString() ?? '${b['year'] ?? ''}';
          if (aDate.isEmpty != bDate.isEmpty) return aDate.isEmpty ? 1 : -1;
          final byDate = aDate.compareTo(bDate);
          if (byDate != 0) return byDate;
        }
        return titleKey(a).compareTo(titleKey(b));
      });
    return [for (final member in sorted) member['ratingKey'].toString()];
  }

  @override
  Future<LibraryPage<MediaItem>> fetchPersonMediaPage(
    String personId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    // Plezy+: one filmography across all role tags of the person.
    List<PlexMetadataDto>? merged;
    if ((start ?? 0) == 0) _plezyPersonCastCount.remove(personId);
    try {
      merged = await _mergedPersonMedia(personId, refresh: (start ?? 0) == 0, abort: abort);
    } catch (e, st) {
      appLogger.w('Plezy+: merging person roles failed', error: e, stackTrace: st);
    }
    if (merged != null) {
      final offset = (start ?? 0).clamp(0, merged.length);
      final end = size == null ? merged.length : (offset + size).clamp(offset, merged.length);
      return LibraryPage<MediaItem>(
        items: merged.sublist(offset, end).map(PlexMappers.mediaItem).toList(),
        totalCount: merged.length,
        offset: offset,
      );
    }
    final result = await _getPersonMedia(personId, start: start, size: size, abort: abort);
    return LibraryPage<MediaItem>(
      items: result.items.map(PlexMappers.mediaItem).toList(),
      totalCount: result.totalSize,
      offset: start ?? 0,
    );
  }

  Future<List<PlexLibraryDto>> _getLibraries();

  /// Plezy+: merged media per person id, refreshed when the first page loads.
  final Map<String, Future<List<PlexMetadataDto>?>> _plezyPersonMedia = {};

  /// Plezy+: writer/producer listings per section, kept for 30 minutes.
  final Map<String, (DateTime, Future<List<Map<String, dynamic>>>)> _plezyRoleLists = {};

  Future<List<PlexMetadataDto>?> _mergedPersonMedia(String personId, {required bool refresh, AbortController? abort}) {
    final cached = _plezyPersonMedia[personId];
    if (cached != null && !refresh) return cached;
    final future = _loadMergedPersonMedia(personId, abort: abort);
    _plezyPersonMedia[personId] = future;
    future.catchError((_) {
      _plezyPersonMedia.remove(personId);
      return null;
    });
    return future;
  }

  /// All tag ids of the person: actor and director via the search index
  /// (same plex.tv `tagKey`), writer and producer via the section listings
  /// (same name and photo; those carry no `tagKey`). Null when the person
  /// has no name, so the caller keeps the server's own list.
  Future<List<PlexMetadataDto>?> _loadMergedPersonMedia(String personId, {AbortController? abort}) async {
    final tagResponse = await _getWithFailover('/library/people/$personId', abort: abort);
    final person = firstFlexibleMap(_getMediaContainer(tagResponse)?['Directory']);
    final name = (person?['tag'] ?? person?['title'])?.toString().trim() ?? '';
    if (name.isEmpty) return null;
    var tagKey = person?['tagKey']?.toString() ?? '';
    var thumb = person?['thumb']?.toString() ?? '';
    if (tagKey.isEmpty) {
      // .nfo person: borrow the identity of the namesake the agents matched.
      final namesake = await _plezyNamesake(
        name,
        selfId: personId,
      ).catchError((_) => (thumb: null, tagKey: null));
      tagKey = namesake.tagKey ?? '';
      if (thumb.isEmpty) thumb = namesake.thumb ?? '';
    }
    bool samePhoto(Object? other) {
      final o = other?.toString() ?? '';
      return thumb.isEmpty || o.isEmpty || o == thumb;
    }

    final ids = <String>{personId};
    // Tags that are not acting roles (director, writer, producer).
    final crewIds = <String>{};
    var personFound = false;

    Future<void> fromSearch() async {
      final response = await _getWithFailover('/hubs/search', queryParameters: {'query': name, 'searchTypes': 'people', 'limit': 50}, abort: abort);
      final hubs = _getMediaContainer(response)?['Hub'];
      if (hubs is! List) return;
      for (final hub in hubs) {
        if (hub is! Map) continue;
        for (final list in [hub['Directory'], hub['Metadata']]) {
          for (final entry in flexibleMapList(list)) {
            if (entry['type'] != 'tag') continue;
            final id = entry['id']?.toString() ?? '';
            if (id.isEmpty) continue;
            final key = entry['tagKey']?.toString() ?? '';
            final match = tagKey.isNotEmpty && key.isNotEmpty
                ? key == tagKey
                : entry['tag']?.toString().trim() == name && samePhoto(entry['thumb']);
            if (id == personId) personFound = true;
            if (!match && id != personId) continue;
            ids.add(id);
            if (flexibleInt(entry['tagType']) != 6) crewIds.add(id);
          }
        }
      }
    }

    Future<void> fromRoleLists() async {
      final sections = (await _getLibraries()).where((l) => l.type == 'movie' || l.type == 'show');
      final lists = await Future.wait([
        for (final section in sections)
          for (final role in const ['writer', 'producer'])
            _plezyRoleList(section.key, role, abort).catchError((_) => <Map<String, dynamic>>[]),
      ]);
      for (final list in lists) {
        for (final entry in list) {
          if (entry['title']?.toString().trim() != name || !samePhoto(entry['thumb'])) continue;
          final id = entry['key']?.toString() ?? '';
          if (id.isEmpty || id.contains('/')) continue;
          ids.add(id);
          crewIds.add(id);
          if (id == personId) personFound = true;
        }
      }
    }

    await Future.wait([
      fromSearch().catchError((Object e) => appLogger.w('Plezy+: person search failed', error: e)),
      fromRoleLists().catchError((Object e) => appLogger.w('Plezy+: role lists failed', error: e)),
    ]);

    // A tag found nowhere counts as acting (the cast row is the usual way in).
    if (!personFound) crewIds.remove(personId);

    final idList = ids.toList();
    final results = await Future.wait([
      for (final id in idList)
        id == personId
            ? _getPersonMedia(id, abort: abort)
            : _getPersonMedia(id, abort: abort).catchError((_) => const _LibraryContentResult(items: [], totalSize: 0)),
    ]);
    // Two lists, cast and crew; a film can be in both, but only once in each.
    List<PlexMetadataDto> collect(bool crew) {
      final seen = <String>{};
      final list = [
        for (final (i, result) in results.indexed)
          if (crewIds.contains(idList[i]) == crew)
            for (final item in result.items)
              if (seen.add(item.ratingKey)) item,
      ];
      // Newest year first, alphabetical within a year (the card shows only the year).
      int year(PlexMetadataDto m) => m.year ?? int.tryParse((m.originallyAvailableAt ?? '').split('-').first) ?? 0;
      list.sort((a, b) {
        final byYear = year(b).compareTo(year(a));
        if (byYear != 0) return byYear;
        return (a.titleSort ?? a.title ?? '').toLowerCase().compareTo((b.titleSort ?? b.title ?? '').toLowerCase());
      });
      return list;
    }

    final cast = collect(false);
    final crew = collect(true);
    _plezyPersonCastCount[personId] = cast.length;
    return [...cast, ...crew];
  }

  /// Plezy+: per person id, how many entries of the merged filmography are
  /// acting roles; they come first, the crew roles after them.
  final Map<String, int> _plezyPersonCastCount = {};

  /// Plezy+: number of acting roles at the start of [fetchPersonMediaPage]'s
  /// list for [personId], or null when the list is not split (not loaded,
  /// or the merge failed).
  int? personCastCount(String personId) => _plezyPersonCastCount[personId];

  /// Plezy+: photo and plex.tv id of a person's matched namesake, per name.
  final Map<String, Future<({String? thumb, String? tagKey})>> _plezyNamesakes = {};

  /// Plezy+: people from local .nfo files are plain tags without photo or
  /// plex.tv id. Takes both from the tags of the same name the metadata
  /// agents matched, found by search (actor, director). Plex keeps one tag
  /// per library, and different people can share a name, so the choice is:
  /// 1. a single tagKey among the namesakes in the same library
  ///    ([sectionId], or the library of the tag [selfId]);
  /// 2. else a single tagKey among all namesakes that have a photo;
  /// 3. else a single tagKey among all namesakes.
  /// Without any tagKey only an unambiguous photo is taken. With
  /// [roleLists], writer and producer listings are consulted as well when
  /// the search finds nothing.
  Future<({String? thumb, String? tagKey})> _plezyNamesake(
    String name, {
    bool roleLists = false,
    String? sectionId,
    String? selfId,
  }) {
    final cacheKey = '${roleLists ? 'L' : 'S'}|${sectionId ?? ''}|${selfId ?? ''}|$name';
    final cached = _plezyNamesakes[cacheKey];
    if (cached != null) return cached;
    Future<({String? thumb, String? tagKey})> load() async {
      if (roleLists) {
        final searched = await _plezyNamesake(name, sectionId: sectionId);
        if (searched.thumb != null || searched.tagKey != null) return searched;
      }
      String? only(Iterable<Object?> values) {
        final set = {for (final v in values) if (v != null && v.toString().isNotEmpty) v.toString()};
        return set.length == 1 ? set.single : null;
      }

      String key(Map<String, dynamic> m) => m['tagKey']?.toString() ?? '';
      String photo(Map<String, dynamic> m) => m['thumb']?.toString() ?? '';

      if (!roleLists) {
        final matches = <Map<String, dynamic>>[];
        final response = await _getWithFailover(
          '/hubs/search',
          queryParameters: {'query': name, 'searchTypes': 'people', 'limit': 15},
        );
        final hubs = _getMediaContainer(response)?['Hub'];
        for (final hub in hubs is List ? hubs : const []) {
          if (hub is! Map) continue;
          for (final list in [hub['Directory'], hub['Metadata']]) {
            for (final entry in flexibleMapList(list)) {
              if (entry['type'] == 'tag' && entry['tag']?.toString().trim() == name) matches.add(entry);
            }
          }
        }
        final section =
            sectionId ??
            matches.where((m) => m['id']?.toString() == selfId).map((m) => m['librarySectionID']?.toString()).firstOrNull;
        final keyed = matches.where((m) => key(m).isNotEmpty).toList();
        String? chosen;
        for (final candidates in [
          if (section != null) keyed.where((m) => m['librarySectionID']?.toString() == section),
          keyed.where((m) => photo(m).isNotEmpty),
          keyed,
        ]) {
          final keys = {for (final m in candidates) key(m)};
          if (keys.length == 1) {
            chosen = keys.single;
            break;
          }
        }
        if (chosen != null) {
          final thumb = keyed.where((m) => key(m) == chosen).map(photo).firstWhere((t) => t.isNotEmpty, orElse: () => '');
          return (thumb: thumb.isEmpty ? null : thumb, tagKey: chosen);
        }
        if (keyed.isNotEmpty) return (thumb: null, tagKey: null);
        return (thumb: only(matches.map(photo)), tagKey: null);
      }

      final sections = (await _getLibraries()).where((l) => l.type == 'movie' || l.type == 'show');
      final lists = await Future.wait([
        for (final section in sections)
          for (final role in const ['writer', 'producer'])
            _plezyRoleList(section.key, role, null).catchError((_) => <Map<String, dynamic>>[]),
      ]);
      final thumb = only([
        for (final list in lists)
          for (final entry in list)
            if (entry['title']?.toString().trim() == name) entry['thumb'],
      ]);
      return (thumb: thumb, tagKey: null);
    }

    final future = load();
    _plezyNamesakes[cacheKey] = future;
    future.catchError((_) {
      _plezyNamesakes.remove(cacheKey);
      return (thumb: null, tagKey: null);
    });
    return future;
  }

  /// Plezy+: [item] with photos filled in for cast and crew that have none,
  /// or null when nothing changed. [onUpdate] receives intermediate results
  /// (at most every 300 ms) so photos appear as they are found.
  Future<MediaItem?> withNamesakePhotos(MediaItem item, {void Function(MediaItem item)? onUpdate}) async {
    final roles = item.roles ?? const <MediaRole>[];
    final crewRaw = item.raw?[plexCrewRawKey];
    final crew = [for (final e in crewRaw is List ? crewRaw : const []) if (e is Map) Map<String, Object?>.from(e)];
    // Only people from .nfo files: those the agents matched (with a plex.tv
    // id) but without a photo have no better photo to find.
    final nfoRaw = item.raw?[plexNfoPeopleRawKey];
    final nfo = nfoRaw is List ? {for (final n in nfoRaw) n.toString()} : null;
    bool missing(Object? thumb) => (thumb?.toString() ?? '').isEmpty;
    String nameOf(Object? tag) => tag?.toString().trim() ?? '';
    bool wanted(Object? tag, Object? thumb) =>
        missing(thumb) && nameOf(tag).isNotEmpty && (nfo == null || nfo.contains(nameOf(tag)));
    final cast = {for (final r in roles) if (wanted(r.tag, r.thumbPath)) nameOf(r.tag)};
    // Writers and producers are not in the search index; only they need the listings.
    final listed = {
      for (final c in crew)
        if (wanted(c['tag'], c['thumb']) && c['job'] != 'director' && !cast.contains(nameOf(c['tag'])))
          nameOf(c['tag']),
    };
    final searched = {
      ...cast,
      for (final c in crew)
        if (wanted(c['tag'], c['thumb']) && !listed.contains(nameOf(c['tag']))) nameOf(c['tag']),
    };
    if (searched.isEmpty && listed.isEmpty) return null;

    final found = <String, String>{};
    MediaItem apply() => item.copyWith(
      roles: item.roles == null
          ? null
          : [
              for (final r in roles)
                missing(r.thumbPath) && found[nameOf(r.tag)] != null
                    ? MediaRole(id: r.id, tag: r.tag, role: r.role, thumbPath: found[nameOf(r.tag)])
                    : r,
            ],
      raw: crew.isEmpty
          ? item.raw
          : {
              ...?item.raw,
              plexCrewRawKey: [
                for (final c in crew)
                  missing(c['thumb']) && found[nameOf(c['tag'])] != null ? {...c, 'thumb': found[nameOf(c['tag'])]} : c,
              ],
            },
    );
    Timer? pending;
    void record(String name, ({String? thumb, String? tagKey}) n) {
      if (n.thumb == null) return;
      found[name] = n.thumb!;
      if (onUpdate != null) {
        pending ??= Timer(const Duration(milliseconds: 300), () {
          pending = null;
          onUpdate(apply());
        });
      }
    }

    await Future.wait([
      for (final name in searched)
        _plezyNamesake(name, sectionId: item.libraryId).then((n) => record(name, n), onError: (_) {}),
      for (final name in listed)
        _plezyNamesake(name, roleLists: true, sectionId: item.libraryId).then((n) => record(name, n), onError: (_) {}),
    ]);
    pending?.cancel();
    return found.isEmpty ? null : apply();
  }

  Future<List<Map<String, dynamic>>> _plezyRoleList(String sectionId, String role, AbortController? abort) {
    final cacheKey = '$sectionId/$role';
    final cached = _plezyRoleLists[cacheKey];
    if (cached != null && DateTime.now().difference(cached.$1) < const Duration(minutes: 30)) return cached.$2;
    final future = _getWithFailover('/library/sections/$sectionId/$role', abort: abort)
        .then((response) => flexibleMapList(_getMediaContainer(response)?['Directory']));
    _plezyRoleLists[cacheKey] = (DateTime.now(), future);
    future.catchError((_) {
      _plezyRoleLists.remove(cacheKey);
      return <Map<String, dynamic>>[];
    });
    return future;
  }

  @override
  Future<MediaPersonDetails> fetchPersonDetails(String personId, {AbortController? abort}) async {
    final accountToken = plexAccountToken;
    if (isOfflineMode || accountToken == null || accountToken.isEmpty) return MediaPersonDetails.empty;
    final tagResponse = await _getWithFailover('/library/people/$personId', abort: abort);
    final person = firstFlexibleMap(_getMediaContainer(tagResponse)?['Directory']);
    var tagKey = person?['tagKey'];
    if (tagKey is! String || tagKey.isEmpty) {
      // Plezy+: .nfo people carry no plex.tv id; borrow the namesake's.
      final name = (person?['tag'] ?? person?['title'])?.toString().trim() ?? '';
      tagKey = name.isEmpty ? null : (await _plezyNamesake(name, selfId: personId).catchError((_) => (thumb: null, tagKey: null))).tagKey;
    }
    if (tagKey is! String || tagKey.isEmpty) return MediaPersonDetails.empty;
    // A plex.tv failure says nothing about this server's endpoints, so it
    // must not walk (or exhaust) the server's failover list.
    final response = await _http.get(
      '$_discoverPeopleUrl${Uri.encodeComponent(tagKey)}',
      headers: {'X-Plex-Token': accountToken},
      abort: abort,
      allowEndpointFailover: false,
    );
    throwIfHttpError(response);
    final container = _getMediaContainer(response);
    return PlexMappers.personDetails(firstFlexibleMap(container?['Metadata']));
  }

  @override
  Future<bool> deleteCollection(MediaItem collection) {
    return deleteCollectionById(collection.libraryId ?? '', collection.id);
  }

  Future<bool> deleteCollectionById(String sectionId, String collectionId) async {
    appLogger.d(
      'Deleting collection: sectionId=$sectionId, '
      'collectionId=$collectionId',
    );
    final result = await _wrapBoolApiCall(
      () => _http.delete('/library/collections/$collectionId'),
      'Failed to delete collection',
    );
    if (result) appLogger.d('Delete collection response: 200');
    return result;
  }

  @override
  Future<String?> createCollection({
    required String libraryId,
    required String title,
    required List<MediaItem> items,
    MediaKind? itemKind,
  }) async {
    final uri = items.isEmpty ? '' : await buildMetadataUri(items.map((item) => item.id).join(','));
    // Plex collections are only created for video kinds; music kinds send no type.
    final type = itemKind == null || itemKind.isMusic ? null : PlexMetadataType.forKind(itemKind);
    return createCollectionFromUri(sectionId: libraryId, title: title, uri: uri, type: type);
  }

  Future<String?> createCollectionFromUri({
    required String sectionId,
    required String title,
    required String uri,
    int? type,
  }) async {
    appLogger.d('Creating collection: sectionId=$sectionId, title=$title, type=$type');
    final response = await _http.post(
      '/library/collections',
      queryParameters: {'type': ?type, 'title': title, 'smart': 0, 'sectionId': sectionId, 'uri': uri},
    );
    throwIfHttpError(response);
    appLogger.d('Create collection response: ${response.statusCode}');

    final metadata = _getMediaContainer(response)?['Metadata'];
    if (metadata is! List || metadata.isEmpty || metadata.first is! Map) return null;
    final collectionId = (metadata.first as Map)['ratingKey']?.toString().trim();
    if (collectionId == null || collectionId.isEmpty) return null;
    appLogger.d('Created collection with ID: $collectionId');
    return collectionId;
  }

  @override
  Future<bool> addToCollection({required String collectionId, required List<MediaItem> items}) async {
    if (items.isEmpty) return true;
    final uri = await buildMetadataUri(items.map((item) => item.id).join(','));
    return addItemsToCollectionByUri(collectionId: collectionId, uri: uri);
  }

  Future<bool> addItemsToCollectionByUri({required String collectionId, required String uri}) async {
    appLogger.d('Adding items to collection: collectionId=$collectionId');
    final result = await _wrapBoolApiCall(
      () => _http.put('/library/collections/$collectionId/items', queryParameters: {'uri': uri}),
      'Failed to add items to collection',
    );
    if (result) appLogger.d('Add to collection response: 200');
    return result;
  }

  @override
  Future<bool> removeFromCollection({required String collectionId, required MediaItem item}) async {
    appLogger.d(
      'Removing item from collection: collectionId=$collectionId, '
      'itemId=${item.id}',
    );
    final result = await _wrapBoolApiCall(
      () => _http.delete('/library/collections/$collectionId/items/${item.id}'),
      'Failed to remove item from collection',
    );
    if (result) appLogger.d('Remove from collection response: 200');
    return result;
  }
}
