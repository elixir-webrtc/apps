import { Socket } from 'phoenix';

const locArray = window.location.pathname.split('/');
const roomId = locArray[locArray.length - 1];

const pcConfig = { iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] };

const videoPlayer = document.getElementById('videoPlayer');
const button = document.getElementById('leaveButton');
const imgpred = document.getElementById('imgpred');
const imgscore = document.getElementById('imgscore');
const time = document.getElementById('time');

let localStream;
let audioStrem;
let socket;
let channel;
let pc;

let audioRecorder;
let audioChunks = [];
let audioSendInterval;

async function startAudioRecording() {
  audioChunks = [];

  audioRecorder = new MediaRecorder(audioStrem, { mimeType: 'audio/webm;codecs=opus'});

  audioRecorder.ondataavailable = (event) => {
    if (event.data.size > 0) {
      audioChunks.push(event.data);
    }
  };

  audioRecorder.onstop = () => {
    const audioBlob = new Blob(audioChunks, { type: 'audio/webm;codecs=opus' });
    sendAudio(audioBlob);
    audioChunks = [];
  };

  audioRecorder.start();
}

function stopAudioRecording() {
  if (audioRecorder) {
    audioRecorder.stop();
  }
}

function sendAudio(audioBlob) {
  if (!channel || !channel.push) {
    console.error('Channel is not initialized or push method is not available. Cannot send audio.');
    return;
  }

  const reader = new FileReader();
  reader.readAsDataURL(audioBlob);
  reader.onloadend = () => {
    try {
      const base64AudioMessage = reader.result.split(',')[1];
      channel.push('audio_chunk', { audio: base64AudioMessage });
      console.log('📤 Audio sent:', base64AudioMessage.length, 'bytes');
    } catch (error) {
      console.error('Error sending audio:', error);
    }
  };
}

function startAudioSendingLoop() {
  audioSendInterval = setInterval(() => {
    stopAudioRecording();
    startAudioRecording();
  }, 5000); // Send audio every 5 seconds
}

function stopAudioSendingLoop() {
  if (audioSendInterval) {
    clearInterval(audioSendInterval);
  }
}


async function connect() {
  console.log('Connecting');
  button.onclick = disconnect;

  localStream = await navigator.mediaDevices.getUserMedia({
    audio: true,
    video: {
      width: { ideal: 320 },
      height: { ideal: 160 },
      frameRate: { ideal: 15 },
    },
  });

  audioStrem = await navigator.mediaDevices.getUserMedia({
    audio: {
      echoCancellation: true,
      noiseSuppression: true
    },
    video: false}
  )

  videoPlayer.srcObject = localStream;
  startAudioRecording();

  socket = new Socket('/socket', {});
  socket.connect();

  channel = socket.channel('room:' + roomId, {});
  channel.onClose((_) => {
    window.location.href = '/';
  });

  channel
    .join()
    .receive('ok', (resp) => {
      console.log('Joined successfully', resp);
    })
    .receive('error', (resp) => {
      console.log('Unable to join', resp);
      window.location.href = '/';
    });

  channel.on('signaling', (msg) => {
    if (msg.type == 'answer') {
      console.log('Setting remote answer');
      pc.setRemoteDescription(msg);
    } else if (msg.type == 'ice') {
      console.log('Adding ICE candidate');
      pc.addIceCandidate(msg.data);
    }
  });

  channel.on('imgReco', (pred) => {
    imgpred.innerText = pred['label'];
    imgscore.innerText = pred['score'].toFixed(3);
  });

  channel.on('audioTranscription', (msg) => {
    audiotranscription.innerText = msg['text']
  });

  channel.on('sessionTime', (msg) => {
    time.innerText = msg['time'];
  });

  pc = new RTCPeerConnection(pcConfig);
  pc.onicecandidate = (ev) => {
    channel.push(
      'signaling',
      JSON.stringify({ type: 'ice', data: ev.candidate })
    );
  };
  pc.addTrack(localStream.getAudioTracks()[0]);
  pc.addTrack(localStream.getVideoTracks()[0]);

  const offer = await pc.createOffer();
  await pc.setLocalDescription(offer);
  channel.push('signaling', JSON.stringify(offer));

  startAudioSendingLoop()
}

function disconnect() {
  console.log('Disconnecting');
  localStream.getTracks().forEach((track) => track.stop());
  videoPlayer.srcObject = null;

  stopAudioSendingLoop()

  if (typeof channel !== 'undefined') {
    channel.leave();
  }

  if (typeof socket !== 'undefined') {
    socket.disconnect();
  }

  if (typeof pc !== 'undefined') {
    pc.close();
  }
}

export const Room = {
  mounted() {
    connect();
  },
};
