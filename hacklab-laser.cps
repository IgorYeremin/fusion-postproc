
description = "Hacklab.to laser cutter";
vendor = "hacklab.to";
vendorUrl = "https://hacklab.to";
legal = "???";
certificationLevel = 2;
minimumRevision = 39000;

longDescription = "Uses M3/M5 for laser power, sets tool diameter to allow G41/G42 tool compensation.";

capabilities = CAPABILITY_JET;
extension = "ngc";
setCodePage("ascii");

tolerance = spatial(0.002, MM);

minimumChordLength = spatial(0.01, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);
allowHelicalMoves = false;
allowedCircularPlanes = undefined; // allow any circular motion



// user-defined properties
properties = {
  writeMachine: true, // write machine
  showSequenceNumbers: true, // show sequence numbers
  sequenceNumberStart: 10, // first sequence number
  sequenceNumberIncrement: 5, // increment for sequence numbers
  allowHeadSwitches: true, // output code to allow heads to be manually switched for piercing and cutting
  useRetracts: true, // output retracts - otherwise only output part contours for importing in third-party jet application
  separateWordsWithSpace: true, // specifies that the words should be separated with a white space
  cutLeadInOut: false // is the laser on when doing lead-in and lead-out moves?
};



var gFormat = createFormat({prefix:"G", decimals:0});
var mFormat = createFormat({prefix:"M", decimals:0});
var lFormat = createFormat({prefix:"L", decimals:0});
var pFormat = createFormat({prefix:"P", decimals:0});
var qFormat = createFormat({prefix:"Q", decimals:0});
var rFormat = createFormat({prefix:"R", decimals:(unit == MM ? 4 : 5)});
var sFormat = createFormat({prefix:"S", decimals:0});

var xyzFormat = createFormat({decimals:(unit == MM ? 3 : 4)});
var feedFormat = createFormat({decimals:(unit == MM ? 1 : 2)});
var secFormat = createFormat({decimals:3, forceDecimal:true}); // seconds - range 0.001-1000

var xOutput = createVariable({prefix:"X"}, xyzFormat);
var yOutput = createVariable({prefix:"Y"}, xyzFormat);
var feedOutput = createVariable({prefix:"F"}, feedFormat);

// circular output
var iOutput = createReferenceVariable({prefix:"I"}, xyzFormat);
var jOutput = createReferenceVariable({prefix:"J"}, xyzFormat);

var gMotionModal = createModal({}, gFormat); // modal group 1 // G0-G3, ...
var gAbsIncModal = createModal({}, gFormat); // modal group 3 // G90-91
var gUnitModal = createModal({}, gFormat); // modal group 6 // G20-21

var WARNING_WORK_OFFSET = 0;

// collected state
var sequenceNumber;
var currentWorkOffset;
var split = false;

/**
  Writes the specified block.
*/
function writeBlock() {
  if (properties.showSequenceNumbers) {
    writeWords2("N" + sequenceNumber, arguments);
    sequenceNumber += properties.sequenceNumberIncrement;
  } else {
    writeWords(arguments);
  }
}

function formatComment(text) {
  return "(" + String(text).replace(/[\(\)]/g, "") + ")";
}

/**
  Output a comment.
*/
function writeComment(text) {
  writeln(formatComment(text));
}

function onOpen() {
  
  if (!properties.separateWordsWithSpace) {
    setWordSeparator("");
  }

  sequenceNumber = properties.sequenceNumberStart;

  if (programName) {
    writeComment(programName);
  }
  if (programComment) {
    writeComment(programComment);
  }

  // dump machine configuration
  var vendor = machineConfiguration.getVendor();
  var model = machineConfiguration.getModel();
  var description = machineConfiguration.getDescription();

  if (properties.writeMachine && (vendor || model || description)) {
    writeComment(localize("Machine"));
    if (vendor) {
      writeComment("  " + localize("vendor") + ": " + vendor);
    }
    if (model) {
      writeComment("  " + localize("model") + ": " + model);
    }
    if (description) {
      writeComment("  " + localize("description") + ": "  + description);
    }
  }

  if (hasGlobalParameter("material")) {
    writeComment("MATERIAL = " + getGlobalParameter("material"));
  }

  if (hasGlobalParameter("material-hardness")) {
    writeComment("MATERIAL HARDNESS = " + getGlobalParameter("material-hardness"));
  }

  { // stock - workpiece
    var workpiece = getWorkpiece();
    var delta = Vector.diff(workpiece.upper, workpiece.lower);
    if (delta.isNonZero()) {
      writeComment("THICKNESS = " + xyzFormat.format(workpiece.upper.z - workpiece.lower.z));
    }
  }

  // absolute coordinates and feed per min
  writeBlock(gAbsIncModal.format(90));
  
  switch (unit) {
  case IN:
    writeBlock(gUnitModal.format(20));
    break;
  case MM:
    writeBlock(gUnitModal.format(21));
    break;
  }

  // motion blending with tolerance
  writeBlock(gFormat.format(64) + " P" + xyzFormat.format(tolerance));

  // non-zero spindle speed
  writeBlock(sFormat.format(123456));

  // spindle off
  writeBlock(mFormat.format(5));

  // laser enable on
  writeBlock(
    mFormat.format(63),
    pFormat.format(0)
  );
}

