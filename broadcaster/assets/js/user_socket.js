import {Socket, Presence} from "phoenix"

let socket = new Socket("/socket", {params: {token: window.userToken}})

// When you connect, you'll often need to authenticate the client.
// For example, imagine you have an authentication plug, `MyAuth`,
// which authenticates the session and assigns a `:current_user`.
// If the current user exists you can assign the user's token in
// the connection for use in the layout.
//
// In your "lib/broadcaster_web/router.ex":
//
//     pipeline :browser do
//       ...
//       plug MyAuth
//       plug :put_user_token
//     end
//
//     defp put_user_token(conn, _) do
//       if current_user = conn.assigns[:current_user] do
//         token = Phoenix.Token.sign(conn, "user socket", current_user.id)
//         assign(conn, :user_token, token)
//       else
//         conn
//       end
//     end
//
// Now you need to pass this token to JavaScript. You can do so
// inside a script tag in "lib/broadcaster_web/templates/layout/app.html.heex":
//
//     <script>window.userToken = "<%= assigns[:user_token] %>";</script>
//
// You will need to verify the user token in the "connect/3" function
// in "lib/broadcaster_web/channels/user_socket.ex":
//
//     def connect(%{"token" => token}, socket, _connect_info) do
//       # max_age: 1209600 is equivalent to two weeks in seconds
//       case Phoenix.Token.verify(socket, "user socket", token, max_age: 1_209_600) do
//         {:ok, user_id} ->
//           {:ok, assign(socket, :user, user_id)}
//
//         {:error, reason} ->
//           :error
//       end
//     end
//

socket.connect()

const channel = socket.channel("stream:chat", {name: "TODO get user name"})
const presence = new Presence(channel)
const viewercount = document.getElementById("viewercount")

presence.onSync(() => {
  viewercount.innerText = presence.list().length
})

channel.join()
  .receive("ok", resp => { console.log("Joined chat channel successfully", resp) })
  .receive("error", resp => { console.log("Unable to join chat channel", resp) })

channel.on("chat_msg", payload => {
  // TODO capture message from some kind of input
  console.log("RECEIVED CHAT MESSAGE", payload)
})

// TODO when user types message in chat, do this
channel.push("chat_msg", {body: "TODO get chat message"})

export default socket
