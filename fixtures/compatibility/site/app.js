const fixtureLog = document.querySelector("#fixture-log");
const markerKey = "atoll-compatibility-marker";
let unreadCount = 0;
let serviceWorkerRegistration = null;
let activeStream = null;
let peerConnections = [];
let audioContext = null;
let microphoneAnimationFrame = null;
const fixtureEvents = [];

function control(id) {
  return document.getElementById(id);
}

function log(message) {
  const timestamp = new Date().toISOString();
  fixtureEvents.push({ timestamp, message });
  const item = document.createElement("li");
  item.textContent = `${timestamp} — ${message}`;
  fixtureLog.prepend(item);
}

function setStatus(id, value) {
  control(id).textContent = value;
}

async function requestNotificationPermission() {
  if (!("Notification" in window)) {
    throw new Error("This page has no Notification constructor");
  }
  return Notification.requestPermission();
}

async function sendPageNotification(title = "Atoll fixture", tag = "page-notification") {
  await requestNotificationPermission();
  new Notification(title, {
    body: "The page called the Notification constructor.",
    tag,
  });
  log(`Page notification requested with tag “${tag}”.`);
}

async function registerServiceWorker() {
  if (!("serviceWorker" in navigator)) {
    log("Service workers are not available in this WebKit context.");
    return;
  }
  try {
    serviceWorkerRegistration = await navigator.serviceWorker.register("/service-worker.js");
    log("Service worker registered.");
  } catch (error) {
    log(`Service worker registration failed: ${error.message}`);
  }
}

control("page-notification").addEventListener("click", async () => {
  log("Page notification button clicked.");
  try {
    await sendPageNotification();
  } catch (error) {
    log(`Page notification failed: ${error.message}`);
  }
});

control("worker-notification").addEventListener("click", async () => {
  log("Service worker notification button clicked.");
  try {
    await requestNotificationPermission();
    if (!serviceWorkerRegistration) {
      await registerServiceWorker();
    }
    if (!serviceWorkerRegistration) {
      throw new Error("No service worker registration is available");
    }
    await serviceWorkerRegistration.showNotification("Atoll fixture worker call", {
      body: "The page called showNotification on its worker registration.",
      tag: "worker-notification",
    });
    log("Service worker notification requested.");
  } catch (error) {
    log(`Service worker notification failed: ${error.message}`);
  }
});

control("delayed-notification").addEventListener("click", () => {
  log("Delayed notification button clicked. A page notification will run in 10 seconds.");
  window.setTimeout(() => {
    sendPageNotification("Delayed Atoll fixture event", "delayed-notification").catch((error) => {
      log(`Delayed notification failed: ${error.message}`);
    });
  }, 10_000);
});

control("increment-badge").addEventListener("click", () => {
  unreadCount += 1;
  document.title = `(${unreadCount}) Atoll compatibility fixture`;
  log(`Document title unread count changed to ${unreadCount}.`);
});

control("reset-badge").addEventListener("click", () => {
  unreadCount = 0;
  document.title = "Atoll compatibility fixture";
  log("Document title unread count reset.");
});

control("open-popup").addEventListener("click", () => {
  const popup = window.open(
    "/popup.html",
    "atollFixturePopup",
    "popup,width=720,height=540,resizable=yes"
  );
  log(popup ? "Test pop-up requested." : "The test pop-up was blocked.");
});

control("upload-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const input = control("upload-input");
  if (!input.files.length) {
    log("Select a file before upload.");
    return;
  }
  try {
    const response = await fetch("/upload", {
      method: "POST",
      body: new FormData(event.currentTarget),
    });
    const result = await response.json();
    if (!response.ok) {
      throw new Error(result.message || `HTTP ${response.status}`);
    }
    log(`Upload completed. The fixture received ${result.receivedBytes} bytes.`);
  } catch (error) {
    log(`Upload failed: ${error.message}`);
  }
});

async function startMedia(constraints, label) {
  stopMedia();
  activeStream = await navigator.mediaDevices.getUserMedia(constraints);
  const videoTracks = activeStream.getVideoTracks();
  const audioTracks = activeStream.getAudioTracks();
  control("local-video").srcObject = videoTracks.length ? activeStream : null;
  setStatus("camera-status", videoTracks.length ? "Active" : "Inactive");
  setStatus("microphone-status", audioTracks.length ? "Active — waiting for sound" : "Inactive");
  if (audioTracks.length) startMicrophoneMeter(activeStream);
  log(`${label} capture started.`);
  return activeStream;
}

function startMicrophoneMeter(stream) {
  const AudioContext = window.AudioContext || window.webkitAudioContext;
  if (!AudioContext) {
    setStatus("microphone-status", "Active — level meter unavailable");
    return;
  }

  const context = new AudioContext();
  audioContext = context;
  const source = context.createMediaStreamSource(stream);
  const analyser = context.createAnalyser();
  analyser.fftSize = 256;
  source.connect(analyser);
  const samples = new Uint8Array(analyser.fftSize);

  function updateLevel() {
    if (audioContext !== context) return;
    analyser.getByteTimeDomainData(samples);
    let squareTotal = 0;
    samples.forEach((sample) => {
      const centered = (sample - 128) / 128;
      squareTotal += centered * centered;
    });
    const level = Math.min(1, Math.sqrt(squareTotal / samples.length) * 4);
    control("microphone-level").value = level;
    setStatus(
      "microphone-status",
      level > 0.04 ? "Active — signal detected" : "Active — waiting for sound"
    );
    microphoneAnimationFrame = window.requestAnimationFrame(updateLevel);
  }

  if (context.state === "running") {
    updateLevel();
  } else {
    context.resume().then(updateLevel).catch((error) => {
      if (audioContext === context) {
        setStatus("microphone-status", "Active — level meter failed");
        log(`Microphone level meter failed: ${error.message}`);
      }
    });
  }
}