function onComment(message) {
  writeComment(message);
}

/** Force output of X, Y, and Z. */
function forceXYZ() {
  xOutput.reset();
  yOutput.reset();
}

/** Force output of X, Y, Z, A, B, C, and F on next output. */
function forceAny() {
  forceXYZ();
  feedOutput.reset();
}

function onSection() {
  var insertToolCall = isFirstSection() ||
    currentSection.getForceToolChange && currentSection.getForceToolChange() ||
    (tool.number != getPreviousSection().getTool().number) ||
    (tool.jetDiameter != getPreviousSection().getTool().jetDiameter);
  
  var retracted = false; // specifies that the tool has been retracted to the safe plane
  var newWorkOffset = isFirstSection() ||
    (getPreviousSection().workOffset != currentSection.workOffset); // work offset changes
  var newWorkPlane = isFirstSection() ||
    !isSameDirection(getPreviousSection().getGlobalFinalToolAxis(), currentSection.getGlobalInitialToolAxis());

  writeln("");

  if (hasParameter("operation-comment")) {
    var comment = getParameter("operation-comment");
    if (comment) {
      writeComment(comment);
    }
  }

  if (insertToolCall) {
    retracted = true;
    onCommand(COMMAND_COOLANT_OFF);

    switch (tool.type) {
    case TOOL_LASER_CUTTER:
      writeComment("laser cutting");
      break;
    default:
      error(localize("This post processor only support the Laser Cutter tool mode."));
      return;
    }
    writeln("");

    writeComment("tool.jetDiameter = " + xyzFormat.format(tool.jetDiameter));
    writeComment("tool.jetDistance = " + xyzFormat.format(tool.jetDistance));
    writeBlock(
      gFormat.format(10),
      lFormat.format(1), // set tool table
      pFormat.format(1), // tool #1
      rFormat.format(tool.jetDiameter / 2 * .995) // fudge factor because generated lead arcs are very close to this radius, and linuxcnc does not like that
    );
    writeBlock(
      mFormat.format(61), // override current tool
      qFormat.format(1) // tool #1
    );
    writeln("");

    switch (currentSection.jetMode) {
    case JET_MODE_THROUGH:
      writeComment("THROUGH CUTTING");
      break;
    case JET_MODE_ETCHING:
      writeComment("ETCH CUTTING");
      break;
    case JET_MODE_VAPORIZE:
      writeComment("VAPORIZE CUTTING");
      break;
    default:
      error(localize("Unsupported cutting mode."));
      return;
    }
    writeComment("QUALITY = " + currentSection.quality);

    if (tool.comment) {
      writeComment(tool.comment);
    }
    writeln("");
  }

/*
  // wcs
  if (insertToolCall) { // force work offset when changing tool
    currentWorkOffset = undefined;
  }
  var workOffset = currentSection.workOffset;
  if (workOffset == 0) {
    warningOnce(localize("Work offset has not been specified. Using G54 as WCS."), WARNING_WORK_OFFSET);
    workOffset = 1;
  }
  if (workOffset > 0) {
    if (workOffset > 6) {
      var code = workOffset - 6;
      if (code > 3) {
        error(localize("Work offset out of range."));
        return;
      }
      if (workOffset != currentWorkOffset) {
        writeBlock(gFormat.format(59) + "." + code);
        currentWorkOffset = workOffset;
      }
    } else {
      if (workOffset != currentWorkOffset) {
        writeBlock(gFormat.format(53 + workOffset)); // G54->G59
        currentWorkOffset = workOffset;
      }
    }
  }
*/

  forceXYZ();

  { // pure 3D
    var remaining = currentSection.workPlane;
    if (!isSameDirection(remaining.forward, new Vector(0, 0, 1))) {
      error(localize("Tool orientation is not supported."));
      return;
    }
    setRotation(remaining);
  }

/*
  // set coolant after we have positioned at Z
  if (false) {
    var c = mapCoolantTable.lookup(tool.coolant);
    if (c) {
      writeBlock(mFormat.format(c));
    } else {
      warning(localize("Coolant not supported."));
    }
  }
*/

  forceAny();

  split = false;
  if (properties.useRetracts) {

    var initialPosition = getFramePosition(currentSection.getInitialPosition());

    if (insertToolCall || retracted) {
      gMotionModal.reset();

      if (!machineConfiguration.isHeadConfiguration()) {
        writeBlock(
          gAbsIncModal.format(90),
          gMotionModal.format(0), xOutput.format(initialPosition.x), yOutput.format(initialPosition.y)
        );
      } else {
        writeBlock(
          gAbsIncModal.format(90),
          gMotionModal.format(0),
          xOutput.format(initialPosition.x),
          yOutput.format(initialPosition.y)
        );
      }
    } else {
      writeBlock(
        gAbsIncModal.format(90),
        gMotionModal.format(0),
        xOutput.format(initialPosition.x),
        yOutput.format(initialPosition.y)
      );
    }
  } else {
    split = true;
  }
}

