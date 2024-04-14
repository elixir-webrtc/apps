const pcConfig = { iceServers: [{ urls: "stun:stun.l.google.com:19302" }] };
const whepEndpoint = `${window.location.href}api/whep`;
const videoPlayer = document.getElementById("videoPlayer");
const viewersCount = document.getElementById("viewersCount");
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

async function setupViewerscountStream(link) {
  // ignore rel and events attributes for now
  let sseEntrypointEndpoint = link.split(";")[0];
  // link address is enclosed in <> 
  sseEntrypointEndpoint = sseEntrypointEndpoint.substring(1, sseEntrypointEndpoint.length - 1);

  const response = await fetch(sseEntrypointEndpoint, {
    method: "POST",
    cache: "no-cache",
  });

  sseEndpoint = response.headers.get("location");

  evtSource = new EventSource(sseEndpoint);

  evtSource.onmessage = (ev) => {
    data = JSON.parse(ev.data);
    console.log(data);
    viewersCount.innerText = data.viewerscount;
  };

  evtSource.onerror = (err) => {
    console.log(err);
    evtSource.close();
  }
}

async function connect() {
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
    console.log("Sucessfully initialized WHEP connection");
  } else {
    console.error(`Failed to initialize WHEP connection, status: ${response.status}`);
    return;
  }

  setupViewerscountStream(response.headers.get("link"));

  for (const candidate of candidates) {
    sendCandidate(candidate);
  }

  let sdp = await response.text();
  await pc.setRemoteDescription({ type: "answer", sdp: sdp });
}

connect();
