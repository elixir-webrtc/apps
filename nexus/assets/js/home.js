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
      videoPlayer.classList.add(
        'm-auto',
        'rounded-xl',
        'max-h-full',
        'max-w-full'
      );

      videoPlayerWrapper.appendChild(videoPlayer);

      event.track.onended = (_) => {
        console.log('Track ended: ' + trackId);
        videoPlayerWrapper.removeChild(videoPlayer);
      };
    } else {
      // Audio tracks are associated with the stream (`event.streams[0]`) and require no separate actions
      console.log('New audio track added');
    }
  };

  pc.onicegatheringstatechange = () =>
    console.log('Gathering state change: ' + pc.iceGatheringState);
  pc.onconnectionstatechange = () =>
    console.log('Connection state change: ' + pc.connectionState);
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

  channel.join();
  console.log('Joined channel peer:signalling');
}

export const Home = {
  async mounted() {
    connectChat();

    await createPeerConnection();
    await setupLocalMedia();
    joinChannel();
  },
};
