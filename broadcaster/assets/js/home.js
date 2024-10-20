import { Socket } from 'phoenix';

import { connectChat } from './chat.js';
import { WHEPClient } from './whep-client.js';

const chatToggler = document.getElementById('chat-toggler');
const chat = document.getElementById('chat');
const settingsToggler = document.getElementById('settings-toggler');
const settings = document.getElementById('settings');
const videoQuality = document.getElementById('video-quality');
const videoPlayerWrapper = document.getElementById('videoplayer-wrapper');
const videoPlayerGrid = document.getElementById('videoplayer-grid');
const statusMessage = document.getElementById('status-message');

const whepEndpointBase = `${window.location.origin}/api/whep`;
const inputsData = new Map();
let defaultLayer = 'h';

async function connectSignaling(socket) {
  const channel = socket.channel('broadcaster:signaling');

  channel.on('input_added', ({ id: id }) => {
    console.log('New input:', id);
    connectInput(id);
  });

  channel.on('input_removed', ({ id: id }) => {
    console.log('Input removed:', id);
    removeInput(id);
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
        connectInput(id);
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

async function connectInput(id) {
  const whepEndpoint = whepEndpointBase + '?inputId=' + id;
  const whepClient = new WHEPClient(whepEndpoint);

  const inputData = {
    whepClient: whepClient,
    videoPlayer: undefined,
  };
  inputsData.set(id, inputData);

  whepClient.id = id;

  whepClient.onstream = (stream) => {
    console.log(`[${id}]: Creating new video element`);


    const w = document.createElement('div');
    w.className = 'w'

    const videoPlayer = document.createElement('video');
    videoPlayer.srcObject = stream;
    videoPlayer.autoplay = true;
    videoPlayer.controls = true;
    videoPlayer.muted = true;
    videoPlayer.className = 'rounded-xl w-full h-full object-cover bg-black';

    w.appendChild(videoPlayer);

    // const a = document.createElement('a');
    // a.appendChild(w);
    // a.href = "https://swmansion.com"
    // a.className = 'a-watermark';

    const watermark = document.createElement('div');
    watermark.style = 'position: absolute; width: 20px; height: 20px; background-color: red;'
    const p = document.createElement('div');
    p.style = 'position: relative; display: inline-block;';
    p.appendChild(videoPlayer);
    p.appendChild(watermark);
    videoPlayerGrid.appendChild(p);
    inputData.videoPlayer = videoPlayer;
    updateVideoGrid();
    statusMessage.classList.add('hidden');
  };

  whepClient.onconnected = () => {
    whepClient.changeLayer(defaultLayer);
  };

  whepClient.connect();
}

async function removeInput(id) {
  const inputData = inputsData.get(id);
  inputsData.delete(id);

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

export const Home = {
  mounted() {
    const socket = new Socket('/socket', {
      params: { token: window.userToken },
    });
    socket.connect();

    connectSignaling(socket);
    connectChat(socket, false);

    videoQuality.onchange = () => setDefaultLayer(videoQuality.value);

    chatToggler.onclick = () => toggleBox(chat, settings);
    settingsToggler.onclick = () => toggleBox(settings, chat);
  },
};
