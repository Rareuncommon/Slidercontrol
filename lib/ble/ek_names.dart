/// Recognising an edelkrone device by its advertised name.
///
/// Kept free of any BLE or Flutter import so it stays under `dart test` with
/// the rest of the protocol layer. CoreBluetooth hides MAC addresses and hands
/// out per-host UUIDs, so the advertised name is the only identifier that means
/// the same thing on two different machines (EDELKRONE_PROTOCOL.md §9).
library;

/// Advertised names, per §1: `SldrPlsV1` and `HeadOneFM`.
///
/// Matched case-insensitively as a prefix, so firmware that appends a suffix
/// still resolves. The `V1` in the slider's name is an advertising version, not
/// the product generation — a v6 slider still advertises `SldrPlsV1` — so the
/// prefix deliberately stops before it.
const ekKnownNamePrefixes = ['sldrpls', 'headone'];

/// Whether an advertised name belongs to an edelkrone device we can drive.
///
/// This gate exists separately from `EkProfile.forName`, which answers a
/// different question. `forName` falls back to the slider for anything it does
/// not recognise — the right default *once a device is known to be edelkrone*,
/// but it would label every unrelated peripheral in the room a slider if fed
/// raw scan results. So a device must pass here first, then get its profile.
bool isEdelkroneName(String? advertisedName) {
  final n = (advertisedName ?? '').toLowerCase();
  return ekKnownNamePrefixes.any(n.startsWith);
}
