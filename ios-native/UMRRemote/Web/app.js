const commandLabel = document.querySelector("#last-command");

function sendCommand(command) {
  if (!command) {
    return;
  }

  window.dispatchEvent(
    new CustomEvent("remote-command", {
      detail: { command, timestamp: Date.now() }
    })
  );

  if (commandLabel) {
    commandLabel.textContent = command;
  }

  console.log(`[REMOTE] ${command}`);
}

function createJoystick(type) {
  const root = document.querySelector(`[data-joystick="${type}"]`);
  const knob = root?.querySelector(".joystick-knob");
  const readout = document.querySelector(`[data-readout="${type}"]`);

  if (!root || !knob) {
    return;
  }

  const deadZone = 0.32;
  const maxRadiusFactor = 0.36;
  let activePointerId = null;
  let activeCommand = null;
  let repeatTimer = null;

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

  const setCommand = (command) => {
    if (command === activeCommand) {
      return;
    }

    activeCommand = command;
    setReadout(command ? command : "Idle");

    if (repeatTimer) {
      clearInterval(repeatTimer);
      repeatTimer = null;
    }

    if (command) {
      sendCommand(command);
      repeatTimer = setInterval(() => sendCommand(command), 180);
    }
  };

  const mapCommand = (xNorm, yNorm) => {
    const magnitude = Math.hypot(xNorm, yNorm);
    if (magnitude < deadZone) {
      return null;
    }

    if (type === "move") {
      if (Math.abs(xNorm) > Math.abs(yNorm)) {
        return xNorm > 0 ? "right" : "left";
      }
      return yNorm > 0 ? "back" : "forward";
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
    updateKnob(0, 0);
    setCommand(null);
    activePointerId = null;
  };

  root.addEventListener("pointerdown", (event) => {
    activePointerId = event.pointerId;
    root.classList.add("active");
    root.setPointerCapture(event.pointerId);

    const normalized = normalizePointer(event);
    updateKnob(normalized.x, normalized.y);
    setCommand(mapCommand(normalized.x, normalized.y));
  });

  root.addEventListener("pointermove", (event) => {
    if (event.pointerId !== activePointerId) {
      return;
    }

    const normalized = normalizePointer(event);
    updateKnob(normalized.x, normalized.y);
    setCommand(mapCommand(normalized.x, normalized.y));
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

createJoystick("move");
createJoystick("rotate");
