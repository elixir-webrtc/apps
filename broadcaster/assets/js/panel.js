import { Socket } from 'phoenix';

import { connectChat } from './chat.js';

const audioDevices = document.getElementById('audioDevices');
const videoDevices = document.getElementById('videoDevices');
const serverUrl = document.getElementById('serverUrl');
const serverToken = document.getElementById('serverToken');
const button = document.getElementById('button');
const previewPlayer = document.getElementById('previewPlayer');
const highVideoBitrate = document.getElementById('highVideoBitrate');
const mediumVideoBitrate = document.getElementById('mediumVideoBitrate');
const lowVideoBitrate = document.getElementById('lowVideoBitrate');
const echoCancellation = document.getElementById('echoCancellation');
const autoGainControl = document.getElementById('autoGainControl');
const noiseSuppression = document.getElementById('noiseSuppression');
const saveStreamConfigButton = document.getElementById('save-stream-config');

const audioBitrate = document.getElementById('audio-bitrate');
const videoBitrate = document.getElementById('video-bitrate');
const packetLoss = document.getElementById('packet-loss');
const time = document.getElementById('time');
const status = document.getElementById('status');

let lastAudioReport = undefined;
let lastVideoReport = undefined;
let statsIntervalId = undefined;
let startTime = undefined;

const mediaConstraints = {
  video: {
    width: { ideal: 1280 },
    height: { ideal: 720 },
    frameRate: { ideal: 24 },
  },
  audio: true,
};

let localStream = undefined;
let pc = undefined;

function setupSaveStreamConfigButton() {
  saveStreamConfigButton.onclick = async () => {
    const title = document.getElementById('stream-title').value;
    const description = document.getElementById('stream-description').value;

    const response = await fetch(`${window.location.origin}/api/admin/stream`, {
      method: 'POST',
      body: JSON.stringify({ title: title, description: description }),
    });
    if (response.status != 200) {
      console.warn('Setting stream title and description failed');
    }
  };
}

async function setupStream() {
  if (localStream != undefined) {
    closeStream();
  }

  const videoDevice = videoDevices.value;
  const audioDevice = audioDevices.value;

  console.log(
    `Setting up stream: audioDevice: ${audioDevice}, videoDevice: ${videoDevice}`
  );

  localStream = await navigator.mediaDevices.getUserMedia({
    video: {
      deviceId: { exact: videoDevice },
      width: { ideal: 1280 },
      height: { ideal: 720 },
    },
    audio: {
      deviceId: { exact: audioDevice },
      echoCancellation: echoCancellation.checked,
      autoGainControl: autoGainControl.checked,
      noiseSuppression: noiseSuppression.checked,
    },
  });

  console.log(`Obtained stream with id: ${localStream.id}`);

  previewPlayer.srcObject = localStream;
}

