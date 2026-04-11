#!/bin/bash
# =============================================================================
# Hermes VPS Setup Script
# Instalação completa: Distrobox + Hermes + ecossistema
# Uso: curl -sSL https://raw.githubusercontent.com/ViFigueiredo/hermes-agent/main/deploy/hermes-setup.sh | bash
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

HERMES_HOME="$HOME/.hermes"
HERMES_REPO="$HERMES_HOME/hermes-agent"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           HERMES VPS DEPLOYMENT - INSTALAÇÃO COMPLETA       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# =============================================================================
# 1. DEPENDÊNCIAS DO SISTEMA
# =============================================================================
log "Instalando dependências do sistema..."
apt-get update -qq
apt-get install -y -qq \
    curl wget git zsh python3 python3-pip python3-venv \
    build-essential libssl-dev zlib1g-dev libbz2-dev \
    libreadline-dev libsqlite3-dev libncursesw5-dev \
    xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
    podman distrobox \
    > /dev/null 2>&1

log "Sistema atualizado"

# =============================================================================
# 2. DISTROBOX + CONTAINER UBUNTU
# =============================================================================
log "Configurando Distrobox com Ubuntu..."
if ! command -v distrobox &> /dev/null; then
    curl -sL https://raw.githubusercontent.com/89luca89/distrobox/main/install | sudo sh
fi

# Cria container Ubuntu igual ao ambiente de dev
if ! distrobox list | grep -q "hermes"; then
    distrobox create --name hermes --image ubuntu:24.04 --yes
fi

log "Distrobox configurado"

# =============================================================================
# 3. INSTALAÇÃO DENTRO DO DISTROBOX
# =============================================================================
log "Instalando Hermes dentro do Distrobox..."

distrobox enter hermes -- bash -c '
set -euo pipefail

# 3.1 Pacotes dentro do container
sudo apt-get update -qq
sudo apt-get install -y -qq \
    curl wget git zsh python3 python3-pip python3-venv \
    build-essential jq unzip ffmpeg > /dev/null 2>&1

# 3.2 NVM + Node.js
export NVM_DIR="$HOME/.nvm"
if [ ! -d "$NVM_DIR" ]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
fi
. "$NVM_DIR/nvm.sh"
nvm install 22
nvm use 22
npm install -g pnpm

# 3.3 Pyenv
if [ ! -d "$HOME/.pyenv" ]; then
    curl https://pyenv.run | bash
fi
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - zsh)"

# 3.4 Hermes Agent (clone ou pull)
if [ ! -d "$HOME/.hermes/hermes-agent" ]; then
    git clone https://github.com/ViFigueiredo/hermes-agent.git "$HOME/.hermes/hermes-agent"
else
    cd "$HOME/.hermes/hermes-agent"
    git pull origin main
fi

# 3.5 Instalar Hermes
cd "$HOME/.hermes/hermes-agent"
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[all]" > /dev/null 2>&1
pip install hermes-agent > /dev/null 2>&1

# 3.6 Linkar executável
ln -sf "$HOME/.hermes/hermes-agent/.venv/bin/hermes" "$HOME/.local/bin/hermes" 2>/dev/null || true

# 3.7 Oh My Zsh
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# 3.8 Spaceship Theme
if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/spaceship-prompt" ]; then
    git clone https://github.com/spaceship-prompt/spaceship-prompt.git \
        "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/spaceship-prompt" --depth=1
    ln -sf "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/spaceship-prompt/spaceship.zsh-theme" \
        "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/spaceship.zsh-theme"
fi

# 3.9 Zsh plugins
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions.git "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi

echo "[✓] Hermes instalado dentro do Distrobox"
'

log "Hermes instalado no container"

# =============================================================================
# 4. SINCRONIZAR CONFIGURAÇÕES DO HOST
# =============================================================================
log "Sincronizando configurações..."

# Copia .env e config.yaml do repositório (template)
if [ -f "$HERMES_REPO/deploy/config.yaml.template" ]; then
    cp "$HERMES_REPO/deploy/config.yaml.template" "$HERMES_HOME/config.yaml"
