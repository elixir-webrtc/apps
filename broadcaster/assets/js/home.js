import { Socket } from 'phoenix';

import { connectChat } from './chat.js';

const chatToggler = document.getElementById('chat-toggler');
const chat = document.getElementById('chat');
const settingsToggler = document.getElementById('settings-toggler');
const settings = document.getElementById('settings');
const videoQuality = document.getElementById('video-quality');
const videoPlayerWrapper = document.getElementById('videoplayer-wrapper');
const statusMessage = document.getElementById('status-message');

const pcConfig = { iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] };
const whepEndpointBase = `${window.location.origin}/api/whep`;
const streamsData = new Map();

async function connectMedia(socket) {
  const channel = socket.channel('stream:signalling');

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
        'Joined signalling channel successfully\nAvailable streams:',
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
        'Catastrophic failure: Unable to join signalling channel',
        resp
      );

      statusMessage.innerText =
        'Unable to join the stream, try again in a few minutes';
      statusMessage.classList.remove('hidden');
    });
}

async function connectStream(streamId) {
  const candidates = [];

  const pc = new RTCPeerConnection(pcConfig);

  const streamData = {
    pc: pc,
    patchEndpoint: undefined,
    videoPlayer: undefined,
  };
  streamsData.set(streamId, streamData);

  pc.ontrack = (event) => {
    if (event.track.kind == 'video') {
      console.log(`[${streamId}]: Creating new video element`);

      const videoPlayer = document.createElement('video');
      videoPlayer.srcObject = event.streams[0];
      videoPlayer.autoplay = true;
      videoPlayer.controls = true;
      videoPlayer.muted = true;
      videoPlayer.className = 'rounded-xl w-full h-full object-cover bg-black';

      videoPlayerWrapper.appendChild(videoPlayer);
      streamData.videoPlayer = videoPlayer;
      updateVideoGrid();
    } else {
      // Audio tracks are associated with the stream (`event.streams[0]`) and require no separate actions
      console.log(`[${streamId}]: Audio track added`);
    }
  };

  pc.onicegatheringstatechange = () =>
    console.log(`[${streamId}]: Gathering state change:`, pc.iceGatheringState);
  pc.onconnectionstatechange = () =>
    console.log(`[${streamId}]: Connection state change:`, pc.connectionState);
  pc.onicecandidate = (event) => {
    if (event.candidate == null) {
      return;
    }

    const candidate = JSON.stringify(event.candidate);
    if (streamData.patchEndpoint === undefined) {
      candidates.push(candidate);
    } else {
      sendCandidate(candidate, streamData.patchEndpoint, streamId);
    }
  };

  pc.addTransceiver('video', { direction: 'recvonly' });
  pc.addTransceiver('audio', { direction: 'recvonly' });

  const offer = await pc.createOffer();
  await pc.setLocalDescription(offer);

  const whepEndpoint = whepEndpointBase + '?streamId=' + streamId;
  const response = await fetch(whepEndpoint, {
    method: 'POST',
    cache: 'no-cache',
    headers: {
      Accept: 'application/sdp',
      'Content-Type': 'application/sdp',
    },
    body: pc.localDescription.sdp,
  });

  if (response.status !== 201) {
    console.error(
      `[${streamId}]: Failed to initialize WHEP connection, status: ${response.status}`
    );
    return;
  }

  streamData.patchEndpoint = response.headers.get('location');
  console.log(`[${streamId}]: Sucessfully initialized WHEP connection`);

  for (const candidate of candidates) {
    sendCandidate(candidate, streamData.patchEndpoint, streamId);
  }

  const sdp = await response.text();
  await pc.setRemoteDescription({ type: 'answer', sdp: sdp });

  statusMessage.classList.add('hidden');
}

async function removeStream(streamId) {
  const streamData = streamsData.get(streamId);
  streamsData.delete(streamId);

  if (streamData) {
    streamData.pc.close();

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

async function sendCandidate(candidate, patchEndpoint, streamId) {
  const response = await fetch(patchEndpoint, {
    method: 'PATCH',
    cache: 'no-cache',
    headers: {
      'Content-Type': 'application/trickle-ice-sdpfrag',
    },
    body: candidate,
  });

  if (response.status === 204) {
    console.log(`[${streamId}]: Successfully sent ICE candidate:`, candidate);
  } else {
    console.error(
      `[${streamId}]: Failed to send ICE, status: ${response.status}, candidate:`,
      candidate
    );
  }
}

async function changeLayer(layer) {
  // According to the spec, we should gather the info about available layers from the `layers` event
  // emitted in the SSE stream tied to *one* given WHEP session.
  //
  // However, to simplify the implementation and decrease resource usage, we're assuming each stream
  // has the layers with `encodingId` of `h`, `m` and `l`, corresponding to high, medium and low video quality.
  // If that's not the case (e.g. the stream doesn't use simulcast), the server returns an error response which we ignore.
  //
  // Nevertheless, the server supports the `Server Sent Events` and `Video Layer Selection` WHEP extensions,
  // and WHEP players other than this site are free to use them.
  //
  // For more info refer to https://www.ietf.org/archive/id/draft-ietf-wish-whep-01.html#section-4.6.2
  for (const [
    streamId,
    { patchEndpoint: patchEndpoint },
  ] of streamsData.entries()) {
    if (patchEndpoint) {
      const response = await fetch(`${patchEndpoint}/layer`, {
        method: 'POST',
        cache: 'no-cache',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ encodingId: layer }),
      });

      if (response.status != 200) {
        console.warn(`[${streamId}]: Changing layer failed`, response);
      }
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

    connectMedia(socket);
    connectChat(socket, false);

    videoQuality.onchange = () => changeLayer(videoQuality.value);

    chatToggler.onclick = () => toggleBox(chat, settings);
    settingsToggler.onclick = () => toggleBox(settings, chat);
  },
};
