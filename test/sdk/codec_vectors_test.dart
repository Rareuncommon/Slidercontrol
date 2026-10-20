/// The Dart protocol codecs against the Python SDK they were ported from.
///
/// Every case in vectors/codec_vectors.json.gz was recorded by running the real
/// `edelkrone` 0.1.0 Python package (tool/sdk_port/gen_vectors.py). Each one is
/// replayed here against lib/sdk/protocol/generated/, and must agree exactly:
/// every byte a builder writes into its buffer, every field a parser fills in,
/// every return value, and every call that throws.
///
/// This is the test that stands between a transcription slip and a wrong byte
/// in a motor command, so it compares all of it rather than spot-checking.
///
/// Cases run in recorded order, in one isolate: the codec keeps module-level
/// state (the remote device type a status frame reports changes how a later
/// manual-slide command is encoded), so order is part of the input.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'codec_dispatch.g.dart';

Object? decode(Map<String, dynamic> d) {
  switch (d['t']) {
    case 'bytes':
    case 'ints':
      return List<int>.from(d['v'] as List);
    case 'doubles':
      return List<double>.filled(d['v'] as int, 0.0, growable: true);
    case 'int':
      return d['v'] as int;
    case 'double':
      return _parseDouble(d['v'] as String);
    case 'bool':
      return d['v'] as bool;
    case 'enum':
      return enumByName(d['c'] as String, d['v'] as String);
    case 'obj':
      return makeObject(d['c'] as String, d, (x) => decode(x));
    case 'objlist':
      return <Object?>[decode(d['v'] as Map<String, dynamic>)];
  }
  throw ArgumentError('unknown input kind ${d['t']}');
}

double _parseDouble(String s) {
  switch (s) {
    case 'NaN':
    case 'nan':
      return double.nan;
    case 'Infinity':
    case 'inf':
      return double.infinity;
    case '-Infinity':
    case '-inf':
      return double.negativeInfinity;
  }
  return double.parse(s);
}

/// Exact structural equality, where a number is equal across int and double
/// only if the values are identical. Returns the path of the first mismatch.
String? diff(Object? want, Object? got, String path) {
  if (want is Map && want.containsKey('f')) {
    final w = _parseDouble(want['f'].toString());
    final g = got is Map && got.containsKey('f') ? got['f'] : got;
    final gd = g is String ? _parseDouble(g) : (g as num?)?.toDouble();
    if (gd == null) return '$path: want $w, got $got';
    if (w.isNaN && gd.isNaN) return null;
    return w == gd ? null : '$path: want $w, got $gd';
  }
  if (got is Map && got.containsKey('f') && want is num) {
    final gd = got['f'] is num ? (got['f'] as num).toDouble() : _parseDouble(got['f'] as String);
    return want.toDouble() == gd ? null : '$path: want $want, got $gd';
  }
  if (want is Map) {
    if (got is! Map) return '$path: want map, got $got';
    for (final k in want.keys) {
      final r = diff(want[k], got[k], '$path.$k');
      if (r != null) return r;
    }
    for (final k in got.keys) {
      if (!want.containsKey(k)) return '$path: extra key $k';
    }
    return null;
  }
  if (want is List) {
    if (got is! List) return '$path: want list, got $got';
    if (want.length != got.length) return '$path: length ${want.length} vs ${got.length}';
    for (var i = 0; i < want.length; i++) {
      final r = diff(want[i], got[i], '$path[$i]');
      if (r != null) return r;
    }
    return null;
  }
  return want == got ? null : '$path: want $want, got $got';
}

void main() {
  final raw = File('test/sdk/vectors/codec_vectors.json.gz').readAsBytesSync();
  final cases = (jsonDecode(utf8.decode(gzip.decode(raw))) as List).cast<Map<String, dynamic>>();

  test('the vectors cover every function the dispatch table knows', () {
    final keys = cases.map((c) => c['k']).toSet();
    expect(keys, containsAll(calls.keys));
    expect(calls.keys.toSet(), containsAll(keys));
  });

  test('every recorded call agrees with the Python SDK, in order', () {
    final failures = <String>[];
    var agreed = 0;
    for (var i = 0; i < cases.length; i++) {
      final c = cases[i];
      final key = c['k'] as String;
      final call = calls[key]!;
      final args = [for (final d in (c['in'] as List)) decode(d as Map<String, dynamic>)];
      final out = c['out'] as Map<String, dynamic>;

      Object? ret;
      Object? thrown;
      try {
        ret = call(args);
      } catch (e) {
        thrown = e;
      }

      if (out.containsKey('throws')) {
        if (thrown == null) failures.add('#$i $key: Python threw ${out['throws']}, Dart did not');
        continue;
      }
      if (thrown != null) {
        failures.add('#$i $key: Dart threw $thrown, Python did not');
        continue;
      }
      final mismatch = diff(out['ret'], ser(ret), 'ret') ??
          diff(out['args'], ser(args), 'args');
      if (mismatch != null) {
        failures.add('#$i $key: $mismatch');
      } else {
        agreed++;
      }
    }
    expect(failures, isEmpty, reason: '${failures.length} of ${cases.length} disagree; first: ${failures.take(8).join('\n')}');
    expect(agreed, greaterThan(5000));
  });
}
