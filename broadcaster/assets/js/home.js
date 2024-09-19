import { Socket } from 'phoenix';

import { connectChat } from './chat.js';
import { WHEPClient } from './whep-client.js';

const chatToggler = document.getElementById('chat-toggler');
const chat = document.getElementById('chat');
const settingsToggler = document.getElementById('settings-toggler');
const settings = document.getElementById('settings');
const videoQuality = document.getElementById('video-quality');
const videoPlayerWrapper = document.getElementById('videoplayer-grid');
const statusMessage = document.getElementById('status-message');

const whepEndpointBase = `${window.location.origin}/api/whep`;
const streamsData = new Map();
let defaultLayer = 'h';

async function connectSignaling(socket) {
  const channel = socket.channel('broadcaster:signaling');

  channel.on('stream_added', ({ id: id }) => {
    console.log('New stream:', id);
    connectStream(id);
  });

  channel.on('stream_removed', ({ id: id }) => {
    console.log('Stream ended:', id);
    removeStream(id);
  });

  channel
    .join()
    .receive('ok', ({ streams: streams }) => {
      console.log(
        'Joined signaling channel successfully\nAvailable streams:',
        streams
      );

      if (streams.length === 0) {
        statusMessage.innerText =
          'Connected. Waiting for the stream to begin...';
        statusMessage.classList.remove('hidden');
      }

      for (const id of streams) {
        connectStream(id);
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

async function connectStream(streamId) {
  const whepEndpoint = whepEndpointBase + '?streamId=' + streamId;
  const whepClient = new WHEPClient(whepEndpoint);

  const streamData = {
    whepClient: whepClient,
    videoPlayer: undefined,
  };
  streamsData.set(streamId, streamData);

  whepClient.id = streamId;

  whepClient.onstream = (stream) => {
    console.log(`[${streamId}]: Creating new video element`);

    const videoPlayer = document.createElement('video');
    videoPlayer.srcObject = stream;
    videoPlayer.autoplay = true;
    videoPlayer.controls = true;
    videoPlayer.muted = true;
    videoPlayer.className = 'rounded-xl w-full h-full object-cover bg-black';

    videoPlayerWrapper.appendChild(videoPlayer);
    streamData.videoPlayer = videoPlayer;
    updateVideoGrid();
    whepClient.changeLayer(defaultLayer);
    statusMessage.classList.add('hidden');
  };

  whepClient.connect();
}

async function removeStream(streamId) {
  const streamData = streamsData.get(streamId);
  streamsData.delete(streamId);

  if (streamData) {
    streamData.whepClient.disconnect();

    if (streamData.videoPlayer) {
      videoPlayerWrapper.removeChild(streamData.videoPlayer);
      updateVideoGrid();
    }
  }

  if (streamsData.size === 0) {
    statusMessage.innerText = 'Connected. Waiting for the stream to begin...';
    statusMessage.classList.remove('hidden');
  }
}

async function setDefaultLayer(layer) {
  if (defaultLayer !== layer) {
    defaultLayer = layer;
    for (const { whepClient: whepClient } of streamsData.values()) {
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
  const videoCount = videoPlayerWrapper.children.length;

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

  videoPlayerWrapper.classList.remove(
    'grid-cols-1',
    'grid-cols-2',
    'grid-cols-3',
    'grid-cols-4',
    'grid-cols-5'
  );
  videoPlayerWrapper.classList.add(columns);
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
