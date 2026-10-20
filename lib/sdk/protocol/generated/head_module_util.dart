// GENERATED FILE — do not edit by hand.
//
// Transpiled from the edelkrone Python SDK 0.1.0 (protocol/_generated/head_module_util.py) by
// tool/sdk_port/py2dart.py. That file is itself a transliteration of the
// official edelkrone app's Dart protocol library, so this is a round trip back
// to Dart. Verified byte for byte against the Python original by
// test/sdk/codec_vectors_test.dart.
//
// Copyright (c) 2026 edelkrone. MIT licensed; see lib/sdk/LICENSE.
//
// ignore_for_file: constant_identifier_names, non_constant_identifier_names, unnecessary_parenthesis, prefer_final_locals, unused_local_variable, prefer_const_constructors, unnecessary_this, prefer_initializing_formals, unused_import, curly_braces_in_flow_control_structures, unnecessary_brace_in_string_interps, dead_code

class LibHeadModuleUtil {

  static void put32b(List<int> ptr, int offset, int val) {
    ptr[offset] = ((val & 0xFF000000) >> 24);
    ptr[(offset + 1)] = ((val & 0xFF0000) >> 16);
    ptr[(offset + 2)] = ((val & 0xFF00) >> 8);
    ptr[(offset + 3)] = ((val & 0xFF) >> 0);
  }

  static void put16b(List<int> ptr, int offset, int val) {
    ptr[offset] = ((val & 0xFF00) >> 8);
    ptr[(offset + 1)] = ((val & 0xFF) >> 0);
  }

  static int make32b(List<int> ptr, int base) {
    late int value;
    value = ((((ptr[base] << 24) | (ptr[(base + 1)] << 16)) | (ptr[(base + 2)] << 8)) | ptr[(base + 3)]);
    if (((value & 0x80000000) != 0)) {
      return (value | -0x100000000);
    }
    return value;
  }

  static int makeU24b(List<int> ptr, int base) {
    return ((((ptr[base] << 16) | (ptr[(base + 1)] << 8)) | ptr[(base + 2)]) >>> 0);
  }

  static int makeS24b(List<int> ptr, int base) {
    late int val;
    val = (((ptr[base] << 16) | (ptr[(base + 1)] << 8)) | ptr[(base + 2)]);
    return (val).toSigned(24);
  }

  static int make16b(List<int> ptr, int base) {
    late int value;
    value = ((ptr[base] << 8) | ptr[(base + 1)]);
    return ((value > 0x7FFF) ? (value - 0x10000) : value);
  }

  static int makeS8b(List<int> ptr, int base) {
    return ((ptr[base] & 0xFF)).toSigned(8);
  }
}
