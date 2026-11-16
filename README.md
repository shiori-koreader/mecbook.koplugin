# MECBook

[English](README.en.md) | **Português**

Plugin do [KOReader](https://koreader.rocks) para ler livros emprestados no [MEC Livros](https://meclivros.mec.gov.br) (Ministério da Educação). Cada empréstimo é tratado como empréstimo: o livro fica no aparelho só enquanto o prazo vale, e o seu progresso de leitura sobrevive a ele.

A interface é em português do Brasil.

## Aviso

- Projeto independente e não oficial, sem vínculo com o Ministério da Educação (MEC) nem com o MEC Livros.
- Feito para a leitura pessoal dos empréstimos da sua própria conta: o livro fica protegido no aparelho, não pode ser exportado e é removido quando o empréstimo termina.
- Cada pessoa usa a própria conta, por sua conta e risco, respeitando os termos de uso da plataforma. O MEC pode bloquear o acesso a qualquer momento.

## Recursos

- **Busca** no catálogo do MEC Livros, com tela de detalhes: título, autores, editora, ano, páginas, categoria, se é obra licenciada ou domínio público, disponibilidade e sinopse (com opção de ler a sinopse completa).
- **Emprestar e ler**: emprestar baixa o livro e já abre. Só um livro por vez, como a plataforma exige.
- **Regras explicadas na tela**: livros licenciados são emprestados por 14 dias; a confirmação avisa que o empréstimo conta para os limites da plataforma (4 empréstimos a cada 30 dias, 4 resgates por título, renovações incluídas).
- **Já emprestou pelo site?** Escolher esse livro na busca apenas baixa o arquivo, sem gastar outro empréstimo. Se você já tem outro livro, o plugin diz qual e até quando, e oferece baixá-lo.
- **Avisos de vencimento**: configuráveis em *MECBook > Avisos de vencimento* (7, 3 ou 1 dia antes, qualquer valor de 1 a 60, ou nenhum). Cada aviso aparece uma vez por empréstimo e mostra a data final.
- **O livro sai quando o empréstimo acaba**: o vencimento é conferido sem internet ao abrir o KOReader, ao despertar o aparelho, antes de abrir o livro e por um temporizador local durante o uso. Um livro vencido nunca abre. Um empréstimo devolvido pelo site também é removido na próxima sincronização.
- **O progresso fica**: antes da remoção, os metadados do livro no KOReader (posição, destaques, anotações) são guardados pelo id do livro e restaurados se você emprestar o mesmo livro de novo.
- **Aviso ao remover**: ao voltar depois do fim do empréstimo, o plugin explica o que aconteceu, mostra onde você parou e oferece emprestar de novo ou buscar outro livro.
- **Renovação** (+14 dias), oferecida quando a plataforma permite, com confirmação sobre os limites consumidos.
- **Devolução**: depois de ler pelo menos 90% do livro, *Meu empréstimo > Devolver* informa seu progresso real à plataforma e devolve o livro. Antes disso a plataforma não aceita a devolução, e a tela explica.
- **EPUB determinístico**: o mesmo livro sempre gera o mesmo EPUB, byte a byte, o que mantém anotações e estatísticas do KOReader ligadas ao livro.
- **Atalhos**: três ações podem ser ligadas a gestos ou botões do KOReader: abrir o MECBook, meu empréstimo e buscar.

## Requisitos

- Um aparelho com KOReader. Testado em Kindle Paperwhite de 10ª geração e Paperwhite Signature Edition; em outros aparelhos não foi testado.
- Uma conta no MEC Livros (login gov.br).
- Wi-Fi para buscar, emprestar, renovar, devolver e sincronizar. Ler e conferir o vencimento funcionam offline.

## Instalação

- **Pela Storefront** (recomendado): instale o MECBook pela loja de plugins Storefront. As atualizações aparecem lá quando uma nova versão é publicada no GitHub.
- **Manualmente**: baixe `mecbook.koplugin-v<versão>.zip` na [última versão](https://github.com/shiori-koreader/mecbook.koplugin/releases/latest) e extraia em `koreader/plugins/` (o zip contém a pasta `mecbook.koplugin/`). Reinicie o KOReader.

Atualizar troca só a pasta do plugin. Configurações e chaves ficam em `koreader/settings/` e são mantidas.

## Configuração: chaves de acesso

A plataforma não tem login com usuário e senha (usa gov.br), então o plugin precisa dos dois cookies de sessão da sua conta:

1. Entre em meclivros.mec.gov.br em um navegador e abra as ferramentas de desenvolvedor (F12) > Aplicativo (ou Armazenamento) > Cookies.
2. Copie os valores de `auth_token` e `refresh_token`.
3. Crie o arquivo `koreader/settings/mecbook_tokens.lua` no aparelho (há um `mecbook_tokens.lua.sample` no repositório):

   ```lua
   return { auth_token = "COLE_AQUI", refresh_token = "COLE_AQUI" }
   ```

4. Com o Wi-Fi ligado, abra o *MECBook*. O plugin importa as chaves para o próprio arquivo de configurações e esvazia o `mecbook_tokens.lua`.

A chave de renovação dura cerca de 30 dias e se renova a cada uso. Se ficar mais tempo sem abrir o plugin, repita os passos. Nunca compartilhe essas chaves: elas dão acesso à sua conta.

## Uso

Abra o *MECBook* no menu de ferramentas (ou por um gesto configurado). Na primeira vez ele mostra o aviso; *Sobre* mostra de novo depois.

| Menu | O que faz |
| --- | --- |
| Meu empréstimo | Mostra o empréstimo atual, a data final e as ações disponíveis: ler, renovar (quando permitido), devolver (após 90%). Sem empréstimo local, procura um na sua conta e oferece baixar. |
| Buscar livros | Busca por título, autor ou assunto. Toque em um resultado para ver a tela do livro. |
| Avisos de vencimento | Escolhe quando ser avisado antes do fim do empréstimo. |
| Chaves de acesso | Importa as chaves de `mecbook_tokens.lua`, ou informa que já estão configuradas. |
| Sobre | Mostra o aviso de novo. |

## Regras de empréstimo (da plataforma)

- Livros licenciados: um por vez, 14 dias, devolvido automaticamente ao fim do prazo, renovável por mais 14 dias.
- Cada título pode ser resgatado até 4 vezes (empréstimos e renovações somados), e uma conta pode fazer até 4 empréstimos a cada 30 dias, renovações incluídas.
- Obras em domínio público não têm prazo nem limite na plataforma.

## Uso moderado e segurança

- Sem consultas em segundo plano: o plugin confere seus empréstimos só quando abre, ou quando o aparelho desperta com o Wi-Fi já ligado, no máximo uma vez por hora.
- Cada livro é baixado uma vez por empréstimo, um recurso por vez, com espera crescente em caso de erro do servidor.
- Se a plataforma responder HTTP 403 (acesso bloqueado), o plugin para, explica e não tenta de novo até ser aberto outra vez. Ele nunca contorna um bloqueio.
- As chaves ficam só nas configurações do plugin, nunca vão para logs, e o arquivo de importação é esvaziado após o uso.
- O EPUB fica em uma pasta oculta (`.mecbook/`) dentro da pasta de dados do KOReader, nunca na sua biblioteca, com o nome `<título> - <id>.epub`. Não existe função de exportar.
- Dentro do KOReader, a pasta `.mecbook/` não aparece no gerenciador de arquivos (mesmo com "mostrar arquivos ocultos"), não dá para navegar até ela, e copiar ou mover arquivos dela é bloqueado.

## Limitações conhecidas

- Mudar o relógio do aparelho engana a conferência de vencimento offline.
- As proteções valem dentro do KOReader. O arquivo não é criptografado, então quem acessa o armazenamento do aparelho por USB ou SSH ainda o encontra em `koreader/.mecbook/`.
- Livros em domínio público passam pelo mesmo fluxo dos licenciados e não foram verificados de ponta a ponta.
- Renovação, devolução após 90% e a mensagem do limite de 30 dias foram implementadas conforme o comportamento da plataforma, mas não foram testadas de ponta a ponta em um aparelho.
- O plugin mostra a posição de leitura em porcentagem, não o nome do capítulo.
- Não há fila de espera: livros sem cópias disponíveis aparecem como tal.

## Reportar problemas e sugerir melhorias

Antes de abrir uma issue, confira as [limitações conhecidas](#limitações-conhecidas), as [releases](https://github.com/shiori-koreader/mecbook.koplugin/releases) e as [issues já abertas](https://github.com/shiori-koreader/mecbook.koplugin/issues). Depois, use o [formulário de problema ou de sugestão](https://github.com/shiori-koreader/mecbook.koplugin/issues/new/choose). Nunca cole suas chaves de acesso.

## Desenvolvimento

```
luacheck .
busted
```

`scripts/deploy.sh` copia o plugin para um Kindle montado como unidade. Aparelhos que conectam por MTP precisam de cópia manual para `koreader/plugins/`.

A lógica de negócio fica em módulos Lua puros, com relógio, sistema de arquivos e transporte injetados (`api/`, `loans/`, `epub/`, `storage/`, `books/`), e o `main.lua` é a camada do KOReader. O código, os comentários e os commits ficam em inglês; só a interface é em português.

## Publicando uma versão

1. Atualize `VERSION` em `mecbook.koplugin/main.lua`.
2. `git tag vX.Y.Z && git push --tags`. Uma tag com `-` (por exemplo `v1.1.0-rc1`) é publicada como pré-lançamento.
3. O workflow de Release roda luacheck e busted, monta o zip com `scripts/package.py` e o anexa a uma release do GitHub. As notas da release são bilíngues (pt-BR e inglês), a partir de `.github/release-notes.md`.

## Licença

MIT. Veja `LICENSE`. Partes do construtor de EPUB são adaptadas de [luizcorreia/meclivros.koplugin](https://github.com/luizcorreia/meclivros.koplugin) (MIT, Copyright (c) 2026 Luiz Correia).
