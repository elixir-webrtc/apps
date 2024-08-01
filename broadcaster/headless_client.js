'use strict';

const puppeteer = require('puppeteer');

const url = (process.env.URL === undefined) ? 'http://localhost:4000' : process.env.URL;
const token = (process.env.TOKEN === undefined) ? 'example' : process.env.TOKEN;

async function start() {
    const browser = await puppeteer.launch({
        // headless: false,
        dumpio: true,
        args: [
            '--no-sandbox',
            '--use-fake-ui-for-media-stream',
            '--use-fake-device-for-media-stream'
        ]
    });

    const page = await browser.newPage();
    // we need a page with secure context in order to access userMedia
    await page.goto(`${url}/notfound`);
    await page.evaluate(async (url, token) => {
        const localStream = await navigator.mediaDevices.getUserMedia({
            video: {
                width: { ideal: 1280 },
                height: { ideal: 720 },
                frameRate: { ideal: 24 },
            },
            audio: true,
        });

        const pc = new RTCPeerConnection({ iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] });
        pc.onconnectionstatechange = async (_) => {
            if (pc.connectionState === "failed") {
                await browser.close();
                start();
            }
        };

        pc.addTrack(localStream.getAudioTracks()[0], localStream);
        pc.addTransceiver(localStream.getVideoTracks()[0], {
            streams: [localStream],
            sendEncodings: [
            { rid: 'h', maxBitrate: 1500 * 1024 },
            { rid: 'm', scaleResolutionDownBy: 2, maxBitrate: 600 * 1024 },
            { rid: 'l', scaleResolutionDownBy: 4, maxBitrate: 300 * 1024 },
            ],
        });

        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);

        const response = await fetch(`${url}/api/whip`, {
            method: 'POST',
            cache: 'no-cache',
            headers: {
                Accept: 'application/sdp',
                'Content-Type': 'application/sdp',
                Authorization: `Bearer ${token}`,
            },
            body: offer.sdp,
        });

        if (response.status !== 201) {
            throw Error("Unable to connect to the server");
        }

        const sdp = await response.text();
        await pc.setRemoteDescription({ type: 'answer', sdp: sdp });
    }, url, token);
}

start();
