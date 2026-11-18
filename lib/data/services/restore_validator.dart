import 'dart:convert';
import 'dart:io';

import '../../core/error_codes.dart';
import '../../domain/enums/enums.dart';

class RestorePreview {
  const RestorePreview({
    required this.books,
    required this.drafts,
    required this.playlists,
  });
  final int books;
  final int drafts;
  final int playlists;
}

/// UI의 관대한 fromJson 폴백을 복원 승인 검사로 사용하지 않는다.
/// 실제 미디어 참조는 필수. 삭제된 책/전집을 가리키는 역사적 ID는 기존 폴백을 유지한다.
class RestoreValidator {
  static const maxJsonBytes = 8 * 1024 * 1024;
  static const maxAllJsonBytes = 64 * 1024 * 1024;
  final _idPattern = RegExp(r'^[a-zA-Z0-9_-]+$');
  Never _invalid() => throw const AppException(ErrorCode.backupInvalid);
  void _check(bool value) {
    if (!value) _invalid();
  }

  String _id(Object? value) {
    _check(
      value is String && value.length <= 255 && _idPattern.hasMatch(value),
    );
    return value as String;
  }

  Map _map(Object? value) {
    _check(value is Map);
    return value as Map;
  }

  List _list(Object? value) {
    _check(value is List);
    return value as List;
  }

  void _date(Object? value) =>
      _check(value is String && DateTime.tryParse(value) != null);
  void _optionalStrings(Map value, List<String> keys) {
    for (final key in keys) {
      _check(value[key] == null || value[key] is String);
    }
  }

  void _number(Object? value) => _check(value is int && value >= 0);
  void _ids(List values) {
    final seen = <String>{};
    for (final value in values) {
      _check(seen.add(_id(value)));
    }
  }

  Future<RestorePreview> validate(Directory root) async {
    var bytes = 0;
    var books = 0;
    var drafts = 0;
    var playlists = 0;
    final files = <String, File>{};
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      _check(entity is File || entity is Directory);
      if (entity is File) {
        files[entity.path.substring(root.path.length + 1)] = entity;
      }
    }
    void media(String prefix, Object? value, {bool optional = true}) {
      if (optional && value == null) return;
      _check(value is String && value.isNotEmpty);
      final path = value as String;
      _check(
        path.length <= 1024 &&
            path
                .split('/')
                .every(
                  (s) => RegExp(r'^[a-zA-Z0-9_-][a-zA-Z0-9_.-]*$').hasMatch(s),
                ),
      );
      final file = files['$prefix$path'];
      _check(file != null && file.lengthSync() > 0);
    }

    void content(Map value, String id, String prefix, {required bool draft}) {
      _check(_id(value['id']) == id);
      _check(ContentType.values.any((v) => v.name == value['type']));
      _check(value['title'] is String);
      _date(value['createdAt']);
      _date(value['updatedAt']);
      _optionalStrings(value, ['author', 'publisher', 'seriesId']);
      if (value['seriesId'] != null) _id(value['seriesId']);
      if (value['volume'] != null) _check(value['volume'] is int);
      media(prefix, value['coverPath']);
      media(prefix, value['videoPath']);
      final pages = _list(value['pages']);
      final pageIds = <String>{};
      final orders = <int>{};
      for (final raw in pages) {
        final page = _map(raw);
        _check(pageIds.add(_id(page['id'])));
        _number(page['orderIndex']);
        _check(orders.add(page['orderIndex']));
        media(prefix, page['imagePath'], optional: false);
        _optionalStrings(page, ['text']);
        final trackIds = <String>{};
        for (final rawTrack in _list(page['tracks'])) {
          final track = _map(rawTrack);
          _check(trackIds.add(_id(track['id'])));
          _check(AudioSource.values.any((v) => v.name == track['source']));
          _date(track['createdAt']);
          if (track['durationMs'] != null) _number(track['durationMs']);
          if (track['voiceProfileId'] != null) _id(track['voiceProfileId']);
          media(
            prefix,
            track['path'],
            optional: track['source'] == 'deviceTts',
          );
        }
      }
      _check(_list(value['tags']).every((tag) => tag is String));
      if (value['dimensions'] != null) {
        _check(
          _map(value['dimensions']).values.every((v) => v is num && v.isFinite),
        );
      }
      for (final raw in _list(value['clips'] ?? [])) {
        final clip = _map(raw);
        _id(clip['id']);
        _number(clip['startMs']);
        _number(clip['endMs']);
        _check(clip['endMs'] > clip['startMs']);
        _optionalStrings(clip, ['subtitle']);
      }
      if (draft) _check(value['type'] == 'pagedBook');
    }

