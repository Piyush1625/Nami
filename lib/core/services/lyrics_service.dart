import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/lyrics.dart';
import '../models/track.dart';

class LyricsService {
  final Map<int, Lyrics> _cache = {};

  Future<Lyrics> loadFor(Track track) async {
    final cached = _cache[track.id];
    if (cached != null) return cached;

    var result = await _readSidecarLrc(track.path);
    if (result.isEmpty) {
      result = await _readEmbeddedLyrics(track.path);
    }
    _cache[track.id] = result;
    return result;
  }

  Future<Lyrics> shiftLyrics(Track track, int offsetMs) async {
    final current = await loadFor(track);
    if (!current.isSynced) return current;

    final shifted = <LyricLine>[];
    for (final line in current.synced) {
      final nextMs = (line.time.inMilliseconds + offsetMs).clamp(0, 86400000);
      shifted.add(LyricLine(Duration(milliseconds: nextMs), line.text));
    }
    shifted.sort((a, b) => a.time.compareTo(b.time));

    final buffer = StringBuffer();
    for (final l in shifted) {
      final min = l.time.inMinutes.toString().padLeft(2, '0');
      final sec = (l.time.inSeconds % 60).toString().padLeft(2, '0');
      final cs = ((l.time.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
      buffer.writeln('[$min:$sec.$cs]${l.text}');
    }
    return saveCustomLrc(track, buffer.toString());
  }

  Future<Lyrics> _readSidecarLrc(String audioPath) async {
    try {
      final base = p.withoutExtension(audioPath);
      for (final ext in ['.lrc', '.LRC', '.txt']) {
        final file = File('$base$ext');
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final content = _decodeBytesWithFallback(bytes);
          if (content.trim().isNotEmpty) {
            return Lyrics.parseLrc(content);
          }
        }
      }
    } catch (_) {}
    return const Lyrics();
  }

  Future<Lyrics> _readEmbeddedLyrics(String audioPath) async {
    RandomAccessFile? raf;
    try {
      final file = File(audioPath);
      if (!await file.exists()) return const Lyrics();
      final len = await file.length();
      if (len < 16) return const Lyrics();

      raf = await file.open(mode: FileMode.read);
      final header = await raf.read(4);

      if (header.length == 4 &&
          header[0] == 0x66 &&
          header[1] == 0x4C &&
          header[2] == 0x61 &&
          header[3] == 0x43) {
        final text = await _parseFlacVorbisLyrics(raf, len);
        if (text != null && text.trim().isNotEmpty) {
          return Lyrics.parseLrc(text);
        }
      }

      if (header.length >= 3 &&
          header[0] == 0x49 &&
          header[1] == 0x44 &&
          header[2] == 0x33) {
        await raf.setPosition(0);
        final id3Header = await raf.read(10);
        final version = id3Header[3];
        final tagSize = _synchsafeInt(id3Header, 6);
        final maxRead = (tagSize + 10).clamp(0, 512 * 1024);
        final tagBytes = await raf.read(maxRead);
        final text = _parseId3Uslt(tagBytes, version);
        if (text != null && text.trim().isNotEmpty) {
          return Lyrics.parseLrc(text);
        }
      }
    } catch (_) {
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }
    return const Lyrics();
  }

  Future<String?> _parseFlacVorbisLyrics(RandomAccessFile raf, int fileLen) async {
    var isLast = false;
    while (!isLast && await raf.position() + 4 < fileLen) {
      final blockHeader = await raf.read(4);
      if (blockHeader.length < 4) break;
      isLast = (blockHeader[0] & 0x80) != 0;
      final blockType = blockHeader[0] & 0x7F;
      final blockLen =
          (blockHeader[1] << 16) | (blockHeader[2] << 8) | blockHeader[3];
      if (blockLen <= 0 || blockLen > 2 * 1024 * 1024) break;

      if (blockType == 4) {
        final data = await raf.read(blockLen);
        final bd = ByteData.sublistView(data);
        var offset = 0;
        if (offset + 4 > data.length) return null;
        final vendorLen = bd.getUint32(offset, Endian.little);
        offset += 4 + vendorLen;
        if (offset + 4 > data.length) return null;
        final commentCount = bd.getUint32(offset, Endian.little);
        offset += 4;
        for (var i = 0; i < commentCount && offset + 4 <= data.length; i++) {
          final cLen = bd.getUint32(offset, Endian.little);
          offset += 4;
          if (cLen < 0 || offset + cLen > data.length) break;
          final entry = utf8.decode(
            data.sublist(offset, offset + cLen),
            allowMalformed: true,
          );
          offset += cLen;
          final eq = entry.indexOf('=');
          if (eq > 0) {
            final key = entry.substring(0, eq).toUpperCase();
            if (key == 'LYRICS' || key == 'UNSYNCEDLYRICS') {
              return entry.substring(eq + 1);
            }
          }
        }
        return null;
      } else {
        await raf.setPosition(await raf.position() + blockLen);
      }
    }
    return null;
  }

  String? _parseId3Uslt(Uint8List bytes, int version) {
    var offset = 0;
    while (offset + 10 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      if (id.codeUnits.any((c) => c < 32 || c > 90)) break;
      final size = version == 4
          ? _synchsafeInt(bytes, offset + 4)
          : ((bytes[offset + 4] << 24) |
              (bytes[offset + 5] << 16) |
              (bytes[offset + 6] << 8) |
              bytes[offset + 7]);
      offset += 10;
      if (size <= 0 || offset + size > bytes.length) break;

      if (id == 'USLT' && size > 4) {
        final frame = bytes.sublist(offset, offset + size);
        final encoding = frame[0];
        var descEnd = 4;
        if (encoding == 1 || encoding == 2) {
          while (descEnd + 1 < frame.length &&
              !(frame[descEnd] == 0 && frame[descEnd + 1] == 0)) {
            descEnd += 2;
          }
          descEnd += 2;
        } else {
          while (descEnd < frame.length && frame[descEnd] != 0) {
            descEnd++;
          }
          descEnd++;
        }
        if (descEnd < frame.length) {
          return _decodeBytesWithFallback(frame.sublist(descEnd), encodingHint: encoding);
        }
      }
      offset += size;
    }
    return null;
  }

  int _synchsafeInt(Uint8List b, int offset) {
    return ((b[offset] & 0x7F) << 21) |
        ((b[offset + 1] & 0x7F) << 14) |
        ((b[offset + 2] & 0x7F) << 7) |
        (b[offset + 3] & 0x7F);
  }

  String _decodeBytesWithFallback(Uint8List bytes, {int? encodingHint}) {
    if (bytes.isEmpty) return '';
    if (encodingHint == 1 ||
        encodingHint == 2 ||
        (bytes.length >= 2 &&
            ((bytes[0] == 0xFF && bytes[1] == 0xFE) ||
                (bytes[0] == 0xFE && bytes[1] == 0xFF)))) {
      final isBigEndian =
          encodingHint == 2 || (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF);
      final start = (bytes.length >= 2 &&
              ((bytes[0] == 0xFF && bytes[1] == 0xFE) ||
                  (bytes[0] == 0xFE && bytes[1] == 0xFF)))
          ? 2
          : 0;
      final codeUnits = <int>[];
      for (var i = start; i + 1 < bytes.length; i += 2) {
        final unit = isBigEndian
            ? ((bytes[i] << 8) | bytes[i + 1])
            : (bytes[i] | (bytes[i + 1] << 8));
        if (unit != 0) codeUnits.add(unit);
      }
      return String.fromCharCodes(codeUnits);
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  Future<Lyrics> saveCustomLrc(Track track, String lrcContent) async {
    final parsed = Lyrics.parseLrc(lrcContent);
    _cache[track.id] = parsed;
    try {
      final lrcFile = File('${p.withoutExtension(track.path)}.lrc');
      await lrcFile.writeAsString(lrcContent, flush: true);
    } catch (_) {}
    return parsed;
  }
}
