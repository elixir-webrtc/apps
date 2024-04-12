const pcConfig = { iceServers: [{ urls: "stun:stun.l.google.com:19302" }] };
const whepEndpoint = `${window.location.href}/api/whep`;
const videoPlayer = document.getElementById("videoPlayer");

const pc = new RTCPeerConnection(pcConfig);

pc.ontrack = event => videoPlayer.srcObject = event.streams[0];
pc.onicegatheringstatechange = async () => {
  if (pc.iceGatheringState === "complete") {
    console.log("ICE candidates have been succesfully gathered");

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
      console.log("Sucessfully initialized WHEP connection")
    } else {
      console.error(`Failed to initialize WHEP connection, received status ${response.status}`);
      return;
    }

    let sdp = await response.text();
    await pc.setRemoteDescription({ type: "answer", sdp: sdp });
  }
}

pc.addTransceiver("video", { direction: "recvonly" });
pc.addTransceiver("audio", { direction: "recvonly" });

pc.createOffer().then(offer => pc.setLocalDescription(offer));
