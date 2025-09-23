
# 🍊 Orange Pi Provisioning

Uma solução completa e automatizada para provisionamento headless de cartões microSD para Orange Pi Zero 3 e Zero 2W, otimizada para projetos de impressão 3D e corte a laser.

## 📋 Visão Geral

Este projeto fornece um script interativo que automatiza todo o processo de preparação de cartões microSD para Single Board Computers (SBC) Orange Pi, configurando-os para operação headless (sem monitor/teclado) com WiFi e SSH pré-configurados.

### 🎯 Cenários Suportados

| Perfil | SBC | Equipamento | Software Alvo |
|--------|-----|-------------|---------------|
| **Ender 3 SE** | Orange Pi Zero 3 (2GB) | Impressora 3D Creality Ender 3 SE | Klipper v0.12.0 + Moonraker + Mainsail |
| **LaserTree K1** | Orange Pi Zero 2W (1GB/2GB) | Máquina de corte a laser LaserTree K1 | LightBurn v1.6.x (ARM64) |

### 🖥️ Sistemas Operacionais Suportados

- **Armbian Bookworm v6.12** (current minimal)
- **DietPi v9.17** (Bookworm)

## ✅ Pré-requisitos

### Sistema Host
- **Linux Desktop** (testado em Pop!_OS 22.04, Ubuntu 22.04+)
- **Privilégios sudo** para operações de disco
- **Conexão WiFi ativa** (para detecção automática de rede)
- **Acesso à internet** para download das imagens

### Dependências de Software
```bash
# Instalar dependências (Ubuntu/Debian)
sudo apt update
sudo apt install -y wget xz-utils parted util-linux network-manager
```

### Hardware
- **Cartão microSD** (mínimo 8GB, recomendado 16GB+, Classe 10)
- **Leitor de cartão USB** ou slot SD integrado
- **Orange Pi Zero 3** ou **Zero 2W**

## 🚀 Uso

### 1. Clone o Repositório
```bash
git clone https://github.com/SEU_USUARIO/orange-pi-provisioning.git
cd orange-pi-provisioning
```

### 2. Execute o Script
```bash
./scripts/provision_sbc.sh
```

### 3. Siga o Assistente Interativo

O script irá guiá-lo através de:

1. **Seleção do Projeto**
   - Ender 3 SE (Klipper) ou LaserTree K1 (LightBurn)

2. **Escolha do Sistema Operacional**
   - Armbian ou DietPi

3. **Configuração de Rede**
   - Detecção automática do WiFi atual
   - Configuração de IP fixo
   - Definição de gateway e DNS

4. **Configuração SSH**
   - Porta personalizada (padrão: 8022)
   - Senha do usuário root

5. **Seleção do Dispositivo**
   - Detecção automática de cartões SD/USB

6. **Confirmações de Segurança**
   - Checkpoints antes de operações destrutivas

### 4. Primeiro Boot

Após a gravação:

1. **Inserir** o cartão microSD no Orange Pi
2. **Conectar alimentação** e aguardar 2-3 minutos
3. **Conectar via SSH**:
   ```bash
   ssh root@SEU_IP_FIXO -p 8022
   ```

## 🔧 Configurações Automáticas

### WiFi
- ✅ Conexão automática no primeiro boot
- ✅ IP fixo configurado
- ✅ DNS configurado (8.8.8.8)

### SSH
- ✅ Habilitado na porta 8022
- ✅ Login root permitido
- ✅ Configuração persistente

### Sistema
- ✅ Timezone: America/Sao_Paulo
- ✅ Locale: pt_BR.UTF-8
- ✅ Otimizações para operação headless

## 📊 Relatórios

Cada execução gera um relatório detalhado em `reports/deploy-YYYYMMDD-HHMM.md` contendo:

- Configurações aplicadas
- Informações de rede
- Status do provisionamento
- Instruções de próximos passos
- Troubleshooting específico

## 🛠️ Troubleshooting

### WiFi não conecta

**Sintomas:** SBC não aparece na rede após boot

**Soluções:**
1. Verificar se a rede é **2.4GHz** (SBCs não suportam 5GHz)
2. Confirmar SSID e senha corretos
3. Verificar logs no SBC:
   ```bash
   journalctl -u wpa_supplicant
   journalctl -u NetworkManager
   ```
4. Testar com hotspot móvel para isolamento

### SSH não conecta

**Sintomas:** `Connection refused` ou timeout

**Soluções:**
1. Verificar se SBC obteve IP:
   ```bash
   ping SEU_IP_FIXO
   nmap -p 8022 SEU_IP_FIXO
   ```
2. Aguardar mais tempo (primeiro boot pode demorar 5+ minutos)
3. Verificar firewall do host:
   ```bash
   sudo ufw status
   ```
4. Tentar porta padrão temporariamente:
   ```bash
   ssh root@SEU_IP_FIXO -p 22
   ```

### Display TFT Ender 3 SE

**Problema:** Display não funciona após instalação do Klipper

