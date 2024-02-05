import { Socket } from "phoenix"

const locArray = window.location.pathname.split('/');
const roomId = locArray[locArray.length - 1];

const pcConfig = { 'iceServers': [{ 'urls': 'stun:stun.l.google.com:19302' }] };

const videoPlayer = document.getElementById("videoPlayer");
const button = document.getElementById("leaveButton");
const imgpred = document.getElementById("imgpred");
const imgscore = document.getElementById("imgscore");
const time = document.getElementById("time");

let localStream;
let socket;
let channel;
let pc;

async function run() {
  console.log("Starting");

  localStream = await navigator.mediaDevices.getUserMedia({
    audio: true,
    video: {
      width: { ideal: 320 },
      height: { ideal: 160 },
      frameRate: { ideal: 10 }
    }
  });

  videoPlayer.srcObject = localStream;

  socket = new Socket("/socket", {});
  socket.connect();

  channel = socket.channel("room:" + roomId, {});
  channel.onClose(_ => { window.location.href = "/reco" });

  channel.join()
    .receive("ok", resp => { console.log("Joined successfully", resp) })
    .receive("error", resp => {
      console.log("Unable to join", resp);
      window.location.href = "/reco";
    })

  channel.on("signaling", msg => {
    if (msg.type == 'answer') {
      console.log("Setting remote answer");
      pc.setRemoteDescription(msg);
    } else if (msg.type == 'ice') {
      console.log("Adding ICE candidate");
      pc.addIceCandidate(msg.data);
    }
  })

  channel.on("imgReco", msg => {
    const pred = msg['predictions'][0];
    imgpred.innerText = pred['label'];
    imgscore.innerText = pred['score'];
  })

  channel.on("sessionTime", msg => {
    time.innerText = msg['time'];
  })

  pc = new RTCPeerConnection(pcConfig);
  pc.onicecandidate = ev => {
    channel.push('signaling', JSON.stringify({ type: 'ice', data: ev.candidate }));
  };
  pc.addTrack(localStream.getAudioTracks()[0]);
  pc.addTrack(localStream.getVideoTracks()[0]);

  offer = await pc.createOffer();
  await pc.setLocalDescription(offer);
  channel.push("signaling", JSON.stringify(offer));
}

button.onclick = () => {
  console.log("Leaving");
  localStream.getTracks().forEach(track => track.stop());
  videoPlayer.srcObject = null;

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

run();
