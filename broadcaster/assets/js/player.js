const audioDevices = document.getElementById('audioDevices');
const videoDevices = document.getElementById('videoDevices');
const maxVideoBitrate = document.getElementById('maxVideoBitrate');
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

  console.log(`Setting up stream: audioDevice: ${audioDevice}, videoDevice: ${videoDevice}`)

  localStream = await navigator.mediaDevices.getUserMedia({
    video: { deviceId: { exact: videoDevice }, width: { ideal: 1280 }, height: { ideal: 720 } },
    audio: { deviceId: { exact: audioDevice } }
  });

  console.log(`Obtained stream with id: ${localStream.id}`)

  previewPlayer.srcObject = localStream;
}

function closeStream() {
  if (localStream != undefined) {
    console.log(`Closing stream with id: ${localStream.id}`)
    localStream.getTracks().forEach((track) => track.stop());
    localStream = undefined;
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

  // limit max bitrate
  pc.getSenders()
    .filter((sender) => sender.track.kind === 'video')
    .forEach(async (sender) => {
      const params = sender.getParameters();
      params.encodings[0].maxBitrate = parseInt(maxVideoBitrate.value) * 1024;
      await sender.setParameters(params);
    });

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

  console.log(`Obtained stream with id: ${localStream.id}`);

  // enumerate devices
  const devices = await navigator.mediaDevices.enumerateDevices();
  devices.forEach((device) => {
    if (device.kind === 'videoinput') {
      videoDevices.options[videoDevices.options.length] = new Option(device.label, device.deviceId);
    } else if (device.kind === 'audioinput') {
      audioDevices.options[audioDevices.options.length] = new Option(device.label, device.deviceId);
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

export const Player = {
  mounted() {
    run()
  }
}
