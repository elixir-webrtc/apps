# Broadcaster

A [WHIP](https://datatracker.ietf.org/doc/html/draft-ietf-wish-whip-13)/[WHEP](https://datatracker.ietf.org/doc/html/draft-ietf-wish-whep-01) broadcasting server with a simple browser front-end.

## Usage

Clone this repo and change the working directory to `apps/broadcaster`.

Fetch dependencies and run the app:

```shell
mix setup
mix phx.server
```

We will use [OBS](https://github.com/obsproject/obs-studio) as a media source.
Open OBS an go to `settings > Stream` and change `Service` to `WHIP`.

Pass `http://localhost:4000/api/whip` as the `Server` value and `example` as the `Bearer Token` value, using the environment
variables values that have been set a moment ago. Press `Apply`.

Close the settings, choose a source of you liking (e.g. a web-cam feed) and press `Start Streaming`.

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser. You should see the stream from OBS.

## Running with Docker

You can also run Broadcaster using Docker.

Build an image (or use `ghcr.io/elixir-webrtc/apps/broadcaster:latest`):

```
docker build -t broadcaster .
```

and run:

```
docker run \
    -e SECRET_KEY_BASE="secret" \
    -e PHX_HOST=localhost \
    -e ADMIN_USERNAME=admin \
    -e ADMIN_PASSWORD=admin \
    -e WHIP_TOKEN=token \
    --network host \
    broadcaster
```

Note that secret has to be at least 64 bytes long.
You can generate one with `mix phx.gen.secret`.

If you are running on MacOS, instead of using `--network host` option, you have to explicitly publish ports:

```
docker run \
    -e SECRET_KEY_BASE="secert" \
    -e PHX_HOST=localhost \
    -e ADMIN_USERNAME=admin \
    -e ADMIN_PASSWORD=admin \
    -e WHIP_TOKEN=token \
    -p 4000:4000 \
    -p 50000-50010/udp \
    broadcaster
```
