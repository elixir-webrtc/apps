# Recognizer

Phoenix app for real-time image recognition using [Elixir WebRTC](https://github.com/elixir-webrtc) and [Elixir Nx](https://github.com/elixir-nx/nx).

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:5002`](http://localhost:5002) from your browser.

## Running with Docker

You can also run Recognizer using Docker.

Build an image:

```
docker build -t recognizer .
```

and run:

```
docker run -e SECRET_KEY_BASE="secret" -e PHX_HOST=localhost --network host recognizer
```

Note that secret has to be at least 64 bytes long.
You can generate one with `mix phx.gen.secret`.

If you are running on MacOS, instead of using `--network host` option, you have to explicitly publish ports:

```
docker run -e SECRET_KEY_BASE="secert" -e PHX_HOST=localhost -p 4000:4000 -p 50000-50010/udp recognizer
```

