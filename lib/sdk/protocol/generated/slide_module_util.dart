// GENERATED FILE — do not edit by hand.
//
// Transpiled from the edelkrone Python SDK 0.1.0 (protocol/_generated/slide_module_util.py) by
// tool/sdk_port/py2dart.py. That file is itself a transliteration of the
// official edelkrone app's Dart protocol library, so this is a round trip back
// to Dart. Verified byte for byte against the Python original by
// test/sdk/codec_vectors_test.dart.
//
// Copyright (c) 2026 edelkrone. MIT licensed; see lib/sdk/LICENSE.
//
// ignore_for_file: constant_identifier_names, non_constant_identifier_names, unnecessary_parenthesis, prefer_final_locals, unused_local_variable, prefer_const_constructors, unnecessary_this, prefer_initializing_formals, unused_import, curly_braces_in_flow_control_structures, unnecessary_brace_in_string_interps, dead_code

class LibSlideModuleUtil {

  static bool checkBit(int reg, int bit) {
    return (((reg & (1 << bit)) >> bit) != 0);
  }

  static void put32b(List<int> data, int offset, int val) {
    data[offset] = ((val >> 24) & 0xFF);
    data[(offset + 1)] = ((val >> 16) & 0xFF);
    data[(offset + 2)] = ((val >> 8) & 0xFF);
    data[(offset + 3)] = (val & 0xFF);
  }

  static void put16b(List<int> data, int offset, int val) {
    data[offset] = ((val >> 8) & 0xFF);
    data[(offset + 1)] = (val & 0xFF);
  }

  static int makeU32b(List<int> data, int base) {
    return (((((data[base] << 24) | (data[(base + 1)] << 16)) | (data[(base + 2)] << 8)) | data[(base + 3)]) & 0xFFFFFFFF);
  }

  static int make32b(List<int> data, int base) {
    late int value;
    value = ((((data[base] << 24) | (data[(base + 1)] << 16)) | (data[(base + 2)] << 8)) | data[(base + 3)]);
    if (((value & 0x80000000) != 0)) {
      return (value | -0x100000000);
    }
    return value;
  }

  static int makeU24b(List<int> data, int base) {
    return ((((data[base] << 16) | (data[(base + 1)] << 8)) | data[(base + 2)]) & 0xFFFFFF);
  }

  static int make16b(List<int> data, int base) {
    late int value;
    value = ((data[base] << 8) | data[(base + 1)]);
    if (((value & 0x8000) != 0)) {
      return (value | 0xFFFF0000);
    }
    return value;
  }
}