fi
if [ -f "$HERMES_REPO/deploy/env.template" ]; then
    cp "$HERMES_REPO/deploy/env.template" "$HERMES_HOME/.env"
fi

# Copia skills
if [ -d "$HERMES_REPO/deploy/skills" ]; then
    cp -r "$HERMES_REPO/deploy/skills/"* "$HERMES_HOME/skills/" 2>/dev/null || true
fi

# Copia memória e perfil do usuário
if [ -f "$HERMES_REPO/deploy/memory.md" ]; then
    cp "$HERMES_REPO/deploy/memory.md" "$HERMES_HOME/memory.md"
fi
if [ -f "$HERMES_REPO/deploy/user_profile.md" ]; then
    cp "$HERMES_REPO/deploy/user_profile.md" "$HERMES_HOME/user_profile.md"
fi

# Copia .zshrc
if [ -f "$HERMES_REPO/deploy/zshrc.template" ]; then
    cp "$HERMES_REPO/deploy/zshrc.template" "$HOME/.zshrc"
fi

log "Configurações sincronizadas"

# =============================================================================
# 5. COMANDOS DE ATALHO
# =============================================================================
log "Criando comandos de atalho..."

# Script para iniciar hermes no distrobox
cat > "$HOME/.local/bin/hermes-start" << 'SCRIPT'
#!/bin/bash
distrobox enter hermes -- zsh -c "cd ~/.hermes/hermes-agent && source .venv/bin/activate && hermes chat $@"
SCRIPT
chmod +x "$HOME/.local/bin/hermes-start"

# Script para gateway
cat > "$HOME/.local/bin/hermes-gateway" << 'SCRIPT'
#!/bin/bash
distrobox enter hermes -- zsh -c "cd ~/.hermes/hermes-agent && source .venv/bin/activate && hermes gateway start $@"
SCRIPT
chmod +x "$HOME/.local/bin/hermes-gateway"

log "Comandos criados: hermes-start, hermes-gateway"

# =============================================================================
# 6. SYSTEMD SERVICE (OPCIONAL)
# =============================================================================
log "Criando serviço systemd..."

cat > /etc/systemd/system/hermes.service << 'SERVICE'
[Unit]
Description=Hermes Agent Gateway
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/home/desenvolvimento/.hermes/hermes-agent
ExecStart=/usr/bin/distrobox enter hermes -- zsh -c "cd ~/.hermes/hermes-agent && source .venv/bin/activate && hermes gateway start"
Restart=on-failure
RestartSec=10
Environment=HOME=/home/desenvolvimento

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
log "Serviço systemd criado (hermes.service)"
echo "  Para iniciar: sudo systemctl start hermes"
echo "  Para auto-start: sudo systemctl enable hermes"

# =============================================================================
# 7. CLEANUP DE ÁUDIO (CRON DIÁRIO)
# =============================================================================
log "Configurando limpeza de áudio..."
cat > /etc/cron.daily/cleanup-hermes-audio << 'CRON'
#!/bin/bash
find /home/desenvolvimento/.hermes/audio_cache -type f -mtime +1 -delete 2>/dev/null
CRON
chmod +x /etc/cron.daily/cleanup-hermes-audio

log "Limpeza diária de áudio configurada"

# =============================================================================
# FIM
# =============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    INSTALAÇÃO COMPLETA!                     ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║                                                              ║"
echo "║  Próximos passos:                                            ║"
echo "║                                                              ║"
echo "║  1. Configure as chaves em ~/.hermes/.env                    ║"
echo "║     (API keys, tokens do Telegram, etc.)                     ║"
echo "║                                                              ║"
echo "║  2. Inicie o Hermes:                                         ║"
echo "║     hermes-start        # chat interativo                    ║"
echo "║     hermes-gateway      # gateway (Telegram, etc.)           ║"
echo "║                                                              ║"
echo "║  3. Ou ative o serviço:                                      ║"
echo "║     sudo systemctl enable --now hermes                       ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
