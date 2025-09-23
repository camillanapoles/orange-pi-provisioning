#!/bin/bash
# Orange Pi Provisioning Script
# Versão: 1.0
# Data: 2025-09-23
# Descrição: Script interativo para provisionamento headless de cartões microSD
#           para Orange Pi Zero 3 e Zero 2W com Armbian/DietPi

set -euo pipefail

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variáveis globais
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
# CONFIGS_DIR="$PROJECT_ROOT/configs"  # Reservado para uso futuro
REPORTS_DIR="$PROJECT_ROOT/reports"
TEMP_DIR="/tmp/orange-pi-provisioning"

# URLs oficiais das imagens (atualizadas para 2025)
ARMBIAN_URL="https://github.com/armbian/build/releases/download/v24.11.0/Armbian_24.11.0_Orangepizero3_bookworm_current_6.12.0_minimal.img.xz"
DIETPI_URL="https://dietpi.com/downloads/images/DietPi_OrangePiZero3-ARMv8-Bookworm.img.xz"

# Função para logging
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Função para confirmação
confirm() {
    local prompt="$1"
    local response
    while true; do
        echo -e "${YELLOW}$prompt [s/n]:${NC} "
        read -r response
        case $response in
            [Ss]|[Ss][Ii][Mm]|[Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Aa][Oo]|[Nn][Oo]) return 1 ;;
            *) echo "Por favor, responda 's' para sim ou 'n' para não." ;;
        esac
    done
}

# Função para detectar rede WiFi atual
detect_wifi() {
    log "Detectando configuração WiFi atual..."
    
    # Detectar SSID atual
    CURRENT_SSID=$(nmcli -t -f active,ssid dev wifi | grep '^yes' | cut -d: -f2 || echo "")
    
    if [[ -z "$CURRENT_SSID" ]]; then
        warning "Não foi possível detectar SSID WiFi ativo"
        echo -n "Digite o SSID da rede WiFi: "
        read -r WIFI_SSID
    else
        info "SSID detectado: $CURRENT_SSID"
        if confirm "Usar este SSID ($CURRENT_SSID)?"; then
            WIFI_SSID="$CURRENT_SSID"
        else
            echo -n "Digite o SSID da rede WiFi: "
            read -r WIFI_SSID
        fi
    fi
    
    # Tentar capturar PSK (senha)
    WIFI_PSK=""
    if [[ -n "$CURRENT_SSID" ]] && [[ "$WIFI_SSID" == "$CURRENT_SSID" ]]; then
        # Tentar extrair senha do NetworkManager
        local nm_file="/etc/NetworkManager/system-connections/$CURRENT_SSID.nmconnection"
        if [[ -f "$nm_file" ]] && sudo test -r "$nm_file"; then
            WIFI_PSK=$(sudo grep -E "^psk=" "$nm_file" 2>/dev/null | cut -d= -f2 || echo "")
        fi
    fi
    
    if [[ -z "$WIFI_PSK" ]]; then
        echo -n "Digite a senha da rede WiFi: "
        read -rs WIFI_PSK
        echo
        echo -n "Confirme a senha da rede WiFi: "
        read -rs WIFI_PSK_CONFIRM
        echo
        
        if [[ "$WIFI_PSK" != "$WIFI_PSK_CONFIRM" ]]; then
            error "Senhas não coincidem!"
            exit 1
        fi
    else
        info "Senha WiFi detectada automaticamente"
        if ! confirm "Usar senha detectada automaticamente?"; then
            echo -n "Digite a senha da rede WiFi: "
            read -rs WIFI_PSK
            echo
        fi
    fi
}

