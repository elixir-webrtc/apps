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
let layers = null;

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

  if (response.status !== 201) {
    console.error(`Failed to initialize WHEP connection, status: ${response.status}`);
    return;
  }

  patchEndpoint = response.headers.get("location");
  console.log("Sucessfully initialized WHEP connection")

  for (const candidate of candidates) {
    sendCandidate(candidate);
  }

  let sdp = await response.text();
  await pc.setRemoteDescription({ type: "answer", sdp: sdp });

  connectServerEvents();
}

async function connectServerEvents() {
  const response = await fetch(`${patchEndpoint}/sse`, {
    method: "POST",
    cache: "no-cache",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(["layers"])
  });

  if (response.status !== 201) {
    console.error(`Failed to fetch SSE endpoint, status: ${response.status}`);
    return;
  }

  const eventStream = response.headers.get("location");
  const eventSource = new EventSource(eventStream);
  eventSource.onopen = (ev) => {
    console.log("EventStream opened", ev);
  }

  eventSource.onmessage = (ev) => {
    const data = JSON.parse(ev.data);
    updateLayers(data.layers)
  };

  eventSource.onerror = (ev) => {
    console.log("EventStream closed", ev);
    eventSource.close();
  };
}

function updateLayers(new_layers) {
  // check if layers changed, if not, just return
  if (new_layers === null && layers === null) return;
  if (
    layers !== null &&
    new_layers !== null &&
    new_layers.length === layers.length &&
    new_layers.every((layer, i) => layer === layers[i])
  ) return;

  if (new_layers === null) {
    videoQuality.appendChild(new Option("Disabled", null, true, true));
    videoQuality.disabled = true;
    layers = null;
    return;
  }

  while (videoQuality.firstChild) {
    videoQuality.removeChild(videoQuality.firstChild);
  }

  if (new_layers === null) {
    videoQuality.appendChild(new Option("Disabled", null, true, true));
    videoQuality.disabled = true;
  } else {
    videoQuality.disabled = false;
    new_layers
      .map((layer, i) => {
        var text = layer;
        if (layer == "h") text = "High";
        if (layer == "m") text = "Medium";
        if (layer == "l") text = "Low";
        return new Option(text, layer, i == 0, layer == 0);
      })
      .forEach(option => videoQuality.appendChild(option))
  }

  layers = new_layers;
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
      console.warn("Changing layer failed", response)
      updateLayers(null);
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
  }
}
