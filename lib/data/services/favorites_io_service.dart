import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../models/radio_station.dart';

/// Read/write favorites to a portable JSON file.
///
/// Wire format:
/// ```json
/// { "format": "justradio.favorites", "version": 1,
///   "exported_at": "2026-04-24T10:00:00.000Z",
///   "stations": [ <radio-browser-shaped station>, ... ] }
/// ```
/// Each station uses [RadioStation.toJson] (radio-browser API field names),
/// so re-tying to radio-browser by `stationuuid` is lossless. A bare top-level
/// `[ ... ]` array is also accepted on import to support hand-edited files
/// or raw radio-browser API dumps.
class FavoritesIoService {
  static const _formatTag = 'justradio.favorites';
  static const _formatVersion = 1;

  /// Returns the saved file path, or null if the user cancelled.
  Future<String?> exportToFile(List<RadioStation> stations) async {
    final payload = <String, dynamic>{
      'format': _formatTag,
      'version': _formatVersion,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'stations': stations.map((s) => s.toJson()).toList(),
    };
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
    );
    final today = DateTime.now();
    final stamp = '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    return FilePicker.saveFile(
      dialogTitle: 'Export favorites',
      fileName: 'justradio-favorites-$stamp.json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: bytes,
    );
  }

  /// Returns the parsed station list, or null if the user cancelled.
  /// Throws [FormatException] on malformed input.
  Future<List<RadioStation>?> importFromFile() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Import favorites',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final bytes = result.files.single.bytes;
    if (bytes == null) {
      throw const FormatException('Could not read file contents');
    }
    final text = utf8.decode(bytes);
    final decoded = jsonDecode(text);

    final List<dynamic> raw;
    if (decoded is List) {
      raw = decoded;
    } else if (decoded is Map<String, dynamic>) {
      final stations = decoded['stations'];
      if (stations is! List) {
        throw const FormatException(
            'Missing "stations" array in favorites file');
      }
      raw = stations;
    } else {
      throw const FormatException('Unrecognized favorites file shape');
    }

    final stations = <RadioStation>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final station = RadioStation.fromJson(Map<String, dynamic>.from(item));
      if (station.stationuuid.isEmpty || station.url.isEmpty) continue;
      stations.add(station);
    }
    return stations;
  }
}
