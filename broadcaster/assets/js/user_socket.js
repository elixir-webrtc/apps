import {Socket, Presence} from "phoenix"

let socket = new Socket("/socket", {params: {token: window.userToken}})

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
