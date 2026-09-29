const commandLabel = document.querySelector("#last-command");
const estopButton = document.querySelector("#estop-button");

const REMOTE_TRANSPORT = {
  sendIntervalMs: 50
};

const ESTOP = {
  message: "ESTOP",
  repeat: 5,
  intervalMs: 20
};

let estopSent = false;

const joystickState = {
  move: { command: null },
  rotate: { command: null }
};

let transmitTimer = null;

function commandToLegacyTuple() {
  let x = 0;
  let y = 0;
  let z = 0;

  if (joystickState.move.command === "left") {
    x = -1;
  } else if (joystickState.move.command === "right") {
    x = 1;
  }

  if (joystickState.move.command === "forward") {
    y = 1;
  } else if (joystickState.move.command === "back") {
    y = -1;
  }

  if (joystickState.rotate.command === "rotate-left") {
    z = -1;
  } else if (joystickState.rotate.command === "rotate-right") {
    z = 1;
  }

  return `(${x},${y},${z})`;
}

function updateLastCommandLabel() {
  if (!commandLabel) {
    return;
  }

  commandLabel.textContent = commandToLegacyTuple();
}

function postPayload(payload) {
  const bridge = window.webkit?.messageHandlers?.remoteBLE;
  if (bridge) {
    bridge.postMessage({ payload });
  }

  window.dispatchEvent(
    new CustomEvent("remote-command", {
      detail: { command: payload, timestamp: Date.now() }
    })
  );
}

function sendRemoteState() {
  postPayload(commandToLegacyTuple());
}

function triggerEstop() {
  if (estopSent) {
    return;
  }

  estopSent = true;

  // Stop joystick messages so nothing else goes out after the E-Stop
  clearInterval(transmitTimer);
  transmitTimer = null;

  for (let i = 0; i < ESTOP.repeat; i += 1) {
    setTimeout(() => postPayload(ESTOP.message), i * ESTOP.intervalMs);
  }

  console.log("[REMOTE] E-STOP sent");
  document.body.classList.add("estopped");

  if (estopButton) {
    estopButton.textContent = "E-STOP SENT";
    estopButton.disabled = true;
  }

  if (commandLabel) {
    commandLabel.textContent = "E-STOP (reopen app to resume)";
  }
}

function ensureTransmitLoop() {
  if (transmitTimer || estopSent) {
    return;
  }

  transmitTimer = setInterval(sendRemoteState, REMOTE_TRANSPORT.sendIntervalMs);
}

function sendCommand(command) {
  console.log(`[REMOTE] ${command ?? "idle"}`);
}

