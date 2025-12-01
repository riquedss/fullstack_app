# Fullstack App – Guia de Instalação e Uso

Este projeto é um sistema web fullstack composto por:
- **Backend:** Ruby on Rails 8.x (API, autenticação, regras de negócio, integrações)
- **Frontend:** React + TypeScript (SPA com Vite)
- **Banco de Dados:** MySQL

> **Requisitos:**
> - Ruby 3.3.x
> - Node.js (v18+) e npm
> - MySQL Server (5.7+ recom.)
> - Bundler 2+

## 1. Preparação do ambiente

### a) Dependências globais
```bash
# Instale o Ruby 3.3.10 (use RVM, rbenv, asdf ou pacote Linux)
# Instale o Node.js (https://nodejs.org/en/download/)
# Instale o MySQL (sudo apt install mysql-server) e crie um usuário/root
# Bundler Ruby (se ainda não possuir)
gem install bundler
```

### b) Clone o repositório
```bash
git clone git@github.com:riquedss/fullstack_app.git
cd fullstack_app
```

## 2. Configuração de variáveis de ambiente (.env)

Toda configuração sensível (usuário e senha do banco, nomes customizados etc) deve ficar em um arquivo `.env` na raiz do projeto (nunca suba isso para o git!).

Exemplo de `.env`:
```env
# Credenciais do banco de dados (usadas pelo database.yml)
DB_USERNAME=root
DB_PASSWORD=sua_senha_aqui

# Alternativamente, você pode usar DATABASE_URL (Rails prioriza esta variável se presente)
# DATABASE_URL="mysql2://root:sua_senha_aqui@127.0.0.1:3306/fullstack_app_development"

# Para produção, use variáveis específicas:
# FULLSTACK_APP_DATABASE_PASSWORD=senha_producao
```
**Crie o arquivo `.env`** baseado nesse modelo e ajuste as credenciais do seu banco local.

> **Nota:** As variáveis do `.env` são carregadas automaticamente em desenvolvimento e teste graças à gem `dotenv-rails`. Não é necessário rodar comandos de export manualmente, apenas crie/edite o `.env` antes de rodar a aplicação.

## 3. Configuração do Banco de Dados

O arquivo `config/database.yml` já está configurado para usar variáveis de ambiente do arquivo `.env`:

- **Desenvolvimento e Teste:** Usa `DB_USERNAME` e `DB_PASSWORD` do `.env`
- **Produção:** Usa `FULLSTACK_APP_DATABASE_PASSWORD` do `.env` (ou variáveis de ambiente do sistema)

**Importante:**
- O `database.yml` não contém senhas hardcoded - todas vêm das variáveis de ambiente
- Se você definir `DATABASE_URL` no `.env`, o Rails priorizará essa variável sobre as configurações individuais do `database.yml`
- Os nomes dos bancos são fixos: `fullstack_app_development`, `fullstack_app_test`, `fullstack_app_production`

Se necessário, crie os bancos:
```bash
mysql -u root -p
# No prompt MySQL:
CREATE DATABASE fullstack_app_development;
CREATE DATABASE fullstack_app_test;
```

## 4. Instalando dependências do backend (Ruby/Rails)

```bash
bundle install
```

## 5. Instalando dependências do Frontend (React)

```bash
cd client
npm install
cd ..
```

## 6. Inicialização do Projeto (ambiente local)

### Forma recomendada (tudo integrado na porta 3000):
```bash
bin/dev
```
> Este comando inicia automaticamente o Vite (frontend) e o Rails (backend), e tudo fica acessível em **http://localhost:3000**. O Rails faz proxy reverso para o Vite em desenvolvimento, então você acessa tudo pela mesma porta!

### Forma alternativa (setup completo):
```bash
bin/setup
```
> Este comando instala dependências, prepara o banco, limpa logs/temp e já inicia os servidores.

### Manualmente (se preferir rodar separadamente)
1. **Em um terminal, suba o frontend:**
    ```bash
    cd client
    npm run dev # Vite na porta 5173
    ```
2. **Em outro terminal, suba o backend:**
    ```bash
    ./bin/rails server # Rails na porta 3000
    ```
3. **Acesse:**
    - Frontend: http://localhost:5173 (faz proxy para Rails)
    - Backend: http://localhost:3000 (API apenas)

> **Nota:** Com `bin/dev`, tudo fica integrado na porta 3000. O Rails detecta requisições de API e processa normalmente, e faz proxy reverso para o Vite em todas as outras requisições.

## 7. Rodando os testes

### Backend (Rails com RSpec):
```bash
# Rodar todos os testes
bundle exec rspec

# Rodar testes de um arquivo específico
bundle exec rspec spec/models/user_spec.rb

# Rodar testes de um diretório
bundle exec rspec spec/models/

# Rodar um teste específico (por linha)
bundle exec rspec spec/models/user_spec.rb:10

# Com formatação detalhada
bundle exec rspec --format documentation
```

### Frontend (React):
- (Adicionar testes se necessário, não há configuração pronta nesta base)

### Ferramentas de teste configuradas:
- **RSpec**: Framework de testes BDD
- **FactoryBot**: Criação de dados de teste
- **Shoulda Matchers**: Matchers para validações e associações
- **Database Cleaner**: Limpeza do banco entre testes
- **Faker**: Geração de dados aleatórios para testes

## 8. Build de produção

### Frontend
```bash
cd client
npm run build  # Gera arquivos estáticos em client/dist
```
### Backend + Frontend juntos (produção)
- O Rails serve os arquivos prontos do React de `client/dist/` automaticamente (veja config/application.rb e rotas). Basta buildar o front e rodar o Rails em produção.

## 9. Docker
- A imagem Dockerfile está preparada para produção (não para dev!).
- Rode conforme doc do topo do `Dockerfile`, exemplo:
```bash
docker build -t fullstack_app .
docker run -d -p 80:80 -e RAILS_MASTER_KEY=<valor> --name fullstack_app fullstack_app
```
- Recomenda-se definir também o `DATABASE_URL` via variável de ambiente.

## 10. Estrutura das Pastas
- `app/` – rails API (models, controllers, serviços)
- `client/` – app React (src, componentes, serviços)
- `db/` – migrações e seeds
- `bin/` – scripts utilitários e devtools
- `config/` – configs gerais e do Rails

## 11. Outras dicas
- Variáveis sensíveis (produção/dev) nunca devem estar versionadas! Use `.env` + variáveis ambiente.
- Testes automatizados: veja exemplos em `test/` (backend).
- Qualquer dúvida, verifique logs ou consulte documentações de Rails, React, MySQL, Vite.

---