function onDwell(seconds) {
  if (seconds > 99999.999) {
    warning(localize("Dwelling time is out of range."));
  }
  seconds = clamp(0.001, seconds, 99999.999);
  writeBlock(gFormat.format(4), "X" + secFormat.format(seconds));
}

function onCycle() {
  onError("Drilling is not supported by CNC.");
}

var pendingRadiusCompensation = -1;

function onRadiusCompensation() {
  pendingRadiusCompensation = radiusCompensation;
}

var shapeArea = 0;
var shapePerimeter = 0;
var shapeSide = "inner";
var cuttingSequence = "";

function onParameter(name, value) {
  if ((name == "action") && (value == "pierce")) {
    writeComment("RUN POINT-PIERCE COMMAND HERE");
  } else if (name == "shapeArea") {
    shapeArea = value;
    writeComment("SHAPE AREA = " + xyzFormat.format(shapeArea));
  } else if (name == "shapePerimeter") {
    shapePerimeter = value;
    writeComment("SHAPE PERIMETER = " + xyzFormat.format(shapePerimeter));
  } else if (name == "shapeSide") {
    shapeSide = value;
    writeComment("SHAPE SIDE = " + value);
  } else if (name == "beginSequence") {
    if (value == "piercing") {
      if (cuttingSequence != "piercing") {
        if (properties.allowHeadSwitches) {
          writeln("");
          writeComment("Switch to piercing head before continuing");
          onCommand(COMMAND_STOP);
          writeln("");
        }
      }
    } else if (value == "cutting") {
      if (cuttingSequence == "piercing") {
        if (properties.allowHeadSwitches) {
          writeln("");
          writeComment("Switch to cutting head before continuing");
          onCommand(COMMAND_STOP);
          writeln("");
        }
      }
    }
    cuttingSequence = value;
  }
}

var powerOn = false;
var beamOn = false;

function setBeamOn(enable) {
  if ((powerOn && enable) != beamOn) {
    beamOn = enable;
    if (beamOn) {
      writeBlock(mFormat.format(3));
    } else {
      writeBlock(mFormat.format(5));
    }
  }
}

function onPower(power) {
  powerOn = power;
}

function onMovement(movement) {
  switch (movement) {
  case MOVEMENT_CUTTING:
  case MOVEMENT_FINISH_CUTTING:
    setBeamOn(true);
    break;
  case MOVEMENT_LEAD_IN:
  case MOVEMENT_LEAD_OUT:
    setBeamOn(properties.cutLeadInOut);
    break;
  case MOVEMENT_RAPID:
    setBeamOn(false);
    break;
  default:
    writeComment("Unhandled onMovement: " + movement);
  }
}

function onRapid(_x, _y, _z) {

  if (!properties.useRetracts && ((movement == MOVEMENT_RAPID) || (movement == MOVEMENT_HIGH_FEED))) {
    doSplit();
    return;
  }

  if (split) {
    split = false;
    var start = getCurrentPosition();
    onRapid(start.x, start.y, start.z);
  }

  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  if (x || y) {
    if (pendingRadiusCompensation >= 0) {
      error(localize("Radius compensation mode cannot be changed at rapid traversal."));
      return;
    }
    writeBlock(gMotionModal.format(0), x, y);
    feedOutput.reset();
  }
}

