# SlapMac

App de barra de menus para macOS: dê um tapa no MacBook e ele reage com um som. Quanto mais forte o tapa, mais agudo e mais alto o som.

## Como funciona
- **Acelerômetro (padrão):** lê o sensor de movimento escondido dos MacBooks Apple Silicon (`AppleSPUHIDDevice`, página HID 0xFF00, uso 3) a cerca de 800 Hz, sem precisar de root.
- **Microfone (alternativa):** em Macs sem o sensor, detecta o estalo do tapa pelo microfone.
- A força do tapa controla a altura (de -3 a +5 semitons) e o volume do som.

## Sons
- **Botão do WhatsApp** (padrão)
- **Miau + Rizz:** mia na maioria das vezes e solta o rizz em cerca de 30% dos tapas
- **Gemidos:** sintetizados
- **Voz:** gritos em pt-BR com a voz do sistema
- **Desenho animado:** boing, bonk, guincho e estalo sintetizados
- **Sons do macOS**
- **Personalizado:** botão "Importar áudio…" no painel. Os arquivos ficam em `~/Library/Application Support/SlapMac/Sounds`.

## Painel
Clique na mão na barra de menus para ver o contador de tapas, o medidor de impacto ao vivo e os ajustes de sensibilidade, intervalo entre tapas, sensor e abertura no login.

Para fechar o app, use o ✕ no topo do painel, o botão "Fechar SlapMac" no rodapé, ou ⌘Q com o painel aberto.

## Compilar
Requer as ferramentas de linha de comando do Xcode (`swiftc`). Requer macOS 13 ou mais recente.

    ./build.sh                                  # gera build/SlapMac.app (universal)
    open build/SlapMac.app
    open build/SlapMac.app --args --test-slap   # simula 3 tapas

## Créditos dos sons
Os arquivos em `Resources/` foram baixados do [myinstants.com](https://www.myinstants.com):
- `whatsapp.mp3`: [botao do whatsapp](https://www.myinstants.com/en/instant/botao-do-whatsapp-97196/)
- `meow.mp3`: [M E O W](https://www.myinstants.com/en/instant/m-e-o-w-82698/)
- `rizz.mp3`: [Rizz Sound Effect](https://www.myinstants.com/en/instant/rizz-sound-effect-54189/)
