const pcConfig = { iceServers: [{ urls: "stun:stun.l.google.com:19302" }] };
const whepEndpoint = `${window.location.href}api/whep`;
const videoPlayer = document.getElementById("videoPlayer");

const pc = new RTCPeerConnection(pcConfig);
let resourceLocation;
let candidates = [];

async function connect() {
  pc.ontrack = event => videoPlayer.srcObject = event.streams[0];
  pc.onicegatheringstatechange = () => console.log("Gathering state change: " + pc.iceGatheringState);
  pc.onicecandidate = event => {
    if (event.candidate == null) {
      return;
    }

    const candidate = JSON.stringify(event.candidate);
    if (resourceLocation == undefined) {
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
    resourceLocation = `${window.location.protocol}//${window.location.host}` + response.headers.get("location");
    console.log("Sucessfully initialized WHEP connection")

    for (const candidate of candidates) {
      sendCandidate(candidate);
    }

  } else {
    console.error(`Failed to initialize WHEP connection, received status ${response.status}`);
    return;
  }

  let sdp = await response.text();
  await pc.setRemoteDescription({ type: "answer", sdp: sdp });
}

function sendCandidate(candidate) {
  fetch(resourceLocation, {
    method: "PATCH",
    cache: "no-cache",
    headers: {
      "Content-Type": "application/trickle-ice-sdpfrag"
    },
    body: candidate
  }).then((response => {
    if (response.status === 204) {
      console.log(`Successfully sent ICE candidate: ${candidate}.`);
    } else {
      console.log(`Failed to send ICE candidate: ${candidate}, reason: ${response.status}`)
    }
  }))
}

connect();