function closeStream() {
  if (localStream != undefined) {
    console.log(`Closing stream with id: ${localStream.id}`);
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
  audioDevices.setAttribute('disabled', 'disabled');
  videoDevices.setAttribute('disabled', 'disabled');
  serverUrl.setAttribute('disabled', 'disabled');
  serverToken.setAttribute('disabled', 'disabled');
}

function enableControls() {
  audioDevices.removeAttribute('disabled');
  videoDevices.removeAttribute('disabled');
  serverUrl.removeAttribute('disabled');
  serverToken.removeAttribute('disabled');
}

async function startStreaming() {
  disableControls();

  const candidates = [];
  let patchEndpoint = undefined;
  pc = new RTCPeerConnection();

  pc.onicegatheringstatechange = () =>
    console.log('Gathering state change:', pc.iceGatheringState);
  pc.onconnectionstatechange = () => {
    console.log('Connection state change:', pc.connectionState);
    if (pc.connectionState === "connected") {
      startTime = new Date();
      status.classList.remove("bg-red-500");
      // TODO use tailwind
      status.style.backgroundColor = "rgb(34, 197, 94)";

      statsIntervalId = setInterval(async function () {
        if (!pc) {
          clearInterval(statsIntervalId);
          statsIntervalId = undefined;
          return;
        }

        time.innerText = toHHMMSS(new Date() - startTime);

        const stats = await pc.getStats(null);
        let bitrate;

        stats.forEach((report) => {
          if (report.type === "outbound-rtp" && report.kind === "video") {
            if (!lastVideoReport) {
              bitrate = (report.bytesSent * 8) / 1000;
            } else {
              const timeDiff =
                (report.timestamp - lastVideoReport.timestamp) / 1000;
              if (timeDiff == 0) {
                // this should never happen as we are getting stats every second
                bitrate = 0;
              } else {
                bitrate =
                  ((report.bytesSent - lastVideoReport.bytesSent) *
                    8) /
                  timeDiff;
              }
            }

            videoBitrate.innerText = (bitrate / 1000).toFixed();
            lastVideoReport = report;
          } else if (
            report.type === "outbound-rtp" &&
            report.kind === "audio"
          ) {
            if (!lastAudioReport) {
              bitrate = report.bytesSent;
            } else {
              const timeDiff =
                (report.timestamp - lastAudioReport.timestamp) / 1000;
              if (timeDiff == 0) {
                // this should never happen as we are getting stats every second
                bitrate = 0;
              } else {
                bitrate =
                  ((report.bytesSent - lastAudioReport.bytesSent) *
                    8) /
                  timeDiff;
              }
            }

            audioBitrate.innerText = (bitrate / 1000).toFixed();
            lastAudioReport = report;
          }
        });

        // calculate packet loss
        if (!lastAudioReport || !lastVideoReport) {
          packetLoss.innerText = 0;
        } else {
          const packetsSent =
            lastVideoReport.packetsSent +
            lastAudioReport.packetsSent;
          const rtxPacketsSent =
            lastVideoReport.retransmittedPacketsSent +
            lastAudioReport.retransmittedPacketsSent;
          const nackReceived =
            lastVideoReport.nackCount + lastAudioReport.nackCount;

          if (nackReceived == 0) {
            packetLoss.innerText = 0;
          } else {
            packetLoss.innerText = (
              (nackReceived / (packetsSent - rtxPacketsSent)) *
              100
            ).toFixed();
          }
        }
      }, 1000);
    } else if (pc.connectionState === "failed") {
      stopStreaming(view);
    }
  }

  pc.onicecandidate = (event) => {
    if (event.candidate == null) {
      return;
    }

    const candidate = JSON.stringify(event.candidate);
    if (patchEndpoint === undefined) {
      candidates.push(candidate);
    } else {
      sendCandidate(patchEndpoint, candidate);
    }
  };

  pc.addTrack(localStream.getAudioTracks()[0], localStream);
  const { sender: videoSender } = pc.addTransceiver(
    localStream.getVideoTracks()[0],
    {
      streams: [localStream],
      sendEncodings: [
        { rid: 'h', maxBitrate: 1500 * 1024 },
        { rid: 'm', scaleResolutionDownBy: 2, maxBitrate: 600 * 1024 },
        { rid: 'l', scaleResolutionDownBy: 4, maxBitrate: 300 * 1024 },
      ],
    }
  );

  // limit max bitrate
  const params = videoSender.getParameters();
  params.encodings.find((e) => e.rid === 'h').maxBitrate =
    parseInt(highVideoBitrate.value) * 1024;
  params.encodings.find((e) => e.rid === 'm').maxBitrate =
    parseInt(mediumVideoBitrate.value) * 1024;
  params.encodings.find((e) => e.rid === 'l').maxBitrate =
    parseInt(lowVideoBitrate.value) * 1024;
  await videoSender.setParameters(params);

  const offer = await pc.createOffer();
  await pc.setLocalDescription(offer);

  try {
    const response = await fetch(serverUrl.value, {
      method: 'POST',
      cache: 'no-cache',
      headers: {
        Accept: 'application/sdp',
        'Content-Type': 'application/sdp',
        Authorization: `Bearer ${serverToken.value}`,
      },
      body: offer.sdp,
    });

    if (response.status == 201) {
      patchEndpoint = response.headers.get('location');
      console.log('Successfully initialized WHIP connection');

      for (const candidate of candidates) {
        sendCandidate(patchEndpoint, candidate);
      }

      const sdp = await response.text();
      await pc.setRemoteDescription({ type: 'answer', sdp: sdp });
      button.innerText = 'Stop Streaming';
      button.onclick = stopStreaming;
    } else {
      console.error('Request to server failed with response:', response);
      pc.close();
      pc = undefined;
      enableControls();
    }
  } catch (err) {
    console.error(err);
    pc.close();
    pc = undefined;
    enableControls();
  }
}

async function sendCandidate(patchEndpoint, candidate) {
  const response = await fetch(patchEndpoint, {
    method: 'PATCH',
    cache: 'no-cache',
    headers: {
      'Content-Type': 'application/trickle-ice-sdpfrag',
    },
    body: candidate,
  });

  if (response.status === 204) {
    console.log(`Successfully sent ICE candidate:`, candidate);
  } else {
    console.error(
      `Failed to send ICE, status: ${response.status}, candidate:`,
      candidate
    );
  }
}
function stopStreaming() {
  pc.close();
  pc = undefined;

  resetStats();
  enableControls();

  button.innerText = 'Start Streaming';
  button.onclick = startStreaming;
}

function resetStats() {
  startTime = undefined;
  lastAudioReport = undefined;
  lastVideoReport = undefined;
  audioBitrate.innerText = 0;
  videoBitrate.innerText = 0;
  packetLoss.innerText = 0;
  time.innerText = "00:00:00";
  status.style.backgroundColor = "rgb(239, 68, 68)";
}

function toHHMMSS(milliseconds) {
  // Calculate hours
  let hours = Math.floor(milliseconds / (1000 * 60 * 60));
  // Calculate minutes, subtracting the hours part
  let minutes = Math.floor((milliseconds % (1000 * 60 * 60)) / (1000 * 60));
  // Calculate seconds, subtracting the hours and minutes parts
  let seconds = Math.floor((milliseconds % (1000 * 60)) / 1000);

  // Formatting each unit to always have at least two digits
  hours = hours < 10 ? "0" + hours : hours;
  minutes = minutes < 10 ? "0" + minutes : minutes;
  seconds = seconds < 10 ? "0" + seconds : seconds;

  return hours + ":" + minutes + ":" + seconds;
}

async function run() {
  // ask for permissions
  localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);

  console.log(`Obtained stream with id: ${localStream.id}`);

  // enumerate devices
  const devices = await navigator.mediaDevices.enumerateDevices();
  devices.forEach((device) => {
    if (device.kind === 'videoinput') {
      videoDevices.options[videoDevices.options.length] = new Option(
        device.label,
        device.deviceId
      );
    } else if (device.kind === 'audioinput') {
      audioDevices.options[audioDevices.options.length] = new Option(
        device.label,
        device.deviceId
      );
    }
  });

  // for some reasons, firefox loses labels after closing the stream
  // so we close it after filling audio/video devices selects
  closeStream();

  // setup preview
  await setupStream();

  // bind buttons
  bindControls();
}

export const Panel = {
  mounted() {
    const socket = new Socket('/socket', {
      params: { token: window.userToken },
    });
    socket.connect();

    setupSaveStreamConfigButton();
    connectChat(socket, true);
    run();
  },
};