function stopMicrophoneMeter() {
  if (microphoneAnimationFrame !== null) {
    window.cancelAnimationFrame(microphoneAnimationFrame);
    microphoneAnimationFrame = null;
  }
  if (audioContext) {
    audioContext.close().catch(() => {});
    audioContext = null;
  }
  control("microphone-level").value = 0;
}

function closePeerConnections() {
  peerConnections.forEach((connection) => connection.close());
  peerConnections = [];
  control("remote-audio").srcObject = null;
  setStatus("call-status", "Inactive");
}

function stopMedia() {
  stopMicrophoneMeter();
  closePeerConnections();
  if (activeStream) {
    activeStream.getTracks().forEach((track) => track.stop());
    activeStream = null;
  }
  control("local-video").srcObject = null;
  setStatus("camera-status", "Inactive");
  setStatus("microphone-status", "Inactive");
}

control("start-camera").addEventListener("click", async () => {
  log("Start camera button clicked.");
  try {
    await startMedia({ video: true, audio: false }, "Camera");
  } catch (error) {
    log(`Camera request failed: ${error.message}`);
  }
});

control("start-microphone").addEventListener("click", async () => {
  log("Start microphone button clicked.");
  try {
    await startMedia({ video: false, audio: true }, "Microphone");
  } catch (error) {
    log(`Microphone request failed: ${error.message}`);
  }
});

control("start-call").addEventListener("click", async () => {
  log("Start loopback call button clicked.");
  try {
    const stream = await startMedia({ video: false, audio: true }, "Microphone");
    const caller = new RTCPeerConnection();
    const receiver = new RTCPeerConnection();
    peerConnections = [caller, receiver];
    setStatus("call-status", "Connecting");

    receiver.addEventListener("connectionstatechange", () => {
      const state = receiver.connectionState;
      setStatus("call-status", state.charAt(0).toUpperCase() + state.slice(1));
      log(`Loopback receiver state changed to ${state}.`);
    });

    caller.addEventListener("icecandidate", (event) => {
      if (event.candidate) receiver.addIceCandidate(event.candidate);
    });
    receiver.addEventListener("icecandidate", (event) => {
      if (event.candidate) caller.addIceCandidate(event.candidate);
    });
    receiver.addEventListener("track", (event) => {
      control("remote-audio").srcObject = event.streams[0];
    });
    stream.getTracks().forEach((track) => caller.addTrack(track, stream));

    const offer = await caller.createOffer();
    await caller.setLocalDescription(offer);
    await receiver.setRemoteDescription(offer);
    const answer = await receiver.createAnswer();
    await receiver.setLocalDescription(answer);
    await caller.setRemoteDescription(answer);
    log("Loopback WebRTC call started.");
  } catch (error) {
    stopMedia();
    log(`Loopback call failed: ${error.message}`);
  }
});

control("stop-media").addEventListener("click", () => {
  stopMedia();
  log("Media capture and loopback connections stopped.");
});

function prepareDiagnosticReport() {
  const mediaTracks = activeStream
    ? activeStream.getTracks().map((track) => ({
        kind: track.kind,
        readyState: track.readyState,
        enabled: track.enabled,
        muted: track.muted,
      }))
    : [];
  const notificationPermission = "Notification" in window
    ? Notification.permission
    : "unavailable";
  const report = {
    generatedAt: new Date().toISOString(),
    origin: window.location.origin,
    visibility: document.visibilityState,
    notificationPermission,
    serviceWorkerRegistered: Boolean(serviceWorkerRegistration),
    cameraStatus: control("camera-status").textContent,
    microphoneStatus: control("microphone-status").textContent,
    loopbackStatus: control("call-status").textContent,
    mediaTracks,
    peerConnectionStates: peerConnections.map((connection) => connection.connectionState),
    events: fixtureEvents,
  };
  const output = control("diagnostic-output");
  output.value = JSON.stringify(report, null, 2);
  output.focus();
  output.select();
}

control("prepare-diagnostics").addEventListener("click", () => {
  log("Prepare diagnostic report button clicked.");
  prepareDiagnosticReport();
});

control("save-marker").addEventListener("click", () => {
  const value = control("session-marker").value.trim();
  localStorage.setItem(markerKey, value);
  log("Saved the session marker.");
});

control("read-marker").addEventListener("click", () => {
  const value = localStorage.getItem(markerKey);
  control("session-marker").value = value || "";
  log(value === null ? "No session marker is stored." : "Read the session marker.");
});

control("clear-marker").addEventListener("click", () => {
  localStorage.removeItem(markerKey);
  control("session-marker").value = "";
  log("Cleared the session marker.");
});

control("simulate-process-failure").addEventListener("click", () => {
  window.location.href = "atoll-fixture://web-content-process-failure";
});

window.addEventListener("message", (event) => {
  if (event.data && event.data.source === "atoll-compatibility-fixture") {
    log(`${event.data.frame}: ${event.data.message}`);
  }
});

window.addEventListener("beforeunload", stopMedia);
registerServiceWorker();
log("Fixture ready.");