# Função para detectar gateway e sugerir IP
detect_network() {
    log "Detectando configuração de rede..."
    
    # Detectar gateway
    GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)
    if [[ -z "$GATEWAY" ]]; then
        error "Não foi possível detectar gateway padrão"
        exit 1
    fi
    
    # Extrair prefixo da rede (assumindo /24)
    NETWORK_PREFIX=$(echo "$GATEWAY" | cut -d. -f1-3)
    
    info "Gateway detectado: $GATEWAY"
    info "Prefixo de rede: $NETWORK_PREFIX.x"
    
    # Sugerir IP fixo
    SUGGESTED_IP="$NETWORK_PREFIX.100"
    echo -n "IP fixo para o SBC [$SUGGESTED_IP]: "
    read -r FIXED_IP
    
    if [[ -z "$FIXED_IP" ]]; then
        FIXED_IP="$SUGGESTED_IP"
    fi
    
    # Validar formato IP
    if ! [[ "$FIXED_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        error "Formato de IP inválido: $FIXED_IP"
        exit 1
    fi
    
    info "IP fixo configurado: $FIXED_IP"
}

# Função para escolher projeto
choose_project() {
    echo
    echo "=== Escolha o Projeto ==="
    echo "1) Orange Pi Zero 3 + Ender 3 SE (Klipper)"
    echo "2) Orange Pi Zero 2W + LaserTree K1 (LightBurn)"
    echo
    echo -n "Escolha [1-2]: "
    read -r PROJECT_CHOICE
    
    case $PROJECT_CHOICE in
        1)
            PROJECT_NAME="Ender3SE-Klipper"
            SBC_MODEL="Orange Pi Zero 3"
            TARGET_SOFTWARE="Klipper v0.12.0 + Moonraker + Mainsail"
            ;;
        2)
            PROJECT_NAME="LaserTreeK1-LightBurn"
            SBC_MODEL="Orange Pi Zero 2W"
            TARGET_SOFTWARE="LightBurn v1.6.x (ARM64)"
            ;;
        *)
            error "Opção inválida"
            exit 1
            ;;
    esac
    
    info "Projeto selecionado: $PROJECT_NAME"
    info "SBC: $SBC_MODEL"
    info "Software: $TARGET_SOFTWARE"
}

# Função para escolher OS
choose_os() {
    echo
    echo "=== Escolha o Sistema Operacional ==="
    echo "1) Armbian Bookworm v6.12 (minimal)"
    echo "2) DietPi v9.17 (Bookworm)"
    echo
    echo -n "Escolha [1-2]: "
    read -r OS_CHOICE
    
    case $OS_CHOICE in
        1)
            OS_NAME="Armbian"
            OS_VERSION="24.11.0"
            IMAGE_URL="$ARMBIAN_URL"
            IMAGE_FILE="Armbian_24.11.0_Orangepizero3_bookworm_current_6.12.0_minimal.img.xz"
            ;;
        2)
            OS_NAME="DietPi"
            OS_VERSION="9.17"
            IMAGE_URL="$DIETPI_URL"
            IMAGE_FILE="DietPi_OrangePiZero3-ARMv8-Bookworm.img.xz"
            ;;
        *)
            error "Opção inválida"
            exit 1
            ;;
    esac
    
    info "OS selecionado: $OS_NAME $OS_VERSION"
}

