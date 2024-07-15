# Nexus

A multimedia relay server (SFU) facilitating video conference calls with a simple browser front-end.

## Usage

Clone this repo and change the working directory to `apps/nexus`.

Fetch dependencies and run the app:

```shell
mix setup
mix phx.server
```

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.
If you join from another tab/browser on the same device, you should see two streams.

### Caveats

Seeing as access to video and audio devices requires the browser to be
in a [secure context](https://developer.mozilla.org/en-US/docs/Web/Security/Secure_Contexts),
if you want to connect from another device on your network, you have to set up HTTPS access to the server.
Refer to the comments in `config/dev.exs` for more info.

At the moment, there is no way to choose the devices to be used or join without sharing media.
