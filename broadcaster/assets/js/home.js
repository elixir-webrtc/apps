import { Socket } from 'phoenix';

import { WHEPClient } from './whep-client.js';

const settingsToggler = document.getElementById('settings-toggler');
const settings = document.getElementById('settings');
const videoQuality = document.getElementById('video-quality');
const videoPlayerWrapper = document.getElementById('videoplayer-wrapper');
const videoPlayerGrid = document.getElementById('videoplayer-grid');
const statusMessage = document.getElementById('status-message');

const whepEndpointBase = `${window.location.origin}/api/whep`;
const inputsData = new Map();
const stats = {
  time: document.getElementById('time'),
  audioBitrate: document.getElementById('audio-bitrate'),
  videoBitrate: document.getElementById('video-bitrate'),
  frameWidth: document.getElementById('frame-width'),
  frameHeight: document.getElementById('frame-height'),
  fps: document.getElementById('fps'),
  keyframesDecoded: document.getElementById('keyframes-decoded'),
  pliCount: document.getElementById('pli-count'),
  packetLoss: document.getElementById('packet-loss'),
  avgJitterBufferDelay: document.getElementById('avg-jitter-buffer-delay'),
  freezeCount: document.getElementById('freeze-count'),
  freezeDuration: document.getElementById('freeze-duration')
};
let defaultLayer = 'h';
let url;
let inputId;

const button1 = document.getElementById('button-1');
const button2 = document.getElementById('button-2');
const button3 = document.getElementById('button-3');
const buttonAuto = document.getElementById('button-auto');


async function connectSignaling(socket) {
  const channel = socket.channel('broadcaster:signaling');

  channel.on('input_added', ({ id: id }) => {
    console.log('New input:', id);
    inputId = id;
    connectInput();
  });

  channel.on('input_removed', ({ id: id }) => {
    console.log('Input removed:', id);
    removeInput();
  });

  channel
    .join()
    .receive('ok', ({ inputs: inputs }) => {
      console.log(
        'Joined signaling channel successfully\nAvailable inputs:',
        inputs
      );

      if (inputs.length === 0) {
        statusMessage.innerText =
          'Connected. Waiting for the stream to begin...';
        statusMessage.classList.remove('hidden');
      }

      for (const id of inputs) {
        inputId = id;
      }

      if (inputId) {
        connectInput();
      }
    })
    .receive('error', (resp) => {
      console.error(
        'Catastrophic failure: Unable to join signaling channel',
        resp
      );

      statusMessage.innerText =
        'Unable to join the stream, try again in a few minutes';
      statusMessage.classList.remove('hidden');
    });
}

async function connectInput() {

  let whepEndpoint;
  if (url) {
     whepEndpoint = url + 'api/whep?inputId=' + inputId;
  } else {
     whepEndpoint = whepEndpointBase + '?inputId=' + inputId;
  } 

  console.log("Trying to connect to: ", whepEndpoint);

  if (inputId) {
    removeInput();
  }

  const pcConfigUrl = (url || window.location.origin) + '/api/pc-config'
  const response = await fetch(pcConfigUrl, {
    method: 'GET',
    cache: 'no-cache',
  });
  const pcConfig = await response.json();
  console.log('Fetched PC config from server: ', pcConfig)

  const whepClient = new WHEPClient(whepEndpoint, pcConfig);

  const inputData = {
    whepClient: whepClient,
    videoPlayer: undefined,
  };
  inputsData.set(inputId, inputData);

  whepClient.id = inputId;

  whepClient.onstream = (stream) => {
    console.log(`[${inputId}]: Creating new video element`);

    const videoPlayer = document.createElement('video');
    videoPlayer.srcObject = stream;
    videoPlayer.autoplay = true;
    videoPlayer.controls = true;
    videoPlayer.muted = true;
    videoPlayer.className = 'rounded-xl w-full h-full object-cover bg-black';

    videoPlayerGrid.appendChild(videoPlayer);
    inputData.videoPlayer = videoPlayer;
    updateVideoGrid();
    statusMessage.classList.add('hidden');
  };

  whepClient.onconnected = () => {
    whepClient.changeLayer(defaultLayer);

    if (whepClient.pc.connectionState === "connected") {
          stats.startTime = new Date();
          stats.intervalId = setInterval(async function () {
            if (!whepClient.pc) {
              clearInterval(stats.intervalId);
              stats.intervalId = undefined;
              return;
            }

            stats.time.innerText = toHHMMSS(new Date() - stats.startTime);

            let bitrate;

           (await whepClient.pc.getStats(null)).forEach((report) => {
              if (report.type === "inbound-rtp" && report.kind === "video") {
                if (!stats.lastVideoReport) {
                  bitrate = (report.bytesReceived * 8) / 1000;
                } else {
                  const timeDiff =
                    (report.timestamp - stats.lastVideoReport.timestamp) / 1000;
                  if (timeDiff == 0) {
                    // this should never happen as we are getting stats every second
                    bitrate = 0;
                  } else {
                    bitrate =
                      ((report.bytesReceived - stats.lastVideoReport.bytesReceived) *
                        8) /
                      timeDiff;
                  }
                }

                stats.videoBitrate.innerText = (bitrate / 1000).toFixed();
                stats.frameWidth.innerText = report.frameWidth;
                stats.frameHeight.innerText = report.frameHeight;
                stats.fps.innerText = report.framesPerSecond;
                stats.keyframesDecoded.innerText = report.keyFramesDecoded;
                stats.pliCount.innerText = report.pliCount;
                stats.avgJitterBufferDelay.innerText = report.jitterBufferDelay * 1000 / report.jitterBufferEmittedCount;
                stats.freezeCount.innerText = report.freezeCount;
                stats.freezeDuration.innerText = report.totalFreezesDuration;
                stats.lastVideoReport = report;
              } else if (
                report.type === "inbound-rtp" &&
                report.kind === "audio"
              ) {
                if (!stats.lastAudioReport) {
                  bitrate = report.bytesReceived;
                } else {
                  const timeDiff =
                    (report.timestamp - stats.lastAudioReport.timestamp) / 1000;
                  if (timeDiff == 0) {
                    // this should never happen as we are getting stats every second
                    bitrate = 0;
                  } else {
                    bitrate =
                      ((report.bytesReceived - stats.lastAudioReport.bytesReceived) *
                        8) /
                      timeDiff;
                  }
                }

                stats.audioBitrate.innerText = (bitrate / 1000).toFixed();
                stats.lastAudioReport = report;
              }
            });

            let packetLoss = 0;
            // calculate packet loss
            if (stats.lastAudioReport) {
              packetLoss += stats.lastAudioReport.packetsLost;
            }

            if (stats.lastVideoReport) {
              packetLoss += stats.lastVideoReport.packetsLost;
            }

            stats.packetLoss.innerText = packetLoss;
          }, 1000);
        } else if (view.pc.connectionState === "failed") {
        }
  };

  whepClient.connect();
}

