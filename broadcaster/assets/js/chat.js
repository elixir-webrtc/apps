import { Presence } from 'phoenix';

export async function connectChat(socket, isAdmin) {
  const viewercount = document.getElementById('viewercount');
  const chatMessages = document.getElementById('chat-messages');
  const chatInput = document.getElementById('chat-input');
  const chatNickname = document.getElementById('chat-nickname');
  const chatButton = document.getElementById('chat-button');

  const channel = socket.channel('broadcaster:chat');
  channel.onError((reason) => console.log('Channel error. Reason: ', reason));

  const presence = new Presence(channel);
  presence.onSync(() => (viewercount.innerText = presence.list().length));

  const send = () => {
    const body = chatInput.value.trim();
    if (body != '') {
      channel.push('chat_msg', { body: body });
      chatInput.value = '';
    }
  };

  channel.on('join_chat_resp', async (resp) => {
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
      console.log(`Couldn't join chat, reason: ${resp.reason}`);
      chatNickname.classList.add('invalid-input');
    }
  });

  chatButton.onclick = async () => {
    let adminChatToken = null;

    if (isAdmin) {
      const response = await fetch(
        `${window.location.origin}/api/admin/chat-token`,
        { method: 'GET' }
      );

      const body = await response.json();
      adminChatToken = body.token;

      if (response.status != 200) {
        console.warn('Could not get admin chat token');
      }
    }

    channel.push('join_chat', {
      nickname: chatNickname.value,
      token: adminChatToken,
    });
  };

  chatNickname.onclick = () => {
    chatNickname.classList.remove('invalid-input');
  };

  channel.on('chat_msg', (msg) => {
    appendChatMessage(chatMessages, msg, isAdmin);
  });
  channel.on('delete_chat_msg', (msg) => deleteChatMessage(chatMessages, msg));

  channel
    .join()
    .receive('ok', (resp) => {
      console.log('Joined chat channel successfully', resp);
    })
    .receive('error', (resp) => {
      console.error('Unable to join chat channel', resp);
    });
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

  console.log(msg);

  if (msg.admin === true) {
    nickname.classList.add('chat-admin');
    nickname.innerText = '📹 ' + nickname.innerText;
  }

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

  // allow for 3-scroll history
  if (chatMessages.scrollHeight > 4 * chatMessages.clientHeight) {
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
