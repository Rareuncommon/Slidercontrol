/// The control page, rendered against the simulated rig at real screen sizes.
///
/// The page is meant to show everything at once with nothing to scroll, and
/// Flutter only reports a layout overflow when it renders — so this renders
/// it, on a small phone, a large phone, both ways up, and a laptop window.
///
/// Run with `flutter test test_widget` (it needs the Flutter binding, so it
/// lives outside test/, which runs under plain `dart test`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/app/rig_controller.dart';
import '../lib/control/stop_registry.dart';
import '../lib/ui/rig_page.dart';

import '../test/sdk/fake_rig.dart';

Future<(RigController, FakeHeadLink)> joinedRig() async {
  final link = FakeHeadLink(unit: fakeHeadUnit(group: 0x0101));
  final c = RigController(
    transport: FakeTransport(link, seen: [link.device, fakeSliderUnit()]),
    registry: StopRegistry(),
  );
  await c.startScan();
  final head = c.seen.firstWhere((s) => s.name == 'HeadONE V2');
  await c.connect(head, join: c.joinable(head));
  link.pan = 0;
  await c.save(0, name: 'wide');
  link
    ..pan = 35
    ..slide = 60;
  await c.save(1, name: 'push in');
  link.pan = 80;
  await c.save(2);
  return (c, link);
}

void main() {
  const sizes = {
    'small phone': Size(360, 640),
    'phone': Size(390, 844),
    'large phone': Size(430, 932),
    'phone, landscape': Size(844, 390),
    'tablet': Size(820, 1180),
    'laptop window': Size(1280, 800),
  };

  for (final entry in sizes.entries) {
    testWidgets(
      'fits a ${entry.key} (${entry.value.width.toInt()}×${entry.value.height.toInt()}) with nothing cut off',
      (tester) async {
        final (c, _) = (await tester.runAsync(joinedRig))!;
        // Real timers drive the simulated rig, so the disconnect must run even
        // when the test fails, or the run hangs on them.
        addTearDown(() => tester.runAsync(c.disconnect));
        tester.view
          ..physicalSize = entry.value * 3
          ..devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark, useMaterial3: true),
            home: RigPage(controller: c),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull, reason: 'a RenderFlex overflow is reported as an exception');
        expect(find.text('STOP ALL · Esc'), findsOneWidget);
        expect(find.text('PAN'), findsWidgets);
        expect(find.text('SLIDE'), findsWidgets);
        expect(find.text('wide'), findsOneWidget);
        expect(find.text('push in'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
