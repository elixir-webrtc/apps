import { connectChat } from "./chat.js"

const chatToggler = document.getElementById("chat-toggler");
const chat = document.getElementById("chat");
const settingsToggler = document.getElementById("settings-toggler");
const settings = document.getElementById("settings");
const videoQuality = document.getElementById("video-quality");

const pcConfig = { iceServers: [{ urls: "stun:stun.l.google.com:19302" }] };
const whepEndpoint = `${window.location.origin}/api/whep`
const videoPlayer = document.getElementById("videoplayer");
const candidates = [];
let patchEndpoint;

async function sendCandidate(candidate) {
  const response = await fetch(patchEndpoint, {
    method: "PATCH",
    cache: "no-cache",
    headers: {
      "Content-Type": "application/trickle-ice-sdpfrag"
    },
    body: candidate
  });

  if (response.status === 204) {
    console.log("Successfully sent ICE candidate:", candidate);
  } else {
    console.error(`Failed to send ICE, status: ${response.status}, candidate:`, candidate)
  }
}

async function connectMedia() {
  const pc = new RTCPeerConnection(pcConfig);

  pc.ontrack = event => videoPlayer.srcObject = event.streams[0];
  pc.onicegatheringstatechange = () => console.log("Gathering state change: " + pc.iceGatheringState);
  pc.onconnectionstatechange = () => console.log("Connection state change: " + pc.connectionState);
  pc.onicecandidate = event => {
    if (event.candidate == null) {
      return;
    }

    const candidate = JSON.stringify(event.candidate);
    if (patchEndpoint === undefined) {
      candidates.push(candidate);
    } else {
      sendCandidate(candidate);
    }
  }

  pc.addTransceiver("video", { direction: "recvonly" });
  pc.addTransceiver("audio", { direction: "recvonly" });

  const offer = await pc.createOffer()
  await pc.setLocalDescription(offer);

  const response = await fetch(whepEndpoint, {
    method: "POST",
    cache: "no-cache",
    headers: {
      "Accept": "application/sdp",
      "Content-Type": "application/sdp"
    },
    body: pc.localDescription.sdp
  });

  if (response.status === 201) {
    patchEndpoint = response.headers.get("location");
    console.log("Sucessfully initialized WHEP connection")

  } else {
    console.error(`Failed to initialize WHEP connection, status: ${response.status}`);
    return;
  }

  for (const candidate of candidates) {
    sendCandidate(candidate);
  }

  let sdp = await response.text();
  await pc.setRemoteDescription({ type: "answer", sdp: sdp });
}

async function changeLayer(layer) {
  if (patchEndpoint) {
    const response = await fetch(`${patchEndpoint}/layer`, {
      method: "POST",
      cache: "no-cache",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({encodingId: layer})
    });

    if (response.status != 200) {
      videoQuality.disabled = true;
    }
  }
}

function toggleBox(element, other) {
    if (window.getComputedStyle(element).display === "none") {
      element.style.display = "flex";
      other.style.display = "none";

      // For screen's width lower than 1024,
      // eiter show video player or chat at the same time.
      if (window.innerWidth < 1024) {
        document.getElementById("videoplayer-wrapper").style.display = "none";
      }
    } else {
      element.style.display = "none";

      if (window.innerWidth < 1024) {
        document.getElementById("videoplayer-wrapper").style.display = "block";
      }
    } 
}

export const Home = {
  mounted() {
    connectMedia()
    connectChat()

    videoQuality.onchange = () => changeLayer(videoQuality.value)

    chatToggler.onclick = () => toggleBox(chat, settings);
    settingsToggler.onclick = () => toggleBox(settings, chat);

    document.getElementById("lowButton").onclick = _ => changeLayer("l")
    document.getElementById("mediumButton").onclick = _ => changeLayer("m")
    document.getElementById("highButton").onclick = _ => changeLayer("h")
  }
}
