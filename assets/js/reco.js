import { Socket } from "phoenix"

const pcConfig = { 'iceServers': [{ 'urls': 'stun:stun.l.google.com:19302' }] };

const button = document.getElementById("button");
const videoPlayer = document.getElementById("videoPlayer");

let localStream;
let socket;
let channel;

async function start() {
  console.log("Starting");
  localStream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });
  videoPlayer.srcObject = localStream;

  socket = new Socket("/socket", {});
  socket.connect();

  channel = socket.channel("room:room1", {})
  channel.join()
    .receive("ok", resp => { console.log("Joined successfully", resp) })
    .receive("error", resp => { console.log("Unable to join", resp) })



}

function stop() {
  console.log("Stopping");
  localStream.getTracks().forEach(track => track.stop());
  videoPlayer.srcObject = null;
  channel.leave();
  socket.disconnect();
}

button.onclick = () => {
  if (button.innerText == "Start") {
    button.innerText = "Stop";
    start();
  } else if (button.innerText == "Stop") {
    button.innerText = "Start";
    stop();
  }
}
