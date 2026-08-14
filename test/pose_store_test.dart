/// Keypose slots.
///
/// The rules under test come straight from §3: poses are volatile, and nothing
/// reads them back off the device. So "saved earlier" can never be upgraded to
/// "still there" by anything except saving again.
library;

import 'package:test/test.dart';

import '../lib/control/pose_store.dart';

void main() {
  group('slots', () {
    test('starts with the two slots the captures cover', () {
      final set = PoseSet.initial();
      expect(set.length, 2);
      expect(set.poses.map((p) => p.slot), [0, 1]);
      expect(set.poses.every((p) => p.isEmpty), isTrue);
    });

    test('adds the lowest free slot number', () {
      var set = PoseSet.initial().withNewSlot();
      expect(set.poses.map((p) => p.slot), [0, 1, 2]);
      set = set.withNewSlot();
      expect(set.poses.map((p) => p.slot), [0, 1, 2, 3]);
    });

    test('reuses a gap left by a removed slot', () {
      var set = PoseSet.initial().withNewSlot().withNewSlot();
      set = set.withoutSlot(1);
      expect(set.poses.map((p) => p.slot), [0, 2, 3]);
      set = set.withNewSlot();
      expect(set.poses.map((p) => p.slot), [0, 1, 2, 3]);
    });

    test('never removes the last slot', () {
      var set = PoseSet([const Pose(slot: 0)]);
      set = set.withoutSlot(0);
      expect(set.length, 1);
    });

    test('refuses to exceed what a single slot byte can carry', () {
      var set = PoseSet([
        for (var i = 0; i <= 255; i++) Pose(slot: i),
      ]);
      final before = set.length;
      set = set.withNewSlot();
      expect(set.length, before, reason: 'the slot is one payload byte');
    });
  });

  group('saving and clearing', () {
    test('a saved slot records position and time', () {
      final set = PoseSet.initial().withSaved(0, counts: 12345, fraction: 0.25);
      final p = set.bySlot(0)!;
      expect(p.isSet, isTrue);
      expect(p.counts, 12345);
      expect(p.fraction, 0.25);
      expect(p.savedAt, isNotNull);
      expect(p.isVerified, isTrue, reason: 'just written this session');
    });

    test('re-saving over an occupied slot replaces it without ceremony', () {
      var set = PoseSet.initial().withSaved(0, counts: 100);
      set = set.withSaved(0, counts: 900);
      expect(set.bySlot(0)!.counts, 900);
      expect(set.length, 2);
    });

    test('clearing empties the slot but keeps its name', () {
      var set = PoseSet.initial().withName(0, 'wide').withSaved(0, counts: 5);
      set = set.withCleared(0);
      final p = set.bySlot(0)!;
      expect(p.isEmpty, isTrue);
      expect(p.counts, isNull);
      expect(p.name, 'wide', reason: 'clearing a pose should not lose its label');
    });

    test('names are free text and independent of contents', () {
      final set = PoseSet.initial().withName(1, 'tight');
      expect(set.bySlot(1)!.name, 'tight');
      expect(set.bySlot(1)!.isEmpty, isTrue);
    });
  });

  group('verification after a reconnect', () {
    test('every slot reverts to unverified', () {
      // The device may have been power-cycled, and §3 gives no way to ask it.
      var set = PoseSet.initial().withSaved(0, counts: 1).withSaved(1, counts: 2);
      expect(set.poses.every((p) => p.isVerified), isTrue);

      set = set.asUnverified();

      expect(set.poses.every((p) => p.isVerified), isFalse);
      expect(set.poses.every((p) => p.isSet), isTrue,
          reason: 'still recorded, just no longer known to be on the device');
    });

    test('a pose loaded from disk is never verified', () {
      final saved = PoseSet.initial().withSaved(0, counts: 42);
      final reloaded = PoseSet.decode(saved.encode());
      expect(reloaded.bySlot(0)!.isSet, isTrue);
      expect(reloaded.bySlot(0)!.isVerified, isFalse);
    });
  });

  group('restorability', () {
    test('a pose with a fraction can survive a power cycle', () {
      final set = PoseSet.initial().withSaved(0, counts: 5000, fraction: 0.4);
      expect(set.bySlot(0)!.isRestorable, isTrue);
    });

    test('a pose saved without homing cannot', () {
      // Raw counts are arbitrary per session, so they mean nothing next time.
      final set = PoseSet.initial().withSaved(0, counts: 5000);
      expect(set.bySlot(0)!.isRestorable, isFalse);
    });
  });

  group('persistence', () {
    test('round-trips names, counts, fractions and times', () {
      final set = PoseSet.initial()
          .withName(0, 'wide')
          .withSaved(0, counts: 1234, fraction: 0.1)
          .withNewSlot()
          .withName(2, 'tight')
          .withSaved(2, counts: 9999, fraction: 0.9);

      final back = PoseSet.decode(set.encode());

      expect(back.length, 3);
      expect(back.bySlot(0)!.name, 'wide');
      expect(back.bySlot(0)!.counts, 1234);
      expect(back.bySlot(0)!.fraction, closeTo(0.1, 1e-9));
      expect(back.bySlot(2)!.name, 'tight');
      expect(back.bySlot(2)!.fraction, closeTo(0.9, 1e-9));
      expect(back.bySlot(1)!.isEmpty, isTrue);
    });

    test('a corrupt store falls back to the default rather than failing', () {
      expect(PoseSet.decode('not json').length, 2);
      expect(PoseSet.decode('[]').length, 2);
      expect(PoseSet.decode(null).length, 2);
      expect(PoseSet.decode('{"not":"a list"}').length, 2);
    });

    test('an out-of-range stored fraction is clamped on load', () {
      const raw = '[{"slot":0,"name":"x","fraction":5.0,"savedAt":1}]';
      expect(PoseSet.decode(raw).bySlot(0)!.fraction, 1.0);
    });

    test('a non-finite stored fraction is dropped', () {
      const raw = '[{"slot":0,"name":"x","fraction":null,"savedAt":1}]';
      expect(PoseSet.decode(raw).bySlot(0)!.fraction, isNull);
    });
  });
}