**Solução:**
1. Seguir configurações do repositório: [jpcurti/ender3-v3-se-klipper-with-display](https://github.com/jpcurti/ender3-v3-se-klipper-with-display)
2. Configurar `printer.cfg` com definições específicas do display
3. Instalar drivers TFT apropriados

### Comunicação GRBL LaserTree K1

**Problema:** Baud rate incorreto ou comunicação instável

**Soluções:**
1. Configurar baud rate correto (geralmente 115200)
2. Verificar cabo USB e conexões
3. Instalar LightBurn ARM64:
   ```bash
   wget https://github.com/LightBurnSoftware/deployment/releases/download/1.6.00/LightBurn-Linux64-v1.6.00.run
   chmod +x LightBurn-Linux64-v1.6.00.run
   ./LightBurn-Linux64-v1.6.00.run
   ```

### Cartão SD corrompido

**Sintomas:** Boot loops, filesystem errors

**Soluções:**
1. Re-executar o script com formatação completa
2. Testar cartão em outro dispositivo
3. Usar cartão de marca confiável (SanDisk, Samsung)
4. Verificar integridade SHA256 da imagem

## ⚠️ Segurança

### 🔴 AVISOS IMPORTANTES

- **Login root com senha** está habilitado por conveniência, mas representa **RISCO DE SEGURANÇA**
- **Porta SSH não padrão** (8022) oferece proteção básica contra varreduras
- **IP fixo** pode conflitar com outros dispositivos na rede

### 🛡️ Recomendações Pós-Instalação

1. **Criar usuário não-root:**
   ```bash
   adduser usuario
   usermod -aG sudo usuario
   ```

2. **Configurar autenticação por chave SSH:**
   ```bash
   ssh-keygen -t ed25519
   ssh-copy-id usuario@SEU_IP_FIXO -p 8022
   ```

3. **Desabilitar login root:**
   ```bash
   sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
   sudo systemctl restart ssh
   ```

4. **Configurar firewall:**
   ```bash
   sudo ufw enable
   sudo ufw allow 8022/tcp
   sudo ufw default deny incoming
   ```

## 📁 Estrutura do Projeto

```
orange-pi-provisioning/
├── scripts/
│   └── provision_sbc.sh          # Script principal
├── configs/
│   ├── armbian_first_run.txt.template  # Template Armbian
│   ├── dietpi.txt                # Configuração DietPi
│   └── dietpi-wifi.txt           # WiFi DietPi
├── reports/                      # Relatórios gerados
├── .github/
│   └── workflows/
│       └── validate.yml          # CI/CD
├── README.md                     # Esta documentação
└── LICENSE                       # Licença MIT
```

## 🔄 CI/CD

O projeto inclui validação automática via GitHub Actions:

- ✅ **ShellCheck** para scripts Bash
- ✅ **YAML Lint** para workflows
- ✅ **Validação de templates** e placeholders
- ✅ **Verificação de estrutura** do repositório
- ✅ **Security check** básico

## 📜 Licenciamento

### Software Livre
- **Este projeto:** MIT License
- **Armbian:** GPLv2
- **DietPi:** GPLv2
- **Klipper:** GPLv3

### Software Proprietário
- **LightBurn:** Licença comercial necessária
  - Versão trial disponível (30 dias)
  - Licença pessoal: ~$60 USD
  - Licença comercial: ~$120 USD
  - Site oficial: [lightburnsoftware.com](https://lightburnsoftware.com)

## 🤝 Contribuição

Contribuições são bem-vindas! Por favor:

1. Fork o repositório
2. Crie uma branch para sua feature
3. Commit suas mudanças
4. Abra um Pull Request

### Áreas de Melhoria

- [ ] Suporte para mais modelos de Orange Pi
- [ ] Integração com Raspberry Pi
- [ ] Interface web para configuração
- [ ] Backup/restore de configurações
- [ ] Suporte para múltiplas redes WiFi

## 📚 Referências Técnicas (2025)

### Documentação Oficial
- [Armbian Documentation](https://docs.armbian.com/) - v6.12+
- [DietPi Documentation](https://dietpi.com/docs/) - v9.17+
- [Klipper Documentation](https://www.klipper3d.org/) - v0.12.0+
- [Orange Pi Official](http://www.orangepi.org/)

### Comunidades e Fóruns
- [r/klippers](https://reddit.com/r/klippers) - Comunidade Klipper
- [r/OrangePI](https://reddit.com/r/OrangePI) - Comunidade Orange Pi
- [r/dietpi](https://reddit.com/r/dietpi) - Comunidade DietPi
- [Armbian Forum](https://forum.armbian.com/)

### Repositórios Relacionados
- [jpcurti/ender3-v3-se-klipper-with-display](https://github.com/jpcurti/ender3-v3-se-klipper-with-display)
- [Klipper3d/klipper](https://github.com/Klipper3d/klipper)
- [Arksine/moonraker](https://github.com/Arksine/moonraker)

---

## 📞 Suporte

Para suporte e dúvidas:

1. **Issues do GitHub:** Para bugs e feature requests
2. **Discussions:** Para dúvidas gerais
3. **Wiki:** Para documentação adicional

---

**⚡ Desenvolvido com ❤️ para a comunidade maker brasileira**

*Última atualização: Setembro 2025*
