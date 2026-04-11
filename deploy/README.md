# Hermes Deploy

## Estrutura

```
deploy/
├── hermes-setup.sh          # Script principal de instalação na VPS
├── config.yaml.template      # Config do Hermes (tokens mascarados)
├── env.template              # Variáveis de ambiente (.env)
├── zshrc.template            # Config do Zsh
├── memory.md                 # Memória do Hermes (fatcs aprendidos)
├── user_profile.md           # Perfil e preferências do usuário
└── README.md                 # Este arquivo
```

## Como Deployar

### 1. Na VPS (primeira vez)
```bash
# Instala tudo automaticamente
curl -sSL https://raw.githubusercontent.com/ViFigueiredo/hermes-agent/main/deploy/hermes-setup.sh | bash

# Configure as chaves
nano ~/.hermes/.env
nano ~/.hermes/config.yaml

# Inicie
hermes-gateway    # ou: sudo systemctl enable --now hermes
```

### 2. Atualizações (CI/CD)
```bash
# Faça commit no main e o GitHub Actions deploya automaticamente
git add . && git commit -m "feat: atualização" && git push

# Ou force manualmente:
# GitHub → Actions → Deploy Hermes to VPS → Run workflow
```

### 3. Secrets do GitHub (necessários)
Configure em: https://github.com/ViFigueiredo/hermes-agent/settings/secrets/actions

- `VPS_HOST` → IP do servidor
- `VPS_USER` → usuário SSH (ex: root)
- `VPS_SSH_KEY` → chave privada SSH

## Fluxo de Trabalho

```
[Distrobox local] → git push → [GitHub Actions] → [VPS]
     ↓                                    ↓
  Desenvolvimento                  Deploy automático
  e testes                         + restart do gateway
```
