import { Socket, Presence } from 'phoenix';

export async function connectChat(isAdmin) {
  const viewercount = document.getElementById('viewercount');
  const chatMessages = document.getElementById('chat-messages');
  const chatInput = document.getElementById('chat-input');
  const chatNickname = document.getElementById('chat-nickname');
  const chatButton = document.getElementById('chat-button');

  let socket = new Socket('/socket', { params: { token: window.userToken } });

  socket.connect();

  const channel = socket.channel('stream:chat');
  const presence = new Presence(channel);

  presence.onSync(() => {
    viewercount.innerText = presence.list().length;
  });

  if (!isAdmin) {
    const send = () => {
      const body = chatInput.value.trim();
      if (body != '') {
        channel.push('chat_msg', { body: body });
        chatInput.value = '';
      }
    };

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

    chatButton.onclick = () => {
      channel.push('join_chat', { nickname: chatNickname.value });
    };

    chatNickname.onclick = () => {
      chatNickname.classList.remove('invalid-input');
    };
  }

  channel
    .join()
    .receive('ok', (resp) => {
      console.log('Joined chat channel successfully', resp);
    })
    .receive('error', (resp) => {
      console.log('Unable to join chat channel', resp);
    });

  channel.on('chat_msg', (msg) =>
    appendChatMessage(chatMessages, msg, isAdmin)
  );
  channel.on('delete_chat_msg', (msg) => deleteChatMessage(chatMessages, msg));
}

function appendChatMessage(chatMessages, msg, isAdmin) {
  if (msg.nickname == undefined || msg.body == undefined) return;

  // Check whether we have already been at the bottom of the chat.
  // If not, we won't scroll down after appending a message.
  const wasAtBottom =
    chatMessages.scrollHeight - chatMessages.clientHeight <=
    chatMessages.scrollTop + 10;

  const chatMessage = document.createElement('div');
  chatMessage.classList.add('chat-message');
  chatMessage.setAttribute('data-id', msg.id);

  const bar = document.createElement('div');
  bar.classList.add('chat-bar');

  const nickname = document.createElement('div');
  nickname.classList.add('chat-nickname');
  nickname.innerText = msg.nickname;
  bar.appendChild(nickname);

  if (isAdmin) {
    const remove = document.createElement('button');
    remove.innerText = 'remove';
    remove.classList.add('chat-remove');
    remove.onclick = async () => {
      const response = await fetch(
        `${window.location.origin}/api/admin/chat/${msg.id}`,
        { method: 'DELETE' }
      );
      if (response.status != 200) {
        console.warn('Deleting message failed');
      }
    };
    bar.appendChild(remove);
  }

  chatMessage.appendChild(bar);

  const body = document.createElement('div');
  body.innerText = msg.body;
  chatMessage.appendChild(body);

  chatMessages.appendChild(chatMessage);

  if (wasAtBottom == true) {
    chatMessages.scrollTop = chatMessages.scrollHeight;
  }

  // allow for 1 scroll history
  if (chatMessages.scrollHeight > 2 * chatMessages.clientHeight) {
    chatMessages.removeChild(chatMessages.children[0]);
  }
}

function deleteChatMessage(chatMessages, msg) {
  for (const child of chatMessages.children) {
    if (child.getAttribute('data-id') == msg.id) {
      child.lastChild.innerText = 'Removed by moderator';
      child.lastChild.style.fontStyle = 'italic';
    }
  }
}
