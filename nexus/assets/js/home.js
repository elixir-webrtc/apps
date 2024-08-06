import { connectChat } from './chat.js';
import { Socket } from 'phoenix';

const pcConfig = { iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] };
const localVideoPlayer = document.getElementById('videoplayer-local');
const videoPlayerWrapper = document.getElementById('videoplayer-wrapper');

let localStream = undefined;
let channel = undefined;
let pc = undefined;
let localTracksAdded = false;

async function createPeerConnection() {
  pc = new RTCPeerConnection(pcConfig);

  pc.ontrack = (event) => {
    if (event.track.kind == 'video') {
      console.log('Creating new video element');

      const trackId = event.track.id;
      const videoPlayer = document.createElement('video');
      videoPlayer.srcObject = event.streams[0];
      videoPlayer.autoplay = true;
      videoPlayer.className = 'rounded-xl w-full h-full object-cover';

      videoPlayerWrapper.appendChild(videoPlayer);
      updateVideoGrid();

      event.track.onended = (_) => {
        console.log('Track ended: ' + trackId);
        videoPlayerWrapper.removeChild(videoPlayer);
        updateVideoGrid();
      };
    } else {
      // Audio tracks are associated with the stream (`event.streams[0]`) and require no separate actions
      console.log('New audio track added');
    }
  };

  pc.onicegatheringstatechange = () =>
    console.log('Gathering state change: ' + pc.iceGatheringState);

  pc.onconnectionstatechange = () => {
    console.log('Connection state change: ' + pc.connectionState);
    if (pc.connectionState == 'failed') {
      pc.restartIce();
    }
  };
  pc.onicecandidate = (event) => {
    if (event.candidate == null) {
      console.log('Gathering candidates complete');
      return;
    }

    const candidate = JSON.stringify(event.candidate);
    console.log('Sending ICE candidate: ' + candidate);
    channel.push('ice_candidate', { body: candidate });
  };
}

async function setupLocalMedia() {
  console.log('Setting up local media stream');
  // ask for permissions
  localStream = await navigator.mediaDevices.getUserMedia({
    video: true,
    audio: true,
  });
  console.log(`Obtained stream with id: ${localStream.id}`);

  setupPreview();
}

function setupPreview() {
  localVideoPlayer.srcObject = localStream;
}

async function joinChannel() {
  const socket = new Socket('/socket');
  socket.connect();
  channel = socket.channel(`peer:signalling`);

  channel.onError(() => {
    socket.disconnect();
    window.location.reload();
  });
  channel.onClose(() => {
    socket.disconnect();
    window.location.reload();
  });

  channel.on('sdp_offer', async (payload) => {
    const sdpOffer = payload.body;

    console.log('SDP offer received');

    await pc.setRemoteDescription({ type: 'offer', sdp: sdpOffer });

    if (!localTracksAdded) {
      console.log('Adding local tracks to peer connection');
      localStream.getTracks().forEach((track) => pc.addTrack(track));
      localTracksAdded = true;
    }

    const sdpAnswer = await pc.createAnswer();
    await pc.setLocalDescription(sdpAnswer);

    console.log('SDP offer applied, forwarding SDP answer');
    const answer = pc.localDescription;
    channel.push('sdp_answer', { body: answer.sdp });
  });

  channel.on('ice_candidate', (payload) => {
    const candidate = JSON.parse(payload.body);
    console.log('Received ICE candidate: ' + payload.body);
    pc.addIceCandidate(candidate);
  });

  channel
    .join()
    .receive('ok', (_) => console.log('Joined channel peer:signalling'))
    .receive('error', (resp) => {
      console.error('Unable to join the room:', resp);
      socket.disconnect();

      videoPlayerWrapper.removeChild(localVideoPlayer);
      console.log(`Closing stream with id: ${localStream.id}`);
      localStream.getTracks().forEach((track) => track.stop());
      localStream = undefined;

      const errorNode = document.getElementById('join-error-message');
      errorNode.innerText = 'Unable to join the room';
      if (resp == 'peer_limit_reached') {
        errorNode.innerText +=
          ': Peer limit reached. Try again in a few minutes';
      }
      errorNode.classList.remove('hidden');
    });
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

  videoPlayerWrapper.className = `w-full h-full grid gap-2 p-2 auto-rows-fr ${columns}`;
}

export const Home = {
  async mounted() {
    connectChat();

    await createPeerConnection();
    await setupLocalMedia();
    joinChannel();
  },
};