    for (final entry in files.entries) {
      final path = entry.key;
      // media 경로 안의 JSON은 실행/해석하지 않는다. 알려진 메타데이터만 읽는다.
      final parts = path.split('/');
      final metadata =
          parts.length == 3 &&
          parts.last == 'data.json' &&
          ['library', 'drafts', 'reading_positions'].contains(parts.first);
      final index =
          parts.length == 2 && parts.first == 'index' && path.endsWith('.json');
      if (!metadata && !index) continue;
      final length = await entry.value.length();
      bytes += length;
      _check(length <= maxJsonBytes && bytes <= maxAllJsonBytes);
      Object? decoded;
      try {
        decoded = jsonDecode(await entry.value.readAsString());
      } on FormatException {
        _invalid();
      }
      Object? data = decoded;
      if (decoded is Map) {
        if (decoded.containsKey('schemaVersion')) {
          _check(
            decoded['schemaVersion'] is int &&
                decoded['schemaVersion'] == 1 &&
                decoded.containsKey('data'),
          );
          data = decoded['data'];
        } else {
          // JsonStore가 지원하는 구형 raw map/list도 같은 엄격한 검사로 검증한다.
          data = decoded['data'] ?? decoded;
        }
      }
      if (metadata) {
        final id = _id(parts[1]);
        final value = _map(data);
        if (parts.first == 'library') {
          content(value, id, 'library/$id/', draft: false);
          books++;
        } else if (parts.first == 'drafts') {
          content(_map(value['content']), id, 'drafts/$id/', draft: true);
          _date(value['savedAt']);
          if (value['sourceUpdatedAt'] != null) _date(value['sourceUpdatedAt']);
          _check(
            [
              'cover',
              'pages',
              'text',
              'voice',
              'preview',
            ].contains(value['step']),
          );
          drafts++;
        } else {
          _check(_id(value['contentId']) == id);
          _id(value['pageId']);
          _date(value['updatedAt']);
        }
      } else if (parts.last == 'recent_playback.json') {
        final value = _map(data);
        final ids = _list(value['bookIds']);
        _check(ids.length <= 1000);
        _ids(ids);
        _check(value['currentId'] == null || ids.contains(value['currentId']));
      } else {
        _check(
          [
            'series.json',
            'playlists.json',
            'children.json',
            'voice_profiles.json',
            'reading_events.json',
          ].contains(parts.last),
        );
        final rows = _list(data);
        final ids = <String>{};
        for (final raw in rows) {
          final row = _map(raw);
          _check(ids.add(_id(row['id'])));
          switch (parts.last) {
            case 'series.json':
              _check(row['title'] is String);
              _optionalStrings(row, ['publisher']);
              media('', row['coverPath']);
            case 'playlists.json':
              _check(row['title'] is String);
              _date(row['createdAt']);
              _ids(_list(row['contentIds']));
              media('', row['coverPath']);
              playlists++;
            case 'children.json':
              _check(row['name'] is String);
              if (row['birthDate'] != null) _date(row['birthDate']);
              media('', row['avatarPath']);
            case 'voice_profiles.json':
              _check(row['label'] is String);
              _date(row['registeredAt']);
              _check(VoiceStatus.values.any((v) => v.name == row['status']));
              _optionalStrings(row, ['remoteVoiceId', 'failureReason']);
            case 'reading_events.json':
              _id(row['contentId']);
              if (row['childId'] != null) _id(row['childId']);
              _date(row['startedAt']);
              if (row['endedAt'] != null) _date(row['endedAt']);
              _number(row['durationSec']);
              _check(row['completed'] is bool);
          }
        }
      }
    }
    return RestorePreview(books: books, drafts: drafts, playlists: playlists);
  }
}