# Função para detectar dispositivos SD
detect_sd_devices() {
    log "Detectando dispositivos de armazenamento..."
    
    # Listar dispositivos removíveis
    mapfile -t SD_DEVICES < <(lsblk -d -n -o NAME,SIZE,TRAN | grep usb | awk '{print "/dev/" $1 " (" $2 ")"}')
    
    if [[ ${#SD_DEVICES[@]} -eq 0 ]]; then
        error "Nenhum dispositivo USB/SD detectado"
        exit 1
    fi
    
    echo
    echo "=== Dispositivos Detectados ==="
    for i in "${!SD_DEVICES[@]}"; do
        echo "$((i+1))) ${SD_DEVICES[i]}"
    done
    echo
    echo -n "Escolha o dispositivo [1-${#SD_DEVICES[@]}]: "
    read -r DEVICE_CHOICE
    
    if [[ ! "$DEVICE_CHOICE" =~ ^[0-9]+$ ]] || [[ "$DEVICE_CHOICE" -lt 1 ]] || [[ "$DEVICE_CHOICE" -gt ${#SD_DEVICES[@]} ]]; then
        error "Opção inválida"
        exit 1
    fi
    
    SD_DEVICE=$(echo "${SD_DEVICES[$((DEVICE_CHOICE-1))]}" | awk '{print $1}')
    info "Dispositivo selecionado: $SD_DEVICE"
    
    # Verificar se está montado
    if mount | grep -q "$SD_DEVICE"; then
        warning "Dispositivo está montado. Desmontando..."
        sudo umount "${SD_DEVICE}"* 2>/dev/null || true
    fi
}

# Função para configurar SSH
configure_ssh() {
    echo
    echo "=== Configuração SSH ==="
    echo -n "Porta SSH [8022]: "
    read -r SSH_PORT
    
    if [[ -z "$SSH_PORT" ]]; then
        SSH_PORT="8022"
    fi
    
    echo -n "Senha para usuário root: "
    read -rs ROOT_PASSWORD
    echo
    echo -n "Confirme a senha: "
    read -rs ROOT_PASSWORD_CONFIRM
    echo
    
    if [[ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]]; then
        error "Senhas não coincidem!"
        exit 1
    fi
    
    warning "ATENÇÃO: Login root com senha é um risco de segurança!"
    warning "Recomenda-se substituir por chave SSH após primeiro acesso."
    
    if ! confirm "Continuar mesmo assim?"; then
        exit 1
    fi
}

# Função para download da imagem
download_image() {
    log "Preparando download da imagem..."
    
    mkdir -p "$TEMP_DIR"
    local image_path="$TEMP_DIR/$IMAGE_FILE"
    
    if [[ -f "$image_path" ]]; then
        info "Imagem já existe: $image_path"
        if ! confirm "Usar imagem existente?"; then
            rm -f "$image_path"
        else
            return 0
        fi
    fi
    
    log "Baixando $OS_NAME $OS_VERSION..."
    if ! wget -O "$image_path" "$IMAGE_URL"; then
        error "Falha no download da imagem"
        exit 1
    fi
    
    # Verificar SHA256 (opcional)
    if confirm "Verificar integridade SHA256 da imagem?"; then
        warning "Verificação SHA256 não implementada nesta versão"
        warning "Recomenda-se verificar manualmente no site oficial"
    fi
}

# Função para formatar SD card
format_sd_card() {
    warning "ATENÇÃO: Esta operação irá APAGAR TODOS os dados do dispositivo $SD_DEVICE"
    if ! confirm "Continuar com a formatação?"; then
        exit 1
    fi
    
    log "Limpando início do dispositivo..."
    sudo dd if=/dev/zero of="$SD_DEVICE" bs=1M count=10 conv=fsync status=progress
    
    log "Criando nova tabela de partições..."
    sudo parted "$SD_DEVICE" --script mklabel msdos
    
    log "Formatação concluída"
}

# Função para gravar imagem
write_image() {
    local image_path="$TEMP_DIR/$IMAGE_FILE"
    
    warning "ATENÇÃO: Gravando imagem no dispositivo $SD_DEVICE"
    if ! confirm "Continuar com a gravação?"; then
        exit 1
    fi
    
    log "Gravando imagem (isso pode demorar alguns minutos)..."
    
    if [[ "$IMAGE_FILE" == *.xz ]]; then
        xz -dc "$image_path" | sudo dd of="$SD_DEVICE" bs=4M conv=fsync status=progress
    else
        sudo dd if="$image_path" of="$SD_DEVICE" bs=4M conv=fsync status=progress
    fi
    
    log "Sincronizando dados..."
    sudo sync
    
    log "Gravação concluída"
}

# Função para configurar boot headless
configure_headless_boot() {
    log "Configurando boot headless..."
    
    # Montar partição boot
    local mount_point="/tmp/sd_boot"
    sudo mkdir -p "$mount_point"
    
    # Aguardar sistema reconhecer partições
    sleep 2
    sudo partprobe "$SD_DEVICE" 2>/dev/null || true
    sleep 2
    
    # Encontrar partição boot
    local boot_partition
    if [[ -e "${SD_DEVICE}1" ]]; then
        boot_partition="${SD_DEVICE}1"
    elif [[ -e "${SD_DEVICE}p1" ]]; then
        boot_partition="${SD_DEVICE}p1"
    else
        error "Não foi possível encontrar partição boot"
        exit 1
    fi
    
    log "Montando partição boot: $boot_partition"
    sudo mount "$boot_partition" "$mount_point"
    
    case $OS_NAME in
        "Armbian")
            configure_armbian_headless "$mount_point"
            ;;
        "DietPi")
            configure_dietpi_headless "$mount_point"
            ;;
    esac
    
    log "Desmontando partição boot..."
    sudo umount "$mount_point"
    sudo rmdir "$mount_point"
}

# Função para configurar Armbian headless
configure_armbian_headless() {
    local mount_point="$1"
    
    log "Configurando Armbian para boot headless..."
    
    # Criar armbian_first_run.txt
    local first_run_file="$mount_point/armbian_first_run.txt"
    
    sudo tee "$first_run_file" > /dev/null <<EOF
FR_general_delete_this_file_after_completion=1
FR_general_subsequent_boots_delete_this_file=1

# Network Configuration
FR_net_change_defaults=1
FR_net_ethernet_enabled=1
FR_net_wifi_enabled=1
FR_net_wifi_ssid=$WIFI_SSID
FR_net_wifi_key=$WIFI_PSK
FR_net_use_static=1
FR_net_static_ip=$FIXED_IP
FR_net_static_mask=255.255.255.0
FR_net_static_gateway=$GATEWAY
FR_net_static_dns=8.8.8.8

# SSH Configuration
FR_openssh_enable=1
FR_openssh_port=$SSH_PORT
FR_openssh_permit_root_login=yes

# User Configuration
FR_user_root_password=$ROOT_PASSWORD
FR_user_root_pw_generate=0

# System Configuration
FR_general_lang=pt_BR.UTF-8
FR_general_timezone=America/Sao_Paulo

# Disable unnecessary services
FR_general_desktop_disable=1
FR_general_swap_disable=1
EOF

    # Criar script pós-boot para configurar SSH na porta 8022
    local post_boot_script="$mount_point/post_boot_setup.sh"
    
    sudo tee "$post_boot_script" > /dev/null <<'EOF'
#!/bin/bash
# Script executado após primeiro boot para configurar SSH

# Configurar SSH na porta 8022
sed -i "s/#Port 22/Port 8022/" /etc/ssh/sshd_config
sed -i "s/Port 22/Port 8022/" /etc/ssh/sshd_config

# Permitir login root
sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin yes/" /etc/ssh/sshd_config
sed -i "s/PermitRootLogin prohibit-password/PermitRootLogin yes/" /etc/ssh/sshd_config

# Reiniciar SSH
systemctl restart ssh
systemctl restart sshd

# Configurar firewall para porta 8022
ufw allow 8022/tcp

# Remover este script
rm -f /boot/post_boot_setup.sh
EOF

    sudo chmod +x "$post_boot_script"
    
    info "Configuração Armbian headless concluída"
}

# Função para configurar DietPi headless
configure_dietpi_headless() {
    local mount_point="$1"
    
    log "Configurando DietPi para boot headless..."
    
    # Configurar dietpi.txt
    local dietpi_txt="$mount_point/dietpi.txt"
    
    if [[ -f "$dietpi_txt" ]]; then
        sudo cp "$dietpi_txt" "$dietpi_txt.backup"
        
        # Configurações principais
        sudo sed -i "s/AUTO_SETUP_AUTOMATED=0/AUTO_SETUP_AUTOMATED=1/" "$dietpi_txt"
        sudo sed -i "s/AUTO_SETUP_GLOBAL_PASSWORD=dietpi/AUTO_SETUP_GLOBAL_PASSWORD=$ROOT_PASSWORD/" "$dietpi_txt"
        sudo sed -i "s/#AUTO_SETUP_SSH_SERVER_INDEX=-1/AUTO_SETUP_SSH_SERVER_INDEX=-2/" "$dietpi_txt"
        sudo sed -i "s/AUTO_SETUP_NET_ETHERNET_ENABLED=1/AUTO_SETUP_NET_ETHERNET_ENABLED=1/" "$dietpi_txt"
        sudo sed -i "s/AUTO_SETUP_NET_WIFI_ENABLED=0/AUTO_SETUP_NET_WIFI_ENABLED=1/" "$dietpi_txt"
        sudo sed -i "s/AUTO_SETUP_NET_USESTATIC=0/AUTO_SETUP_NET_USESTATIC=1/" "$dietpi_txt"
        sudo sed -i "s/AUTO_SETUP_NET_STATIC_IP=192.168.0.100/AUTO_SETUP_NET_STATIC_IP=$FIXED_IP/" "$dietpi_txt"
        sudo sed -i "s/AUTO_SETUP_NET_STATIC_MASK=255.255.255.0/AUTO_SETUP_NET_STATIC_MASK=255.255.255.0/" "$dietpi_txt"
        sudo sed -i "s/AUTO_SETUP_NET_STATIC_GATEWAY=192.168.0.1/AUTO_SETUP_NET_STATIC_GATEWAY=$GATEWAY/" "$dietpi_txt"
        sudo sed -i "s/AUTO_SETUP_NET_STATIC_DNS=8.8.8.8/AUTO_SETUP_NET_STATIC_DNS=8.8.8.8/" "$dietpi_txt"
        sudo sed -i "s/AUTO_SETUP_TIMEZONE=Europe\/London/AUTO_SETUP_TIMEZONE=America\/Sao_Paulo/" "$dietpi_txt"
        sudo sed -i "s/AUTO_SETUP_LOCALE=en_GB.UTF-8/AUTO_SETUP_LOCALE=pt_BR.UTF-8/" "$dietpi_txt"
    fi
    
    # Configurar dietpi-wifi.txt
    local wifi_txt="$mount_point/dietpi-wifi.txt"
    
    sudo tee "$wifi_txt" > /dev/null <<EOF
aWIFI_SSID[0]='$WIFI_SSID'
aWIFI_KEY[0]='$WIFI_PSK'
aWIFI_KEYMGR[0]='WPA-PSK'
aWIFI_PROTO[0]='RSN'
aWIFI_PAIRWISE[0]='CCMP'
aWIFI_AUTH_ALG[0]='OPEN'
aWIFI_EAPMETHOD[0]=''
aWIFI_IDENTITY[0]=''
aWIFI_PASSWORD[0]=''
aWIFI_CERT[0]=''
aWIFI_CA_CERT[0]=''
aWIFI_PRIVATE_KEY[0]=''
aWIFI_PRIVATE_KEY_PASSWD[0]=''
aWIFI_PHASE1[0]=''
aWIFI_PHASE2[0]=''
EOF

    # Criar script para configurar SSH na porta 8022
    local ssh_config_script="$mount_point/dietpi_ssh_config.sh"
    
    sudo tee "$ssh_config_script" > /dev/null <<EOF
#!/bin/bash
# Configurar SSH na porta 8022 para DietPi

# Aguardar sistema inicializar
sleep 30

# Configurar SSH
sed -i "s/#Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config
sed -i "s/Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config
sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin yes/" /etc/ssh/sshd_config
sed -i "s/PermitRootLogin prohibit-password/PermitRootLogin yes/" /etc/ssh/sshd_config

# Reiniciar SSH
systemctl restart ssh

# Configurar para executar na inicialização
echo "@reboot root /boot/dietpi_ssh_config.sh" >> /etc/crontab

# Remover este script após execução
rm -f /boot/dietpi_ssh_config.sh
EOF

    sudo chmod +x "$ssh_config_script"
    
    info "Configuração DietPi headless concluída"
}

# Função para gerar relatório
generate_report() {
    log "Gerando relatório..."
    
    mkdir -p "$REPORTS_DIR"
    local report_file
    report_file="$REPORTS_DIR/deploy-$(date +%Y%m%d-%H%M).md"
    
    cat > "$report_file" <<EOF
# Relatório de Provisionamento Orange Pi

**Data/Hora:** $(date '+%Y-%m-%d %H:%M:%S')  
**Usuário:** $(whoami)  
**Host:** $(hostname)  

## Configuração do Projeto

- **Projeto:** $PROJECT_NAME
- **SBC:** $SBC_MODEL  
- **Software Alvo:** $TARGET_SOFTWARE
- **Sistema Operacional:** $OS_NAME $OS_VERSION

## Configuração de Rede

- **SSID WiFi:** $WIFI_SSID
- **IP Fixo:** $FIXED_IP
- **Gateway:** $GATEWAY
- **Porta SSH:** $SSH_PORT

## Dispositivo de Armazenamento

- **Dispositivo:** $SD_DEVICE
- **Imagem:** $IMAGE_FILE

## Status

✅ **Provisionamento concluído com sucesso!**

## Próximos Passos

1. Inserir o cartão microSD no $SBC_MODEL
2. Conectar alimentação e aguardar boot (2-3 minutos)
3. Conectar via SSH:
   \`\`\`bash
   ssh root@$FIXED_IP -p $SSH_PORT
   \`\`\`

## Notas de Segurança

⚠️ **IMPORTANTE:** O login root com senha está habilitado por conveniência, mas representa um risco de segurança. Recomenda-se:

1. Após primeiro acesso, criar usuário não-root
2. Configurar autenticação por chave SSH
3. Desabilitar login root com senha
4. Configurar firewall adequadamente

## Troubleshooting

### WiFi não conecta
- Verificar SSID e senha
- Verificar se rede é 2.4GHz (SBC não suporta 5GHz)
- Verificar logs: \`journalctl -u wpa_supplicant\`

### SSH não conecta
- Verificar se SBC obteve IP correto: \`ping $FIXED_IP\`
- Verificar porta SSH: \`nmap -p $SSH_PORT $FIXED_IP\`
- Aguardar mais tempo para boot completo

### Para Ender 3 SE (Display TFT)
- Configurar display após instalação do Klipper
- Referência: jpcurti/ender3-v3-se-klipper-with-display

### Para LaserTree K1 (GRBL)
- Configurar baud rate correto para comunicação GRBL
- Instalar LightBurn ARM64 após boot

---
*Relatório gerado automaticamente pelo Orange Pi Provisioning Script v1.0*
EOF

    info "Relatório salvo em: $report_file"
}

# Função principal
main() {
    echo
    echo "========================================"
    echo "  Orange Pi Provisioning Script v1.0"
    echo "========================================"
    echo
    
    # Verificar privilégios sudo
    if ! sudo -n true 2>/dev/null; then
        error "Este script requer privilégios sudo"
        exit 1
    fi
    
    # Verificar dependências
    for cmd in nmcli wget xz dd parted lsblk; do
        if ! command -v "$cmd" &> /dev/null; then
            error "Comando necessário não encontrado: $cmd"
            exit 1
        fi
    done
    
    # Fluxo principal
    choose_project
    choose_os
    detect_wifi
    detect_network
    configure_ssh
    detect_sd_devices
    
    # Resumo final
    echo
    echo "=== RESUMO DA CONFIGURAÇÃO ==="
    echo "Projeto: $PROJECT_NAME"
    echo "OS: $OS_NAME $OS_VERSION"
    echo "Dispositivo: $SD_DEVICE"
    echo "SSID: $WIFI_SSID"
    echo "IP Fixo: $FIXED_IP"
    echo "Porta SSH: $SSH_PORT"
    echo
    
    if ! confirm "Confirma todas as configurações acima?"; then
        exit 1
    fi
    
    # Executar provisionamento
    download_image
    format_sd_card
    write_image
    configure_headless_boot
    generate_report
    
    echo
    log "🎉 Provisionamento concluído com sucesso!"
    echo
    echo "Próximos passos:"
    echo "1. Inserir cartão microSD no $SBC_MODEL"
    echo "2. Conectar alimentação e aguardar boot (2-3 minutos)"
    echo "3. Conectar via SSH: ssh root@$FIXED_IP -p $SSH_PORT"
    echo
    warning "Lembre-se de configurar autenticação por chave SSH após primeiro acesso!"
}

# Executar função principal
main "$@"
