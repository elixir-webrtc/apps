const audioDevices = document.getElementById('audioDevices');
const videoDevices = document.getElementById('videoDevices');
const serverUrl = document.getElementById('serverUrl');
const serverToken = document.getElementById('serverToken');
const button = document.getElementById('button');
const previewPlayer = document.getElementById('previewPlayer');

let localStream = undefined;
let pc = undefined;

async function setupStream() {
  if (localStream != undefined) {
    closeStream();
  }

  const videoDevice = videoDevices.value;
  const audioDevice = audioDevices.value;

  localStream = await navigator.mediaDevices.getUserMedia({
    video: { deviceId: { exact: videoDevice.deviceId }, width: { ideal: 1280 }, height: { ideal: 720 } },
    audio: { deviceId: { exact: audioDevice.deviceId } }
  });

  previewPlayer.srcObject = localStream;
}

function closeStream() {
  if (localStream != undefined) {
    localStream.getTracks().forEach((track) => track.stop());
  }
}

function bindControls() {
  audioDevices.onchange = setupStream;
  videoDevices.onchange = setupStream;
  button.onclick = startStreaming;
}

function disableControls() {
  audioDevices.setAttribute("disabled", "disabled");
  videoDevices.setAttribute("disabled", "disabled");
  serverUrl.setAttribute("disabled", "disabled");
  serverToken.setAttribute("disabled", "disabled");
}

function enableControls() {
  audioDevices.removeAttribute("disabled");
  videoDevices.removeAttribute("disabled");
  serverUrl.removeAttribute("disabled");
  serverToken.removeAttribute("disabled");
}

async function startStreaming() {
  disableControls();

  pc = new RTCPeerConnection();
  for (const track of localStream.getTracks()) {
    pc.addTrack(track);
  }

  const offer = await pc.createOffer();
  await pc.setLocalDescription(offer)

  try {
    const response = await fetch(serverUrl.value, {
      method: "POST",
      cache: "no-cache",
      headers: {
        "Accept": "application/sdp",
        "Content-Type": "application/sdp",
        "Authorization": `Bearer ${serverToken.value}`
      },
      body: offer.sdp,
    });

    if (response.status == 201) {
      const sdp = await response.text();
      await pc.setRemoteDescription({ type: "answer", sdp: sdp });
    }

    button.innerText = "Stop Streaming";
    button.onclick = stopStreaming;
  } catch (err) {
    pc.close();
    pc = undefined;
    enableControls();
  }
}

function stopStreaming() {
  pc.close();
  pc = undefined;

  enableControls();

  button.innerText = "Start Streaming";
  button.onclick = startStreaming;
}

async function run() {
  // ask for permissions
  localStream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });

  // enumerate devices
  const devices = await navigator.mediaDevices.enumerateDevices();
  devices.forEach((device) => {
    if (device.kind === 'videoinput') {
      videoDevices.options[videoDevices.options.length] = new Option(device.label, device);
    } else if (device.kind === 'audioinput') {
      audioDevices.options[audioDevices.options.length] = new Option(device.label, device);
    }
  });

  // for some reasons, firefox loses labels after closing the stream
  // so we close it after filling audio/video devices selects
  closeStream();

  // setup preview
  setupStream();

  // bind buttons
  bindControls();
}

run();
