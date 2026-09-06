# ☸️ RepairShop — Infraestrutura Kubernetes (AWS EKS)

[![Terraform](https://img.shields.io/badge/Terraform-1.8.5+-844FBA?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS EKS](https://img.shields.io/badge/AWS-Amazon%20EKS-FF9900?logo=amazon-aws&logoColor=white)](https://aws.amazon.com/eks/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.30+-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Helm](https://img.shields.io/badge/Helm-3.x-0F1689?logo=helm&logoColor=white)](https://helm.sh/)
[![GitHub Actions](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF?logo=github-actions&logoColor=white)](https://github.com/features/actions)

Repositório de **Infraestrutura como Código (IaC)** responsável pelo provisionamento do **Cluster Kubernetes Gerenciado (AWS EKS)**, **Managed Node Groups**, controladores essenciais e **Security Groups de Workloads** do projeto **RepairShop** (FIAP Tech Challenge — Fase 3).

---

## 🎯 Propósito e Escopo Arquitetural

Este módulo provisiona a camada de computação elástica em nuvem para execução dos microsserviços da aplicação e da stack de observabilidade OpenTelemetry:

- **EKS Control Plane Gerenciado:** Alta disponibilidade gerenciada pela AWS através de múltiplas Zonas de Disponibilidade (Multi-AZ).
- **Managed Node Groups em Sub-redes Privadas:** Worker Nodes EC2 provisionados estritamente nas sub-redes privadas da VPC para impedir qualquer exposição indevida à internet pública.
- **Security Groups Descentralizados (`aws_security_group.eks_nodes`):**
  - Porta `8080`: Tráfego HTTP da aplicação principal roteado via Load Balancer / API Gateway.
  - Portas `4317` (gRPC) e `4318` (HTTP): Ingestão de métricas e traces pelo OpenTelemetry Collector Gateway.
- **Integração com IAM LabRole (AWS Academy):** Configuração segura de roles de execução de nós e pods.
- **Evolução Multi-Ambiente:** Parametrização via `environments/dev.tfvars`, `hml.tfvars` e `prd.tfvars`.

---

## 🏗️ Topologia da Arquitetura do Cluster EKS

```mermaid
flowchart TB
    %% Definições de Estilo
    classDef cloudStyle fill:#ECEFF1,stroke:#607D8B,stroke-width:2px,color:#263238
    classDef vpcStyle fill:#F5F7FA,stroke:#0277BD,stroke-width:2px,color:#01579B,stroke-dasharray: 4 4
    classDef eksStyle fill:#E8EAF6,stroke:#3F51B5,stroke-width:2px,color:#1A237E
    classDef nodeGroupStyle fill:#E3F2FD,stroke:#1976D2,stroke-width:2px,color:#0D47A1
    classDef workloadStyle fill:#FFFFFF,stroke:#00ACC1,stroke-width:1.5px,color:#006064
    classDef sgStyle fill:#FFEBEE,stroke:#D32F2F,stroke-width:2px,color:#B71C1C
    classDef obsStyle fill:#F3E5F5,stroke:#8E24AA,stroke-width:1.5px,color:#4A148C
    classDef tagStyle fill:#FFFFFF,stroke:#78909C,stroke-width:1px,stroke-dasharray: 2 2,color:#37474F

    subgraph AWS_Cloud["☁️ AWS Cloud"]
        subgraph VPC["🏢 VPC Privada (VPC do repositório infra-network)"]
            subgraph EKS_Cluster["☸️ Amazon EKS Cluster — repairshop-eks"]
                ControlPlane["🧠 Control Plane (Gerenciado pela AWS)"]
                
                subgraph NodeGroup["⚙️ Managed Node Group — Subnets Privadas Multi-AZ"]
                    direction TB
                    TagNodes["🏷️ Instâncias EC2: t3.medium / t3.large (Auto Scaling)"]:::tagStyle
                    
                    Node1["💻 Worker Node 1\n(AZ: us-east-1a)"]:::nodeGroupStyle
                    Node2["💻 Worker Node 2\n(AZ: us-east-1b)"]:::nodeGroupStyle
                    TagNodes ~~~ Node1
                    
                    subgraph Workloads["📦 Workloads (Namespace: repairshop)"]
                        direction TB
                        AppPods["🚀 App Pods (Spring Boot / Java 24)\nPorta 8080 (HPA: 2 a 10 réplicas)"]:::workloadStyle
                        OTelPod["🔭 OpenTelemetry Collector\nPortas 4317 (gRPC) / 4318 (HTTP)"]:::obsStyle
                        ObsPods["📊 Stack de Métricas\n(Prometheus / Jaeger / Loki)"]:::obsStyle
                        
                        AppPods -->|"Traces & Metrics OTLP"| OTelPod
                        OTelPod --> ObsPods
                    end
                end
            end

            SG_EKS["🛡️ Security Group: eks_nodes-sg\n• Ingress: 8080 (App), 4317/4318 (OTel)\n• Egress: Irrestrito na VPC/Internet"]:::sgStyle
        end
    end
    class AWS_Cloud cloudStyle
    class VPC vpcStyle
    class EKS_Cluster eksStyle
    class NodeGroup nodeGroupStyle

    ControlPlane --- NodeGroup
    NodeGroup --- SG_EKS
```

---

## 🗂️ Estrutura de Arquivos

```text
.
├── .github/workflows/
│   ├── ci-cd-eks.yml         # Pipeline principal de CI/CD (Build, Test & Deploy EKS)
│   └── destroy.yml           # Pipeline de destruição controlada com Safety Gate
├── infra/
│   ├── main.tf               # Cluster EKS, Node Groups, Security Groups e Remote State
│   ├── variables.tf          # Definição de instâncias, capacidade de nós e variáveis
│   ├── outputs.tf            # Export de Cluster Name, Endpoint, CA e SG ID
│   ├── providers.tf          # Configuração dos provedores AWS, Kubernetes e Helm
│   ├── versions.tf           # Versões mínimas requeridas de Terraform e Provedores
│   ├── backend.tf            # Configuração do backend remoto S3
│   └── environments/
│       ├── dev.tfvars        # Parâmetros de Desenvolvimento (1-2 nós t3.medium)
│       ├── hml.tfvars        # Parâmetros de Homologação (2 nós t3.medium)
│       └── prd.tfvars        # Parâmetros de Produção (2-4 nós t3.large)
└── README.md
```

---

## 🚀 Pipeline de CI/CD (GitHub Actions)

A esteira de integração e entrega contínua do EKS está configurada em [`.github/workflows/ci-cd-eks.yml`](.github/workflows/ci-cd-eks.yml).

### Desenho da Pipeline CI/CD

```mermaid
flowchart TD
    classDef triggerStyle fill:#E1F5FE,stroke:#0288D1,stroke-width:2px,color:#01579B
    classDef stepStyle fill:#F3E5F5,stroke:#7B1FA2,stroke-width:2px,color:#4A148C
    classDef gateStyle fill:#FFF9C4,stroke:#FBC02D,stroke-width:2px,color:#F57F17
    classDef deployStyle fill:#E8F5E9,stroke:#388E3C,stroke-width:2px,color:#1B5E20
    classDef reportStyle fill:#ECEFF1,stroke:#455A64,stroke-width:2px,color:#263238

    A["🎯 Disparo / Trigger\n• Push ou PR (main, homolog, dev)\n• Workflow Dispatch Manual"]:::triggerStyle
    A --> B["⚙️ Autenticação AWS\n(Configure AWS Credentials / IAM LabRole)"]:::stepStyle
    B --> C["📦 Garantia do Bucket S3\n(Verifica/Cria fiap-repairshop2)"]:::stepStyle
    C --> D["🌐 Validação do Estado da Rede\n(Remote State: network/${ENV}.tfstate)"]:::stepStyle
    D --> E["🔍 Checagem de Formatação\n(terraform fmt -check na pasta infra/)"]:::stepStyle
    E --> F["⚡ Inicialização do Terraform\n(terraform init com backend S3 eks/${ENV}.tfstate)"]:::stepStyle
    F --> G["📝 Geração do Plano\n(terraform plan -var-file=environments/${ENV}.tfvars)"]:::stepStyle
    G --> H{"🌿 Branch é 'main' com Push\nou Dispatch Manual?"}:::gateStyle
    
    H -- "✅ Sim (Deploy Aprovado)" --> I["🚀 Terraform Apply\n(terraform apply -auto-approve)"]:::deployStyle
    H -- "🛡️ Não (PR ou Homologação)" --> J["📋 Modo Dry-Run / Plan Only\n(Validação Sintática e Recursos)"]:::reportStyle
    
    I --> K["📊 GitHub Step Summary\n(Status da Execução e Métricas)"]:::reportStyle
    J --> K
```

### Detalhamento e Justificativa de Cada Passo da Pipeline

| Passo | Ação Executada | Justificativa Arquitetural |
| :--- | :--- | :--- |
| **1. Checkout repository** | Obtém o código na versão exata do commit. | Garante a reproduzibilidade do provisionamento da infraestrutura. |
| **2. Configure AWS Credentials** | Autentica via credenciais seguras do GitHub Secrets. | Permite acesso aos recursos do laboratório AWS com permissões do `LabRole`. |
| **3. Ensure S3 Bucket State** | Valida a presença do bucket S3 `fiap-repairshop2`. | Previne falhas de inicialização do backend remoto de estado. |
| **4. Check Remote Network State** | Verifica se o arquivo `network/${ENV}.tfstate` existe no S3. | Garante a dependência arquitetural: o EKS só pode ser provisionado se a VPC e sub-redes já existirem. |
| **5. Setup Terraform** | Instala a versão `1.8.5` do Terraform. | Garante paridade de ambiente de execução com a infraestrutura de rede. |
| **6. Terraform Format Check** | Executa validação de lint e formatação HCL. | Mantém o padrão de estilo e legibilidade do código de infraestrutura. |
| **7. Terraform Init** | Inicializa os providers e conecta o estado `eks/${ENV}.tfstate`. | Mantém o estado do EKS totalmente desacoplado do estado da rede e do banco de dados. |
| **8. Terraform Plan** | Simula a criação/alteração dos recursos do EKS. | Permite auditoria prévia das mudanças sem aplicar efeitos colaterais. |
| **9. Terraform Apply** | Executa a criação do Cluster EKS e Node Groups na AWS. | Deploy automatizado exclusivo para a branch `main` ou disparo manual aprovado. |
| **10. Generate Summary** | Publica o resumo da execução no log da pipeline. | Rastreabilidade operacional imediata com detalhes do ambiente e status. |

### 💡 Decisão de Arquitetura: Estratégia de Único Job (Single Job)

> **Decisão Arquitetural:** O workflow foi desenhado com um **único JOB contínuo (`runs-on: ubuntu-latest`)**.
> 
> **Motivação Técnica:**
> 1. **Otimização de Limite de Minutos do GitHub Actions:** O provisionamento de um cluster Kubernetes gerenciado na AWS leva entre 8 a 15 minutos. Separar em múltiplos jobs exigiria múltiplos warm-ups de runners, esgotando rapidamente a cota mensal de minutos da conta.
> 2. **Sem Overhead de Caching/Re-download de Providers:** Os binários dos provedores AWS, Kubernetes e Helm permanecem em cache local durante todo o ciclo de vida do job.
> 3. **Consistência de Variáveis de Sessão:** As credenciais temporárias do AWS CLI e tokens de autenticação do cluster EKS são mantidos no mesmo contexto sem necessidade de reautenticação entre steps.

---

## 🔀 Governança de Branches e Ciclo de Promoção (Git Flow)

A governança do repositório segue isolamento estrito com aprovação controlada para promoção de ambientes:

```mermaid
flowchart LR
    classDef branchDev fill:#E3F2FD,stroke:#1E88E5,stroke-width:2px,color:#0D47A1
    classDef branchHml fill:#FFF3E0,stroke:#FB8C00,stroke-width:2px,color:#E65100
    classDef branchMain fill:#E8F5E9,stroke:#43A047,stroke-width:2px,color:#1B5E20
    classDef gateStyle fill:#FFEBEE,stroke:#E53935,stroke-width:2px,color:#B71C1C

    Dev["🌿 Feature / Fix / Chore\n(feat/*, fix/*, chore/*)"]:::branchDev
    PR_HML{"Pull Request\npara homolog"}:::gateStyle
    HML["🛡️ Branch homolog\n(Ambiente hml / Validação)"]:::branchHml
    PR_MAIN{"Pull Request\npara main"}:::gateStyle
    Main["🚀 Branch main\n(Deploy em Produção)"]:::branchMain

    Dev -->|"Abertura de PR"| PR_HML
    PR_HML -->|"Validação & Merge"| HML
    HML -->|"Abertura de PR de Promoção"| PR_MAIN
    PR_MAIN -->|"Aprovação Manual Obrigatória"| Main
```

> ⚠️ **Regra de Governança:** É expressamente proibido commit ou push direto na branch `main`. Toda alteração deve passar pelo pipeline de validação e aprovação formal.

---

## 💻 Execução e Deploy Local (Terraform CLI)

Para provisionar ou inspecionar o cluster localmente:

```bash
# 1. Navegue até a pasta de infraestrutura
cd infra

# 2. Inicialize o backend remoto S3
terraform init \
  -backend-config="bucket=fiap-repairshop2" \
  -backend-config="key=eks/dev.tfstate" \
  -backend-config="region=us-east-1"

# 3. Formate e valide o código
terraform fmt -check
terraform validate

# 4. Planeje a execução
terraform plan -var-file="environments/dev.tfvars"

# 5. Aplique as modificações
terraform apply -var-file="environments/dev.tfvars"

# 6. Atualize o kubeconfig local para acessar o cluster via kubectl
aws eks update-kubeconfig --region us-east-1 --name repairshop-eks-dev
kubectl get nodes
```

---

## 🔗 Links e Integrações no Ecossistema

- **Documentação Swagger UI da Aplicação:** [http://localhost:8080/swagger-ui/index.html](http://localhost:8080/swagger-ui/index.html)
- **Coleção Postman:** [`tech-challenge-repairshop-app/docs/postman/`](file:///c:/Users/Alexandre-AGAMIN/Projetos-%20FIAP/github-organizations-projects/tech-challenge-repairshop-app/docs/postman/)
- **Repositórios Relacionados:**
  - [`tech-challenge-repairshop-infra-network`](https://github.com/fiap-postech-repairshop/tech-challenge-repairshop-infra-network) (Fornece VPC e Subnets Privadas)
  - [`tech-challenge-repairshop-infra-db-rds`](https://github.com/fiap-postech-repairshop/tech-challenge-repairshop-infra-db-rds) (Banco de Dados PostgreSQL)
  - [`tech-challenge-repairshop-infra-apigateway`](https://github.com/fiap-postech-repairshop/tech-challenge-repairshop-infra-apigateway) (Roteador de Entrada / Proxy)
  - [`tech-challenge-repairshop-lambda-auth`](https://github.com/fiap-postech-repairshop/tech-challenge-repairshop-lambda-auth) (Autenticação Serverless)
  - [`tech-challenge-repairshop-app`](https://github.com/fiap-postech-repairshop/tech-challenge-repairshop-app) (Manifestos K8s e Código-Fonte da Aplicação)
