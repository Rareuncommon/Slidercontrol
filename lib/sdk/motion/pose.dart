/// Positions in degrees and centimetres, and how a reading is assembled.
///
/// Ported from `edelkrone/motion/{rig_pose,pose_from_state}.py`.
///
/// This is what the reverse-engineered client could not do: the HeadONE
/// reports its position. The periodic status frame carries no position for
/// any unit — which is what the captures showed, and why the spec concluded
/// the head reports none — but a separate numeric readout (index 255) does,
/// for the head as for the slider.
///
/// Copyright (c) 2026 edelkrone. MIT licensed; see lib/sdk/LICENSE.
library;

import '../protocol/generated/head_module.dart';
import '../protocol/generated/moco.dart';
import '../session/core.dart';
import '../session/state.dart';

enum RigAxis {
  pan('PAN', '°', true),
  tilt('TILT', '°', true),
  slide('SLIDE', ' cm', false),
  focus('FOCUS', ' cm', false),
  jibPan('JIB PAN', '°', true),
  jibTilt('JIB TILT', '°', true);

  const RigAxis(this.label, this.unit, this.angular);
  final String label;
  final String unit;
  final bool angular;

  String format(double v) => '${v.toStringAsFixed(angular ? 2 : 1)}$unit';
}

/// The protocol's marker for an axis that is not fitted.
const axisNotFitted = -1.0;

double? _fitted(double? v) => (v == null || v == axisNotFitted) ? null : v;

/// A position of the equipment. An axis is null if it is not present or has
/// not been reported.
class RigPose {
  const RigPose({this.panDeg, this.tiltDeg, this.slideCm, this.focusCm, this.jibPanDeg, this.jibTiltDeg});

  factory RigPose.fromRaw({
    double? panDeg,
    double? tiltDeg,
    double? slideCm,
    double? focusCm,
    double? jibPanDeg,
    double? jibTiltDeg,
  }) => RigPose(
    panDeg: _fitted(panDeg),
    tiltDeg: _fitted(tiltDeg),
    slideCm: _fitted(slideCm),
    focusCm: _fitted(focusCm),
    jibPanDeg: _fitted(jibPanDeg),
    jibTiltDeg: _fitted(jibTiltDeg),
  );

  static const unknown = RigPose();

  final double? panDeg;
  final double? tiltDeg;
  final double? slideCm;
  final double? focusCm;
  final double? jibPanDeg;
  final double? jibTiltDeg;

  double? operator [](RigAxis a) => switch (a) {
    RigAxis.pan => panDeg,
    RigAxis.tilt => tiltDeg,
    RigAxis.slide => slideCm,
    RigAxis.focus => focusCm,
    RigAxis.jibPan => jibPanDeg,
    RigAxis.jibTilt => jibTiltDeg,
  };

  Set<RigAxis> get presentAxes => {
    for (final a in RigAxis.values)
      if (this[a] != null) a,
  };
  bool get isEmpty => presentAxes.isEmpty;

  /// This pose with every axis outside [keep] blanked.
  RigPose only(Set<RigAxis> keep) => RigPose(
    panDeg: keep.contains(RigAxis.pan) ? panDeg : null,
    tiltDeg: keep.contains(RigAxis.tilt) ? tiltDeg : null,
    slideCm: keep.contains(RigAxis.slide) ? slideCm : null,
    focusCm: keep.contains(RigAxis.focus) ? focusCm : null,
    jibPanDeg: keep.contains(RigAxis.jibPan) ? jibPanDeg : null,
    jibTiltDeg: keep.contains(RigAxis.jibTilt) ? jibTiltDeg : null,
  );

  @override
  String toString() {
    final parts = [
      for (final a in RigAxis.values)
        if (this[a] != null) '${a.label} ${a.format(this[a]!)}',
    ];
    return parts.isEmpty ? 'RigPose(unknown)' : 'RigPose(${parts.join(', ')})';
  }
}

class AbsoluteReading {
  const AbsoluteReading({required this.pose, this.slideFraction, this.trusted = true});
  final RigPose pose;
  final double? slideFraction;
  final bool trusted;
}

const livePositionIndex = 255;

bool? headHasJib(LibHeadModuleMk2Status? status) {
  if (status == null) return null;
  if (status.configuration.name.contains('JIB')) return true;
  if (status.configuration != EdlSetup.NONE && status.configuration != EdlSetup.POSSIBLE_CANBUS_MASTER) {
    return false;
  }
  return status.jibOneA0Ind != 0 || status.jiboneSetupAngleDegEstimation != 0;
}

AbsoluteReading? absoluteReadingOf(DeviceState state) => switch (state.family) {
  DeviceFamily.headModule => _headReading(state as HeadModuleState),
  DeviceFamily.slideModule => _slideReading(state as SlideModuleState),
  _ => null,
};

AbsoluteReading? _headReading(HeadModuleState state) {
  final numeric = state.numericReadout;
  final status = state.generalStatus;
  bool? fitted = status == null ? null : status.haveFocusModule == 1;
  final lensed = status == null ? null : status.lensCalibrated == 1;
  if (fitted != false && lensed == false) fitted = false;
  final focusFromStatus = (status == null || fitted == false) ? null : status.currentFocusDistanceCm;
  final jibbed = headHasJib(status);
  if (numeric == null) {
    if (focusFromStatus == null) return null;
    return AbsoluteReading(pose: RigPose.fromRaw(focusCm: focusFromStatus));
  }
  final r = numeric.value;
  final jibPairOk = r.jibPanDeg != axisNotFitted && r.jibTiltDeg != axisNotFitted;
  final jibOk = jibbed != false && jibPairOk;
  final pose = RigPose.fromRaw(
    slideCm: r.sliderCm,
    focusCm: fitted == false ? null : (focusFromStatus ?? r.focusCm),
    jibPanDeg: jibOk ? r.jibPanDeg : null,
    jibTiltDeg: jibOk ? r.jibTiltDeg : null,
  );
  // Pan and tilt are taken as reported, not filtered for "not fitted": the
  // SDK replaces them after the filter, so -1.0 is a real angle here.
  return AbsoluteReading(
    pose: RigPose(
      panDeg: r.panDeg,
      tiltDeg: r.tiltDeg,
      slideCm: pose.slideCm,
      focusCm: pose.focusCm,
      jibPanDeg: pose.jibPanDeg,
      jibTiltDeg: pose.jibTiltDeg,
    ),
    trusted: numeric.index == livePositionIndex,
  );
}

AbsoluteReading? _slideReading(SlideModuleState state) {
  final numeric = state.numericReadout;
  final fraction = state.generalStatus?.positionRelative;
  if (numeric == null && fraction == null) return null;
  return AbsoluteReading(
    pose: numeric == null ? RigPose.unknown : RigPose.fromRaw(slideCm: numeric.value),
    slideFraction: fraction,
    trusted: numeric == null || numeric.index == livePositionIndex,
  );
}