async function removeInput() {
  const inputData = inputsData.get(inputId);
  inputsData.delete(inputId);

  if (inputData) {
    inputData.whepClient.disconnect();

    if (inputData.videoPlayer) {
      videoPlayerGrid.removeChild(inputData.videoPlayer);
      updateVideoGrid();
    }
  }

  if (inputsData.size === 0) {
    statusMessage.innerText = 'Connected. Waiting for the stream to begin...';
    statusMessage.classList.remove('hidden');
  }

  clearInterval(stats.intervalId);
  stats.lastAudioReport = null;
  stats.lastVideoReport = null;
                stats.time.innerText = 0; 
                stats.audioBitrate.innerText = 0; 
                stats.videoBitrate.innerText = 0; 
                stats.frameWidth.innerText = 0;
                stats.frameHeight.innerText = 0; 
                stats.fps.innerText = 0;
                stats.keyframesDecoded.innerText = 0;
                stats.pliCount.innerText = 0;
                stats.packetLoss.innerText = 0;
                stats.avgJitterBufferDelay.innerText = 0;
                stats.freezeCount.innerText = 0;
                stats.freezeDuration.innerText = 0;
  
}

async function setDefaultLayer(layer) {
  if (defaultLayer !== layer) {
    defaultLayer = layer;
    for (const { whepClient: whepClient } of inputsData.values()) {
      whepClient.changeLayer(layer);
    }
  }
}

function toggleBox(element, other) {
  if (window.getComputedStyle(element).display === 'none') {
    // For screen's width lower than 1024,
    // eiter show video player or chat at the same time.
    if (window.innerWidth < 1024) {
      element.classList.add('flex');
      element.classList.remove('hidden', 'lg:flex');
      other.classList.add('hidden');
      other.classList.remove('flex', 'lg:flex');
      videoPlayerWrapper.classList.remove('block');
      videoPlayerWrapper.classList.add('hidden', 'lg:block');
    } else {
      element.classList.add('lg:flex', 'hidden');
      element.classList.remove('flex');
      other.classList.add('hidden');
      other.classList.remove('flex', 'lg:flex');
      videoPlayerWrapper.classList.remove('hidden', 'lg:block');
      videoPlayerWrapper.classList.add('block');
    }
  } else {
    element.classList.add('hidden');
    element.classList.remove('flex', 'lg:flex');
    videoPlayerWrapper.classList.remove('hidden', 'lg:block');
    videoPlayerWrapper.classList.add('block');
  }
}

function updateVideoGrid() {
  const videoCount = videoPlayerGrid.children.length;

  let columns;
  if (videoCount <= 1) {
    columns = 'grid-cols-1';
  } else if (videoCount <= 4) {
    columns = 'grid-cols-2';
  } else if (videoCount <= 9) {
    columns = 'grid-cols-3';
  } else if (videoCount <= 16) {
    columns = 'grid-cols-4';
  } else {
    columns = 'grid-cols-5';
  }

  videoPlayerGrid.classList.remove(
    'grid-cols-1',
    'grid-cols-2',
    'grid-cols-3',
    'grid-cols-4',
    'grid-cols-5'
  );
  videoPlayerGrid.classList.add(columns);
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

export const Home = {
  mounted() {
    const socket = new Socket('/socket', {
      params: { token: window.userToken },
    });
    socket.connect();

    connectSignaling(socket);

    //videoQuality.onchange = () => setDefaultLayer(videoQuality.value);

    settingsToggler.onclick = () => toggleBox(settings, chat);

    button1.onclick = () => {
      url = button1.value
      console.log(url);
      connectInput();
    };

    button2.onclick = () => {
      url = button2.value
      connectInput();
    };

    button3.onclick = () => {
      url = button3.value
      connectInput();
    };
    
    buttonAuto.onclick = () => {
      url = buttonAuto.value
      connectInput();
    };
  },
};
