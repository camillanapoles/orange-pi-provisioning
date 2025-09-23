
# Orange Pi Provisioning System - CI/CD Docker Edition

Sistema automatizado de provisionamento de microSDs para Orange Pi com ambiente Docker isolado, workflows independentes e validação automática.

## 🚀 Características

- **Ambiente Docker Isolado**: Todas as ferramentas em container, sem instalações na máquina local
- **Coleta Automática**: Dados da máquina Pop!_OS (WiFi, SSH, IP, usuário) coletados automaticamente
- **Workflows Independentes**: Dois projetos com configurações distintas
- **Persistência de Estado**: Configuração em etapas com recuperação de falhas
- **Validação Automática**: Ping, SSH e serviços validados automaticamente

## 📋 Projetos Suportados

### 1. Orange Pi Zero 3 (2GB) - Ender 3 SE
- **Finalidade**: Impressora 3D com Klipper
- **IP**: 192.168.1.100
- **Hostname**: ender3-pi
- **Usuário**: ender3
- **Software**: Klipper + firmware fix + screen

### 2. Orange Pi Zero 2W (1GB) - LaserTree K1
- **Finalidade**: Máquina de corte a laser com LightBurn
- **IP**: 192.168.1.101
- **Hostname**: laser-pi
- **Usuário**: laser
- **Software**: LightBurn + controle de laser

## 🛠️ Pré-requisitos

- Docker e Docker Compose
- MicroSD (mínimo 8GB)
- Rede WiFi configurada
- Chave SSH configurada (`~/.ssh/id_rsa.pub`)

## 🚀 Início Rápido

### 1. Clonar e Preparar

```bash
git clone <repository-url>
cd orange-pi-provisioning
```

### 2. Construir Container

```bash
docker compose build
```

### 3. Executar Interface Principal

```bash
docker compose run --rm provisioner scripts/provision-manager.sh
```

### 4. Seguir Menu Interativo

1. **Coletar informações do sistema local** (primeira execução)
2. **Escolher projeto** (Ender3 ou Laser)
3. **Inserir microSD** quando solicitado
4. **Aguardar gravação** (5-15 minutos)
5. **Inserir microSD no Orange Pi** e ligar
6. **Aguardar primeira inicialização** (5-10 minutos)
7. **Executar validação**

## 📁 Estrutura do Projeto

```
orange-pi-provisioning/
├── Dockerfile                     # Container com todas as dependências
├── docker-compose.yml            # Orquestração dos serviços
├── scripts/
│   ├── provision-manager.sh      # Interface principal
│   ├── collect-local-info.sh     # Coleta dados da máquina local
│   ├── deploy-ender3.sh          # Workflow Orange Pi Zero 3
│   ├── deploy-laser.sh           # Workflow Orange Pi Zero 2W
│   └── validate-deployment.sh    # Validação automática
├── configs/
│   ├── projects-config.json      # Configurações dos projetos
│   └── state-persistence.json    # Estado persistente
├── state/                        # Estados dos deployments (criado automaticamente)
├── logs/                         # Logs detalhados (criado automaticamente)
├── images/                       # Imagens Armbian baixadas (criado automaticamente)
└── reports/                      # Relatórios de validação
```

## 🔧 Comandos Avançados

### Executar Scripts Individuais

```bash
# Coletar informações do sistema
docker compose run --rm provisioner scripts/collect-local-info.sh

# Deploy específico
docker compose run --rm provisioner scripts/deploy-ender3.sh
docker compose run --rm provisioner scripts/deploy-laser.sh

# Validação específica
docker compose run --rm provisioner scripts/validate-deployment.sh ender3
docker compose run --rm provisioner scripts/validate-deployment.sh laser
```

### Executar Apenas Validação

```bash
docker compose run --rm --profile validation validator scripts/validate-deployment.sh ender3
```

### Acessar Shell do Container

```bash
docker compose run --rm provisioner bash
```

## 📊 Monitoramento e Logs

### Visualizar Logs em Tempo Real

```bash
# Logs do último deployment
tail -f logs/deploy-ender3-*.log

# Logs de validação
tail -f logs/validate-*.log
```

### Verificar Estado dos Projetos

```bash
# Via interface
docker compose run --rm provisioner scripts/provision-manager.sh

# Via arquivos de estado
cat state/ender3-deployment.json
cat state/laser-deployment.json
```

## 🔍 Solução de Problemas

### MicroSD Não Detectado

```bash
# Verificar dispositivos USB
lsblk -d -o NAME,SIZE,TRAN | grep usb

# Executar com privilégios
docker compose run --rm --privileged provisioner scripts/deploy-ender3.sh
```

### Falha na Validação SSH

1. Verificar se Orange Pi está ligado
2. Aguardar primeira inicialização completa (até 10 minutos)
3. Verificar conectividade de rede:

```bash
ping 192.168.1.100  # Ender3
ping 192.168.1.101  # Laser
```

### Problemas de WiFi

1. Verificar se SSID e senha estão corretos
2. Reconfigurar WiFi:

```bash
# Editar configuração
nano state/ender3-config.json  # ou laser-config.json
# Alterar campo "wifi.password"
```

### Logs Detalhados

```bash
# Verificar logs completos
docker compose run --rm provisioner bash
cd logs/
ls -la
cat <arquivo-de-log>
```

## 🔐 Segurança

- Senhas padrão devem ser alteradas após primeira inicialização
- Chaves SSH são configuradas automaticamente
- Acesso root via SSH é desabilitado
- Fail2ban é configurado automaticamente

## 🤝 Contribuição

1. Fork do projeto
2. Criar branch para feature (`git checkout -b feature/nova-funcionalidade`)
3. Commit das mudanças (`git commit -am 'Adiciona nova funcionalidade'`)
4. Push para branch (`git push origin feature/nova-funcionalidade`)
5. Criar Pull Request

## 📄 Licença

Este projeto está licenciado sob a Licença MIT - veja o arquivo [LICENSE](LICENSE) para detalhes.

## 📞 Suporte

Para suporte e dúvidas:
- Abrir issue no GitHub
- Verificar logs em `logs/`
- Consultar documentação em `reports/`

---

**Orange Pi Provisioning System** - Automatizando deployments com Docker e CI/CD
