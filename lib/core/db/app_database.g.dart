// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ArtistsTable extends Artists with TableInfo<$ArtistsTable, Artist> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ArtistsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ratingKeyMeta = const VerificationMeta(
    'ratingKey',
  );
  @override
  late final GeneratedColumn<String> ratingKey = GeneratedColumn<String>(
    'rating_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _normalisedTitleMeta = const VerificationMeta(
    'normalisedTitle',
  );
  @override
  late final GeneratedColumn<String> normalisedTitle = GeneratedColumn<String>(
    'normalised_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _thumbMeta = const VerificationMeta('thumb');
  @override
  late final GeneratedColumn<String> thumb = GeneratedColumn<String>(
    'thumb',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ratingKey,
    title,
    normalisedTitle,
    thumb,
    updatedAt,
    addedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'artists';
  @override
  VerificationContext validateIntegrity(
    Insertable<Artist> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('rating_key')) {
      context.handle(
        _ratingKeyMeta,
        ratingKey.isAcceptableOrUnknown(data['rating_key']!, _ratingKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_ratingKeyMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('normalised_title')) {
      context.handle(
        _normalisedTitleMeta,
        normalisedTitle.isAcceptableOrUnknown(
          data['normalised_title']!,
          _normalisedTitleMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_normalisedTitleMeta);
    }
    if (data.containsKey('thumb')) {
      context.handle(
        _thumbMeta,
        thumb.isAcceptableOrUnknown(data['thumb']!, _thumbMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ratingKey};
  @override
  Artist map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Artist(
      ratingKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rating_key'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      normalisedTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalised_title'],
      )!,
      thumb: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumb'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      ),
    );
  }

  @override
  $ArtistsTable createAlias(String alias) {
    return $ArtistsTable(attachedDatabase, alias);
  }
}

class Artist extends DataClass implements Insertable<Artist> {
  final String ratingKey;
  final String title;

  /// Punctuation-folded, lowercased copy of [title], indexed so search can hit
  /// it directly instead of normalising every row at query time.
  final String normalisedTitle;
  final String? thumb;
  final int? updatedAt;
  final int? addedAt;
  const Artist({
    required this.ratingKey,
    required this.title,
    required this.normalisedTitle,
    this.thumb,
    this.updatedAt,
    this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['rating_key'] = Variable<String>(ratingKey);
    map['title'] = Variable<String>(title);
    map['normalised_title'] = Variable<String>(normalisedTitle);
    if (!nullToAbsent || thumb != null) {
      map['thumb'] = Variable<String>(thumb);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<int>(updatedAt);
    }
    if (!nullToAbsent || addedAt != null) {
      map['added_at'] = Variable<int>(addedAt);
    }
    return map;
  }

  ArtistsCompanion toCompanion(bool nullToAbsent) {
    return ArtistsCompanion(
      ratingKey: Value(ratingKey),
      title: Value(title),
      normalisedTitle: Value(normalisedTitle),
      thumb: thumb == null && nullToAbsent
          ? const Value.absent()
          : Value(thumb),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
      addedAt: addedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(addedAt),
    );
  }

  factory Artist.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Artist(
      ratingKey: serializer.fromJson<String>(json['ratingKey']),
      title: serializer.fromJson<String>(json['title']),
      normalisedTitle: serializer.fromJson<String>(json['normalisedTitle']),
      thumb: serializer.fromJson<String?>(json['thumb']),
      updatedAt: serializer.fromJson<int?>(json['updatedAt']),
      addedAt: serializer.fromJson<int?>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ratingKey': serializer.toJson<String>(ratingKey),
      'title': serializer.toJson<String>(title),
      'normalisedTitle': serializer.toJson<String>(normalisedTitle),
      'thumb': serializer.toJson<String?>(thumb),
      'updatedAt': serializer.toJson<int?>(updatedAt),
      'addedAt': serializer.toJson<int?>(addedAt),
    };
  }

  Artist copyWith({
    String? ratingKey,
    String? title,
    String? normalisedTitle,
    Value<String?> thumb = const Value.absent(),
    Value<int?> updatedAt = const Value.absent(),
    Value<int?> addedAt = const Value.absent(),
  }) => Artist(
    ratingKey: ratingKey ?? this.ratingKey,
    title: title ?? this.title,
    normalisedTitle: normalisedTitle ?? this.normalisedTitle,
    thumb: thumb.present ? thumb.value : this.thumb,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
    addedAt: addedAt.present ? addedAt.value : this.addedAt,
  );
  Artist copyWithCompanion(ArtistsCompanion data) {
    return Artist(
      ratingKey: data.ratingKey.present ? data.ratingKey.value : this.ratingKey,
      title: data.title.present ? data.title.value : this.title,
      normalisedTitle: data.normalisedTitle.present
          ? data.normalisedTitle.value
          : this.normalisedTitle,
      thumb: data.thumb.present ? data.thumb.value : this.thumb,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Artist(')
          ..write('ratingKey: $ratingKey, ')
          ..write('title: $title, ')
          ..write('normalisedTitle: $normalisedTitle, ')
          ..write('thumb: $thumb, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(ratingKey, title, normalisedTitle, thumb, updatedAt, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Artist &&
          other.ratingKey == this.ratingKey &&
          other.title == this.title &&
          other.normalisedTitle == this.normalisedTitle &&
          other.thumb == this.thumb &&
          other.updatedAt == this.updatedAt &&
          other.addedAt == this.addedAt);
}

class ArtistsCompanion extends UpdateCompanion<Artist> {
  final Value<String> ratingKey;
  final Value<String> title;
  final Value<String> normalisedTitle;
  final Value<String?> thumb;
  final Value<int?> updatedAt;
  final Value<int?> addedAt;
  final Value<int> rowid;
  const ArtistsCompanion({
    this.ratingKey = const Value.absent(),
    this.title = const Value.absent(),
    this.normalisedTitle = const Value.absent(),
    this.thumb = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ArtistsCompanion.insert({
    required String ratingKey,
    required String title,
    required String normalisedTitle,
    this.thumb = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ratingKey = Value(ratingKey),
       title = Value(title),
       normalisedTitle = Value(normalisedTitle);
  static Insertable<Artist> custom({
    Expression<String>? ratingKey,
    Expression<String>? title,
    Expression<String>? normalisedTitle,
    Expression<String>? thumb,
    Expression<int>? updatedAt,
    Expression<int>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ratingKey != null) 'rating_key': ratingKey,
      if (title != null) 'title': title,
      if (normalisedTitle != null) 'normalised_title': normalisedTitle,
      if (thumb != null) 'thumb': thumb,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ArtistsCompanion copyWith({
    Value<String>? ratingKey,
    Value<String>? title,
    Value<String>? normalisedTitle,
    Value<String?>? thumb,
    Value<int?>? updatedAt,
    Value<int?>? addedAt,
    Value<int>? rowid,
  }) {
    return ArtistsCompanion(
      ratingKey: ratingKey ?? this.ratingKey,
      title: title ?? this.title,
      normalisedTitle: normalisedTitle ?? this.normalisedTitle,
      thumb: thumb ?? this.thumb,
      updatedAt: updatedAt ?? this.updatedAt,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ratingKey.present) {
      map['rating_key'] = Variable<String>(ratingKey.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (normalisedTitle.present) {
      map['normalised_title'] = Variable<String>(normalisedTitle.value);
    }
    if (thumb.present) {
      map['thumb'] = Variable<String>(thumb.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ArtistsCompanion(')
          ..write('ratingKey: $ratingKey, ')
          ..write('title: $title, ')
          ..write('normalisedTitle: $normalisedTitle, ')
          ..write('thumb: $thumb, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AlbumsTable extends Albums with TableInfo<$AlbumsTable, Album> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AlbumsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ratingKeyMeta = const VerificationMeta(
    'ratingKey',
  );
  @override
  late final GeneratedColumn<String> ratingKey = GeneratedColumn<String>(
    'rating_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _normalisedTitleMeta = const VerificationMeta(
    'normalisedTitle',
  );
  @override
  late final GeneratedColumn<String> normalisedTitle = GeneratedColumn<String>(
    'normalised_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _artistRatingKeyMeta = const VerificationMeta(
    'artistRatingKey',
  );
  @override
  late final GeneratedColumn<String> artistRatingKey = GeneratedColumn<String>(
    'artist_rating_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artistTitleMeta = const VerificationMeta(
    'artistTitle',
  );
  @override
  late final GeneratedColumn<String> artistTitle = GeneratedColumn<String>(
    'artist_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _normalisedArtistMeta = const VerificationMeta(
    'normalisedArtist',
  );
  @override
  late final GeneratedColumn<String> normalisedArtist = GeneratedColumn<String>(
    'normalised_artist',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _thumbMeta = const VerificationMeta('thumb');
  @override
  late final GeneratedColumn<String> thumb = GeneratedColumn<String>(
    'thumb',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
    'year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastViewedAtMeta = const VerificationMeta(
    'lastViewedAt',
  );
  @override
  late final GeneratedColumn<int> lastViewedAt = GeneratedColumn<int>(
    'last_viewed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mbidMeta = const VerificationMeta('mbid');
  @override
  late final GeneratedColumn<String> mbid = GeneratedColumn<String>(
    'mbid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _userRatingMeta = const VerificationMeta(
    'userRating',
  );
  @override
  late final GeneratedColumn<int> userRating = GeneratedColumn<int>(
    'user_rating',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ratingKey,
    title,
    normalisedTitle,
    artistRatingKey,
    artistTitle,
    normalisedArtist,
    thumb,
    year,
    updatedAt,
    addedAt,
    lastViewedAt,
    mbid,
    userRating,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'albums';
  @override
  VerificationContext validateIntegrity(
    Insertable<Album> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('rating_key')) {
      context.handle(
        _ratingKeyMeta,
        ratingKey.isAcceptableOrUnknown(data['rating_key']!, _ratingKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_ratingKeyMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('normalised_title')) {
      context.handle(
        _normalisedTitleMeta,
        normalisedTitle.isAcceptableOrUnknown(
          data['normalised_title']!,
          _normalisedTitleMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_normalisedTitleMeta);
    }
    if (data.containsKey('artist_rating_key')) {
      context.handle(
        _artistRatingKeyMeta,
        artistRatingKey.isAcceptableOrUnknown(
          data['artist_rating_key']!,
          _artistRatingKeyMeta,
        ),
      );
    }
    if (data.containsKey('artist_title')) {
      context.handle(
        _artistTitleMeta,
        artistTitle.isAcceptableOrUnknown(
          data['artist_title']!,
          _artistTitleMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_artistTitleMeta);
    }
    if (data.containsKey('normalised_artist')) {
      context.handle(
        _normalisedArtistMeta,
        normalisedArtist.isAcceptableOrUnknown(
          data['normalised_artist']!,
          _normalisedArtistMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_normalisedArtistMeta);
    }
    if (data.containsKey('thumb')) {
      context.handle(
        _thumbMeta,
        thumb.isAcceptableOrUnknown(data['thumb']!, _thumbMeta),
      );
    }
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    }
    if (data.containsKey('last_viewed_at')) {
      context.handle(
        _lastViewedAtMeta,
        lastViewedAt.isAcceptableOrUnknown(
          data['last_viewed_at']!,
          _lastViewedAtMeta,
        ),
      );
    }
    if (data.containsKey('mbid')) {
      context.handle(
        _mbidMeta,
        mbid.isAcceptableOrUnknown(data['mbid']!, _mbidMeta),
      );
    }
    if (data.containsKey('user_rating')) {
      context.handle(
        _userRatingMeta,
        userRating.isAcceptableOrUnknown(data['user_rating']!, _userRatingMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ratingKey};
  @override
  Album map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Album(
      ratingKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rating_key'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      normalisedTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalised_title'],
      )!,
      artistRatingKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist_rating_key'],
      ),
      artistTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist_title'],
      )!,
      normalisedArtist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalised_artist'],
      )!,
      thumb: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumb'],
      ),
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}year'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      ),
      lastViewedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_viewed_at'],
      ),
      mbid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mbid'],
      ),
      userRating: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}user_rating'],
      ),
    );
  }

  @override
  $AlbumsTable createAlias(String alias) {
    return $AlbumsTable(attachedDatabase, alias);
  }
}

class Album extends DataClass implements Insertable<Album> {
  final String ratingKey;
  final String title;
  final String normalisedTitle;

  /// Plex exposes the album artist as `parentRatingKey` / `parentTitle`.
  final String? artistRatingKey;
  final String artistTitle;
  final String normalisedArtist;
  final String? thumb;
  final int? year;
  final int? updatedAt;

  /// Indexed because "recently added" on the Home screen sorts by it.
  final int? addedAt;

  /// Set when Plex reports a play. Drives "recently played".
  final int? lastViewedAt;

  /// MusicBrainz release-group id, when Plex knows one.
  ///
  /// Phase 5 uses this to filter owned albums out of the "Not in your library"
  /// search tier. Where it is null, matching falls back to
  /// [normalisedArtist] + [normalisedTitle].
  final String? mbid;

  /// Plex `userRating`, 0–10, null when unrated. Indexed because the Favourites
  /// view and filters query on it.
  final int? userRating;
  const Album({
    required this.ratingKey,
    required this.title,
    required this.normalisedTitle,
    this.artistRatingKey,
    required this.artistTitle,
    required this.normalisedArtist,
    this.thumb,
    this.year,
    this.updatedAt,
    this.addedAt,
    this.lastViewedAt,
    this.mbid,
    this.userRating,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['rating_key'] = Variable<String>(ratingKey);
    map['title'] = Variable<String>(title);
    map['normalised_title'] = Variable<String>(normalisedTitle);
    if (!nullToAbsent || artistRatingKey != null) {
      map['artist_rating_key'] = Variable<String>(artistRatingKey);
    }
    map['artist_title'] = Variable<String>(artistTitle);
    map['normalised_artist'] = Variable<String>(normalisedArtist);
    if (!nullToAbsent || thumb != null) {
      map['thumb'] = Variable<String>(thumb);
    }
    if (!nullToAbsent || year != null) {
      map['year'] = Variable<int>(year);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<int>(updatedAt);
    }
    if (!nullToAbsent || addedAt != null) {
      map['added_at'] = Variable<int>(addedAt);
    }
    if (!nullToAbsent || lastViewedAt != null) {
      map['last_viewed_at'] = Variable<int>(lastViewedAt);
    }
    if (!nullToAbsent || mbid != null) {
      map['mbid'] = Variable<String>(mbid);
    }
    if (!nullToAbsent || userRating != null) {
      map['user_rating'] = Variable<int>(userRating);
    }
    return map;
  }

  AlbumsCompanion toCompanion(bool nullToAbsent) {
    return AlbumsCompanion(
      ratingKey: Value(ratingKey),
      title: Value(title),
      normalisedTitle: Value(normalisedTitle),
      artistRatingKey: artistRatingKey == null && nullToAbsent
          ? const Value.absent()
          : Value(artistRatingKey),
      artistTitle: Value(artistTitle),
      normalisedArtist: Value(normalisedArtist),
      thumb: thumb == null && nullToAbsent
          ? const Value.absent()
          : Value(thumb),
      year: year == null && nullToAbsent ? const Value.absent() : Value(year),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
      addedAt: addedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(addedAt),
      lastViewedAt: lastViewedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastViewedAt),
      mbid: mbid == null && nullToAbsent ? const Value.absent() : Value(mbid),
      userRating: userRating == null && nullToAbsent
          ? const Value.absent()
          : Value(userRating),
    );
  }

  factory Album.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Album(
      ratingKey: serializer.fromJson<String>(json['ratingKey']),
      title: serializer.fromJson<String>(json['title']),
      normalisedTitle: serializer.fromJson<String>(json['normalisedTitle']),
      artistRatingKey: serializer.fromJson<String?>(json['artistRatingKey']),
      artistTitle: serializer.fromJson<String>(json['artistTitle']),
      normalisedArtist: serializer.fromJson<String>(json['normalisedArtist']),
      thumb: serializer.fromJson<String?>(json['thumb']),
      year: serializer.fromJson<int?>(json['year']),
      updatedAt: serializer.fromJson<int?>(json['updatedAt']),
      addedAt: serializer.fromJson<int?>(json['addedAt']),
      lastViewedAt: serializer.fromJson<int?>(json['lastViewedAt']),
      mbid: serializer.fromJson<String?>(json['mbid']),
      userRating: serializer.fromJson<int?>(json['userRating']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ratingKey': serializer.toJson<String>(ratingKey),
      'title': serializer.toJson<String>(title),
      'normalisedTitle': serializer.toJson<String>(normalisedTitle),
      'artistRatingKey': serializer.toJson<String?>(artistRatingKey),
      'artistTitle': serializer.toJson<String>(artistTitle),
      'normalisedArtist': serializer.toJson<String>(normalisedArtist),
      'thumb': serializer.toJson<String?>(thumb),
      'year': serializer.toJson<int?>(year),
      'updatedAt': serializer.toJson<int?>(updatedAt),
      'addedAt': serializer.toJson<int?>(addedAt),
      'lastViewedAt': serializer.toJson<int?>(lastViewedAt),
      'mbid': serializer.toJson<String?>(mbid),
      'userRating': serializer.toJson<int?>(userRating),
    };
  }

  Album copyWith({
    String? ratingKey,
    String? title,
    String? normalisedTitle,
    Value<String?> artistRatingKey = const Value.absent(),
    String? artistTitle,
    String? normalisedArtist,
    Value<String?> thumb = const Value.absent(),
    Value<int?> year = const Value.absent(),
    Value<int?> updatedAt = const Value.absent(),
    Value<int?> addedAt = const Value.absent(),
    Value<int?> lastViewedAt = const Value.absent(),
    Value<String?> mbid = const Value.absent(),
    Value<int?> userRating = const Value.absent(),
  }) => Album(
    ratingKey: ratingKey ?? this.ratingKey,
    title: title ?? this.title,
    normalisedTitle: normalisedTitle ?? this.normalisedTitle,
    artistRatingKey: artistRatingKey.present
        ? artistRatingKey.value
        : this.artistRatingKey,
    artistTitle: artistTitle ?? this.artistTitle,
    normalisedArtist: normalisedArtist ?? this.normalisedArtist,
    thumb: thumb.present ? thumb.value : this.thumb,
    year: year.present ? year.value : this.year,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
    addedAt: addedAt.present ? addedAt.value : this.addedAt,
    lastViewedAt: lastViewedAt.present ? lastViewedAt.value : this.lastViewedAt,
    mbid: mbid.present ? mbid.value : this.mbid,
    userRating: userRating.present ? userRating.value : this.userRating,
  );
  Album copyWithCompanion(AlbumsCompanion data) {
    return Album(
      ratingKey: data.ratingKey.present ? data.ratingKey.value : this.ratingKey,
      title: data.title.present ? data.title.value : this.title,
      normalisedTitle: data.normalisedTitle.present
          ? data.normalisedTitle.value
          : this.normalisedTitle,
      artistRatingKey: data.artistRatingKey.present
          ? data.artistRatingKey.value
          : this.artistRatingKey,
      artistTitle: data.artistTitle.present
          ? data.artistTitle.value
          : this.artistTitle,
      normalisedArtist: data.normalisedArtist.present
          ? data.normalisedArtist.value
          : this.normalisedArtist,
      thumb: data.thumb.present ? data.thumb.value : this.thumb,
      year: data.year.present ? data.year.value : this.year,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      lastViewedAt: data.lastViewedAt.present
          ? data.lastViewedAt.value
          : this.lastViewedAt,
      mbid: data.mbid.present ? data.mbid.value : this.mbid,
      userRating: data.userRating.present
          ? data.userRating.value
          : this.userRating,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Album(')
          ..write('ratingKey: $ratingKey, ')
          ..write('title: $title, ')
          ..write('normalisedTitle: $normalisedTitle, ')
          ..write('artistRatingKey: $artistRatingKey, ')
          ..write('artistTitle: $artistTitle, ')
          ..write('normalisedArtist: $normalisedArtist, ')
          ..write('thumb: $thumb, ')
          ..write('year: $year, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('addedAt: $addedAt, ')
          ..write('lastViewedAt: $lastViewedAt, ')
          ..write('mbid: $mbid, ')
          ..write('userRating: $userRating')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ratingKey,
    title,
    normalisedTitle,
    artistRatingKey,
    artistTitle,
    normalisedArtist,
    thumb,
    year,
    updatedAt,
    addedAt,
    lastViewedAt,
    mbid,
    userRating,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Album &&
          other.ratingKey == this.ratingKey &&
          other.title == this.title &&
          other.normalisedTitle == this.normalisedTitle &&
          other.artistRatingKey == this.artistRatingKey &&
          other.artistTitle == this.artistTitle &&
          other.normalisedArtist == this.normalisedArtist &&
          other.thumb == this.thumb &&
          other.year == this.year &&
          other.updatedAt == this.updatedAt &&
          other.addedAt == this.addedAt &&
          other.lastViewedAt == this.lastViewedAt &&
          other.mbid == this.mbid &&
          other.userRating == this.userRating);
}

class AlbumsCompanion extends UpdateCompanion<Album> {
  final Value<String> ratingKey;
  final Value<String> title;
  final Value<String> normalisedTitle;
  final Value<String?> artistRatingKey;
  final Value<String> artistTitle;
  final Value<String> normalisedArtist;
  final Value<String?> thumb;
  final Value<int?> year;
  final Value<int?> updatedAt;
  final Value<int?> addedAt;
  final Value<int?> lastViewedAt;
  final Value<String?> mbid;
  final Value<int?> userRating;
  final Value<int> rowid;
  const AlbumsCompanion({
    this.ratingKey = const Value.absent(),
    this.title = const Value.absent(),
    this.normalisedTitle = const Value.absent(),
    this.artistRatingKey = const Value.absent(),
    this.artistTitle = const Value.absent(),
    this.normalisedArtist = const Value.absent(),
    this.thumb = const Value.absent(),
    this.year = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.lastViewedAt = const Value.absent(),
    this.mbid = const Value.absent(),
    this.userRating = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AlbumsCompanion.insert({
    required String ratingKey,
    required String title,
    required String normalisedTitle,
    this.artistRatingKey = const Value.absent(),
    required String artistTitle,
    required String normalisedArtist,
    this.thumb = const Value.absent(),
    this.year = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.lastViewedAt = const Value.absent(),
    this.mbid = const Value.absent(),
    this.userRating = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ratingKey = Value(ratingKey),
       title = Value(title),
       normalisedTitle = Value(normalisedTitle),
       artistTitle = Value(artistTitle),
       normalisedArtist = Value(normalisedArtist);
  static Insertable<Album> custom({
    Expression<String>? ratingKey,
    Expression<String>? title,
    Expression<String>? normalisedTitle,
    Expression<String>? artistRatingKey,
    Expression<String>? artistTitle,
    Expression<String>? normalisedArtist,
    Expression<String>? thumb,
    Expression<int>? year,
    Expression<int>? updatedAt,
    Expression<int>? addedAt,
    Expression<int>? lastViewedAt,
    Expression<String>? mbid,
    Expression<int>? userRating,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ratingKey != null) 'rating_key': ratingKey,
      if (title != null) 'title': title,
      if (normalisedTitle != null) 'normalised_title': normalisedTitle,
      if (artistRatingKey != null) 'artist_rating_key': artistRatingKey,
      if (artistTitle != null) 'artist_title': artistTitle,
      if (normalisedArtist != null) 'normalised_artist': normalisedArtist,
      if (thumb != null) 'thumb': thumb,
      if (year != null) 'year': year,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (addedAt != null) 'added_at': addedAt,
      if (lastViewedAt != null) 'last_viewed_at': lastViewedAt,
      if (mbid != null) 'mbid': mbid,
      if (userRating != null) 'user_rating': userRating,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AlbumsCompanion copyWith({
    Value<String>? ratingKey,
    Value<String>? title,
    Value<String>? normalisedTitle,
    Value<String?>? artistRatingKey,
    Value<String>? artistTitle,
    Value<String>? normalisedArtist,
    Value<String?>? thumb,
    Value<int?>? year,
    Value<int?>? updatedAt,
    Value<int?>? addedAt,
    Value<int?>? lastViewedAt,
    Value<String?>? mbid,
    Value<int?>? userRating,
    Value<int>? rowid,
  }) {
    return AlbumsCompanion(
      ratingKey: ratingKey ?? this.ratingKey,
      title: title ?? this.title,
      normalisedTitle: normalisedTitle ?? this.normalisedTitle,
      artistRatingKey: artistRatingKey ?? this.artistRatingKey,
      artistTitle: artistTitle ?? this.artistTitle,
      normalisedArtist: normalisedArtist ?? this.normalisedArtist,
      thumb: thumb ?? this.thumb,
      year: year ?? this.year,
      updatedAt: updatedAt ?? this.updatedAt,
      addedAt: addedAt ?? this.addedAt,
      lastViewedAt: lastViewedAt ?? this.lastViewedAt,
      mbid: mbid ?? this.mbid,
      userRating: userRating ?? this.userRating,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ratingKey.present) {
      map['rating_key'] = Variable<String>(ratingKey.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (normalisedTitle.present) {
      map['normalised_title'] = Variable<String>(normalisedTitle.value);
    }
    if (artistRatingKey.present) {
      map['artist_rating_key'] = Variable<String>(artistRatingKey.value);
    }
    if (artistTitle.present) {
      map['artist_title'] = Variable<String>(artistTitle.value);
    }
    if (normalisedArtist.present) {
      map['normalised_artist'] = Variable<String>(normalisedArtist.value);
    }
    if (thumb.present) {
      map['thumb'] = Variable<String>(thumb.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (lastViewedAt.present) {
      map['last_viewed_at'] = Variable<int>(lastViewedAt.value);
    }
    if (mbid.present) {
      map['mbid'] = Variable<String>(mbid.value);
    }
    if (userRating.present) {
      map['user_rating'] = Variable<int>(userRating.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AlbumsCompanion(')
          ..write('ratingKey: $ratingKey, ')
          ..write('title: $title, ')
          ..write('normalisedTitle: $normalisedTitle, ')
          ..write('artistRatingKey: $artistRatingKey, ')
          ..write('artistTitle: $artistTitle, ')
          ..write('normalisedArtist: $normalisedArtist, ')
          ..write('thumb: $thumb, ')
          ..write('year: $year, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('addedAt: $addedAt, ')
          ..write('lastViewedAt: $lastViewedAt, ')
          ..write('mbid: $mbid, ')
          ..write('userRating: $userRating, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TracksTable extends Tracks with TableInfo<$TracksTable, Track> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TracksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ratingKeyMeta = const VerificationMeta(
    'ratingKey',
  );
  @override
  late final GeneratedColumn<String> ratingKey = GeneratedColumn<String>(
    'rating_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _normalisedTitleMeta = const VerificationMeta(
    'normalisedTitle',
  );
  @override
  late final GeneratedColumn<String> normalisedTitle = GeneratedColumn<String>(
    'normalised_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _albumRatingKeyMeta = const VerificationMeta(
    'albumRatingKey',
  );
  @override
  late final GeneratedColumn<String> albumRatingKey = GeneratedColumn<String>(
    'album_rating_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _albumTitleMeta = const VerificationMeta(
    'albumTitle',
  );
  @override
  late final GeneratedColumn<String> albumTitle = GeneratedColumn<String>(
    'album_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _artistTitleMeta = const VerificationMeta(
    'artistTitle',
  );
  @override
  late final GeneratedColumn<String> artistTitle = GeneratedColumn<String>(
    'artist_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _trackIndexMeta = const VerificationMeta(
    'trackIndex',
  );
  @override
  late final GeneratedColumn<int> trackIndex = GeneratedColumn<int>(
    'track_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _discIndexMeta = const VerificationMeta(
    'discIndex',
  );
  @override
  late final GeneratedColumn<int> discIndex = GeneratedColumn<int>(
    'disc_index',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _partKeyMeta = const VerificationMeta(
    'partKey',
  );
  @override
  late final GeneratedColumn<String> partKey = GeneratedColumn<String>(
    'part_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _containerMeta = const VerificationMeta(
    'container',
  );
  @override
  late final GeneratedColumn<String> container = GeneratedColumn<String>(
    'container',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _partSizeBytesMeta = const VerificationMeta(
    'partSizeBytes',
  );
  @override
  late final GeneratedColumn<int> partSizeBytes = GeneratedColumn<int>(
    'part_size_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _thumbMeta = const VerificationMeta('thumb');
  @override
  late final GeneratedColumn<String> thumb = GeneratedColumn<String>(
    'thumb',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastViewedAtMeta = const VerificationMeta(
    'lastViewedAt',
  );
  @override
  late final GeneratedColumn<int> lastViewedAt = GeneratedColumn<int>(
    'last_viewed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _userRatingMeta = const VerificationMeta(
    'userRating',
  );
  @override
  late final GeneratedColumn<int> userRating = GeneratedColumn<int>(
    'user_rating',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ratingKey,
    title,
    normalisedTitle,
    albumRatingKey,
    albumTitle,
    artistTitle,
    trackIndex,
    discIndex,
    durationMs,
    partKey,
    container,
    partSizeBytes,
    thumb,
    updatedAt,
    addedAt,
    lastViewedAt,
    userRating,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tracks';
  @override
  VerificationContext validateIntegrity(
    Insertable<Track> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('rating_key')) {
      context.handle(
        _ratingKeyMeta,
        ratingKey.isAcceptableOrUnknown(data['rating_key']!, _ratingKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_ratingKeyMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('normalised_title')) {
      context.handle(
        _normalisedTitleMeta,
        normalisedTitle.isAcceptableOrUnknown(
          data['normalised_title']!,
          _normalisedTitleMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_normalisedTitleMeta);
    }
    if (data.containsKey('album_rating_key')) {
      context.handle(
        _albumRatingKeyMeta,
        albumRatingKey.isAcceptableOrUnknown(
          data['album_rating_key']!,
          _albumRatingKeyMeta,
        ),
      );
    }
    if (data.containsKey('album_title')) {
      context.handle(
        _albumTitleMeta,
        albumTitle.isAcceptableOrUnknown(data['album_title']!, _albumTitleMeta),
      );
    }
    if (data.containsKey('artist_title')) {
      context.handle(
        _artistTitleMeta,
        artistTitle.isAcceptableOrUnknown(
          data['artist_title']!,
          _artistTitleMeta,
        ),
      );
    }
    if (data.containsKey('track_index')) {
      context.handle(
        _trackIndexMeta,
        trackIndex.isAcceptableOrUnknown(data['track_index']!, _trackIndexMeta),
      );
    }
    if (data.containsKey('disc_index')) {
      context.handle(
        _discIndexMeta,
        discIndex.isAcceptableOrUnknown(data['disc_index']!, _discIndexMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('part_key')) {
      context.handle(
        _partKeyMeta,
        partKey.isAcceptableOrUnknown(data['part_key']!, _partKeyMeta),
      );
    }
    if (data.containsKey('container')) {
      context.handle(
        _containerMeta,
        container.isAcceptableOrUnknown(data['container']!, _containerMeta),
      );
    }
    if (data.containsKey('part_size_bytes')) {
      context.handle(
        _partSizeBytesMeta,
        partSizeBytes.isAcceptableOrUnknown(
          data['part_size_bytes']!,
          _partSizeBytesMeta,
        ),
      );
    }
    if (data.containsKey('thumb')) {
      context.handle(
        _thumbMeta,
        thumb.isAcceptableOrUnknown(data['thumb']!, _thumbMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    }
    if (data.containsKey('last_viewed_at')) {
      context.handle(
        _lastViewedAtMeta,
        lastViewedAt.isAcceptableOrUnknown(
          data['last_viewed_at']!,
          _lastViewedAtMeta,
        ),
      );
    }
    if (data.containsKey('user_rating')) {
      context.handle(
        _userRatingMeta,
        userRating.isAcceptableOrUnknown(data['user_rating']!, _userRatingMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ratingKey};
  @override
  Track map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Track(
      ratingKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rating_key'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      normalisedTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalised_title'],
      )!,
      albumRatingKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_rating_key'],
      ),
      albumTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_title'],
      )!,
      artistTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist_title'],
      )!,
      trackIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}track_index'],
      )!,
      discIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}disc_index'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      partKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}part_key'],
      ),
      container: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}container'],
      ),
      partSizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}part_size_bytes'],
      ),
      thumb: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumb'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      ),
      lastViewedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_viewed_at'],
      ),
      userRating: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}user_rating'],
      ),
    );
  }

  @override
  $TracksTable createAlias(String alias) {
    return $TracksTable(attachedDatabase, alias);
  }
}

class Track extends DataClass implements Insertable<Track> {
  final String ratingKey;
  final String title;
  final String normalisedTitle;
  final String? albumRatingKey;
  final String albumTitle;
  final String artistTitle;

  /// Track number within the album.
  final int trackIndex;
  final int? discIndex;
  final int durationMs;

  /// Path to the actual file, e.g. `/library/parts/5678/1699.../file.flac`.
  /// Null means the track has no playable part.
  final String? partKey;

  /// Container format — used by the quality policy to decide whether the
  /// current platform can direct-play or needs a transcode.
  final String? container;

  /// Media > Part's own `size`, in bytes. Source bitrate is derived from this
  /// and [durationMs] rather than stored directly, so the quality policy asks
  /// nothing Plex didn't already send.
  final int? partSizeBytes;
  final String? thumb;
  final int? updatedAt;
  final int? addedAt;
  final int? lastViewedAt;

  /// Plex `userRating`, 0–10, null when unrated.
  final int? userRating;
  const Track({
    required this.ratingKey,
    required this.title,
    required this.normalisedTitle,
    this.albumRatingKey,
    required this.albumTitle,
    required this.artistTitle,
    required this.trackIndex,
    this.discIndex,
    required this.durationMs,
    this.partKey,
    this.container,
    this.partSizeBytes,
    this.thumb,
    this.updatedAt,
    this.addedAt,
    this.lastViewedAt,
    this.userRating,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['rating_key'] = Variable<String>(ratingKey);
    map['title'] = Variable<String>(title);
    map['normalised_title'] = Variable<String>(normalisedTitle);
    if (!nullToAbsent || albumRatingKey != null) {
      map['album_rating_key'] = Variable<String>(albumRatingKey);
    }
    map['album_title'] = Variable<String>(albumTitle);
    map['artist_title'] = Variable<String>(artistTitle);
    map['track_index'] = Variable<int>(trackIndex);
    if (!nullToAbsent || discIndex != null) {
      map['disc_index'] = Variable<int>(discIndex);
    }
    map['duration_ms'] = Variable<int>(durationMs);
    if (!nullToAbsent || partKey != null) {
      map['part_key'] = Variable<String>(partKey);
    }
    if (!nullToAbsent || container != null) {
      map['container'] = Variable<String>(container);
    }
    if (!nullToAbsent || partSizeBytes != null) {
      map['part_size_bytes'] = Variable<int>(partSizeBytes);
    }
    if (!nullToAbsent || thumb != null) {
      map['thumb'] = Variable<String>(thumb);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<int>(updatedAt);
    }
    if (!nullToAbsent || addedAt != null) {
      map['added_at'] = Variable<int>(addedAt);
    }
    if (!nullToAbsent || lastViewedAt != null) {
      map['last_viewed_at'] = Variable<int>(lastViewedAt);
    }
    if (!nullToAbsent || userRating != null) {
      map['user_rating'] = Variable<int>(userRating);
    }
    return map;
  }

  TracksCompanion toCompanion(bool nullToAbsent) {
    return TracksCompanion(
      ratingKey: Value(ratingKey),
      title: Value(title),
      normalisedTitle: Value(normalisedTitle),
      albumRatingKey: albumRatingKey == null && nullToAbsent
          ? const Value.absent()
          : Value(albumRatingKey),
      albumTitle: Value(albumTitle),
      artistTitle: Value(artistTitle),
      trackIndex: Value(trackIndex),
      discIndex: discIndex == null && nullToAbsent
          ? const Value.absent()
          : Value(discIndex),
      durationMs: Value(durationMs),
      partKey: partKey == null && nullToAbsent
          ? const Value.absent()
          : Value(partKey),
      container: container == null && nullToAbsent
          ? const Value.absent()
          : Value(container),
      partSizeBytes: partSizeBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(partSizeBytes),
      thumb: thumb == null && nullToAbsent
          ? const Value.absent()
          : Value(thumb),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
      addedAt: addedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(addedAt),
      lastViewedAt: lastViewedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastViewedAt),
      userRating: userRating == null && nullToAbsent
          ? const Value.absent()
          : Value(userRating),
    );
  }

  factory Track.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Track(
      ratingKey: serializer.fromJson<String>(json['ratingKey']),
      title: serializer.fromJson<String>(json['title']),
      normalisedTitle: serializer.fromJson<String>(json['normalisedTitle']),
      albumRatingKey: serializer.fromJson<String?>(json['albumRatingKey']),
      albumTitle: serializer.fromJson<String>(json['albumTitle']),
      artistTitle: serializer.fromJson<String>(json['artistTitle']),
      trackIndex: serializer.fromJson<int>(json['trackIndex']),
      discIndex: serializer.fromJson<int?>(json['discIndex']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      partKey: serializer.fromJson<String?>(json['partKey']),
      container: serializer.fromJson<String?>(json['container']),
      partSizeBytes: serializer.fromJson<int?>(json['partSizeBytes']),
      thumb: serializer.fromJson<String?>(json['thumb']),
      updatedAt: serializer.fromJson<int?>(json['updatedAt']),
      addedAt: serializer.fromJson<int?>(json['addedAt']),
      lastViewedAt: serializer.fromJson<int?>(json['lastViewedAt']),
      userRating: serializer.fromJson<int?>(json['userRating']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ratingKey': serializer.toJson<String>(ratingKey),
      'title': serializer.toJson<String>(title),
      'normalisedTitle': serializer.toJson<String>(normalisedTitle),
      'albumRatingKey': serializer.toJson<String?>(albumRatingKey),
      'albumTitle': serializer.toJson<String>(albumTitle),
      'artistTitle': serializer.toJson<String>(artistTitle),
      'trackIndex': serializer.toJson<int>(trackIndex),
      'discIndex': serializer.toJson<int?>(discIndex),
      'durationMs': serializer.toJson<int>(durationMs),
      'partKey': serializer.toJson<String?>(partKey),
      'container': serializer.toJson<String?>(container),
      'partSizeBytes': serializer.toJson<int?>(partSizeBytes),
      'thumb': serializer.toJson<String?>(thumb),
      'updatedAt': serializer.toJson<int?>(updatedAt),
      'addedAt': serializer.toJson<int?>(addedAt),
      'lastViewedAt': serializer.toJson<int?>(lastViewedAt),
      'userRating': serializer.toJson<int?>(userRating),
    };
  }

  Track copyWith({
    String? ratingKey,
    String? title,
    String? normalisedTitle,
    Value<String?> albumRatingKey = const Value.absent(),
    String? albumTitle,
    String? artistTitle,
    int? trackIndex,
    Value<int?> discIndex = const Value.absent(),
    int? durationMs,
    Value<String?> partKey = const Value.absent(),
    Value<String?> container = const Value.absent(),
    Value<int?> partSizeBytes = const Value.absent(),
    Value<String?> thumb = const Value.absent(),
    Value<int?> updatedAt = const Value.absent(),
    Value<int?> addedAt = const Value.absent(),
    Value<int?> lastViewedAt = const Value.absent(),
    Value<int?> userRating = const Value.absent(),
  }) => Track(
    ratingKey: ratingKey ?? this.ratingKey,
    title: title ?? this.title,
    normalisedTitle: normalisedTitle ?? this.normalisedTitle,
    albumRatingKey: albumRatingKey.present
        ? albumRatingKey.value
        : this.albumRatingKey,
    albumTitle: albumTitle ?? this.albumTitle,
    artistTitle: artistTitle ?? this.artistTitle,
    trackIndex: trackIndex ?? this.trackIndex,
    discIndex: discIndex.present ? discIndex.value : this.discIndex,
    durationMs: durationMs ?? this.durationMs,
    partKey: partKey.present ? partKey.value : this.partKey,
    container: container.present ? container.value : this.container,
    partSizeBytes: partSizeBytes.present
        ? partSizeBytes.value
        : this.partSizeBytes,
    thumb: thumb.present ? thumb.value : this.thumb,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
    addedAt: addedAt.present ? addedAt.value : this.addedAt,
    lastViewedAt: lastViewedAt.present ? lastViewedAt.value : this.lastViewedAt,
    userRating: userRating.present ? userRating.value : this.userRating,
  );
  Track copyWithCompanion(TracksCompanion data) {
    return Track(
      ratingKey: data.ratingKey.present ? data.ratingKey.value : this.ratingKey,
      title: data.title.present ? data.title.value : this.title,
      normalisedTitle: data.normalisedTitle.present
          ? data.normalisedTitle.value
          : this.normalisedTitle,
      albumRatingKey: data.albumRatingKey.present
          ? data.albumRatingKey.value
          : this.albumRatingKey,
      albumTitle: data.albumTitle.present
          ? data.albumTitle.value
          : this.albumTitle,
      artistTitle: data.artistTitle.present
          ? data.artistTitle.value
          : this.artistTitle,
      trackIndex: data.trackIndex.present
          ? data.trackIndex.value
          : this.trackIndex,
      discIndex: data.discIndex.present ? data.discIndex.value : this.discIndex,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      partKey: data.partKey.present ? data.partKey.value : this.partKey,
      container: data.container.present ? data.container.value : this.container,
      partSizeBytes: data.partSizeBytes.present
          ? data.partSizeBytes.value
          : this.partSizeBytes,
      thumb: data.thumb.present ? data.thumb.value : this.thumb,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      lastViewedAt: data.lastViewedAt.present
          ? data.lastViewedAt.value
          : this.lastViewedAt,
      userRating: data.userRating.present
          ? data.userRating.value
          : this.userRating,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Track(')
          ..write('ratingKey: $ratingKey, ')
          ..write('title: $title, ')
          ..write('normalisedTitle: $normalisedTitle, ')
          ..write('albumRatingKey: $albumRatingKey, ')
          ..write('albumTitle: $albumTitle, ')
          ..write('artistTitle: $artistTitle, ')
          ..write('trackIndex: $trackIndex, ')
          ..write('discIndex: $discIndex, ')
          ..write('durationMs: $durationMs, ')
          ..write('partKey: $partKey, ')
          ..write('container: $container, ')
          ..write('partSizeBytes: $partSizeBytes, ')
          ..write('thumb: $thumb, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('addedAt: $addedAt, ')
          ..write('lastViewedAt: $lastViewedAt, ')
          ..write('userRating: $userRating')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ratingKey,
    title,
    normalisedTitle,
    albumRatingKey,
    albumTitle,
    artistTitle,
    trackIndex,
    discIndex,
    durationMs,
    partKey,
    container,
    partSizeBytes,
    thumb,
    updatedAt,
    addedAt,
    lastViewedAt,
    userRating,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Track &&
          other.ratingKey == this.ratingKey &&
          other.title == this.title &&
          other.normalisedTitle == this.normalisedTitle &&
          other.albumRatingKey == this.albumRatingKey &&
          other.albumTitle == this.albumTitle &&
          other.artistTitle == this.artistTitle &&
          other.trackIndex == this.trackIndex &&
          other.discIndex == this.discIndex &&
          other.durationMs == this.durationMs &&
          other.partKey == this.partKey &&
          other.container == this.container &&
          other.partSizeBytes == this.partSizeBytes &&
          other.thumb == this.thumb &&
          other.updatedAt == this.updatedAt &&
          other.addedAt == this.addedAt &&
          other.lastViewedAt == this.lastViewedAt &&
          other.userRating == this.userRating);
}

class TracksCompanion extends UpdateCompanion<Track> {
  final Value<String> ratingKey;
  final Value<String> title;
  final Value<String> normalisedTitle;
  final Value<String?> albumRatingKey;
  final Value<String> albumTitle;
  final Value<String> artistTitle;
  final Value<int> trackIndex;
  final Value<int?> discIndex;
  final Value<int> durationMs;
  final Value<String?> partKey;
  final Value<String?> container;
  final Value<int?> partSizeBytes;
  final Value<String?> thumb;
  final Value<int?> updatedAt;
  final Value<int?> addedAt;
  final Value<int?> lastViewedAt;
  final Value<int?> userRating;
  final Value<int> rowid;
  const TracksCompanion({
    this.ratingKey = const Value.absent(),
    this.title = const Value.absent(),
    this.normalisedTitle = const Value.absent(),
    this.albumRatingKey = const Value.absent(),
    this.albumTitle = const Value.absent(),
    this.artistTitle = const Value.absent(),
    this.trackIndex = const Value.absent(),
    this.discIndex = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.partKey = const Value.absent(),
    this.container = const Value.absent(),
    this.partSizeBytes = const Value.absent(),
    this.thumb = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.lastViewedAt = const Value.absent(),
    this.userRating = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TracksCompanion.insert({
    required String ratingKey,
    required String title,
    required String normalisedTitle,
    this.albumRatingKey = const Value.absent(),
    this.albumTitle = const Value.absent(),
    this.artistTitle = const Value.absent(),
    this.trackIndex = const Value.absent(),
    this.discIndex = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.partKey = const Value.absent(),
    this.container = const Value.absent(),
    this.partSizeBytes = const Value.absent(),
    this.thumb = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.lastViewedAt = const Value.absent(),
    this.userRating = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ratingKey = Value(ratingKey),
       title = Value(title),
       normalisedTitle = Value(normalisedTitle);
  static Insertable<Track> custom({
    Expression<String>? ratingKey,
    Expression<String>? title,
    Expression<String>? normalisedTitle,
    Expression<String>? albumRatingKey,
    Expression<String>? albumTitle,
    Expression<String>? artistTitle,
    Expression<int>? trackIndex,
    Expression<int>? discIndex,
    Expression<int>? durationMs,
    Expression<String>? partKey,
    Expression<String>? container,
    Expression<int>? partSizeBytes,
    Expression<String>? thumb,
    Expression<int>? updatedAt,
    Expression<int>? addedAt,
    Expression<int>? lastViewedAt,
    Expression<int>? userRating,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ratingKey != null) 'rating_key': ratingKey,
      if (title != null) 'title': title,
      if (normalisedTitle != null) 'normalised_title': normalisedTitle,
      if (albumRatingKey != null) 'album_rating_key': albumRatingKey,
      if (albumTitle != null) 'album_title': albumTitle,
      if (artistTitle != null) 'artist_title': artistTitle,
      if (trackIndex != null) 'track_index': trackIndex,
      if (discIndex != null) 'disc_index': discIndex,
      if (durationMs != null) 'duration_ms': durationMs,
      if (partKey != null) 'part_key': partKey,
      if (container != null) 'container': container,
      if (partSizeBytes != null) 'part_size_bytes': partSizeBytes,
      if (thumb != null) 'thumb': thumb,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (addedAt != null) 'added_at': addedAt,
      if (lastViewedAt != null) 'last_viewed_at': lastViewedAt,
      if (userRating != null) 'user_rating': userRating,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TracksCompanion copyWith({
    Value<String>? ratingKey,
    Value<String>? title,
    Value<String>? normalisedTitle,
    Value<String?>? albumRatingKey,
    Value<String>? albumTitle,
    Value<String>? artistTitle,
    Value<int>? trackIndex,
    Value<int?>? discIndex,
    Value<int>? durationMs,
    Value<String?>? partKey,
    Value<String?>? container,
    Value<int?>? partSizeBytes,
    Value<String?>? thumb,
    Value<int?>? updatedAt,
    Value<int?>? addedAt,
    Value<int?>? lastViewedAt,
    Value<int?>? userRating,
    Value<int>? rowid,
  }) {
    return TracksCompanion(
      ratingKey: ratingKey ?? this.ratingKey,
      title: title ?? this.title,
      normalisedTitle: normalisedTitle ?? this.normalisedTitle,
      albumRatingKey: albumRatingKey ?? this.albumRatingKey,
      albumTitle: albumTitle ?? this.albumTitle,
      artistTitle: artistTitle ?? this.artistTitle,
      trackIndex: trackIndex ?? this.trackIndex,
      discIndex: discIndex ?? this.discIndex,
      durationMs: durationMs ?? this.durationMs,
      partKey: partKey ?? this.partKey,
      container: container ?? this.container,
      partSizeBytes: partSizeBytes ?? this.partSizeBytes,
      thumb: thumb ?? this.thumb,
      updatedAt: updatedAt ?? this.updatedAt,
      addedAt: addedAt ?? this.addedAt,
      lastViewedAt: lastViewedAt ?? this.lastViewedAt,
      userRating: userRating ?? this.userRating,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ratingKey.present) {
      map['rating_key'] = Variable<String>(ratingKey.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (normalisedTitle.present) {
      map['normalised_title'] = Variable<String>(normalisedTitle.value);
    }
    if (albumRatingKey.present) {
      map['album_rating_key'] = Variable<String>(albumRatingKey.value);
    }
    if (albumTitle.present) {
      map['album_title'] = Variable<String>(albumTitle.value);
    }
    if (artistTitle.present) {
      map['artist_title'] = Variable<String>(artistTitle.value);
    }
    if (trackIndex.present) {
      map['track_index'] = Variable<int>(trackIndex.value);
    }
    if (discIndex.present) {
      map['disc_index'] = Variable<int>(discIndex.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (partKey.present) {
      map['part_key'] = Variable<String>(partKey.value);
    }
    if (container.present) {
      map['container'] = Variable<String>(container.value);
    }
    if (partSizeBytes.present) {
      map['part_size_bytes'] = Variable<int>(partSizeBytes.value);
    }
    if (thumb.present) {
      map['thumb'] = Variable<String>(thumb.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (lastViewedAt.present) {
      map['last_viewed_at'] = Variable<int>(lastViewedAt.value);
    }
    if (userRating.present) {
      map['user_rating'] = Variable<int>(userRating.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TracksCompanion(')
          ..write('ratingKey: $ratingKey, ')
          ..write('title: $title, ')
          ..write('normalisedTitle: $normalisedTitle, ')
          ..write('albumRatingKey: $albumRatingKey, ')
          ..write('albumTitle: $albumTitle, ')
          ..write('artistTitle: $artistTitle, ')
          ..write('trackIndex: $trackIndex, ')
          ..write('discIndex: $discIndex, ')
          ..write('durationMs: $durationMs, ')
          ..write('partKey: $partKey, ')
          ..write('container: $container, ')
          ..write('partSizeBytes: $partSizeBytes, ')
          ..write('thumb: $thumb, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('addedAt: $addedAt, ')
          ..write('lastViewedAt: $lastViewedAt, ')
          ..write('userRating: $userRating, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlaylistsTable extends Playlists
    with TableInfo<$PlaylistsTable, Playlist> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ratingKeyMeta = const VerificationMeta(
    'ratingKey',
  );
  @override
  late final GeneratedColumn<String> ratingKey = GeneratedColumn<String>(
    'rating_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _normalisedTitleMeta = const VerificationMeta(
    'normalisedTitle',
  );
  @override
  late final GeneratedColumn<String> normalisedTitle = GeneratedColumn<String>(
    'normalised_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _thumbMeta = const VerificationMeta('thumb');
  @override
  late final GeneratedColumn<String> thumb = GeneratedColumn<String>(
    'thumb',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _itemCountMeta = const VerificationMeta(
    'itemCount',
  );
  @override
  late final GeneratedColumn<int> itemCount = GeneratedColumn<int>(
    'item_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastViewedAtMeta = const VerificationMeta(
    'lastViewedAt',
  );
  @override
  late final GeneratedColumn<int> lastViewedAt = GeneratedColumn<int>(
    'last_viewed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _smartMeta = const VerificationMeta('smart');
  @override
  late final GeneratedColumn<bool> smart = GeneratedColumn<bool>(
    'smart',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("smart" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    ratingKey,
    title,
    normalisedTitle,
    thumb,
    itemCount,
    durationMs,
    updatedAt,
    lastViewedAt,
    smart,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlists';
  @override
  VerificationContext validateIntegrity(
    Insertable<Playlist> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('rating_key')) {
      context.handle(
        _ratingKeyMeta,
        ratingKey.isAcceptableOrUnknown(data['rating_key']!, _ratingKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_ratingKeyMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('normalised_title')) {
      context.handle(
        _normalisedTitleMeta,
        normalisedTitle.isAcceptableOrUnknown(
          data['normalised_title']!,
          _normalisedTitleMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_normalisedTitleMeta);
    }
    if (data.containsKey('thumb')) {
      context.handle(
        _thumbMeta,
        thumb.isAcceptableOrUnknown(data['thumb']!, _thumbMeta),
      );
    }
    if (data.containsKey('item_count')) {
      context.handle(
        _itemCountMeta,
        itemCount.isAcceptableOrUnknown(data['item_count']!, _itemCountMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('last_viewed_at')) {
      context.handle(
        _lastViewedAtMeta,
        lastViewedAt.isAcceptableOrUnknown(
          data['last_viewed_at']!,
          _lastViewedAtMeta,
        ),
      );
    }
    if (data.containsKey('smart')) {
      context.handle(
        _smartMeta,
        smart.isAcceptableOrUnknown(data['smart']!, _smartMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ratingKey};
  @override
  Playlist map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Playlist(
      ratingKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rating_key'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      normalisedTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalised_title'],
      )!,
      thumb: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumb'],
      ),
      itemCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}item_count'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      ),
      lastViewedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_viewed_at'],
      ),
      smart: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}smart'],
      )!,
    );
  }

  @override
  $PlaylistsTable createAlias(String alias) {
    return $PlaylistsTable(attachedDatabase, alias);
  }
}

class Playlist extends DataClass implements Insertable<Playlist> {
  final String ratingKey;
  final String title;
  final String normalisedTitle;
  final String? thumb;
  final int itemCount;
  final int? durationMs;
  final int? updatedAt;

  /// Indexed because the sidebar lists playlists by most recently played,
  /// which was a headline requirement.
  final int? lastViewedAt;

  /// True for Plex smart playlists.
  ///
  /// Their contents are computed server-side and change without an `updatedAt`
  /// bump, so a cached copy goes stale silently — these must be revalidated on
  /// open rather than served cache-first.
  final bool smart;
  const Playlist({
    required this.ratingKey,
    required this.title,
    required this.normalisedTitle,
    this.thumb,
    required this.itemCount,
    this.durationMs,
    this.updatedAt,
    this.lastViewedAt,
    required this.smart,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['rating_key'] = Variable<String>(ratingKey);
    map['title'] = Variable<String>(title);
    map['normalised_title'] = Variable<String>(normalisedTitle);
    if (!nullToAbsent || thumb != null) {
      map['thumb'] = Variable<String>(thumb);
    }
    map['item_count'] = Variable<int>(itemCount);
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<int>(updatedAt);
    }
    if (!nullToAbsent || lastViewedAt != null) {
      map['last_viewed_at'] = Variable<int>(lastViewedAt);
    }
    map['smart'] = Variable<bool>(smart);
    return map;
  }

  PlaylistsCompanion toCompanion(bool nullToAbsent) {
    return PlaylistsCompanion(
      ratingKey: Value(ratingKey),
      title: Value(title),
      normalisedTitle: Value(normalisedTitle),
      thumb: thumb == null && nullToAbsent
          ? const Value.absent()
          : Value(thumb),
      itemCount: Value(itemCount),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
      lastViewedAt: lastViewedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastViewedAt),
      smart: Value(smart),
    );
  }

  factory Playlist.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Playlist(
      ratingKey: serializer.fromJson<String>(json['ratingKey']),
      title: serializer.fromJson<String>(json['title']),
      normalisedTitle: serializer.fromJson<String>(json['normalisedTitle']),
      thumb: serializer.fromJson<String?>(json['thumb']),
      itemCount: serializer.fromJson<int>(json['itemCount']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      updatedAt: serializer.fromJson<int?>(json['updatedAt']),
      lastViewedAt: serializer.fromJson<int?>(json['lastViewedAt']),
      smart: serializer.fromJson<bool>(json['smart']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ratingKey': serializer.toJson<String>(ratingKey),
      'title': serializer.toJson<String>(title),
      'normalisedTitle': serializer.toJson<String>(normalisedTitle),
      'thumb': serializer.toJson<String?>(thumb),
      'itemCount': serializer.toJson<int>(itemCount),
      'durationMs': serializer.toJson<int?>(durationMs),
      'updatedAt': serializer.toJson<int?>(updatedAt),
      'lastViewedAt': serializer.toJson<int?>(lastViewedAt),
      'smart': serializer.toJson<bool>(smart),
    };
  }

  Playlist copyWith({
    String? ratingKey,
    String? title,
    String? normalisedTitle,
    Value<String?> thumb = const Value.absent(),
    int? itemCount,
    Value<int?> durationMs = const Value.absent(),
    Value<int?> updatedAt = const Value.absent(),
    Value<int?> lastViewedAt = const Value.absent(),
    bool? smart,
  }) => Playlist(
    ratingKey: ratingKey ?? this.ratingKey,
    title: title ?? this.title,
    normalisedTitle: normalisedTitle ?? this.normalisedTitle,
    thumb: thumb.present ? thumb.value : this.thumb,
    itemCount: itemCount ?? this.itemCount,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
    lastViewedAt: lastViewedAt.present ? lastViewedAt.value : this.lastViewedAt,
    smart: smart ?? this.smart,
  );
  Playlist copyWithCompanion(PlaylistsCompanion data) {
    return Playlist(
      ratingKey: data.ratingKey.present ? data.ratingKey.value : this.ratingKey,
      title: data.title.present ? data.title.value : this.title,
      normalisedTitle: data.normalisedTitle.present
          ? data.normalisedTitle.value
          : this.normalisedTitle,
      thumb: data.thumb.present ? data.thumb.value : this.thumb,
      itemCount: data.itemCount.present ? data.itemCount.value : this.itemCount,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      lastViewedAt: data.lastViewedAt.present
          ? data.lastViewedAt.value
          : this.lastViewedAt,
      smart: data.smart.present ? data.smart.value : this.smart,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Playlist(')
          ..write('ratingKey: $ratingKey, ')
          ..write('title: $title, ')
          ..write('normalisedTitle: $normalisedTitle, ')
          ..write('thumb: $thumb, ')
          ..write('itemCount: $itemCount, ')
          ..write('durationMs: $durationMs, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastViewedAt: $lastViewedAt, ')
          ..write('smart: $smart')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ratingKey,
    title,
    normalisedTitle,
    thumb,
    itemCount,
    durationMs,
    updatedAt,
    lastViewedAt,
    smart,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Playlist &&
          other.ratingKey == this.ratingKey &&
          other.title == this.title &&
          other.normalisedTitle == this.normalisedTitle &&
          other.thumb == this.thumb &&
          other.itemCount == this.itemCount &&
          other.durationMs == this.durationMs &&
          other.updatedAt == this.updatedAt &&
          other.lastViewedAt == this.lastViewedAt &&
          other.smart == this.smart);
}

class PlaylistsCompanion extends UpdateCompanion<Playlist> {
  final Value<String> ratingKey;
  final Value<String> title;
  final Value<String> normalisedTitle;
  final Value<String?> thumb;
  final Value<int> itemCount;
  final Value<int?> durationMs;
  final Value<int?> updatedAt;
  final Value<int?> lastViewedAt;
  final Value<bool> smart;
  final Value<int> rowid;
  const PlaylistsCompanion({
    this.ratingKey = const Value.absent(),
    this.title = const Value.absent(),
    this.normalisedTitle = const Value.absent(),
    this.thumb = const Value.absent(),
    this.itemCount = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.lastViewedAt = const Value.absent(),
    this.smart = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaylistsCompanion.insert({
    required String ratingKey,
    required String title,
    required String normalisedTitle,
    this.thumb = const Value.absent(),
    this.itemCount = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.lastViewedAt = const Value.absent(),
    this.smart = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ratingKey = Value(ratingKey),
       title = Value(title),
       normalisedTitle = Value(normalisedTitle);
  static Insertable<Playlist> custom({
    Expression<String>? ratingKey,
    Expression<String>? title,
    Expression<String>? normalisedTitle,
    Expression<String>? thumb,
    Expression<int>? itemCount,
    Expression<int>? durationMs,
    Expression<int>? updatedAt,
    Expression<int>? lastViewedAt,
    Expression<bool>? smart,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ratingKey != null) 'rating_key': ratingKey,
      if (title != null) 'title': title,
      if (normalisedTitle != null) 'normalised_title': normalisedTitle,
      if (thumb != null) 'thumb': thumb,
      if (itemCount != null) 'item_count': itemCount,
      if (durationMs != null) 'duration_ms': durationMs,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (lastViewedAt != null) 'last_viewed_at': lastViewedAt,
      if (smart != null) 'smart': smart,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaylistsCompanion copyWith({
    Value<String>? ratingKey,
    Value<String>? title,
    Value<String>? normalisedTitle,
    Value<String?>? thumb,
    Value<int>? itemCount,
    Value<int?>? durationMs,
    Value<int?>? updatedAt,
    Value<int?>? lastViewedAt,
    Value<bool>? smart,
    Value<int>? rowid,
  }) {
    return PlaylistsCompanion(
      ratingKey: ratingKey ?? this.ratingKey,
      title: title ?? this.title,
      normalisedTitle: normalisedTitle ?? this.normalisedTitle,
      thumb: thumb ?? this.thumb,
      itemCount: itemCount ?? this.itemCount,
      durationMs: durationMs ?? this.durationMs,
      updatedAt: updatedAt ?? this.updatedAt,
      lastViewedAt: lastViewedAt ?? this.lastViewedAt,
      smart: smart ?? this.smart,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ratingKey.present) {
      map['rating_key'] = Variable<String>(ratingKey.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (normalisedTitle.present) {
      map['normalised_title'] = Variable<String>(normalisedTitle.value);
    }
    if (thumb.present) {
      map['thumb'] = Variable<String>(thumb.value);
    }
    if (itemCount.present) {
      map['item_count'] = Variable<int>(itemCount.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (lastViewedAt.present) {
      map['last_viewed_at'] = Variable<int>(lastViewedAt.value);
    }
    if (smart.present) {
      map['smart'] = Variable<bool>(smart.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistsCompanion(')
          ..write('ratingKey: $ratingKey, ')
          ..write('title: $title, ')
          ..write('normalisedTitle: $normalisedTitle, ')
          ..write('thumb: $thumb, ')
          ..write('itemCount: $itemCount, ')
          ..write('durationMs: $durationMs, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastViewedAt: $lastViewedAt, ')
          ..write('smart: $smart, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlaylistItemsTable extends PlaylistItems
    with TableInfo<$PlaylistItemsTable, PlaylistItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _playlistRatingKeyMeta = const VerificationMeta(
    'playlistRatingKey',
  );
  @override
  late final GeneratedColumn<String> playlistRatingKey =
      GeneratedColumn<String>(
        'playlist_rating_key',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _trackRatingKeyMeta = const VerificationMeta(
    'trackRatingKey',
  );
  @override
  late final GeneratedColumn<String> trackRatingKey = GeneratedColumn<String>(
    'track_rating_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    playlistRatingKey,
    trackRatingKey,
    position,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlist_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaylistItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('playlist_rating_key')) {
      context.handle(
        _playlistRatingKeyMeta,
        playlistRatingKey.isAcceptableOrUnknown(
          data['playlist_rating_key']!,
          _playlistRatingKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_playlistRatingKeyMeta);
    }
    if (data.containsKey('track_rating_key')) {
      context.handle(
        _trackRatingKeyMeta,
        trackRatingKey.isAcceptableOrUnknown(
          data['track_rating_key']!,
          _trackRatingKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_trackRatingKeyMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {playlistRatingKey, position};
  @override
  PlaylistItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaylistItem(
      playlistRatingKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_rating_key'],
      )!,
      trackRatingKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_rating_key'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $PlaylistItemsTable createAlias(String alias) {
    return $PlaylistItemsTable(attachedDatabase, alias);
  }
}

class PlaylistItem extends DataClass implements Insertable<PlaylistItem> {
  final String playlistRatingKey;
  final String trackRatingKey;

  /// Explicit ordering — playlists are not sorted, they are arranged.
  final int position;
  const PlaylistItem({
    required this.playlistRatingKey,
    required this.trackRatingKey,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['playlist_rating_key'] = Variable<String>(playlistRatingKey);
    map['track_rating_key'] = Variable<String>(trackRatingKey);
    map['position'] = Variable<int>(position);
    return map;
  }

  PlaylistItemsCompanion toCompanion(bool nullToAbsent) {
    return PlaylistItemsCompanion(
      playlistRatingKey: Value(playlistRatingKey),
      trackRatingKey: Value(trackRatingKey),
      position: Value(position),
    );
  }

  factory PlaylistItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaylistItem(
      playlistRatingKey: serializer.fromJson<String>(json['playlistRatingKey']),
      trackRatingKey: serializer.fromJson<String>(json['trackRatingKey']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'playlistRatingKey': serializer.toJson<String>(playlistRatingKey),
      'trackRatingKey': serializer.toJson<String>(trackRatingKey),
      'position': serializer.toJson<int>(position),
    };
  }

  PlaylistItem copyWith({
    String? playlistRatingKey,
    String? trackRatingKey,
    int? position,
  }) => PlaylistItem(
    playlistRatingKey: playlistRatingKey ?? this.playlistRatingKey,
    trackRatingKey: trackRatingKey ?? this.trackRatingKey,
    position: position ?? this.position,
  );
  PlaylistItem copyWithCompanion(PlaylistItemsCompanion data) {
    return PlaylistItem(
      playlistRatingKey: data.playlistRatingKey.present
          ? data.playlistRatingKey.value
          : this.playlistRatingKey,
      trackRatingKey: data.trackRatingKey.present
          ? data.trackRatingKey.value
          : this.trackRatingKey,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistItem(')
          ..write('playlistRatingKey: $playlistRatingKey, ')
          ..write('trackRatingKey: $trackRatingKey, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(playlistRatingKey, trackRatingKey, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaylistItem &&
          other.playlistRatingKey == this.playlistRatingKey &&
          other.trackRatingKey == this.trackRatingKey &&
          other.position == this.position);
}

class PlaylistItemsCompanion extends UpdateCompanion<PlaylistItem> {
  final Value<String> playlistRatingKey;
  final Value<String> trackRatingKey;
  final Value<int> position;
  final Value<int> rowid;
  const PlaylistItemsCompanion({
    this.playlistRatingKey = const Value.absent(),
    this.trackRatingKey = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaylistItemsCompanion.insert({
    required String playlistRatingKey,
    required String trackRatingKey,
    required int position,
    this.rowid = const Value.absent(),
  }) : playlistRatingKey = Value(playlistRatingKey),
       trackRatingKey = Value(trackRatingKey),
       position = Value(position);
  static Insertable<PlaylistItem> custom({
    Expression<String>? playlistRatingKey,
    Expression<String>? trackRatingKey,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (playlistRatingKey != null) 'playlist_rating_key': playlistRatingKey,
      if (trackRatingKey != null) 'track_rating_key': trackRatingKey,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaylistItemsCompanion copyWith({
    Value<String>? playlistRatingKey,
    Value<String>? trackRatingKey,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return PlaylistItemsCompanion(
      playlistRatingKey: playlistRatingKey ?? this.playlistRatingKey,
      trackRatingKey: trackRatingKey ?? this.trackRatingKey,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (playlistRatingKey.present) {
      map['playlist_rating_key'] = Variable<String>(playlistRatingKey.value);
    }
    if (trackRatingKey.present) {
      map['track_rating_key'] = Variable<String>(trackRatingKey.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistItemsCompanion(')
          ..write('playlistRatingKey: $playlistRatingKey, ')
          ..write('trackRatingKey: $trackRatingKey, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncStateTable extends SyncState
    with TableInfo<$SyncStateTable, SyncStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sectionKeyMeta = const VerificationMeta(
    'sectionKey',
  );
  @override
  late final GeneratedColumn<String> sectionKey = GeneratedColumn<String>(
    'section_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverClientIdentifierMeta =
      const VerificationMeta('serverClientIdentifier');
  @override
  late final GeneratedColumn<String> serverClientIdentifier =
      GeneratedColumn<String>(
        'server_client_identifier',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _lastSyncedUpdatedAtMeta =
      const VerificationMeta('lastSyncedUpdatedAt');
  @override
  late final GeneratedColumn<int> lastSyncedUpdatedAt = GeneratedColumn<int>(
    'last_synced_updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _serverUpdatedAtMeta = const VerificationMeta(
    'serverUpdatedAt',
  );
  @override
  late final GeneratedColumn<int> serverUpdatedAt = GeneratedColumn<int>(
    'server_updated_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverScannedAtMeta = const VerificationMeta(
    'serverScannedAt',
  );
  @override
  late final GeneratedColumn<int> serverScannedAt = GeneratedColumn<int>(
    'server_scanned_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _initialSyncCompleteMeta =
      const VerificationMeta('initialSyncComplete');
  @override
  late final GeneratedColumn<bool> initialSyncComplete = GeneratedColumn<bool>(
    'initial_sync_complete',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("initial_sync_complete" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _lastReconcileAtMeta = const VerificationMeta(
    'lastReconcileAt',
  );
  @override
  late final GeneratedColumn<int> lastReconcileAt = GeneratedColumn<int>(
    'last_reconcile_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sectionKey,
    serverClientIdentifier,
    lastSyncedUpdatedAt,
    serverUpdatedAt,
    serverScannedAt,
    initialSyncComplete,
    lastReconcileAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncStateData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('section_key')) {
      context.handle(
        _sectionKeyMeta,
        sectionKey.isAcceptableOrUnknown(data['section_key']!, _sectionKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_sectionKeyMeta);
    }
    if (data.containsKey('server_client_identifier')) {
      context.handle(
        _serverClientIdentifierMeta,
        serverClientIdentifier.isAcceptableOrUnknown(
          data['server_client_identifier']!,
          _serverClientIdentifierMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_serverClientIdentifierMeta);
    }
    if (data.containsKey('last_synced_updated_at')) {
      context.handle(
        _lastSyncedUpdatedAtMeta,
        lastSyncedUpdatedAt.isAcceptableOrUnknown(
          data['last_synced_updated_at']!,
          _lastSyncedUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('server_updated_at')) {
      context.handle(
        _serverUpdatedAtMeta,
        serverUpdatedAt.isAcceptableOrUnknown(
          data['server_updated_at']!,
          _serverUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('server_scanned_at')) {
      context.handle(
        _serverScannedAtMeta,
        serverScannedAt.isAcceptableOrUnknown(
          data['server_scanned_at']!,
          _serverScannedAtMeta,
        ),
      );
    }
    if (data.containsKey('initial_sync_complete')) {
      context.handle(
        _initialSyncCompleteMeta,
        initialSyncComplete.isAcceptableOrUnknown(
          data['initial_sync_complete']!,
          _initialSyncCompleteMeta,
        ),
      );
    }
    if (data.containsKey('last_reconcile_at')) {
      context.handle(
        _lastReconcileAtMeta,
        lastReconcileAt.isAcceptableOrUnknown(
          data['last_reconcile_at']!,
          _lastReconcileAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sectionKey};
  @override
  SyncStateData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncStateData(
      sectionKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}section_key'],
      )!,
      serverClientIdentifier: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_client_identifier'],
      )!,
      lastSyncedUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_synced_updated_at'],
      )!,
      serverUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_updated_at'],
      ),
      serverScannedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_scanned_at'],
      ),
      initialSyncComplete: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}initial_sync_complete'],
      )!,
      lastReconcileAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_reconcile_at'],
      ),
    );
  }

  @override
  $SyncStateTable createAlias(String alias) {
    return $SyncStateTable(attachedDatabase, alias);
  }
}

class SyncStateData extends DataClass implements Insertable<SyncStateData> {
  final String sectionKey;
  final String serverClientIdentifier;

  /// Our clock: the newest `updatedAt` we have successfully stored. Delta sync
  /// asks Plex only for rows at or after this.
  final int lastSyncedUpdatedAt;

  /// Plex's clock, from `/library/sections`. Comparing these two is the cheap
  /// change-detection tier — one small response tells us whether a delta sync
  /// is worth doing at all.
  final int? serverUpdatedAt;
  final int? serverScannedAt;

  /// False until the first full pass finishes, so an interrupted initial sync
  /// resumes rather than being mistaken for an up-to-date cache.
  final bool initialSyncComplete;

  /// Wall-clock time of the last completed reconcile, which is how deletions
  /// are eventually noticed.
  final int? lastReconcileAt;
  const SyncStateData({
    required this.sectionKey,
    required this.serverClientIdentifier,
    required this.lastSyncedUpdatedAt,
    this.serverUpdatedAt,
    this.serverScannedAt,
    required this.initialSyncComplete,
    this.lastReconcileAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['section_key'] = Variable<String>(sectionKey);
    map['server_client_identifier'] = Variable<String>(serverClientIdentifier);
    map['last_synced_updated_at'] = Variable<int>(lastSyncedUpdatedAt);
    if (!nullToAbsent || serverUpdatedAt != null) {
      map['server_updated_at'] = Variable<int>(serverUpdatedAt);
    }
    if (!nullToAbsent || serverScannedAt != null) {
      map['server_scanned_at'] = Variable<int>(serverScannedAt);
    }
    map['initial_sync_complete'] = Variable<bool>(initialSyncComplete);
    if (!nullToAbsent || lastReconcileAt != null) {
      map['last_reconcile_at'] = Variable<int>(lastReconcileAt);
    }
    return map;
  }

  SyncStateCompanion toCompanion(bool nullToAbsent) {
    return SyncStateCompanion(
      sectionKey: Value(sectionKey),
      serverClientIdentifier: Value(serverClientIdentifier),
      lastSyncedUpdatedAt: Value(lastSyncedUpdatedAt),
      serverUpdatedAt: serverUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAt),
      serverScannedAt: serverScannedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverScannedAt),
      initialSyncComplete: Value(initialSyncComplete),
      lastReconcileAt: lastReconcileAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReconcileAt),
    );
  }

  factory SyncStateData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncStateData(
      sectionKey: serializer.fromJson<String>(json['sectionKey']),
      serverClientIdentifier: serializer.fromJson<String>(
        json['serverClientIdentifier'],
      ),
      lastSyncedUpdatedAt: serializer.fromJson<int>(
        json['lastSyncedUpdatedAt'],
      ),
      serverUpdatedAt: serializer.fromJson<int?>(json['serverUpdatedAt']),
      serverScannedAt: serializer.fromJson<int?>(json['serverScannedAt']),
      initialSyncComplete: serializer.fromJson<bool>(
        json['initialSyncComplete'],
      ),
      lastReconcileAt: serializer.fromJson<int?>(json['lastReconcileAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sectionKey': serializer.toJson<String>(sectionKey),
      'serverClientIdentifier': serializer.toJson<String>(
        serverClientIdentifier,
      ),
      'lastSyncedUpdatedAt': serializer.toJson<int>(lastSyncedUpdatedAt),
      'serverUpdatedAt': serializer.toJson<int?>(serverUpdatedAt),
      'serverScannedAt': serializer.toJson<int?>(serverScannedAt),
      'initialSyncComplete': serializer.toJson<bool>(initialSyncComplete),
      'lastReconcileAt': serializer.toJson<int?>(lastReconcileAt),
    };
  }

  SyncStateData copyWith({
    String? sectionKey,
    String? serverClientIdentifier,
    int? lastSyncedUpdatedAt,
    Value<int?> serverUpdatedAt = const Value.absent(),
    Value<int?> serverScannedAt = const Value.absent(),
    bool? initialSyncComplete,
    Value<int?> lastReconcileAt = const Value.absent(),
  }) => SyncStateData(
    sectionKey: sectionKey ?? this.sectionKey,
    serverClientIdentifier:
        serverClientIdentifier ?? this.serverClientIdentifier,
    lastSyncedUpdatedAt: lastSyncedUpdatedAt ?? this.lastSyncedUpdatedAt,
    serverUpdatedAt: serverUpdatedAt.present
        ? serverUpdatedAt.value
        : this.serverUpdatedAt,
    serverScannedAt: serverScannedAt.present
        ? serverScannedAt.value
        : this.serverScannedAt,
    initialSyncComplete: initialSyncComplete ?? this.initialSyncComplete,
    lastReconcileAt: lastReconcileAt.present
        ? lastReconcileAt.value
        : this.lastReconcileAt,
  );
  SyncStateData copyWithCompanion(SyncStateCompanion data) {
    return SyncStateData(
      sectionKey: data.sectionKey.present
          ? data.sectionKey.value
          : this.sectionKey,
      serverClientIdentifier: data.serverClientIdentifier.present
          ? data.serverClientIdentifier.value
          : this.serverClientIdentifier,
      lastSyncedUpdatedAt: data.lastSyncedUpdatedAt.present
          ? data.lastSyncedUpdatedAt.value
          : this.lastSyncedUpdatedAt,
      serverUpdatedAt: data.serverUpdatedAt.present
          ? data.serverUpdatedAt.value
          : this.serverUpdatedAt,
      serverScannedAt: data.serverScannedAt.present
          ? data.serverScannedAt.value
          : this.serverScannedAt,
      initialSyncComplete: data.initialSyncComplete.present
          ? data.initialSyncComplete.value
          : this.initialSyncComplete,
      lastReconcileAt: data.lastReconcileAt.present
          ? data.lastReconcileAt.value
          : this.lastReconcileAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateData(')
          ..write('sectionKey: $sectionKey, ')
          ..write('serverClientIdentifier: $serverClientIdentifier, ')
          ..write('lastSyncedUpdatedAt: $lastSyncedUpdatedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('serverScannedAt: $serverScannedAt, ')
          ..write('initialSyncComplete: $initialSyncComplete, ')
          ..write('lastReconcileAt: $lastReconcileAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sectionKey,
    serverClientIdentifier,
    lastSyncedUpdatedAt,
    serverUpdatedAt,
    serverScannedAt,
    initialSyncComplete,
    lastReconcileAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStateData &&
          other.sectionKey == this.sectionKey &&
          other.serverClientIdentifier == this.serverClientIdentifier &&
          other.lastSyncedUpdatedAt == this.lastSyncedUpdatedAt &&
          other.serverUpdatedAt == this.serverUpdatedAt &&
          other.serverScannedAt == this.serverScannedAt &&
          other.initialSyncComplete == this.initialSyncComplete &&
          other.lastReconcileAt == this.lastReconcileAt);
}

class SyncStateCompanion extends UpdateCompanion<SyncStateData> {
  final Value<String> sectionKey;
  final Value<String> serverClientIdentifier;
  final Value<int> lastSyncedUpdatedAt;
  final Value<int?> serverUpdatedAt;
  final Value<int?> serverScannedAt;
  final Value<bool> initialSyncComplete;
  final Value<int?> lastReconcileAt;
  final Value<int> rowid;
  const SyncStateCompanion({
    this.sectionKey = const Value.absent(),
    this.serverClientIdentifier = const Value.absent(),
    this.lastSyncedUpdatedAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.serverScannedAt = const Value.absent(),
    this.initialSyncComplete = const Value.absent(),
    this.lastReconcileAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncStateCompanion.insert({
    required String sectionKey,
    required String serverClientIdentifier,
    this.lastSyncedUpdatedAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.serverScannedAt = const Value.absent(),
    this.initialSyncComplete = const Value.absent(),
    this.lastReconcileAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sectionKey = Value(sectionKey),
       serverClientIdentifier = Value(serverClientIdentifier);
  static Insertable<SyncStateData> custom({
    Expression<String>? sectionKey,
    Expression<String>? serverClientIdentifier,
    Expression<int>? lastSyncedUpdatedAt,
    Expression<int>? serverUpdatedAt,
    Expression<int>? serverScannedAt,
    Expression<bool>? initialSyncComplete,
    Expression<int>? lastReconcileAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sectionKey != null) 'section_key': sectionKey,
      if (serverClientIdentifier != null)
        'server_client_identifier': serverClientIdentifier,
      if (lastSyncedUpdatedAt != null)
        'last_synced_updated_at': lastSyncedUpdatedAt,
      if (serverUpdatedAt != null) 'server_updated_at': serverUpdatedAt,
      if (serverScannedAt != null) 'server_scanned_at': serverScannedAt,
      if (initialSyncComplete != null)
        'initial_sync_complete': initialSyncComplete,
      if (lastReconcileAt != null) 'last_reconcile_at': lastReconcileAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncStateCompanion copyWith({
    Value<String>? sectionKey,
    Value<String>? serverClientIdentifier,
    Value<int>? lastSyncedUpdatedAt,
    Value<int?>? serverUpdatedAt,
    Value<int?>? serverScannedAt,
    Value<bool>? initialSyncComplete,
    Value<int?>? lastReconcileAt,
    Value<int>? rowid,
  }) {
    return SyncStateCompanion(
      sectionKey: sectionKey ?? this.sectionKey,
      serverClientIdentifier:
          serverClientIdentifier ?? this.serverClientIdentifier,
      lastSyncedUpdatedAt: lastSyncedUpdatedAt ?? this.lastSyncedUpdatedAt,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      serverScannedAt: serverScannedAt ?? this.serverScannedAt,
      initialSyncComplete: initialSyncComplete ?? this.initialSyncComplete,
      lastReconcileAt: lastReconcileAt ?? this.lastReconcileAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sectionKey.present) {
      map['section_key'] = Variable<String>(sectionKey.value);
    }
    if (serverClientIdentifier.present) {
      map['server_client_identifier'] = Variable<String>(
        serverClientIdentifier.value,
      );
    }
    if (lastSyncedUpdatedAt.present) {
      map['last_synced_updated_at'] = Variable<int>(lastSyncedUpdatedAt.value);
    }
    if (serverUpdatedAt.present) {
      map['server_updated_at'] = Variable<int>(serverUpdatedAt.value);
    }
    if (serverScannedAt.present) {
      map['server_scanned_at'] = Variable<int>(serverScannedAt.value);
    }
    if (initialSyncComplete.present) {
      map['initial_sync_complete'] = Variable<bool>(initialSyncComplete.value);
    }
    if (lastReconcileAt.present) {
      map['last_reconcile_at'] = Variable<int>(lastReconcileAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateCompanion(')
          ..write('sectionKey: $sectionKey, ')
          ..write('serverClientIdentifier: $serverClientIdentifier, ')
          ..write('lastSyncedUpdatedAt: $lastSyncedUpdatedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('serverScannedAt: $serverScannedAt, ')
          ..write('initialSyncComplete: $initialSyncComplete, ')
          ..write('lastReconcileAt: $lastReconcileAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ArtistsTable artists = $ArtistsTable(this);
  late final $AlbumsTable albums = $AlbumsTable(this);
  late final $TracksTable tracks = $TracksTable(this);
  late final $PlaylistsTable playlists = $PlaylistsTable(this);
  late final $PlaylistItemsTable playlistItems = $PlaylistItemsTable(this);
  late final $SyncStateTable syncState = $SyncStateTable(this);
  late final Index idxArtistsNorm = Index(
    'idx_artists_norm',
    'CREATE INDEX idx_artists_norm ON artists (normalised_title)',
  );
  late final Index idxAlbumsNormTitle = Index(
    'idx_albums_norm_title',
    'CREATE INDEX idx_albums_norm_title ON albums (normalised_title)',
  );
  late final Index idxAlbumsNormArtist = Index(
    'idx_albums_norm_artist',
    'CREATE INDEX idx_albums_norm_artist ON albums (normalised_artist)',
  );
  late final Index idxAlbumsArtistKey = Index(
    'idx_albums_artist_key',
    'CREATE INDEX idx_albums_artist_key ON albums (artist_rating_key)',
  );
  late final Index idxAlbumsAdded = Index(
    'idx_albums_added',
    'CREATE INDEX idx_albums_added ON albums (added_at)',
  );
  late final Index idxAlbumsRating = Index(
    'idx_albums_rating',
    'CREATE INDEX idx_albums_rating ON albums (user_rating)',
  );
  late final Index idxTracksNorm = Index(
    'idx_tracks_norm',
    'CREATE INDEX idx_tracks_norm ON tracks (normalised_title)',
  );
  late final Index idxTracksAlbum = Index(
    'idx_tracks_album',
    'CREATE INDEX idx_tracks_album ON tracks (album_rating_key)',
  );
  late final Index idxPlaylistsViewed = Index(
    'idx_playlists_viewed',
    'CREATE INDEX idx_playlists_viewed ON playlists (last_viewed_at)',
  );
  late final Index idxPlaylistItemsPlaylist = Index(
    'idx_playlist_items_playlist',
    'CREATE INDEX idx_playlist_items_playlist ON playlist_items (playlist_rating_key)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    artists,
    albums,
    tracks,
    playlists,
    playlistItems,
    syncState,
    idxArtistsNorm,
    idxAlbumsNormTitle,
    idxAlbumsNormArtist,
    idxAlbumsArtistKey,
    idxAlbumsAdded,
    idxAlbumsRating,
    idxTracksNorm,
    idxTracksAlbum,
    idxPlaylistsViewed,
    idxPlaylistItemsPlaylist,
  ];
}

typedef $$ArtistsTableCreateCompanionBuilder =
    ArtistsCompanion Function({
      required String ratingKey,
      required String title,
      required String normalisedTitle,
      Value<String?> thumb,
      Value<int?> updatedAt,
      Value<int?> addedAt,
      Value<int> rowid,
    });
typedef $$ArtistsTableUpdateCompanionBuilder =
    ArtistsCompanion Function({
      Value<String> ratingKey,
      Value<String> title,
      Value<String> normalisedTitle,
      Value<String?> thumb,
      Value<int?> updatedAt,
      Value<int?> addedAt,
      Value<int> rowid,
    });

class $$ArtistsTableFilterComposer
    extends Composer<_$AppDatabase, $ArtistsTable> {
  $$ArtistsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ratingKey => $composableBuilder(
    column: $table.ratingKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalisedTitle => $composableBuilder(
    column: $table.normalisedTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumb => $composableBuilder(
    column: $table.thumb,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ArtistsTableOrderingComposer
    extends Composer<_$AppDatabase, $ArtistsTable> {
  $$ArtistsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ratingKey => $composableBuilder(
    column: $table.ratingKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalisedTitle => $composableBuilder(
    column: $table.normalisedTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumb => $composableBuilder(
    column: $table.thumb,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ArtistsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ArtistsTable> {
  $$ArtistsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ratingKey =>
      $composableBuilder(column: $table.ratingKey, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get normalisedTitle => $composableBuilder(
    column: $table.normalisedTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thumb =>
      $composableBuilder(column: $table.thumb, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$ArtistsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ArtistsTable,
          Artist,
          $$ArtistsTableFilterComposer,
          $$ArtistsTableOrderingComposer,
          $$ArtistsTableAnnotationComposer,
          $$ArtistsTableCreateCompanionBuilder,
          $$ArtistsTableUpdateCompanionBuilder,
          (Artist, BaseReferences<_$AppDatabase, $ArtistsTable, Artist>),
          Artist,
          PrefetchHooks Function()
        > {
  $$ArtistsTableTableManager(_$AppDatabase db, $ArtistsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ArtistsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ArtistsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ArtistsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ratingKey = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> normalisedTitle = const Value.absent(),
                Value<String?> thumb = const Value.absent(),
                Value<int?> updatedAt = const Value.absent(),
                Value<int?> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ArtistsCompanion(
                ratingKey: ratingKey,
                title: title,
                normalisedTitle: normalisedTitle,
                thumb: thumb,
                updatedAt: updatedAt,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ratingKey,
                required String title,
                required String normalisedTitle,
                Value<String?> thumb = const Value.absent(),
                Value<int?> updatedAt = const Value.absent(),
                Value<int?> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ArtistsCompanion.insert(
                ratingKey: ratingKey,
                title: title,
                normalisedTitle: normalisedTitle,
                thumb: thumb,
                updatedAt: updatedAt,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ArtistsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ArtistsTable,
      Artist,
      $$ArtistsTableFilterComposer,
      $$ArtistsTableOrderingComposer,
      $$ArtistsTableAnnotationComposer,
      $$ArtistsTableCreateCompanionBuilder,
      $$ArtistsTableUpdateCompanionBuilder,
      (Artist, BaseReferences<_$AppDatabase, $ArtistsTable, Artist>),
      Artist,
      PrefetchHooks Function()
    >;
typedef $$AlbumsTableCreateCompanionBuilder =
    AlbumsCompanion Function({
      required String ratingKey,
      required String title,
      required String normalisedTitle,
      Value<String?> artistRatingKey,
      required String artistTitle,
      required String normalisedArtist,
      Value<String?> thumb,
      Value<int?> year,
      Value<int?> updatedAt,
      Value<int?> addedAt,
      Value<int?> lastViewedAt,
      Value<String?> mbid,
      Value<int?> userRating,
      Value<int> rowid,
    });
typedef $$AlbumsTableUpdateCompanionBuilder =
    AlbumsCompanion Function({
      Value<String> ratingKey,
      Value<String> title,
      Value<String> normalisedTitle,
      Value<String?> artistRatingKey,
      Value<String> artistTitle,
      Value<String> normalisedArtist,
      Value<String?> thumb,
      Value<int?> year,
      Value<int?> updatedAt,
      Value<int?> addedAt,
      Value<int?> lastViewedAt,
      Value<String?> mbid,
      Value<int?> userRating,
      Value<int> rowid,
    });

class $$AlbumsTableFilterComposer
    extends Composer<_$AppDatabase, $AlbumsTable> {
  $$AlbumsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ratingKey => $composableBuilder(
    column: $table.ratingKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalisedTitle => $composableBuilder(
    column: $table.normalisedTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artistRatingKey => $composableBuilder(
    column: $table.artistRatingKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artistTitle => $composableBuilder(
    column: $table.artistTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalisedArtist => $composableBuilder(
    column: $table.normalisedArtist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumb => $composableBuilder(
    column: $table.thumb,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastViewedAt => $composableBuilder(
    column: $table.lastViewedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mbid => $composableBuilder(
    column: $table.mbid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get userRating => $composableBuilder(
    column: $table.userRating,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AlbumsTableOrderingComposer
    extends Composer<_$AppDatabase, $AlbumsTable> {
  $$AlbumsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ratingKey => $composableBuilder(
    column: $table.ratingKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalisedTitle => $composableBuilder(
    column: $table.normalisedTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artistRatingKey => $composableBuilder(
    column: $table.artistRatingKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artistTitle => $composableBuilder(
    column: $table.artistTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalisedArtist => $composableBuilder(
    column: $table.normalisedArtist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumb => $composableBuilder(
    column: $table.thumb,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastViewedAt => $composableBuilder(
    column: $table.lastViewedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mbid => $composableBuilder(
    column: $table.mbid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get userRating => $composableBuilder(
    column: $table.userRating,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AlbumsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AlbumsTable> {
  $$AlbumsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ratingKey =>
      $composableBuilder(column: $table.ratingKey, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get normalisedTitle => $composableBuilder(
    column: $table.normalisedTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get artistRatingKey => $composableBuilder(
    column: $table.artistRatingKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get artistTitle => $composableBuilder(
    column: $table.artistTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get normalisedArtist => $composableBuilder(
    column: $table.normalisedArtist,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thumb =>
      $composableBuilder(column: $table.thumb, builder: (column) => column);

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<int> get lastViewedAt => $composableBuilder(
    column: $table.lastViewedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mbid =>
      $composableBuilder(column: $table.mbid, builder: (column) => column);

  GeneratedColumn<int> get userRating => $composableBuilder(
    column: $table.userRating,
    builder: (column) => column,
  );
}

class $$AlbumsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AlbumsTable,
          Album,
          $$AlbumsTableFilterComposer,
          $$AlbumsTableOrderingComposer,
          $$AlbumsTableAnnotationComposer,
          $$AlbumsTableCreateCompanionBuilder,
          $$AlbumsTableUpdateCompanionBuilder,
          (Album, BaseReferences<_$AppDatabase, $AlbumsTable, Album>),
          Album,
          PrefetchHooks Function()
        > {
  $$AlbumsTableTableManager(_$AppDatabase db, $AlbumsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AlbumsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AlbumsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AlbumsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ratingKey = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> normalisedTitle = const Value.absent(),
                Value<String?> artistRatingKey = const Value.absent(),
                Value<String> artistTitle = const Value.absent(),
                Value<String> normalisedArtist = const Value.absent(),
                Value<String?> thumb = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<int?> updatedAt = const Value.absent(),
                Value<int?> addedAt = const Value.absent(),
                Value<int?> lastViewedAt = const Value.absent(),
                Value<String?> mbid = const Value.absent(),
                Value<int?> userRating = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AlbumsCompanion(
                ratingKey: ratingKey,
                title: title,
                normalisedTitle: normalisedTitle,
                artistRatingKey: artistRatingKey,
                artistTitle: artistTitle,
                normalisedArtist: normalisedArtist,
                thumb: thumb,
                year: year,
                updatedAt: updatedAt,
                addedAt: addedAt,
                lastViewedAt: lastViewedAt,
                mbid: mbid,
                userRating: userRating,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ratingKey,
                required String title,
                required String normalisedTitle,
                Value<String?> artistRatingKey = const Value.absent(),
                required String artistTitle,
                required String normalisedArtist,
                Value<String?> thumb = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<int?> updatedAt = const Value.absent(),
                Value<int?> addedAt = const Value.absent(),
                Value<int?> lastViewedAt = const Value.absent(),
                Value<String?> mbid = const Value.absent(),
                Value<int?> userRating = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AlbumsCompanion.insert(
                ratingKey: ratingKey,
                title: title,
                normalisedTitle: normalisedTitle,
                artistRatingKey: artistRatingKey,
                artistTitle: artistTitle,
                normalisedArtist: normalisedArtist,
                thumb: thumb,
                year: year,
                updatedAt: updatedAt,
                addedAt: addedAt,
                lastViewedAt: lastViewedAt,
                mbid: mbid,
                userRating: userRating,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AlbumsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AlbumsTable,
      Album,
      $$AlbumsTableFilterComposer,
      $$AlbumsTableOrderingComposer,
      $$AlbumsTableAnnotationComposer,
      $$AlbumsTableCreateCompanionBuilder,
      $$AlbumsTableUpdateCompanionBuilder,
      (Album, BaseReferences<_$AppDatabase, $AlbumsTable, Album>),
      Album,
      PrefetchHooks Function()
    >;
typedef $$TracksTableCreateCompanionBuilder =
    TracksCompanion Function({
      required String ratingKey,
      required String title,
      required String normalisedTitle,
      Value<String?> albumRatingKey,
      Value<String> albumTitle,
      Value<String> artistTitle,
      Value<int> trackIndex,
      Value<int?> discIndex,
      Value<int> durationMs,
      Value<String?> partKey,
      Value<String?> container,
      Value<int?> partSizeBytes,
      Value<String?> thumb,
      Value<int?> updatedAt,
      Value<int?> addedAt,
      Value<int?> lastViewedAt,
      Value<int?> userRating,
      Value<int> rowid,
    });
typedef $$TracksTableUpdateCompanionBuilder =
    TracksCompanion Function({
      Value<String> ratingKey,
      Value<String> title,
      Value<String> normalisedTitle,
      Value<String?> albumRatingKey,
      Value<String> albumTitle,
      Value<String> artistTitle,
      Value<int> trackIndex,
      Value<int?> discIndex,
      Value<int> durationMs,
      Value<String?> partKey,
      Value<String?> container,
      Value<int?> partSizeBytes,
      Value<String?> thumb,
      Value<int?> updatedAt,
      Value<int?> addedAt,
      Value<int?> lastViewedAt,
      Value<int?> userRating,
      Value<int> rowid,
    });

class $$TracksTableFilterComposer
    extends Composer<_$AppDatabase, $TracksTable> {
  $$TracksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ratingKey => $composableBuilder(
    column: $table.ratingKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalisedTitle => $composableBuilder(
    column: $table.normalisedTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get albumRatingKey => $composableBuilder(
    column: $table.albumRatingKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get albumTitle => $composableBuilder(
    column: $table.albumTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artistTitle => $composableBuilder(
    column: $table.artistTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get trackIndex => $composableBuilder(
    column: $table.trackIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get discIndex => $composableBuilder(
    column: $table.discIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get partKey => $composableBuilder(
    column: $table.partKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get container => $composableBuilder(
    column: $table.container,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get partSizeBytes => $composableBuilder(
    column: $table.partSizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumb => $composableBuilder(
    column: $table.thumb,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastViewedAt => $composableBuilder(
    column: $table.lastViewedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get userRating => $composableBuilder(
    column: $table.userRating,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TracksTableOrderingComposer
    extends Composer<_$AppDatabase, $TracksTable> {
  $$TracksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ratingKey => $composableBuilder(
    column: $table.ratingKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalisedTitle => $composableBuilder(
    column: $table.normalisedTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get albumRatingKey => $composableBuilder(
    column: $table.albumRatingKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get albumTitle => $composableBuilder(
    column: $table.albumTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artistTitle => $composableBuilder(
    column: $table.artistTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get trackIndex => $composableBuilder(
    column: $table.trackIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get discIndex => $composableBuilder(
    column: $table.discIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get partKey => $composableBuilder(
    column: $table.partKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get container => $composableBuilder(
    column: $table.container,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get partSizeBytes => $composableBuilder(
    column: $table.partSizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumb => $composableBuilder(
    column: $table.thumb,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastViewedAt => $composableBuilder(
    column: $table.lastViewedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get userRating => $composableBuilder(
    column: $table.userRating,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TracksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TracksTable> {
  $$TracksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ratingKey =>
      $composableBuilder(column: $table.ratingKey, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get normalisedTitle => $composableBuilder(
    column: $table.normalisedTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get albumRatingKey => $composableBuilder(
    column: $table.albumRatingKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get albumTitle => $composableBuilder(
    column: $table.albumTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get artistTitle => $composableBuilder(
    column: $table.artistTitle,
    builder: (column) => column,
  );

  GeneratedColumn<int> get trackIndex => $composableBuilder(
    column: $table.trackIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get discIndex =>
      $composableBuilder(column: $table.discIndex, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get partKey =>
      $composableBuilder(column: $table.partKey, builder: (column) => column);

  GeneratedColumn<String> get container =>
      $composableBuilder(column: $table.container, builder: (column) => column);

  GeneratedColumn<int> get partSizeBytes => $composableBuilder(
    column: $table.partSizeBytes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thumb =>
      $composableBuilder(column: $table.thumb, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<int> get lastViewedAt => $composableBuilder(
    column: $table.lastViewedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get userRating => $composableBuilder(
    column: $table.userRating,
    builder: (column) => column,
  );
}

class $$TracksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TracksTable,
          Track,
          $$TracksTableFilterComposer,
          $$TracksTableOrderingComposer,
          $$TracksTableAnnotationComposer,
          $$TracksTableCreateCompanionBuilder,
          $$TracksTableUpdateCompanionBuilder,
          (Track, BaseReferences<_$AppDatabase, $TracksTable, Track>),
          Track,
          PrefetchHooks Function()
        > {
  $$TracksTableTableManager(_$AppDatabase db, $TracksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TracksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TracksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TracksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ratingKey = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> normalisedTitle = const Value.absent(),
                Value<String?> albumRatingKey = const Value.absent(),
                Value<String> albumTitle = const Value.absent(),
                Value<String> artistTitle = const Value.absent(),
                Value<int> trackIndex = const Value.absent(),
                Value<int?> discIndex = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<String?> partKey = const Value.absent(),
                Value<String?> container = const Value.absent(),
                Value<int?> partSizeBytes = const Value.absent(),
                Value<String?> thumb = const Value.absent(),
                Value<int?> updatedAt = const Value.absent(),
                Value<int?> addedAt = const Value.absent(),
                Value<int?> lastViewedAt = const Value.absent(),
                Value<int?> userRating = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TracksCompanion(
                ratingKey: ratingKey,
                title: title,
                normalisedTitle: normalisedTitle,
                albumRatingKey: albumRatingKey,
                albumTitle: albumTitle,
                artistTitle: artistTitle,
                trackIndex: trackIndex,
                discIndex: discIndex,
                durationMs: durationMs,
                partKey: partKey,
                container: container,
                partSizeBytes: partSizeBytes,
                thumb: thumb,
                updatedAt: updatedAt,
                addedAt: addedAt,
                lastViewedAt: lastViewedAt,
                userRating: userRating,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ratingKey,
                required String title,
                required String normalisedTitle,
                Value<String?> albumRatingKey = const Value.absent(),
                Value<String> albumTitle = const Value.absent(),
                Value<String> artistTitle = const Value.absent(),
                Value<int> trackIndex = const Value.absent(),
                Value<int?> discIndex = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<String?> partKey = const Value.absent(),
                Value<String?> container = const Value.absent(),
                Value<int?> partSizeBytes = const Value.absent(),
                Value<String?> thumb = const Value.absent(),
                Value<int?> updatedAt = const Value.absent(),
                Value<int?> addedAt = const Value.absent(),
                Value<int?> lastViewedAt = const Value.absent(),
                Value<int?> userRating = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TracksCompanion.insert(
                ratingKey: ratingKey,
                title: title,
                normalisedTitle: normalisedTitle,
                albumRatingKey: albumRatingKey,
                albumTitle: albumTitle,
                artistTitle: artistTitle,
                trackIndex: trackIndex,
                discIndex: discIndex,
                durationMs: durationMs,
                partKey: partKey,
                container: container,
                partSizeBytes: partSizeBytes,
                thumb: thumb,
                updatedAt: updatedAt,
                addedAt: addedAt,
                lastViewedAt: lastViewedAt,
                userRating: userRating,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TracksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TracksTable,
      Track,
      $$TracksTableFilterComposer,
      $$TracksTableOrderingComposer,
      $$TracksTableAnnotationComposer,
      $$TracksTableCreateCompanionBuilder,
      $$TracksTableUpdateCompanionBuilder,
      (Track, BaseReferences<_$AppDatabase, $TracksTable, Track>),
      Track,
      PrefetchHooks Function()
    >;
typedef $$PlaylistsTableCreateCompanionBuilder =
    PlaylistsCompanion Function({
      required String ratingKey,
      required String title,
      required String normalisedTitle,
      Value<String?> thumb,
      Value<int> itemCount,
      Value<int?> durationMs,
      Value<int?> updatedAt,
      Value<int?> lastViewedAt,
      Value<bool> smart,
      Value<int> rowid,
    });
typedef $$PlaylistsTableUpdateCompanionBuilder =
    PlaylistsCompanion Function({
      Value<String> ratingKey,
      Value<String> title,
      Value<String> normalisedTitle,
      Value<String?> thumb,
      Value<int> itemCount,
      Value<int?> durationMs,
      Value<int?> updatedAt,
      Value<int?> lastViewedAt,
      Value<bool> smart,
      Value<int> rowid,
    });

class $$PlaylistsTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ratingKey => $composableBuilder(
    column: $table.ratingKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalisedTitle => $composableBuilder(
    column: $table.normalisedTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumb => $composableBuilder(
    column: $table.thumb,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get itemCount => $composableBuilder(
    column: $table.itemCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastViewedAt => $composableBuilder(
    column: $table.lastViewedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get smart => $composableBuilder(
    column: $table.smart,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlaylistsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ratingKey => $composableBuilder(
    column: $table.ratingKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalisedTitle => $composableBuilder(
    column: $table.normalisedTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumb => $composableBuilder(
    column: $table.thumb,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get itemCount => $composableBuilder(
    column: $table.itemCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastViewedAt => $composableBuilder(
    column: $table.lastViewedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get smart => $composableBuilder(
    column: $table.smart,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaylistsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ratingKey =>
      $composableBuilder(column: $table.ratingKey, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get normalisedTitle => $composableBuilder(
    column: $table.normalisedTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thumb =>
      $composableBuilder(column: $table.thumb, builder: (column) => column);

  GeneratedColumn<int> get itemCount =>
      $composableBuilder(column: $table.itemCount, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get lastViewedAt => $composableBuilder(
    column: $table.lastViewedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get smart =>
      $composableBuilder(column: $table.smart, builder: (column) => column);
}

class $$PlaylistsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaylistsTable,
          Playlist,
          $$PlaylistsTableFilterComposer,
          $$PlaylistsTableOrderingComposer,
          $$PlaylistsTableAnnotationComposer,
          $$PlaylistsTableCreateCompanionBuilder,
          $$PlaylistsTableUpdateCompanionBuilder,
          (Playlist, BaseReferences<_$AppDatabase, $PlaylistsTable, Playlist>),
          Playlist,
          PrefetchHooks Function()
        > {
  $$PlaylistsTableTableManager(_$AppDatabase db, $PlaylistsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaylistsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ratingKey = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> normalisedTitle = const Value.absent(),
                Value<String?> thumb = const Value.absent(),
                Value<int> itemCount = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<int?> updatedAt = const Value.absent(),
                Value<int?> lastViewedAt = const Value.absent(),
                Value<bool> smart = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaylistsCompanion(
                ratingKey: ratingKey,
                title: title,
                normalisedTitle: normalisedTitle,
                thumb: thumb,
                itemCount: itemCount,
                durationMs: durationMs,
                updatedAt: updatedAt,
                lastViewedAt: lastViewedAt,
                smart: smart,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ratingKey,
                required String title,
                required String normalisedTitle,
                Value<String?> thumb = const Value.absent(),
                Value<int> itemCount = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<int?> updatedAt = const Value.absent(),
                Value<int?> lastViewedAt = const Value.absent(),
                Value<bool> smart = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaylistsCompanion.insert(
                ratingKey: ratingKey,
                title: title,
                normalisedTitle: normalisedTitle,
                thumb: thumb,
                itemCount: itemCount,
                durationMs: durationMs,
                updatedAt: updatedAt,
                lastViewedAt: lastViewedAt,
                smart: smart,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlaylistsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaylistsTable,
      Playlist,
      $$PlaylistsTableFilterComposer,
      $$PlaylistsTableOrderingComposer,
      $$PlaylistsTableAnnotationComposer,
      $$PlaylistsTableCreateCompanionBuilder,
      $$PlaylistsTableUpdateCompanionBuilder,
      (Playlist, BaseReferences<_$AppDatabase, $PlaylistsTable, Playlist>),
      Playlist,
      PrefetchHooks Function()
    >;
typedef $$PlaylistItemsTableCreateCompanionBuilder =
    PlaylistItemsCompanion Function({
      required String playlistRatingKey,
      required String trackRatingKey,
      required int position,
      Value<int> rowid,
    });
typedef $$PlaylistItemsTableUpdateCompanionBuilder =
    PlaylistItemsCompanion Function({
      Value<String> playlistRatingKey,
      Value<String> trackRatingKey,
      Value<int> position,
      Value<int> rowid,
    });

class $$PlaylistItemsTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistItemsTable> {
  $$PlaylistItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get playlistRatingKey => $composableBuilder(
    column: $table.playlistRatingKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trackRatingKey => $composableBuilder(
    column: $table.trackRatingKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlaylistItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistItemsTable> {
  $$PlaylistItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get playlistRatingKey => $composableBuilder(
    column: $table.playlistRatingKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackRatingKey => $composableBuilder(
    column: $table.trackRatingKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaylistItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistItemsTable> {
  $$PlaylistItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get playlistRatingKey => $composableBuilder(
    column: $table.playlistRatingKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get trackRatingKey => $composableBuilder(
    column: $table.trackRatingKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$PlaylistItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaylistItemsTable,
          PlaylistItem,
          $$PlaylistItemsTableFilterComposer,
          $$PlaylistItemsTableOrderingComposer,
          $$PlaylistItemsTableAnnotationComposer,
          $$PlaylistItemsTableCreateCompanionBuilder,
          $$PlaylistItemsTableUpdateCompanionBuilder,
          (
            PlaylistItem,
            BaseReferences<_$AppDatabase, $PlaylistItemsTable, PlaylistItem>,
          ),
          PlaylistItem,
          PrefetchHooks Function()
        > {
  $$PlaylistItemsTableTableManager(_$AppDatabase db, $PlaylistItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaylistItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> playlistRatingKey = const Value.absent(),
                Value<String> trackRatingKey = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaylistItemsCompanion(
                playlistRatingKey: playlistRatingKey,
                trackRatingKey: trackRatingKey,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String playlistRatingKey,
                required String trackRatingKey,
                required int position,
                Value<int> rowid = const Value.absent(),
              }) => PlaylistItemsCompanion.insert(
                playlistRatingKey: playlistRatingKey,
                trackRatingKey: trackRatingKey,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlaylistItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaylistItemsTable,
      PlaylistItem,
      $$PlaylistItemsTableFilterComposer,
      $$PlaylistItemsTableOrderingComposer,
      $$PlaylistItemsTableAnnotationComposer,
      $$PlaylistItemsTableCreateCompanionBuilder,
      $$PlaylistItemsTableUpdateCompanionBuilder,
      (
        PlaylistItem,
        BaseReferences<_$AppDatabase, $PlaylistItemsTable, PlaylistItem>,
      ),
      PlaylistItem,
      PrefetchHooks Function()
    >;
typedef $$SyncStateTableCreateCompanionBuilder =
    SyncStateCompanion Function({
      required String sectionKey,
      required String serverClientIdentifier,
      Value<int> lastSyncedUpdatedAt,
      Value<int?> serverUpdatedAt,
      Value<int?> serverScannedAt,
      Value<bool> initialSyncComplete,
      Value<int?> lastReconcileAt,
      Value<int> rowid,
    });
typedef $$SyncStateTableUpdateCompanionBuilder =
    SyncStateCompanion Function({
      Value<String> sectionKey,
      Value<String> serverClientIdentifier,
      Value<int> lastSyncedUpdatedAt,
      Value<int?> serverUpdatedAt,
      Value<int?> serverScannedAt,
      Value<bool> initialSyncComplete,
      Value<int?> lastReconcileAt,
      Value<int> rowid,
    });

class $$SyncStateTableFilterComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sectionKey => $composableBuilder(
    column: $table.sectionKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverClientIdentifier => $composableBuilder(
    column: $table.serverClientIdentifier,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSyncedUpdatedAt => $composableBuilder(
    column: $table.lastSyncedUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverScannedAt => $composableBuilder(
    column: $table.serverScannedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get initialSyncComplete => $composableBuilder(
    column: $table.initialSyncComplete,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastReconcileAt => $composableBuilder(
    column: $table.lastReconcileAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncStateTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sectionKey => $composableBuilder(
    column: $table.sectionKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverClientIdentifier => $composableBuilder(
    column: $table.serverClientIdentifier,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSyncedUpdatedAt => $composableBuilder(
    column: $table.lastSyncedUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverScannedAt => $composableBuilder(
    column: $table.serverScannedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get initialSyncComplete => $composableBuilder(
    column: $table.initialSyncComplete,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastReconcileAt => $composableBuilder(
    column: $table.lastReconcileAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncStateTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sectionKey => $composableBuilder(
    column: $table.sectionKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get serverClientIdentifier => $composableBuilder(
    column: $table.serverClientIdentifier,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastSyncedUpdatedAt => $composableBuilder(
    column: $table.lastSyncedUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get serverScannedAt => $composableBuilder(
    column: $table.serverScannedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get initialSyncComplete => $composableBuilder(
    column: $table.initialSyncComplete,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastReconcileAt => $composableBuilder(
    column: $table.lastReconcileAt,
    builder: (column) => column,
  );
}

class $$SyncStateTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncStateTable,
          SyncStateData,
          $$SyncStateTableFilterComposer,
          $$SyncStateTableOrderingComposer,
          $$SyncStateTableAnnotationComposer,
          $$SyncStateTableCreateCompanionBuilder,
          $$SyncStateTableUpdateCompanionBuilder,
          (
            SyncStateData,
            BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateData>,
          ),
          SyncStateData,
          PrefetchHooks Function()
        > {
  $$SyncStateTableTableManager(_$AppDatabase db, $SyncStateTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sectionKey = const Value.absent(),
                Value<String> serverClientIdentifier = const Value.absent(),
                Value<int> lastSyncedUpdatedAt = const Value.absent(),
                Value<int?> serverUpdatedAt = const Value.absent(),
                Value<int?> serverScannedAt = const Value.absent(),
                Value<bool> initialSyncComplete = const Value.absent(),
                Value<int?> lastReconcileAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncStateCompanion(
                sectionKey: sectionKey,
                serverClientIdentifier: serverClientIdentifier,
                lastSyncedUpdatedAt: lastSyncedUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                serverScannedAt: serverScannedAt,
                initialSyncComplete: initialSyncComplete,
                lastReconcileAt: lastReconcileAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sectionKey,
                required String serverClientIdentifier,
                Value<int> lastSyncedUpdatedAt = const Value.absent(),
                Value<int?> serverUpdatedAt = const Value.absent(),
                Value<int?> serverScannedAt = const Value.absent(),
                Value<bool> initialSyncComplete = const Value.absent(),
                Value<int?> lastReconcileAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncStateCompanion.insert(
                sectionKey: sectionKey,
                serverClientIdentifier: serverClientIdentifier,
                lastSyncedUpdatedAt: lastSyncedUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                serverScannedAt: serverScannedAt,
                initialSyncComplete: initialSyncComplete,
                lastReconcileAt: lastReconcileAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncStateTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncStateTable,
      SyncStateData,
      $$SyncStateTableFilterComposer,
      $$SyncStateTableOrderingComposer,
      $$SyncStateTableAnnotationComposer,
      $$SyncStateTableCreateCompanionBuilder,
      $$SyncStateTableUpdateCompanionBuilder,
      (
        SyncStateData,
        BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateData>,
      ),
      SyncStateData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ArtistsTableTableManager get artists =>
      $$ArtistsTableTableManager(_db, _db.artists);
  $$AlbumsTableTableManager get albums =>
      $$AlbumsTableTableManager(_db, _db.albums);
  $$TracksTableTableManager get tracks =>
      $$TracksTableTableManager(_db, _db.tracks);
  $$PlaylistsTableTableManager get playlists =>
      $$PlaylistsTableTableManager(_db, _db.playlists);
  $$PlaylistItemsTableTableManager get playlistItems =>
      $$PlaylistItemsTableTableManager(_db, _db.playlistItems);
  $$SyncStateTableTableManager get syncState =>
      $$SyncStateTableTableManager(_db, _db.syncState);
}
