import { Socket, Presence } from 'phoenix';

export async function connectChat() {
  const viewercount = document.getElementById('viewercount');
  const chatMessages = document.getElementById('chat-messages');
  const chatInput = document.getElementById('chat-input');
  const chatNickname = document.getElementById('chat-nickname');
  const chatButton = document.getElementById('chat-button');

  let socket = new Socket('/socket', { params: { token: window.userToken } });

  socket.connect();

  const channel = socket.channel('stream:chat');
  const presence = new Presence(channel);

  const send = function () {
    const body = chatInput.value.trim();
    if (body != '') {
      channel.push('chat_msg', { body: body });
      chatInput.value = '';
    }
  };

  presence.onSync(() => {
    viewercount.innerText = presence.list().length;
  });

  channel
    .join()
    .receive('ok', (resp) => {
      console.log('Joined chat channel successfully', resp);
    })
    .receive('error', (resp) => {
      console.log('Unable to join chat channel', resp);
    });

  channel.on('join_chat_resp', (resp) => {
    if (resp.result === 'success') {
      chatButton.innerText = 'Send';
      chatButton.onclick = send;
      chatNickname.disabled = true;
      chatInput.disabled = false;
      chatInput.onkeydown = (ev) => {
        if (ev.key === 'Enter') {
          // prevent from adding a new line in our text area
          ev.preventDefault();
          send();
        }
      };
    } else {
      chatNickname.classList.add('invalid-input');
    }
  });

  channel.on('chat_msg', (msg) => {
    if (msg.nickname == undefined || msg.body == undefined) return;

    const chatMessage = document.createElement('div');
    chatMessage.classList.add('chat-message');

    const nickname = document.createElement('div');
    nickname.classList.add('chat-nickname');
    nickname.innerText = msg.nickname;

    const body = document.createElement('div');
    body.innerText = msg.body;

    chatMessage.appendChild(nickname);
    chatMessage.appendChild(body);

    chatMessages.appendChild(chatMessage);

    // scroll to the bottom after adding a message
    chatMessages.scrollTop = chatMessages.scrollHeight;

    // allow for 1 scroll history
    if (chatMessages.scrollHeight > 2 * chatMessages.clientHeight) {
      chatMessages.removeChild(chatMessages.children[0]);
    }
  });

  chatButton.onclick = () => {
    channel.push('join_chat', { nickname: chatNickname.value });
  };

  chatNickname.onclick = () => {
    chatNickname.classList.remove('invalid-input');
  };
}
