# Broadcaster

A [WHIP](https://datatracker.ietf.org/doc/html/draft-ietf-wish-whip-13)/[WHEP](https://datatracker.ietf.org/doc/html/draft-ietf-wish-whep-01) broadcasting server with a simble browser front-end.

## Usage

Clone this repo and change the working directory to `apps/broadcaster`.

Fetch dependencies

```shell
mix deps.get
```

Set the evironment variables

```shell
# note: these are actually the default values,
# so you can omit setting the variables
export BCR_IP="0.0.0.0"
export BCR_PORT="5002"
export BCR_TOKEN="test"
```

Run the app

```shell
mix run --no-halt
```

We will use [OBS](https://github.com/obsproject/obs-studio) as a media source.
Open OBS an go to `settings > Stream` and change `Service` to `WHIP`.

Pass `http://$BSR_IP:$BSR_PORT/api/whip` as the `Server` value and `$BSR_TOKEN` as the `Bearer Token` value, using the environment
variables values that have been set a moment ago. Press `Apply`.

Close the settings, choose a source of you liking (e.g. a web-cam feed) and press `Start Streaming`.

Acces `http://$BSR_IP:$BSR_PORT/` in your browser. You should see the live stream from you OBS.
