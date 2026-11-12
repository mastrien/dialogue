essa aplicação será dividida em duas frentes:

1. mobile (principal)
2. desktop

será um sistema de simulação de conversas extremamente simples, tudo salvo localmente e no máximo uma comunicação em rede local entre a versão desktop com a versão mobile.

o usuário escolhe alguém para conversar, como um app comum de chat, e durante a conversa ele pode alternar quem está falando, ele é quem escreve as mensagens, só escolhe no final quem é o autor (se é ele ou o personagem que está falando). deve ser possível customizar os personagens, com nomes, descrições, imagem de perfil, etc. a rede local deverá servir apenas para sincronização de dados da versão desktop com a versão mobile.

o núcleo da aplicação deve ser em rust, o desktop usa tauri e o mobile usa flutter.

para a estilização do app, verifique se é possível integrar Smooth UI no sistema (https://smoothui.dev/), se não for, pode usar outros componentes, ele é a primeira opção.