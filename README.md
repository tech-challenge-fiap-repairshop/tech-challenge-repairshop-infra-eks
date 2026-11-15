# ☸️🚀 Repair Shop — Infra Cluster EKS (`infra-eks`)

[![CI/CD Pipeline](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-infra-eks/actions/workflows/ci-cd-eks.yml/badge.svg)](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-infra-eks/actions/workflows/ci-cd-eks.yml)
[![Terraform](https://img.shields.io/badge/Terraform-1.8.5-7B42BC?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Amazon EKS](https://img.shields.io/badge/Amazon%20EKS-Kubernetes%201.31-FF9900?logo=amazoneks&logoColor=white)](https://aws.amazon.com/eks/)

Repositório de **Infraestrutura como Código (Terraform + Helm)** que provisiona o cluster gerenciado **Amazon EKS (Kubernetes 1.31)** da plataforma **Repair Shop (Tech Challenge FIAP — 15SOAT)** em sub-redes privadas, incluindo **Node Group escalável**, regras de Security Group para microsserviços e **OpenTelemetry** (`4317`/`4318`), e o **Metrics Server** instalado via Helm para habilitar **Horizontal Pod Autoscaler (HPA)**.

---

## 📋 Índice

- [Recursos Provisionados no Cluster](#recursos-provisionados-no-cluster)
- [Arquitetura Atual — Motivação e Benefícios dos Componentes](#arquitetura-atual--motivação-e-benefícios-dos-componentes)
- [Por que DynamoDB em vez de Banco Relacional nos Workloads do EKS?](#por-que-dynamodb-em-vez-de-banco-relacional-nos-workloads-do-eks)
- [Como Executar e Validar Localmente (Terraform)](#como-executar-e-validar-localmente-terraform)
- [Como Executar em Produção (Esteira CI/CD GitHub Actions)](#como-executar-em-produção-esteira-cicd-github-actions)
- [Documentação Técnica e Collection do Postman](#documentação-técnica-e-collection-do-postman)

---

## Recursos Provisionados no Cluster

Conforme definido em [`infra/main.tf`](infra/main.tf) e `infra/environments/{dev,hml,prd}.tfvars`:

| Componente | Configuração Técnica | Benefício |
| :--- | :--- | :--- |
| **`aws_eks_cluster.eks`** | Kubernetes **`1.31`**, `authentication_mode = "API"`, cluster `repairshop-eks-{env}` nas sub-redes privadas obtidas do state remoto `network/${ENV}.tfstate` | Control plane gerenciado com API de acesso moderna baseada em IAM. |
| **`aws_eks_node_group.nodes`** | Instâncias **`t3.medium`** em `dev`/`hml`/`prd`, capacidade **`min = 2` / `desired = 2` / `max = 4`**, usando role `LabRole` | Alta disponibilidade distribuída em 2 Zonas de Disponibilidade privadas com escalonamento automático de nós. |
| **Security Group (`cluster` / `nodes`)** | Regras liberando comunicação nas portas **`8080`** (microsserviços HTTP), **`4317`** (OTel gRPC) e **`4318`** (OTel HTTP) | Isola o plano de dados e permite ingestão transparente de traces, métricas e logs entre pods e OTel Collector. |
| **Helm Release `metrics-server` (`v3.12.1`)** | Instalado diretamente após provisionamento do cluster | Viabiliza o uso nativo de **HPA (`k8s/hpa.yaml`)** em todos os microsserviços (`register`, `service-order`, `payment`, `notification`). |

---

## Arquitetura Atual — Motivação e Benefícios dos Componentes

| Pilar / Tecnologia | Papel no Ecossistema | Motivação Técnica e Pontos Positivos |
| :--- | :--- | :--- |
| **RDS (PostgreSQL 16)** | Persistência relacional do `app-register-service` ([`infra-db-rds`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-infra-db-rds)) | Acessado pelos pods do `register-service` dentro das sub-redes privadas (porta `5432`), preservando **ACID** e chaves estrangeiras para dados cadastrais. |
| **DynamoDB (NoSQL)** | Persistência dos microsserviços de OS e Pagamentos ([`infra-db-dynamo`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-infra-db-dynamo)) | Evita que o auto-scaling (HPA) dos pods de OS e Pagamentos sature pools de conexões SQL, entregando escala `PAY_PER_REQUEST`, Single-Table Design e GSIs rápidos. |
| **ElastiCache (Redis 7.0)** | Cache em memória na rede privada ([`infra-redis`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-infra-redis)) | Disponível na porta `6379` para os pods do `register-service` dentro da mesma VPC privada, viabilizando cache sub-milissegundo de sessões/login. |
| **Apps (EKS + Lambda Auth)** | **Cluster provisionado aqui (EKS `1.31`)** + [`lambda-auth`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-lambda-auth) | Executa os 4 microsserviços Kotlin/Clean Architecture com probes de liveness/readiness, Graceful Shutdown (`30s`) e HPA (`metrics-server`), integrando-se à autenticação serverless no `lambda-auth`. |
| **Amazon SQS (Mensageria + DLQ)** | Orquestração assíncrona entre pods ([`infra-sqs`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-infra-sqs)) | Permite que os pods produzam e consumam mensagens em 5 filas + 5 DLQs com `SqsListenerHealthIndicator` nas probes do Kubernetes. |
| **API Gateway (HTTP API v2)** | Borda externa roteando aos NLBs do EKS ([`infra-apigateway`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-infra-apigateway)) | Descobre automaticamente os Network Load Balancers criados pelos Services Kubernetes (`kubernetes.io/service-name`) sem expor os nós worker diretamente à internet. |
| **Observabilidade (Grafana)** | Pods de **OTel Collector**, **Prometheus**, **Loki**, **Jaeger**, **Grafana** e **Mailpit** | Toda a stack roda no namespace `repairshop` dentro deste cluster, recebendo telemetria das portas `4317`/`4318` e consolidando os **11 dashboards Grafana**. |

---

## Por que DynamoDB em vez de Banco Relacional nos Workloads do EKS?

Num cluster Kubernetes com **Horizontal Pod Autoscaler (HPA)** ativo, a distinção entre **RDS** (apenas cadastro) e **DynamoDB** (OS e Pagamentos) protege diretamente a estabilidade operacional do EKS:

1. **Prevenção de *Connection Pool Exhaustion***: Quando o HPA multiplica réplicas de `service-order` e `payment` sob picos de tráfego (validados com **Locust** em `docs/delivery/hpa_stress/`), cada pod abriria novas conexões JDBC caso usasse PostgreSQL, derrubando uma instância `db.t3.micro`. O DynamoDB responde via HTTPS *stateless* sem manter conexões abertas.
2. **Agregados polimórficos e leitura direta sem `JOIN`s**: Ordens de Serviço (`ORDER#<id>`) e Faturamentos (`BILLING#<id>`) consolidam múltiplos sub-documentos sob Single-Table Design com transações atômicas (`TransactWriteItems`), evitando gargalos de I/O relacional e *locks* de schema (`ALTER TABLE`).
3. **Consultas assíncronas via GSIs dedicados**: Os pods consultam pendências de pagamento e notificação usando `pending-dispatch-index` e `dispatch-notification-index` com latência previsível.

---

## Como Executar e Validar Localmente (Terraform)

> **Pré-requisitos**: **Terraform `1.8.5`**, **AWS CLI v2**, **`kubectl`**, **Helm 3** e state prévio da VPC em `network/${ENV}.tfstate`.

```bash
cd infra

# Inicializar com state remoto no S3 (ex.: dev)
terraform init \
  -backend-config="bucket=SEU_BUCKET_TERRAFORM_STATE" \
  -backend-config="key=eks/dev.tfstate" \
  -backend-config="region=us-east-1"

terraform fmt -check -recursive
terraform validate
terraform plan -var-file="environments/dev.tfvars"
```

Após o cluster existir na AWS, conecte seu `kubectl` local:
```bash
aws eks update-kubeconfig --region us-east-1 --name repairshop-eks-dev
kubectl get nodes
kubectl get pods -n repairshop
```

> *Dica*: Para simular os manifestos Kubernetes localmente na sua estação (Docker Desktop Kubernetes ou Kind), consulte a pasta `local/` no repositório [`tech-challenge-repairshop-app`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app).

---

## Como Executar em Produção (Esteira CI/CD GitHub Actions)

Definida em [`.github/workflows/ci-cd-eks.yml`](.github/workflows/ci-cd-eks.yml) e destruição controlada em [`.github/workflows/destroy.yml`](.github/workflows/destroy.yml).

### Mapeamento de Ambientes
- `develop` -> **`dev`** (`infra/environments/dev.tfvars`)
- `homolog` -> **`hml`** (`infra/environments/hml.tfvars`)
- `main` -> **`prd`** (`infra/environments/prd.tfvars`)

### Etapas da Esteira
1. `terraform fmt -check` e `terraform validate`.
2. `terraform init` apontando para o state `eks/${ENV}.tfstate` no bucket `AWS_TERRAFORM_STATE_BUCKET`.
3. `terraform plan -var-file="environments/${ENV}.tfvars"`.
4. `terraform apply -auto-approve` em push para `develop`, `homolog` e `main`, provisionando EKS, Node Group e `metrics-server` via Helm.

> **Posição na Ordem Oficial de Provisionamento**: Executado **após `infra-network`** e **antes do deploy dos 4 microsserviços EKS** (`app-register-service`, `app-service-order-execution-service`, `app-payment-service`, `app-notification-service`).

---

## Documentação Técnica e Collection do Postman

- **Arquivos Terraform deste Repositório**: [`infra/main.tf`](infra/main.tf) | [`infra/environments/dev.tfvars`](infra/environments/dev.tfvars) | [`infra/environments/hml.tfvars`](infra/environments/hml.tfvars) | [`infra/environments/prd.tfvars`](infra/environments/prd.tfvars)
- **Manifestos K8s & Teste de Carga HPA**:
  - [Manifestos Kubernetes + Observabilidade (`app-service-order-execution-service/k8s`)](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/tree/main/k8s)
  - [Teste de Carga HPA com Locust (`locustfile.py`)](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/blob/main/docs/delivery/hpa_stress/locustfile.py)
- **ADRs, RFCs e Diagramas**:
  - [ADRs (`ADR-001` a `ADR-013`)](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/blob/main/ADRs/README.md)
  - [RFCs (`RFC-001` a `RFC-014`)](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/blob/main/RFCs/README.md)
  - [`Diagrama de Infraestrutura Cloud`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/blob/main/docs/delivery/infrastructure/repairshop-diagrama-infra-cloud.svg)
- **Postman Collections & Environments (Organização)**:
  - Collection Principal: [`Repair Shop (Tech Challenge FIAP)`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/blob/main/docs/postman/Repair%20Shop%20%28Tech%20Challenge%20FIAP%29.postman_collection.json)
  - Collection Completa: [`Tech Challenge FIAP - Completo`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/blob/main/docs/postman/Tech_Challenge_Fiap_-_Completo.postman_collection.json)
  - Environment Local: [`Local.postman_environment.json`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/blob/main/docs/postman/Local.postman_environment.json)
  - Guia do Postman: [`docs/postman/README.md`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/blob/main/docs/postman/README.md)
- **Dashboards Grafana (11 JSONs)**: [`dashboards/`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/tree/main/local/observability/grafana/dashboards)