function onLinear(_x, _y, _z, feed) {

  if (!properties.useRetracts && ((movement == MOVEMENT_RAPID) || (movement == MOVEMENT_HIGH_FEED))) {
    doSplit();
    return;
  }

  if (split) {
    resumeFromSplit(feed);
  }

  // at least one axis is required
  if (pendingRadiusCompensation >= 0) {
    // ensure that we end at desired position when compensation is turned off
    xOutput.reset();
    yOutput.reset();
  }
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var f = feedOutput.format(feed);
  if (x || y) {
    if (pendingRadiusCompensation >= 0) {
      pendingRadiusCompensation = -1;
      switch (radiusCompensation) {
      case RADIUS_COMPENSATION_LEFT:
        writeBlock(gFormat.format(41));
        writeBlock(gMotionModal.format(1), x, y, f);
        break;
      case RADIUS_COMPENSATION_RIGHT:
        writeBlock(gFormat.format(42));
        writeBlock(gMotionModal.format(1), x, y, f);
        break;
      default:
        writeBlock(gFormat.format(40));
        writeBlock(gMotionModal.format(1), x, y, f);
      }
    } else {
      writeBlock(gMotionModal.format(1), x, y, f);
    }
  } else if (f) {
    if (getNextRecord().isMotion()) { // try not to output feed without motion
      feedOutput.reset(); // force feed on next line
    } else {
      writeBlock(gMotionModal.format(1), f);
    }
  }
}

function onRapid5D(_x, _y, _z, _a, _b, _c) {
  error(localize("The CNC does not support 5-axis simultaneous toolpath."));
}

function onLinear5D(_x, _y, _z, _a, _b, _c, feed) {
  error(localize("The CNC does not support 5-axis simultaneous toolpath."));
}

function doSplit() {
  if (!split) {
    split = true;
    gMotionModal.reset();
    xOutput.reset();
    yOutput.reset();
    feedOutput.reset();
  }
}

function resumeFromSplit(feed) {
  if (split) {
    split = false;
    var start = getCurrentPosition();
    var _pendingRadiusCompensation = pendingRadiusCompensation;
    pendingRadiusCompensation = -1;
    onLinear(start.x, start.y, start.z, feed);
    pendingRadiusCompensation = _pendingRadiusCompensation;
  }
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {

  if (!properties.useRetracts && ((movement == MOVEMENT_RAPID) || (movement == MOVEMENT_HIGH_FEED))) {
    doSplit();
    return;
  }

  // one of X/Y and I/J are required and likewise
  
  if (pendingRadiusCompensation >= 0) {
    error(localize("Radius compensation cannot be activated/deactivated for a circular move."));
    return;
  }

  if (split) {
    resumeFromSplit(feed);
  }

  var start = getCurrentPosition();
  if (isFullCircle()) {
    if (isHelical()) {
      linearize(tolerance);
      return;
    }
    switch (getCircularPlane()) {
    case PLANE_XY:
      writeBlock(gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0), feedOutput.format(feed));
      break;
    default:
      linearize(tolerance);
    }
  } else {
    switch (getCircularPlane()) {
    case PLANE_XY:
      writeBlock(gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0), feedOutput.format(feed));
      break;
    default:
      linearize(tolerance);
    }
  }
}

var mapCommand = {
  COMMAND_STOP:0,
  COMMAND_OPTIONAL_STOP:1,
  COMMAND_END:2
};

function onCommand(command) {
  switch (command) {
  case COMMAND_POWER_ON:
    return;
  case COMMAND_POWER_OFF:
    return;
  case COMMAND_COOLANT_ON:
    return;
  case COMMAND_COOLANT_OFF:
    return;
  case COMMAND_LOCK_MULTI_AXIS:
    return;
  case COMMAND_UNLOCK_MULTI_AXIS:
    return;
  case COMMAND_BREAK_CONTROL:
    return;
  case COMMAND_TOOL_MEASURE:
    return;
  }

  var stringId = getCommandStringId(command);
  var mcode = mapCommand[stringId];
  if (mcode != undefined) {
    writeBlock(mFormat.format(mcode));
  } else {
    onUnsupportedCommand(command);
  }
}

function onSectionEnd() {
  setBeamOn(false);
  forceAny();
}

function onClose() {
  writeln("");
  
  onCommand(COMMAND_COOLANT_OFF);

  // spindle off
  writeBlock(mFormat.format(5));

  writeBlock(
    mFormat.format(61), // override current tool
    qFormat.format(0) // no tool
  );

  // laser enable off
  writeBlock(
    mFormat.format(63),
    pFormat.format(0)
  );

  onImpliedCommand(COMMAND_END);
  writeBlock(mFormat.format(30)); // stop program
}
