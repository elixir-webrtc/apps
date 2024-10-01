const pcConfig = { iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] };

export class WHEPClient {
  constructor(url) {
    this.url = url;
    this.id = 'WHEP Client';
    this.pc = undefined;
    this.patchEndpoint = undefined;
    this.onstream = undefined;
    this.onconnected = undefined;
  }

  async connect() {
    const candidates = [];
    const pc = new RTCPeerConnection(pcConfig);
    this.pc = pc;

    pc.ontrack = (event) => {
      if (event.track.kind == 'video') {
        console.log(`[${this.id}]: Video track added`);

        if (this.onstream) {
          this.onstream(event.streams[0]);
        }
      } else {
        // Audio tracks are associated with the stream (`event.streams[0]`) and require no separate actions
        console.log(`[${this.id}]: Audio track added`);
      }
    };

    pc.onicegatheringstatechange = () =>
      console.log(
        `[${this.id}]: Gathering state change:`,
        pc.iceGatheringState
      );

    pc.onconnectionstatechange = () => {
      console.log(`[${this.id}]: Connection state change:`, pc.connectionState);
      if (pc.connectionState === 'connected' && this.onconnected) {
        this.onconnected();
      }
    };

    pc.onicecandidate = (event) => {
      if (event.candidate == null) {
        return;
      }

      const candidate = JSON.stringify(event.candidate);
      if (this.patchEndpoint === undefined) {
        candidates.push(candidate);
      } else {
        this.sendCandidate(candidate);
      }
    };

    pc.addTransceiver('video', { direction: 'recvonly' });
    pc.addTransceiver('audio', { direction: 'recvonly' });

    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    const response = await fetch(this.url, {
      method: 'POST',
      cache: 'no-cache',
      headers: {
        Accept: 'application/sdp',
        'Content-Type': 'application/sdp',
      },
      body: pc.localDescription.sdp,
    });

    if (response.status !== 201) {
      console.error(
        `[${this.id}]: Failed to initialize WHEP connection, status: ${response.status}`
      );
      return;
    }

    this.patchEndpoint = response.headers.get('location');
    console.log(`[${this.id}]: Sucessfully initialized WHEP connection`);

    for (const candidate of candidates) {
      this.sendCandidate(candidate);
    }

    const sdp = await response.text();
    await pc.setRemoteDescription({ type: 'answer', sdp: sdp });
  }

  async disconnect() {
    this.pc.close();
  }

  async changeLayer(layer) {
    // According to the spec, we should gather the info about available layers from the `layers` event
    // emitted in the SSE stream tied to *one* given WHEP session.
    //
    // However, to simplify the implementation and decrease resource usage, we're assuming each stream
    // has the layers with `encodingId` of `h`, `m` and `l`, corresponding to high, medium and low video quality.
    // If that's not the case (e.g. the stream doesn't use simulcast), the server returns an error response which we ignore.
    //
    // Nevertheless, the server supports the `Server Sent Events` and `Video Layer Selection` WHEP extensions,
    // and WHEP players other than this site are free to use them.
    //
    // For more info refer to https://www.ietf.org/archive/id/draft-ietf-wish-whep-01.html#section-4.6.2
    if (this.patchEndpoint) {
      const response = await fetch(`${this.patchEndpoint}/layer`, {
        method: 'POST',
        cache: 'no-cache',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ encodingId: layer }),
      });

      if (response.status != 200) {
        console.warn(`[${this.id}]: Changing layer failed`, response);
      }
    }
  }

  async sendCandidate(candidate) {
    const response = await fetch(this.patchEndpoint, {
      method: 'PATCH',
      cache: 'no-cache',
      headers: {
        'Content-Type': 'application/trickle-ice-sdpfrag',
      },
      body: candidate,
    });

    if (response.status === 204) {
      console.log(`[${this.id}]: Successfully sent ICE candidate:`, candidate);
    } else {
      console.error(
        `[${this.id}]: Failed to send ICE, status: ${response.status}, candidate:`,
        candidate
      );
    }
  }
}
