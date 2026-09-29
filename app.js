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

// x/y are analog values from -1 to 1 (how far the stick is pushed)
const joystickState = {
  move: { command: null, x: 0, y: 0 },
  rotate: { command: null, x: 0, y: 0 }
};

let transmitTimer = null;

// 2 decimals keeps the longest message, "(-0.99,-0.99,-0.99)", within one 20-byte BLE packet
function formatAxis(value) {
  return String(Number(value.toFixed(2)) || 0);
}

function commandToLegacyTuple() {
  const x = formatAxis(joystickState.move.x);
  const y = formatAxis(joystickState.move.y);
  const z = formatAxis(joystickState.rotate.x);

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
  const fullZone = 0.9; // counts as 100% slightly before the rim
  // Rotate is a horizontal slider, so its knob can travel further
  const maxRadiusFactor = type === "rotate" ? 1.0 : 0.36;
  const smoothing = 0.34;
  let activePointerId = null;
  let activeCommand = null;
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

  // Move can go diagonal; rotate only uses left/right
  const applyJoystickConstraints = (xNorm, yNorm) => {
    if (type === "rotate") {
      return { x: xNorm, y: 0 };
    }

    return { x: xNorm, y: yNorm };
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

  // Scale so the value starts at 0 at the dead zone edge and reaches 1 at fullZone
  const toAnalog = (value) => {
    const scaled = (Math.abs(value) - releaseZone) / (fullZone - releaseZone);
    return Math.sign(value) * Math.min(1, Math.max(0, scaled));
  };

  const percent = (value) => `${Math.round(Math.abs(value) * 100)}%`;

  const updateRemoteState = (command, xNorm = 0, yNorm = 0) => {
    let x = 0;
    let y = 0;

    if (command) {
      x = toAnalog(xNorm);
      y = type === "move" ? -toAnalog(yNorm) : 0; // screen y points down, forward is +
    }

    joystickState[type] = { command, x, y };

    if (command) {
      const parts = [];
      if (y !== 0) {
        parts.push(`${y > 0 ? "forward" : "back"} ${percent(y)}`);
      }
      if (x !== 0) {
        const side = x > 0 ? "right" : "left";
        parts.push(`${type === "rotate" ? `rotate-${side}` : side} ${percent(x)}`);
      }
      setReadout(parts.length ? parts.join(" · ") : command);
    }

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
      const vertical = Math.abs(yNorm) >= releaseZone ? (yNorm > 0 ? "back" : "forward") : null;
      const horizontal = Math.abs(xNorm) >= releaseZone ? (xNorm > 0 ? "right" : "left") : null;
      return [vertical, horizontal].filter(Boolean).join("-") || null;
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

    // Slider: only left/right counts, so drifting up or down doesn't shrink the value
    if (type === "rotate") {
      return { x: Math.max(-1, Math.min(1, dx)), y: 0 };
    }

    const magnitude = Math.hypot(dx, dy);

    if (magnitude > 1) {
      return { x: dx / magnitude, y: dy / magnitude };
    }

    return { x: dx, y: dy };
  };

  const reset = () => {
    root.classList.remove("active");
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
    updateRemoteState(command, constrained.x, constrained.y);
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
    updateRemoteState(command, constrained.x, constrained.y);
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