function createJoystick(type) {
  const root = document.querySelector(`[data-joystick="${type}"]`);
  const knob = root?.querySelector(".joystick-knob");
  const readout = document.querySelector(`[data-readout="${type}"]`);

  if (!root || !knob) {
    return;
  }

  const engageZone = 0.34;
  const releaseZone = 0.24;
  const axisSwitchBias = 0.18;
  const maxRadiusFactor = 0.36;
  const smoothing = 0.34;
  let activePointerId = null;
  let activeCommand = null;
  let activeAxis = null;
  let targetX = 0;
  let targetY = 0;
  let renderedX = 0;
  let renderedY = 0;
  let animationId = null;

  const setReadout = (label) => {
    if (readout) {
      readout.textContent = label;
    }
  };

  const updateKnob = (xNorm, yNorm) => {
    const xPercent = xNorm * 100;
    const yPercent = yNorm * 100;
    knob.style.transform = `translate(calc(-50% + ${xPercent * maxRadiusFactor}%), calc(-50% + ${yPercent * maxRadiusFactor}%))`;
  };

  const applyJoystickConstraints = (xNorm, yNorm) => {
    if (type === "rotate") {
      return { x: xNorm, y: 0 };
    }

    let axis = activeAxis;
    if (!axis) {
      axis = Math.abs(xNorm) >= Math.abs(yNorm) ? "x" : "y";
    } else if (axis === "x" && Math.abs(yNorm) > Math.abs(xNorm) + axisSwitchBias) {
      axis = "y";
    } else if (axis === "y" && Math.abs(xNorm) > Math.abs(yNorm) + axisSwitchBias) {
      axis = "x";
    }

    activeAxis = axis;
    return axis === "x" ? { x: xNorm, y: 0 } : { x: 0, y: yNorm };
  };

  const animateKnob = () => {
    renderedX += (targetX - renderedX) * smoothing;
    renderedY += (targetY - renderedY) * smoothing;

    if (Math.abs(targetX - renderedX) < 0.001) {
      renderedX = targetX;
    }

    if (Math.abs(targetY - renderedY) < 0.001) {
      renderedY = targetY;
    }

    updateKnob(renderedX, renderedY);

    const keepAnimating =
      activePointerId !== null || Math.abs(targetX - renderedX) > 0.001 || Math.abs(targetY - renderedY) > 0.001;

    if (keepAnimating) {
      animationId = requestAnimationFrame(animateKnob);
    } else {
      animationId = null;
    }
  };

  const ensureAnimationLoop = () => {
    if (animationId !== null) {
      return;
    }

    animationId = requestAnimationFrame(animateKnob);
  };

  const updateRemoteState = (command) => {
    joystickState[type].command = command;
    if (!estopSent) {
      updateLastCommandLabel();
    }
  };

  const setCommand = (command) => {
    if (command === activeCommand) {
      return;
    }

    activeCommand = command;
    setReadout(command ? command : "Idle");
    sendCommand(command);
  };

  const mapCommand = (xNorm, yNorm) => {
    const magnitude = Math.hypot(xNorm, yNorm);
    const deadZone = activeCommand ? releaseZone : engageZone;
    if (magnitude < deadZone) {
      return null;
    }

    if (type === "move") {
      if (Math.abs(xNorm) >= deadZone) {
        return xNorm > 0 ? "right" : "left";
      }

      if (Math.abs(yNorm) >= deadZone) {
        return yNorm > 0 ? "back" : "forward";
      }

      return null;
    }

    if (Math.abs(xNorm) < deadZone) {
      return null;
    }

    return xNorm > 0 ? "rotate-right" : "rotate-left";
  };

  const normalizePointer = (event) => {
    const rect = root.getBoundingClientRect();
    const centerX = rect.left + rect.width / 2;
    const centerY = rect.top + rect.height / 2;
    const radius = rect.width / 2;
    const dx = (event.clientX - centerX) / radius;
    const dy = (event.clientY - centerY) / radius;
    const magnitude = Math.hypot(dx, dy);

    if (magnitude > 1) {
      return { x: dx / magnitude, y: dy / magnitude };
    }

    return { x: dx, y: dy };
  };

  const reset = () => {
    root.classList.remove("active");
    activeAxis = null;
    targetX = 0;
    targetY = 0;
    ensureAnimationLoop();
    setCommand(null);
    updateRemoteState(null);
    activePointerId = null;
  };

  root.addEventListener("pointerdown", (event) => {
    event.preventDefault();
    if (estopSent) {
      return;
    }

    activePointerId = event.pointerId;
    root.classList.add("active");
    root.setPointerCapture(event.pointerId);

    const normalized = normalizePointer(event);
    const constrained = applyJoystickConstraints(normalized.x, normalized.y);
    targetX = constrained.x;
    targetY = constrained.y;
    ensureAnimationLoop();
    const command = mapCommand(constrained.x, constrained.y);
    setCommand(command);
    updateRemoteState(command);
  });

  root.addEventListener("pointermove", (event) => {
    if (event.pointerId !== activePointerId) {
      return;
    }

    event.preventDefault();

    const normalized = normalizePointer(event);
    const constrained = applyJoystickConstraints(normalized.x, normalized.y);
    targetX = constrained.x;
    targetY = constrained.y;
    ensureAnimationLoop();
    const command = mapCommand(constrained.x, constrained.y);
    setCommand(command);
    updateRemoteState(command);
  });

  ["pointerup", "pointercancel", "lostpointercapture"].forEach((eventName) => {
    root.addEventListener(eventName, (event) => {
      if (event.pointerId !== activePointerId) {
        return;
      }

      reset();
    });
  });
}

estopButton?.addEventListener("pointerdown", (event) => {
  event.preventDefault();
  triggerEstop();
});

createJoystick("move");
createJoystick("rotate");
updateLastCommandLabel();
ensureTransmitLoop();
sendRemoteState();
