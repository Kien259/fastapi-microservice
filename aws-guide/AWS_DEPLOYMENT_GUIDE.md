# AWS Deployment Guide for FastAPI Microservices - South East Asia

## Table of Contents
1. [South East Asia Region Overview](#south-east-asia-region-overview)
2. [Deployment Options Overview](#deployment-options-overview)
3. [Prerequisites](#prerequisites)
4. [Option 1: Amazon EKS Deployment (Detailed)](#option-1-amazon-eks-deployment-detailed)
7. [Infrastructure as Code](#infrastructure-as-code)
8. [Database Setup](#database-setup)
9. [Networking and Security](#networking-and-security)
10. [CI/CD Pipeline](#cicd-pipeline)
11. [Configuration Management](#configuration-management)
12. [Monitoring and Logging](#monitoring-and-logging)
13. [Auto Scaling](#auto-scaling)
14. [Cost Optimization for SEA](#cost-optimization-for-sea)
15. [SEA-Specific Considerations](#sea-specific-considerations)
16. [Troubleshooting](#troubleshooting)

## South East Asia Region Overview

### Available AWS Regions in SEA
- **ap-southeast-1** (Singapore) - 🇸🇬 Most mature, all services available
- **ap-southeast-2** (Sydney, Australia) - 🇦🇺 Close alternative with all services
- **ap-southeast-3** (Jakarta, Indonesia) - 🇮🇩 Newer region, some service limitations
- **ap-southeast-4** (Melbourne, Australia) - 🇦🇺 Newest region

### Recommended Region Selection
**Primary Choice: Singapore (ap-southeast-1)**
- ✅ All AWS services available
- ✅ Lowest latency for most SEA countries
- ✅ Most mature infrastructure
- ✅ Best for compliance (many local regulations)

**Secondary Choice: Sydney (ap-southeast-2)**
- ✅ All AWS services available
- ✅ Good for Australia/New Zealand
- ❌ Higher latency for mainland SEA

### SEA Region Specific Benefits
- **Data Residency**: Comply with local data protection laws
- **Latency**: <50ms latency within SEA countries
- **Compliance**: GDPR, PDPA (Singapore), Privacy Act (Australia) compliance
- **Local Support**: AWS support teams in local time zones

## Deployment Options Overview

### Option 1: Amazon EKS (Elastic Kubernetes Service)
**Best for**: Production environments, complex orchestration needs, existing Kubernetes expertise
- **Pros**: Full Kubernetes features, easy migration from local setup, advanced networking
- **Cons**: Higher complexity, more expensive, requires Kubernetes knowledge

### Option 2: Amazon ECS with Fargate
**Best for**: Serverless container deployment, simplified management
- **Pros**: Serverless, pay-per-use, easier than EKS, AWS-native
- **Cons**: Less flexibility than Kubernetes, AWS vendor lock-in

### Option 3: AWS App Runner
**Best for**: Simple web applications, rapid deployment
- **Pros**: Fully managed, automatic scaling, simple setup
- **Cons**: Limited customization, newer service with fewer features

## Prerequisites

### AWS Account Setup
1. **AWS Account** with appropriate permissions
2. **AWS CLI** installed and configured
3. **Docker** installed locally
4. **kubectl** (for EKS) or **AWS CLI** (for ECS)

### Required AWS Services
- **ECR** (Elastic Container Registry) - Container images
- **RDS** (Relational Database Service) - PostgreSQL
- **ElastiCache** - Redis
- **VPC** - Networking
- **IAM** - Security roles and policies
- **CloudWatch** - Monitoring and logging

### Install Required Tools

**Step 1: Install AWS CLI v2**
```bash
# Download AWS CLI for Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# For macOS
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /

# Verify installation
aws --version
# Should output: aws-cli/2.x.x Python/3.x.x ...
```

**Step 2: Install kubectl (for EKS)**
```bash
# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# macOS
brew install kubectl

# Verify installation
kubectl version --client
```

**Step 3: Install eksctl (for EKS)**
```bash
# Linux
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# macOS
brew tap weaveworks/tap
brew install weaveworks/tap/eksctl

# Verify installation
eksctl version
```

**Step 4: Install Docker**
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install docker.io
sudo usermod -aG docker $USER
newgrp docker

# macOS
brew install docker
# Or download Docker Desktop from docker.com

# Verify installation
docker --version
```

**Step 5: Configure AWS CLI for Singapore Region**
```bash
aws configure
# AWS Access Key ID [None]: YOUR_ACCESS_KEY
# AWS Secret Access Key [None]: YOUR_SECRET_KEY
# Default region name [None]: ap-southeast-1
# Default output format [None]: json

# Verify configuration
aws sts get-caller-identity
aws ec2 describe-regions --region ap-southeast-1
```

**Step 6: Set Environment Variables**
```bash
# Add to your ~/.bashrc or ~/.zshrc
export AWS_DEFAULT_REGION=ap-southeast-1
export AWS_REGION=ap-southeast-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Reload shell
source ~/.bashrc  # or source ~/.zshrc
```

## Option 1: Amazon EKS Deployment (Detailed)

**⏱️ Estimated Time: 45-60 minutes**
**💰 Estimated Cost: $75-100/month for development setup**

### Step 1: Create ECR Repositories

**Why ECR?** Store your Docker images securely in AWS with integration to EKS

```bash
# Set variables for Singapore region
export AWS_REGION=ap-southeast-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create ECR repositories for your images
echo "Creating ECR repository for FastAPI users service..."
aws ecr create-repository \
    --repository-name fastapi-users \
    --region $AWS_REGION \
    --image-scanning-configuration scanOnPush=true

echo "Creating ECR repository for background worker..."
aws ecr create-repository \
    --repository-name fastapi-users-worker \
    --region $AWS_REGION \
    --image-scanning-configuration scanOnPush=true

# Verify repositories were created
aws ecr describe-repositories --region $AWS_REGION

# Get login token for Docker
echo "Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | \
    docker login --username AWS --password-stdin \
    $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

echo "✅ ECR repositories created successfully!"
echo "📍 Main app repository: $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fastapi-users"
echo "📍 Worker repository: $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fastapi-users-worker"
```

### Step 2: Build and Push Docker Images

**What we're doing**: Building optimized Docker images and pushing to ECR

```bash
# Navigate to project directory
cd /path/to/your/fastapi-microservices

# Build images with optimization for production
echo "🔨 Building FastAPI users service image..."
docker build \
    -t fastapi-users \
    -f users/docker/backend.dockerfile \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    users/

echo "🔨 Building FastAPI worker image..."
docker build \
    -t fastapi-users-worker \
    -f users/docker/worker.dockerfile \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    users/

# Tag images for ECR with Singapore region
set ECR_URI_MAIN "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fastapi-users"
set ECR_URI_WORKER "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fastapi-users-worker"
VERSION_TAG=$(date +%Y%m%d-%H%M%S)

echo "🏷️ Tagging images..."
docker tag fastapi-users:latest $ECR_URI_MAIN:latest
docker tag fastapi-users:latest $ECR_URI_MAIN:$VERSION_TAG
docker tag fastapi-users-worker:latest $ECR_URI_WORKER:latest
docker tag fastapi-users-worker:latest $ECR_URI_WORKER:$VERSION_TAG

# Push to ECR
echo "📤 Pushing main application image..."
docker push $ECR_URI_MAIN:latest
docker push $ECR_URI_MAIN:$VERSION_TAG

echo "📤 Pushing worker image..."
docker push $ECR_URI_WORKER:latest
docker push $ECR_URI_WORKER:$VERSION_TAG

# Verify images in ECR
echo "✅ Verifying images in ECR..."
aws ecr list-images --repository-name fastapi-users --region $AWS_REGION
aws ecr list-images --repository-name fastapi-users-worker --region $AWS_REGION

echo "🎉 Images successfully pushed to ECR!"
echo "📍 Main app: $ECR_URI_MAIN:$VERSION_TAG"
echo "📍 Worker: $ECR_URI_WORKER:$VERSION_TAG"
```

### Step 3: Create EKS Cluster in Singapore

**What we're doing**: Creating a managed Kubernetes cluster optimized for SEA region

**⚠️ Important**: This step takes 15-20 minutes and will incur costs (~$73/month for cluster + ~$30/month for nodes)

```bash
# Create cluster configuration file for better control
cat > eks-cluster-config.yaml << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: fastapi-microservices
  region: ap-southeast-1
  version: "1.28"

# Enable logging for better debugging
cloudWatch:
  clusterLogging:
    enableTypes: ["*"]

# VPC configuration for Singapore region
vpc:
  cidr: "10.0.0.0/16"
  hostNetwork: false
  autoAllocateIPv6: false

# Managed node groups for cost optimization
managedNodeGroups:
  - name: fastapi-nodes
    instanceType: t3.medium
    # Spread across AZs in Singapore for high availability
    availabilityZones: ["ap-southeast-1a", "ap-southeast-1b", "ap-southeast-1c"]
    minSize: 1
    maxSize: 4
    desiredCapacity: 2
    volumeSize: 20
    volumeType: gp3
    amiFamily: AmazonLinux2
    # Enable SSM for easier debugging
    iam:
      withAddonPolicies:
        ebs: true
        fsx: true
        efs: true
        cloudWatch: true
        autoScaler: true
        loadBalancer: true
    labels:
      environment: production
      workload: fastapi-microservices
    tags:
      Environment: production
      Project: fastapi-microservices
      ManagedBy: eksctl

# Add-ons for better functionality
addons:
  - name: vpc-cni
    version: latest
  - name: coredns
    version: latest
  - name: kube-proxy
    version: latest
  - name: aws-ebs-csi-driver
    version: latest

# Identity providers (for better security)
iam:
  withOIDC: true
EOF

# Create the cluster
echo "🚀 Creating EKS cluster in Singapore (this takes 15-20 minutes)..."
echo "☕ Great time for a coffee break!"

eksctl create cluster -f eks-cluster-config.yaml

# Verify cluster creation
echo "✅ Verifying cluster status..."
aws eks describe-cluster --name fastapi-microservices --region $AWS_REGION

# Update kubeconfig
echo "🔧 Updating kubeconfig..."
aws eks update-kubeconfig --region $AWS_REGION --name fastapi-microservices

# Test kubectl connectivity
echo "🔍 Testing cluster connectivity..."
kubectl get nodes
kubectl get pods -A

# Install AWS Load Balancer Controller (needed for ingress)
echo "🔧 Installing AWS Load Balancer Controller..."
eksctl utils associate-iam-oidc-provider --region=$AWS_REGION --cluster=fastapi-microservices --approve

# Create updated IAM policy for load balancer controller with all required permissions
cat > iam_policy_updated.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iam:CreateServiceLinkedRole"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "iam:AWSServiceName": "elasticloadbalancing.amazonaws.com"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeAccountAttributes",
                "ec2:DescribeAddresses",
                "ec2:DescribeAvailabilityZones",
                "ec2:DescribeInternetGateways",
                "ec2:DescribeVpcs",
                "ec2:DescribeVpcPeeringConnections",
                "ec2:DescribeSubnets",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeInstances",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DescribeTags",
                "ec2:GetCoipPoolUsage",
                "ec2:DescribeCoipPools",
                "elasticloadbalancing:DescribeLoadBalancers",
                "elasticloadbalancing:DescribeLoadBalancerAttributes",
                "elasticloadbalancing:DescribeListeners",
                "elasticloadbalancing:DescribeListenerCertificates",
                "elasticloadbalancing:DescribeListenerAttributes",
                "elasticloadbalancing:DescribeSSLPolicies",
                "elasticloadbalancing:DescribeRules",
                "elasticloadbalancing:DescribeTargetGroups",
                "elasticloadbalancing:DescribeTargetGroupAttributes",
                "elasticloadbalancing:DescribeTargetHealth",
                "elasticloadbalancing:DescribeTags",
                "elasticloadbalancing:DescribeTrustStores"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "cognito-idp:DescribeUserPoolClient",
                "acm:ListCertificates",
                "acm:DescribeCertificate",
                "iam:ListServerCertificates",
                "iam:GetServerCertificate",
                "waf-regional:GetWebACL",
                "waf-regional:GetWebACLForResource",
                "waf-regional:AssociateWebACL",
                "waf-regional:DisassociateWebACL",
                "wafv2:GetWebACL",
                "wafv2:GetWebACLForResource",
                "wafv2:AssociateWebACL",
                "wafv2:DisassociateWebACL",
                "shield:GetSubscriptionState",
                "shield:DescribeProtection",
                "shield:CreateProtection",
                "shield:DeleteProtection"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupIngress"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateSecurityGroup"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateTags"
            ],
            "Resource": "arn:aws:ec2:*:*:security-group/*",
            "Condition": {
                "StringEquals": {
                    "ec2:CreateAction": "CreateSecurityGroup"
                },
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateTags",
                "ec2:DeleteTags"
            ],
            "Resource": "arn:aws:ec2:*:*:security-group/*",
            "Condition": {
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "true",
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupIngress",
                "ec2:DeleteSecurityGroup"
            ],
            "Resource": "*",
            "Condition": {
                "Null": {
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:CreateLoadBalancer",
                "elasticloadbalancing:CreateTargetGroup"
            ],
            "Resource": "*",
            "Condition": {
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:CreateListener",
                "elasticloadbalancing:DeleteListener",
                "elasticloadbalancing:CreateRule",
                "elasticloadbalancing:DeleteRule"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:AddTags",
                "elasticloadbalancing:RemoveTags"
            ],
            "Resource": [
                "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
            ],
            "Condition": {
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "true",
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:AddTags",
                "elasticloadbalancing:RemoveTags"
            ],
            "Resource": [
                "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
                "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
                "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
                "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:ModifyLoadBalancerAttributes",
                "elasticloadbalancing:SetIpAddressType",
                "elasticloadbalancing:SetSecurityGroups",
                "elasticloadbalancing:SetSubnets",
                "elasticloadbalancing:DeleteLoadBalancer",
                "elasticloadbalancing:ModifyTargetGroup",
                "elasticloadbalancing:ModifyTargetGroupAttributes",
                "elasticloadbalancing:DeleteTargetGroup"
            ],
            "Resource": "*",
            "Condition": {
                "Null": {
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:AddTags"
            ],
            "Resource": [
                "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
            ],
            "Condition": {
                "StringEquals": {
                    "elasticloadbalancing:CreateAction": [
                        "CreateTargetGroup",
                        "CreateLoadBalancer"
                    ]
                },
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:RegisterTargets",
                "elasticloadbalancing:DeregisterTargets"
            ],
            "Resource": "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:SetWebAcl",
                "elasticloadbalancing:ModifyListener",
                "elasticloadbalancing:AddListenerCertificates",
                "elasticloadbalancing:RemoveListenerCertificates",
                "elasticloadbalancing:ModifyRule"
            ],
            "Resource": "*"
        }
    ]
}
EOF

aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy_updated.json

# Create service account
eksctl create iamserviceaccount \
  --cluster=fastapi-microservices \
  --region=$AWS_REGION \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve

2025-06-25 23:43:23 [ℹ]  1 task: { 
    2 sequential sub-tasks: { 
        create IAM role for serviceaccount "kube-system/aws-load-balancer-controller",
        create serviceaccount "kube-system/aws-load-balancer-controller",
    } }2025-06-25 23:43:23 [ℹ]  building iamserviceaccount stack "eksctl-fastapi-microservices-addon-iamserviceaccount-kube-system-aws-load-balancer-controller"
2025-06-25 23:43:24 [ℹ]  deploying stack "eksctl-fastapi-microservices-addon-iamserviceaccount-kube-system-aws-load-balancer-controller"
2025-06-25 23:43:24 [ℹ]  waiting for CloudFormation stack "eksctl-fastapi-microservices-addon-iamserviceaccount-kube-system-aws-load-balancer-controller"
2025-06-25 23:43:54 [ℹ]  waiting for CloudFormation stack "eksctl-fastapi-microservices-addon-iamserviceaccount-kube-system-aws-load-balancer-controller"
2025-06-25 23:43:54 [ℹ]  created serviceaccount "kube-system/aws-load-balancer-controller"

# Install the controller using Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=fastapi-microservices \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=$AWS_REGION \
  --set vpcId=$(aws eks describe-cluster --name fastapi-microservices --region $AWS_REGION --query "cluster.resourcesVpcConfig.vpcId" --output text)

echo "🎉 EKS cluster created successfully!"
echo "📍 Cluster name: fastapi-microservices"
echo "📍 Region: $AWS_REGION"
echo "📍 Endpoint: $(aws eks describe-cluster --name fastapi-microservices --region $AWS_REGION --query "cluster.endpoint" --output text)"

# Clean up temporary files
rm -f iam_policy_updated.json eks-cluster-config.yaml
```

### Step 4: Deploy Supporting Services

**🎯 What we're doing**: Setting up namespace, AWS RDS PostgreSQL, and AWS ElastiCache Redis

---

#### 4.1 Create Kubernetes Namespace

```bash
echo "📁 Creating Kubernetes namespace for FastAPI microservices..."

cat > namespace.yaml << EOF
apiVersion: v1
kind: Namespace
metadata:
  name: fastapi-microservices
  labels:
    name: fastapi-microservices
    environment: production
    region: sea
EOF

# Apply namespace configuration
kubectl apply -f namespace.yaml

# Verify namespace creation
kubectl get namespaces | grep fastapi-microservices
echo "✅ Namespace 'fastapi-microservices' created successfully!"
```

---

#### 4.2 Setup AWS RDS PostgreSQL Database

**🗄️ Creating managed PostgreSQL database in Singapore region**

**Step 1: Prepare VPC and Subnets**
```bash
echo "🔍 Discovering VPC and subnet configuration..."

# Get EKS VPC ID
VPC_ID=$(aws eks describe-cluster --name fastapi-microservices --region $AWS_REGION --query 'cluster.resourcesVpcConfig.vpcId' --output text)
echo "📍 Using VPC: $VPC_ID"

# Discover available subnets across different AZs
echo "🌐 Finding subnets across Singapore availability zones..."
aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
    --query 'Subnets[*].{SubnetId:SubnetId,AZ:AvailabilityZone,Type:Tags[?Key==`Name`].Value|[0]}' \
    --output table \
    --region $AWS_REGION

# Build subnet list with one subnet per AZ for Multi-AZ deployment
AVAILABLE_AZS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
    --query 'Subnets[*].AvailabilityZone' \
    --output text \
    --region $AWS_REGION | tr '\t' '\n' | sort | uniq)

echo "📍 Available AZs in VPC:"
echo "$AVAILABLE_AZS"

# Select one subnet per AZ (up to 3 for cost efficiency)
SUBNET_LIST=()
AZ_COUNT=0

for AZ in $AVAILABLE_AZS; do
    if [ $AZ_COUNT -lt 3 ]; then
        SUBNET_ID=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=$VPC_ID" "Name=availability-zone,Values=$AZ" "Name=state,Values=available" \
            --query 'Subnets[0].SubnetId' \
            --output text \
            --region $AWS_REGION)
        
        if [ "$SUBNET_ID" != "None" ] && [ "$SUBNET_ID" != "" ]; then
            SUBNET_LIST+=("$SUBNET_ID")
            echo "  ✅ Selected subnet $SUBNET_ID from $AZ"
            AZ_COUNT=$((AZ_COUNT + 1))
        fi
    fi
done

echo "🎉 Selected $AZ_COUNT subnets for Multi-AZ deployment"
```

**Step 2: Create RDS Subnet Group**
```bash
echo "🔧 Setting up RDS subnet group..."

# Clean up any existing subnet group
aws rds delete-db-subnet-group \
    --db-subnet-group-name fastapi-db-subnet-group \
    --region $AWS_REGION 2>/dev/null || echo "  ℹ️  No existing subnet group to clean up"

sleep 3

# Create new subnet group with Multi-AZ support
aws rds create-db-subnet-group \
    --db-subnet-group-name fastapi-db-subnet-group \
    --db-subnet-group-description "Multi-AZ subnet group for FastAPI PostgreSQL in Singapore" \
    --subnet-ids "${SUBNET_LIST[@]}" \
    --region $AWS_REGION

echo "✅ RDS subnet group created with Multi-AZ support!"
```

**Step 3: Configure Security Groups**
```bash
echo "🔒 Creating security group for PostgreSQL..."

# Create dedicated security group for RDS
RDS_SG_ID=$(aws ec2 create-security-group \
    --group-name fastapi-rds-sg \
    --description "Security group for FastAPI RDS PostgreSQL" \
    --vpc-id $VPC_ID \
    --region $AWS_REGION \
    --query 'GroupId' --output text)

echo "📍 Created security group: $RDS_SG_ID"

# Get EKS cluster security group
EKS_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=eks-cluster-sg-fastapi-microservices-*" \
    --query 'SecurityGroups[0].GroupId' \
    --output text \
    --region $AWS_REGION)

# Allow PostgreSQL traffic from EKS nodes (port 5432)
aws ec2 authorize-security-group-ingress \
    --group-id $RDS_SG_ID \
    --protocol tcp \
    --port 5432 \
    --source-group $EKS_SG_ID \
    --region $AWS_REGION

echo "✅ Security group configured - EKS nodes can access PostgreSQL"
```

**Step 4: Create RDS PostgreSQL Instance**
```bash
echo "🚀 Creating RDS PostgreSQL instance (this takes 5-10 minutes)..."

# Generate secure password
RDS_PASSWORD=$(openssl rand -base64 32)
echo "🔐 Generated secure database password"

# Create RDS instance with production-ready configuration
aws rds create-db-instance \
    --db-instance-identifier fastapi-postgres \
    --db-instance-class db.t3.micro \
    --engine postgres \
    --master-username postgres \
    --master-user-password "$RDS_PASSWORD" \
    --allocated-storage 20 \
    --vpc-security-group-ids $RDS_SG_ID \
    --db-subnet-group-name fastapi-db-subnet-group \
    --backup-retention-period 7 \
    --storage-encrypted \
    --region $AWS_REGION \
    --no-publicly-accessible

echo "⏳ Waiting for RDS instance to become available..."
echo "☕ Perfect time for a coffee break! (5-10 minutes)"

# Wait for RDS to be available
aws rds wait db-instance-available --db-instance-identifier fastapi-postgres --region $AWS_REGION

# Get RDS endpoint
RDS_ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier fastapi-postgres \
    --region $AWS_REGION \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text)

echo "🎉 RDS PostgreSQL instance created successfully!"
echo "📍 Endpoint: $RDS_ENDPOINT"
echo "📍 Multi-AZ: Enabled for high availability"
echo "📍 Encryption: Enabled"
echo "📍 Backup retention: 7 days"
```

**Step 5: Create Kubernetes Service for PostgreSQL**
```bash
echo "🔗 Creating Kubernetes service for PostgreSQL..."

cat > postgres-aws.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: postgres-service
  namespace: fastapi-microservices
  labels:
    app: postgres
    type: external
spec:
  type: ExternalName
  externalName: $RDS_ENDPOINT
  ports:
  - port: 5432
    targetPort: 5432
    protocol: TCP
    name: postgresql
EOF

kubectl apply -f postgres-aws.yaml
echo "✅ PostgreSQL service configured to use RDS endpoint: $RDS_ENDPOINT"
```

---

#### 4.3 Setup AWS ElastiCache Redis

**📝 Creating managed Redis cluster for caching and background jobs**

**Step 1: Create ElastiCache Subnet Group**
```bash
echo "🔧 Setting up ElastiCache subnet group..."

aws elasticache create-cache-subnet-group \
    --cache-subnet-group-name fastapi-redis-subnet-group \
    --cache-subnet-group-description "Subnet group for FastAPI Redis" \
    --subnet-ids "${SUBNET_LIST[@]}" \
    --region $AWS_REGION

echo "✅ ElastiCache subnet group created with Multi-AZ support!"
```

**Step 2: Configure Redis Security Group**
```bash
echo "🔒 Creating security group for Redis..."

# Create dedicated security group for ElastiCache
REDIS_SG_ID=$(aws ec2 create-security-group \
    --group-name fastapi-redis-sg \
    --description "Security group for FastAPI ElastiCache Redis" \
    --vpc-id $VPC_ID \
    --region $AWS_REGION \
    --query 'GroupId' --output text)

echo "📍 Created security group: $REDIS_SG_ID"

# Allow Redis traffic from EKS nodes (port 6379)
aws ec2 authorize-security-group-ingress \
    --group-id $REDIS_SG_ID \
    --protocol tcp \
    --port 6379 \
    --source-group $EKS_SG_ID \
    --region $AWS_REGION

echo "✅ Security group configured - EKS nodes can access Redis"
```

**Step 3: Create ElastiCache Redis Cluster**
```bash
echo "🚀 Creating ElastiCache Redis cluster..."

aws elasticache create-cache-cluster \
    --cache-cluster-id fastapi-redis \
    --cache-node-type cache.t3.micro \
    --engine redis \
    --num-cache-nodes 1 \
    --cache-subnet-group-name fastapi-redis-subnet-group \
    --security-group-ids $REDIS_SG_ID \
    --region $AWS_REGION \
    --port 6379

echo "⏳ Waiting for Redis cluster to become available..."
aws elasticache wait cache-cluster-available --cache-cluster-id fastapi-redis --region $AWS_REGION

# Get Redis endpoint
REDIS_ENDPOINT=$(aws elasticache describe-cache-clusters \
    --cache-cluster-id fastapi-redis \
    --show-cache-node-info \
    --region $AWS_REGION \
    --query 'CacheClusters[0].CacheNodes[0].Endpoint.Address' \
    --output text)

echo "✅ ElastiCache Redis created: $REDIS_ENDPOINT"

**Step 4: Create Kubernetes Service for Redis**
```bash
echo "🔗 Creating Kubernetes service for Redis..."

cat > redis-aws.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: redis-service
  namespace: fastapi-microservices
  labels:
    app: redis
    type: external
spec:
  type: ExternalName
  externalName: $REDIS_ENDPOINT
  ports:
  - port: 6379
    targetPort: 6379
    protocol: TCP
    name: redis
EOF

kubectl apply -f redis-aws.yaml
echo "✅ Redis service configured to use ElastiCache endpoint: $REDIS_ENDPOINT"
```

---

#### 4.4 Verify Supporting Services

```bash
echo "🔍 Verifying all supporting services..."

echo ""
echo "📋 Kubernetes Services Status:"
kubectl get services -n fastapi-microservices -o wide

echo ""
echo "📊 AWS Resources Summary:"
echo "════════════════════════════════════════════════════════════"
echo "🗄️  PostgreSQL RDS:"
echo "    • Instance ID: fastapi-postgres"
echo "    • Endpoint: $RDS_ENDPOINT"
echo "    • Multi-AZ: ✅ Enabled"
echo "    • Encryption: ✅ Enabled"
echo "    • Backup: ✅ 7 days retention"
echo ""
echo "📝 Redis ElastiCache:"
echo "    • Cluster ID: fastapi-redis"
echo "    • Endpoint: $REDIS_ENDPOINT"
echo "    • Engine: Redis 7.0"
echo "    • Node Type: cache.t3.micro"
echo ""
echo "🔒 Security Groups:"
echo "    • RDS Security Group: $RDS_SG_ID"
echo "    • Redis Security Group: $REDIS_SG_ID"
echo "    • Access: ✅ EKS nodes only"
echo ""
echo "🌐 Network Configuration:"
echo "    • VPC ID: $VPC_ID"
echo "    • Subnets: $AZ_COUNT availability zones"
echo "    • Region: $AWS_REGION (Singapore)"
echo "════════════════════════════════════════════════════════════"

echo ""
echo "✅ All supporting services deployed successfully!"
echo "🎯 Ready to deploy FastAPI application in Step 5"

# Store endpoints for next steps
echo "📝 Storing endpoints for application deployment..."
echo "export RDS_ENDPOINT='$RDS_ENDPOINT'" >> ~/.bashrc
echo "export REDIS_ENDPOINT='$REDIS_ENDPOINT'" >> ~/.bashrc
echo "export RDS_PASSWORD='$RDS_PASSWORD'" >> ~/.bashrc

echo ""
echo "⚠️  IMPORTANT: Store your database password securely!"
echo "🔐 Database password: $RDS_PASSWORD"
echo ""
```

### Step 5: Deploy FastAPI Application

**What we're doing**: Deploying the main FastAPI application with secrets management

```bash
# First, create secrets for database and application
echo "🔐 Creating Kubernetes secrets..."

# Store the database password in AWS Secrets Manager
aws secretsmanager create-secret \
    --name "fastapi/postgres-password" \
    --description "PostgreSQL password for FastAPI app" \
    --secret-string "$RDS_PASSWORD" \
    --region $AWS_REGION 2>/dev/null || echo "Secret already exists"

# Create JWT secret
JWT_SECRET=$(openssl rand -base64 32)
aws secretsmanager create-secret \
    --name "fastapi/jwt-secret" \
    --description "JWT secret key for FastAPI app" \
    --secret-string "$JWT_SECRET" \
    --region $AWS_REGION 2>/dev/null || echo "Secret already exists"

# Create Kubernetes secrets
kubectl create secret generic postgres-credentials \
    --from-literal=password="$RDS_PASSWORD" \
    --namespace fastapi-microservices 2>/dev/null || echo "Secret already exists"

kubectl create secret generic jwt-secret \
    --from-literal=secret="$JWT_SECRET" \
    --namespace fastapi-microservices 2>/dev/null || echo "Secret already exists"

# Create application configuration
kubectl create configmap fastapi-config \
    --from-literal=PROJECT_NAME="FastAPI Users - Singapore" \
    --from-literal=ACCESS_TOKEN_EXPIRE_MINUTES="30" \
    --from-literal=FIRST_USER_EMAIL="admin@admin.com" \
    --from-literal=POSTGRES_DB="users_db" \
    --from-literal=POSTGRES_USER="postgres" \
    --from-literal=REDIS_PORT="6379" \
    --namespace fastapi-microservices 2>/dev/null || echo "ConfigMap already exists"

# Get the actual endpoints
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier fastapi-postgres --region $AWS_REGION --query 'DBInstances[0].Endpoint.Address' --output text)
REDIS_ENDPOINT=$(aws elasticache describe-cache-clusters --cache-cluster-id fastapi-redis --show-cache-node-info --region $AWS_REGION --query 'CacheClusters[0].CacheNodes[0].Endpoint.Address' --output text)

echo "📍 Using RDS endpoint: $RDS_ENDPOINT"
echo "📍 Using Redis endpoint: $REDIS_ENDPOINT"

# Create the FastAPI application deployment
cat > users-deployment-aws.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: users-deployment
  namespace: fastapi-microservices
  labels:
    app: users
    version: v1
    environment: production
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
  selector:
    matchLabels:
      app: users
  template:
    metadata:
      labels:
        app: users
        version: v1
    spec:
      containers:
      - name: users
        image: $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fastapi-users:latest
        ports:
        - containerPort: 80
          name: http
        env:
        - name: POSTGRES_HOST
          value: "$RDS_ENDPOINT"
        - name: REDIS_HOST
          value: "$REDIS_ENDPOINT"
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: password
        - name: SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: jwt-secret
              key: secret
        - name: FIRST_USER_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: password
        envFrom:
        - configMapRef:
            name: fastapi-config
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /api/health/
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /api/health/
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        startupProbe:
          httpGet:
            path: /api/health/
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 30
---
apiVersion: v1
kind: Service
metadata:
  name: users-service
  namespace: fastapi-microservices
  labels:
    app: users
spec:
  selector:
    app: users
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    name: http
  type: ClusterIP  # We'll use ALB Ingress instead of LoadBalancer
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: users-ingress
  namespace: fastapi-microservices
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/healthcheck-path: /api/health/
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: '15'
    alb.ingress.kubernetes.io/healthcheck-timeout-seconds: '5'
    alb.ingress.kubernetes.io/success-codes: '200'
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
spec:
  ingressClassName: alb
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: users-service
            port:
              number: 80
EOF

# Apply the deployment
echo "🚀 Deploying FastAPI application..."
kubectl apply -f users-deployment-aws.yaml

# IMPORTANT: Before the application can work, we need to create the database and run migrations
echo "🗄️ Setting up database..."

# Step 1: Create the users_db database
echo "📋 Creating users_db database..."
cat > create-database-job.yaml << EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: create-database-job
  namespace: fastapi-microservices
  labels:
    app: database-setup
spec:
  template:
    metadata:
      labels:
        app: database-setup
    spec:
      restartPolicy: Never
      containers:
      - name: db-setup
        image: postgres:14
        command: ["sh", "-c"]
        args:
        - |
          echo "🗄️ Setting up database..."
          echo "Connecting to PostgreSQL server..."
          
          # First, check if the database exists
          DB_EXISTS=\$(PGPASSWORD="\$POSTGRES_PASSWORD" psql -h "\$POSTGRES_HOST" -U postgres -lqt | cut -d \\| -f 1 | grep -w users_db | wc -l)
          
          if [ "\$DB_EXISTS" -eq 0 ]; then
            echo "Creating users_db database..."
            PGPASSWORD="\$POSTGRES_PASSWORD" psql -h "\$POSTGRES_HOST" -U postgres -c "CREATE DATABASE users_db;"
            echo "✅ Database users_db created successfully!"
          else
            echo "✅ Database users_db already exists!"
          fi
          
          # Verify database exists
          echo "📋 Listing all databases:"
          PGPASSWORD="\$POSTGRES_PASSWORD" psql -h "\$POSTGRES_HOST" -U postgres -l
          
          echo "✅ Database setup completed!"
        env:
        - name: POSTGRES_HOST
          value: "$RDS_ENDPOINT"
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: password
        - name: POSTGRES_USER
          value: "postgres"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
  backoffLimit: 3
  ttlSecondsAfterFinished: 300
EOF

kubectl apply -f create-database-job.yaml
kubectl wait --for=condition=complete --timeout=180s job/create-database-job -n fastapi-microservices
kubectl logs job/create-database-job -n fastapi-microservices

# Step 2: Run database migrations
echo "🔄 Running database migrations..."
cat > db-migration-job.yaml << EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration-job
  namespace: fastapi-microservices
  labels:
    app: db-migration
spec:
  template:
    metadata:
      labels:
        app: db-migration
    spec:
      restartPolicy: Never
      containers:
      - name: migration
        image: $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fastapi-users:latest
        command: ["sh", "-c"]
        args:
        - |
          echo "🗄️ Starting database migration..."
          cd /app
          echo "Running Alembic migrations..."
          alembic upgrade head
          echo "✅ Database migration completed successfully!"
        env:
        - name: POSTGRES_HOST
          value: "$RDS_ENDPOINT"
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: password
        - name: POSTGRES_DB
          value: "users_db"
        - name: POSTGRES_USER
          value: "postgres"
        - name: SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: jwt-secret
              key: secret
        - name: PROJECT_NAME
          value: "FastAPI Users - Singapore"
        - name: ACCESS_TOKEN_EXPIRE_MINUTES
          value: "30"
        - name: FIRST_USER_EMAIL
          value: "admin@admin.com"
        - name: FIRST_USER_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: password
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
  backoffLimit: 3
  ttlSecondsAfterFinished: 300
EOF

kubectl apply -f db-migration-job.yaml
kubectl wait --for=condition=complete --timeout=300s job/db-migration-job -n fastapi-microservices
kubectl logs job/db-migration-job -n fastapi-microservices

# Clean up migration jobs
kubectl delete job create-database-job db-migration-job -n fastapi-microservices 2>/dev/null || true
rm -f create-database-job.yaml db-migration-job.yaml

# Wait for deployment to be ready
echo "⏳ Waiting for deployment to be ready..."
kubectl wait --for=condition=available --timeout=600s deployment/users-deployment -n fastapi-microservices

# Restart application to ensure it connects to the newly setup database
echo "🔄 Restarting application to connect to database..."
kubectl rollout restart deployment/users-deployment -n fastapi-microservices
kubectl rollout status deployment/users-deployment -n fastapi-microservices

# Check deployment status
kubectl get deployments -n fastapi-microservices
kubectl get pods -n fastapi-microservices
kubectl get ingress -n fastapi-microservices

# Get the load balancer URL
echo "🔍 Getting load balancer URL..."
sleep 60  # Wait for ALB to be provisioned

ALB_URL=$(kubectl get ingress users-ingress -n fastapi-microservices -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "🌐 Your FastAPI application is available at: http://$ALB_URL"
echo "📚 API Documentation: http://$ALB_URL/docs"
echo "🔍 Health Check: http://$ALB_URL/api/health/"

# Test the deployment
echo "🧪 Testing deployment..."
if [ "$ALB_URL" != "" ]; then
    curl -f "http://$ALB_URL/api/health/" && echo "✅ Health check passed!"
else
    echo "⏳ ALB still provisioning, check again in a few minutes"
fi
```

### Step 6: Deploy Background Worker

**What we're doing**: Deploying ARQ background workers for async task processing

```bash
# Create the background worker deployment
echo "👷 Creating background worker deployment..."

cat > users-worker-deployment-aws.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: users-worker-deployment
  namespace: fastapi-microservices
  labels:
    app: users-worker
    version: v1
    environment: production
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0  # Keep at least one worker running
  selector:
    matchLabels:
      app: users-worker
  template:
    metadata:
      labels:
        app: users-worker
        version: v1
    spec:
      containers:
      - name: users-worker
        image: $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fastapi-users-worker:latest
        env:
        - name: REDIS_HOST
          value: "$REDIS_ENDPOINT"
        - name: POSTGRES_HOST
          value: "$RDS_ENDPOINT"
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: password
        - name: SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: jwt-secret
              key: secret
        envFrom:
        - configMapRef:
            name: fastapi-config
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "250m"
        # Worker health check - ARQ workers don't have HTTP endpoints
        # We'll use a command that checks if the worker process is running
        livenessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - "ps aux | grep -v grep | grep worker.py || exit 1"
          initialDelaySeconds: 30
          periodSeconds: 30
          timeoutSeconds: 5
          failureThreshold: 3
        startupProbe:
          exec:
            command:
            - /bin/sh  
            - -c
            - "ps aux | grep -v grep | grep worker.py || exit 1"
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 30
---
# Optional: HorizontalPodAutoscaler for workers based on Redis queue length
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: users-worker-hpa
  namespace: fastapi-microservices
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: users-worker-deployment
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300  # Wait 5 minutes before scaling down
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 60   # Quick scale up for task bursts
      policies:
      - type: Percent
        value: 100
        periodSeconds: 60
EOF

# Apply the worker deployment
echo "🚀 Deploying background workers..."
kubectl apply -f users-worker-deployment-aws.yaml

# Wait for worker deployment to be ready
echo "⏳ Waiting for worker deployment to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/users-worker-deployment -n fastapi-microservices

# Check worker deployment status
echo "📊 Checking worker deployment status..."
kubectl get deployments -n fastapi-microservices
kubectl get pods -l app=users-worker -n fastapi-microservices

# Check worker logs to ensure they're connecting to Redis
echo "📋 Checking worker logs..."
kubectl logs -l app=users-worker -n fastapi-microservices --tail=20

# Test that workers can connect to Redis
echo "🧪 Testing Redis connectivity from workers..."
kubectl exec -it deployment/users-worker-deployment -n fastapi-microservices -- redis-cli -h $REDIS_ENDPOINT ping || echo "⚠️ Redis connection test failed"

echo "✅ Background workers deployed successfully!"
echo "👷 Worker replicas: $(kubectl get deployment users-worker-deployment -n fastapi-microservices -o jsonpath='{.status.replicas}')"
echo "🟢 Ready replicas: $(kubectl get deployment users-worker-deployment -n fastapi-microservices -o jsonpath='{.status.readyReplicas}')"
```

**Step 8: Verify Complete Deployment**

```bash
# Final verification of all components
echo "🔍 Verifying complete deployment..."

echo "📊 Deployment Status:"
kubectl get all -n fastapi-microservices

echo ""
echo "🔍 Pod Status:"
kubectl get pods -n fastapi-microservices -o wide

echo ""
echo "🌐 Services and Ingress:"
kubectl get svc,ingress -n fastapi-microservices

echo ""
echo "🔐 Secrets and ConfigMaps:"
kubectl get secrets,configmaps -n fastapi-microservices

echo ""
echo "📈 Resource Usage:"
kubectl top pods -n fastapi-microservices 2>/dev/null || echo "Metrics server not available"

echo ""
echo "🎉 Deployment Summary:"
echo "════════════════════════"

ALB_URL=$(kubectl get ingress users-ingress -n fastapi-microservices -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Pending...")
REPLICAS=$(kubectl get deployment users-deployment -n fastapi-microservices -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
WORKERS=$(kubectl get deployment users-worker-deployment -n fastapi-microservices -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")

echo "🌍 Region: $AWS_REGION (Singapore)"
echo "🌐 Application URL: http://$ALB_URL"
echo "📚 API Docs: http://$ALB_URL/docs"
echo "🔍 Health Check: http://$ALB_URL/api/health/"
echo "🚀 API Replicas: $REPLICAS"
echo "👷 Worker Replicas: $WORKERS"
echo "🗄️ Database: RDS PostgreSQL ($RDS_ENDPOINT)"
echo "📝 Cache: ElastiCache Redis ($REDIS_ENDPOINT)"

echo ""
echo "🧪 Testing endpoints..."
if [ "$ALB_URL" != "Pending..." ]; then
    echo "Testing health endpoint..."
    curl -s "http://$ALB_URL/api/health/" | jq . 2>/dev/null || curl -s "http://$ALB_URL/api/health/"
    
    echo ""
    echo "Testing API documentation..."
    curl -s -o /dev/null -w "API Docs Status: %{http_code}\n" "http://$ALB_URL/docs"
else
    echo "⏳ Load balancer still provisioning. Check again in a few minutes."
fi

echo ""
echo "✅ FastAPI Microservices successfully deployed to AWS Singapore!"
echo "🎯 Ready for production traffic!"

# Note about HTTPS configuration
echo ""
echo "📝 To enable HTTPS (recommended for production):"
echo "1. Request an SSL certificate through AWS Certificate Manager (ACM)"
echo "2. Update the ingress annotation to include HTTPS listener:"
echo "   alb.ingress.kubernetes.io/listen-ports: '[{\"HTTP\": 80}, {\"HTTPS\": 443}]'"
echo "3. Add certificate ARN annotation:"
echo "   alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:region:account:certificate/cert-id"
echo "4. Add SSL redirect annotation:"
echo "   alb.ingress.kubernetes.io/ssl-redirect: '443'"
```

### Summary: What You Can Do with the YAML Files

The YAML files from Steps 4-6 are Kubernetes manifests that define your application infrastructure. Here's what each one does and how to use them:

**📁 YAML Files Created:**
- `namespace.yaml` - Creates isolated environment for your app
- `postgres-aws.yaml` - Connects to AWS RDS PostgreSQL
- `redis-aws.yaml` - Connects to AWS ElastiCache Redis  
- `users-deployment-aws.yaml` - Deploys your FastAPI application with ingress
- `users-worker-deployment-aws.yaml` - Deploys background workers with auto-scaling
- `db-migration-job.yaml` - Runs database migrations once

**🔧 Common Operations:**

**Apply all configurations:**
```bash
# Deploy everything in sequence
kubectl apply -f namespace.yaml
kubectl apply -f postgres-aws.yaml
kubectl apply -f redis-aws.yaml
kubectl apply -f users-deployment-aws.yaml
kubectl apply -f users-worker-deployment-aws.yaml
kubectl apply -f db-migration-job.yaml
```

**Update deployments (after code changes):**
```bash
# Update image tags and re-apply
kubectl set image deployment/users-deployment users=$ECR_URI_MAIN:new-version -n fastapi-microservices
kubectl set image deployment/users-worker-deployment users-worker=$ECR_URI_WORKER:new-version -n fastapi-microservices
```

**Scale applications:**
```bash
# Scale API servers
kubectl scale deployment users-deployment --replicas=5 -n fastapi-microservices

# Scale background workers
kubectl scale deployment users-worker-deployment --replicas=3 -n fastapi-microservices
```

**Monitor and debug:**
```bash
# Check status
kubectl get pods -n fastapi-microservices
kubectl describe deployment users-deployment -n fastapi-microservices

# View logs
kubectl logs -f deployment/users-deployment -n fastapi-microservices
kubectl logs -l app=users-worker -n fastapi-microservices
```

**Clean up:**
```bash
# Delete everything
kubectl delete namespace fastapi-microservices
# OR delete individual components
kubectl delete -f users-deployment-aws.yaml
kubectl delete -f users-worker-deployment-aws.yaml
```

**🎯 Next Steps After Deployment:**
1. Set up monitoring with CloudWatch
2. Configure auto-scaling based on metrics
3. Add HTTPS/SSL certificates
4. Set up CI/CD pipelines
5. Configure backup strategies

---
## Infrastructure as Code

### Terraform Configuration
```hcl
# main.tf
provider "aws" {
  region = var.aws_region
}

# VPC
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  
  name = "fastapi-microservices-vpc"
  cidr = "10.0.0.0/16"
  
  azs             = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  
  enable_nat_gateway = true
  enable_vpn_gateway = true
  
  tags = {
    Environment = var.environment
  }
}

# RDS PostgreSQL
resource "aws_db_instance" "postgres" {
  identifier     = "fastapi-postgres"
  engine         = "postgres"
  engine_version = "14.9"
  instance_class = "db.t3.micro"
  
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp2"
  storage_encrypted     = true
  
  db_name  = "users_db"
  username = "postgres"
  password = var.db_password
  
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name
  
  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  skip_final_snapshot = true
  deletion_protection = false
  
  tags = {
    Name = "fastapi-postgres"
  }
}

# ElastiCache Redis
resource "aws_elasticache_subnet_group" "main" {
  name       = "fastapi-cache-subnet"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "fastapi-redis"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  
  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]
  
  tags = {
    Name = "fastapi-redis"
  }
}

# EKS Cluster
module "eks" {
  source = "terraform-aws-modules/eks/aws"
  
  cluster_name    = "fastapi-microservices"
  cluster_version = "1.28"
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  
  eks_managed_node_groups = {
    main = {
      desired_size = 2
      max_size     = 4
      min_size     = 1
      
      instance_types = ["t3.medium"]
      
      k8s_labels = {
        Environment = var.environment
      }
    }
  }
  
  tags = {
    Environment = var.environment
  }
}
```

### Variables
```hcl
# variables.tf
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}
```

## Database Setup

### 1. Amazon RDS PostgreSQL
```bash
# Create RDS instance
aws rds create-db-instance \
    --db-instance-identifier fastapi-postgres \
    --db-instance-class db.t3.micro \
    --engine postgres \
    --engine-version 14.9 \
    --master-username postgres \
    --master-user-password YourSecurePassword \
    --allocated-storage 20 \
    --vpc-security-group-ids sg-12345678 \
    --db-subnet-group-name fastapi-db-subnet-group \
    --backup-retention-period 7 \
    --storage-encrypted
```

### 2. Database Migration
```yaml
# migration-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
  namespace: fastapi-microservices
spec:
  template:
    spec:
      containers:
      - name: migration
        image: <account-id>.dkr.ecr.us-west-2.amazonaws.com/fastapi-users:latest
        command: ["alembic", "upgrade", "head"]
        env:
        - name: POSTGRES_HOST
          value: "your-rds-endpoint.amazonaws.com"
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: password
      restartPolicy: Never
  backoffLimit: 4
```

## Networking and Security

### 1. Security Groups
```bash
# Create security group for EKS nodes
aws ec2 create-security-group \
    --group-name fastapi-eks-nodes \
    --description "Security group for FastAPI EKS nodes"

# Allow HTTP traffic
aws ec2 authorize-security-group-ingress \
    --group-id sg-12345678 \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0

# Create security group for RDS
aws ec2 create-security-group \
    --group-name fastapi-rds \
    --description "Security group for FastAPI RDS"

# Allow PostgreSQL from EKS nodes
aws ec2 authorize-security-group-ingress \
    --group-id sg-87654321 \
    --protocol tcp \
    --port 5432 \
    --source-group sg-12345678
```

### 2. Application Load Balancer
```yaml
# alb-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fastapi-ingress
  namespace: fastapi-microservices
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-west-2:123456789012:certificate/abc123
spec:
  rules:
  - host: api.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: users-service
            port:
              number: 80
```

### 3. IAM Roles and Policies
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": [
        "arn:aws:secretsmanager:us-west-2:*:secret:fastapi/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}
```

## CI/CD Pipeline

### GitHub Actions Workflow
```yaml
# .github/workflows/deploy.yml
name: Deploy to AWS

on:
  push:
    branches: [main]

env:
  AWS_REGION: us-west-2
  ECR_REPOSITORY: fastapi-users
  EKS_CLUSTER_NAME: fastapi-microservices

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
    - name: Checkout
      uses: actions/checkout@v3
    
    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v2
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ${{ env.AWS_REGION }}
    
    - name: Login to Amazon ECR
      id: login-ecr
      uses: aws-actions/amazon-ecr-login@v1
    
    - name: Build, tag, and push image to Amazon ECR
      env:
        ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
        IMAGE_TAG: ${{ github.sha }}
      run: |
        # Build Docker images
        docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG -f users/docker/backend.dockerfile users/
        docker build -t $ECR_REGISTRY/fastapi-users-worker:$IMAGE_TAG -f users/docker/worker.dockerfile users/
        
        # Push to ECR
        docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
        docker push $ECR_REGISTRY/fastapi-users-worker:$IMAGE_TAG
        
        # Tag as latest
        docker tag $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG $ECR_REGISTRY/$ECR_REPOSITORY:latest
        docker tag $ECR_REGISTRY/fastapi-users-worker:$IMAGE_TAG $ECR_REGISTRY/fastapi-users-worker:latest
        docker push $ECR_REGISTRY/$ECR_REPOSITORY:latest
        docker push $ECR_REGISTRY/fastapi-users-worker:latest
    
    - name: Update kubeconfig
      run: |
        aws eks update-kubeconfig --name $EKS_CLUSTER_NAME --region $AWS_REGION
    
    - name: Deploy to EKS
      env:
        ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
        IMAGE_TAG: ${{ github.sha }}
      run: |
        # Update deployment with new image
        kubectl set image deployment/users-deployment users=$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG -n fastapi-microservices
        kubectl set image deployment/users-worker-deployment users-worker=$ECR_REGISTRY/fastapi-users-worker:$IMAGE_TAG -n fastapi-microservices
        
        # Wait for rollout
        kubectl rollout status deployment/users-deployment -n fastapi-microservices
        kubectl rollout status deployment/users-worker-deployment -n fastapi-microservices
```

## Configuration Management

### 1. AWS Secrets Manager
```bash
# Create secret for database password
aws secretsmanager create-secret \
    --name "fastapi/postgres-password" \
    --description "PostgreSQL password for FastAPI app" \
    --secret-string "YourSecurePassword"

# Create secret for JWT secret key
aws secretsmanager create-secret \
    --name "fastapi/jwt-secret" \
    --description "JWT secret key for FastAPI app" \
    --secret-string "YourJWTSecretKey"
```

### 2. Kubernetes Secrets from AWS Secrets Manager
```yaml
# external-secrets.yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: fastapi-microservices
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-west-2
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: postgres-credentials
  namespace: fastapi-microservices
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: postgres-credentials
    creationPolicy: Owner
  data:
  - secretKey: password
    remoteRef:
      key: fastapi/postgres-password
```

## Monitoring and Logging

### 1. CloudWatch Container Insights
```bash
# Install CloudWatch agent
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cloudwatch-namespace.yaml

kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-serviceaccount.yaml

kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-configmap.yaml

kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-daemonset.yaml
```

### 2. Application Metrics
```python
# Add to your FastAPI app
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all
from aws_xray_sdk.fastapi import XRayMiddleware

# Patch AWS SDK calls
patch_all()

# Add X-Ray middleware
app.add_middleware(XRayMiddleware, tracing_name="fastapi-users")

@xray_recorder.capture('health_check')
@app.get("/api/health/")
async def health_check():
    return {"status": "healthy"}
```

### 3. Custom Metrics
```python
import boto3

cloudwatch = boto3.client('cloudwatch')

def put_custom_metric(metric_name, value, unit='Count'):
    cloudwatch.put_metric_data(
        Namespace='FastAPI/Users',
        MetricData=[
            {
                'MetricName': metric_name,
                'Value': value,
                'Unit': unit,
                'Dimensions': [
                    {
                        'Name': 'Environment',
                        'Value': 'production'
                    }
                ]
            }
        ]
    )

# Usage in your endpoints
@app.post("/api/v1/users/")
async def create_user(user_in: UserCreate):
    # Your logic here
    put_custom_metric('UserCreated', 1)
    return created_user
```

## Auto Scaling

### 1. Horizontal Pod Autoscaler (HPA)
```yaml
# hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: users-hpa
  namespace: fastapi-microservices
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: users-deployment
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

### 2. Cluster Autoscaler
```yaml
# cluster-autoscaler.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-autoscaler
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cluster-autoscaler
  template:
    metadata:
      labels:
        app: cluster-autoscaler
    spec:
      containers:
      - image: k8s.gcr.io/autoscaling/cluster-autoscaler:v1.21.0
        name: cluster-autoscaler
        command:
        - ./cluster-autoscaler
        - --v=4
        - --stderrthreshold=info
        - --cloud-provider=aws
        - --skip-nodes-with-local-storage=false
        - --expander=least-waste
        - --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/fastapi-microservices
        env:
        - name: AWS_REGION
          value: us-west-2
```

## Cost Optimization for SEA

### SEA Region Cost Considerations
**Singapore (ap-southeast-1) vs US regions:**
- **EKS**: ~$73/month (same as US)
- **EC2 instances**: ~10-15% higher than US East
- **RDS**: ~15-20% higher than US East
- **Data transfer**: Reduced costs for SEA users
- **Overall**: Higher infrastructure costs but lower latency costs

### 1. Spot Instances for Development
```yaml
# spot-nodegroup.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: fastapi-microservices
  region: us-west-2

managedNodeGroups:
- name: spot-nodes
  instanceTypes: ["t3.medium", "t3a.medium", "t2.medium"]
  spot: true
  minSize: 1
  maxSize: 10
  desiredCapacity: 2
  volumeSize: 20
  ssh:
    allow: true
  labels: {role: worker}
  tags:
    nodegroup-role: worker
    nodegroup-type: spot
```

### 2. Resource Limits
```yaml
# Update deployments with resource limits
resources:
  requests:
    memory: "256Mi"
    cpu: "250m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

### 3. Reserved Instances for Production
```bash
# Check available reserved instance offerings in Singapore
aws rds describe-reserved-db-instances-offerings \
    --region ap-southeast-1 \
    --db-instance-class db.t3.micro \
    --product-description postgresql

# Purchase RDS Reserved Instance (1-year term saves ~30%)
aws rds purchase-reserved-db-instances-offering \
    --reserved-db-instances-offering-id YOUR-OFFERING-ID \
    --reserved-db-instance-id fastapi-postgres-reserved \
    --region ap-southeast-1

# Purchase EC2 Reserved Instances for EKS nodes
aws ec2 describe-reserved-instances-offerings \
    --instance-type t3.medium \
    --region ap-southeast-1

# Consider Savings Plans for compute workloads (more flexible)
```

### 4. SEA-Specific Cost Optimization
```bash
# Monitor costs by region
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=REGION

# Set up billing alerts for SEA region
aws budgets create-budget \
    --account-id $AWS_ACCOUNT_ID \
    --budget '{
        "BudgetName": "FastAPI-SEA-Monthly",
        "BudgetLimit": {
            "Amount": "200",
            "Unit": "USD"
        },
        "TimeUnit": "MONTHLY",
        "BudgetType": "COST",
        "CostFilters": {
            "Region": ["ap-southeast-1"]
        }
    }'
```

## SEA-Specific Considerations

### 1. Latency Optimization
**Network Performance within SEA:**
```bash
# Test latency to different regions
ping ap-southeast-1.amazonaws.com  # Singapore: ~5-20ms within SEA
ping ap-southeast-2.amazonaws.com  # Sydney: ~100-150ms from SEA mainland
ping us-east-1.amazonaws.com       # Virginia: ~200-300ms from SEA

# Choose Singapore for lowest latency to:
# - Indonesia, Malaysia, Thailand: <20ms
# - Philippines, Vietnam: <50ms
# - India, Japan: <100ms
```

### 2. Compliance and Data Residency

**Singapore (ap-southeast-1) Compliance:**
- ✅ PDPA (Personal Data Protection Act) compliance
- ✅ MAS (Monetary Authority of Singapore) requirements
- ✅ GDPR compliance (adequate protection)
- ✅ SOC 1, 2, 3 compliance
- ✅ ISO 27001, 27017, 27018

**Data Residency Configuration:**
```bash
# Ensure data stays in Singapore
export DATA_RESIDENCY_REGION=ap-southeast-1

# Configure RDS with encryption at rest
aws rds create-db-instance \
    --db-instance-identifier fastapi-postgres \
    --region ap-southeast-1 \
    --storage-encrypted \
    --kms-key-id alias/aws/rds \
    --backup-retention-period 7 \
    --delete-automated-backups false

# Configure S3 bucket with region lock
aws s3api create-bucket \
    --bucket fastapi-data-singapore \
    --region ap-southeast-1 \
    --create-bucket-configuration LocationConstraint=ap-southeast-1

# Add bucket policy to prevent cross-region replication
aws s3api put-bucket-policy \
    --bucket fastapi-data-singapore \
    --policy '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:ReplicateObject",
            "Resource": "arn:aws:s3:::fastapi-data-singapore/*",
            "Condition": {
                "StringNotEquals": {
                    "s3:LocationConstraint": "ap-southeast-1"
                }
            }
        }]
    }'
```

### 3. Multi-AZ Deployment for High Availability
```yaml
# EKS nodes across Singapore AZs
availabilityZones:
  - ap-southeast-1a  # Jurong West
  - ap-southeast-1b  # Novena  
  - ap-southeast-1c  # Tuas

# RDS Multi-AZ for 99.95% availability
aws rds create-db-instance \
    --db-instance-identifier fastapi-postgres \
    --multi-az \
    --availability-zone ap-southeast-1a \
    --region ap-southeast-1
```

### 4. SEA Business Hours Considerations
```bash
# Schedule automated backups during low traffic (SEA night time)
# Singapore Time (UTC+8): 2-4 AM = 18:00-20:00 UTC
aws rds modify-db-instance \
    --db-instance-identifier fastapi-postgres \
    --backup-window "18:00-20:00" \
    --maintenance-window "sun:19:00-sun:21:00"

# Schedule EKS maintenance during off-peak hours
# Most SEA countries: Business hours 9 AM - 6 PM local
```

### 5. SEA Internet Infrastructure Considerations
```yaml
# CloudFront configuration for SEA users
CloudFrontDistribution:
  Properties:
    DistributionConfig:
      PriceClass: PriceClass_100  # Use only US, Canada, Europe, Asia
      DefaultCacheBehavior:
        Compress: true
        ViewerProtocolPolicy: redirect-to-https
      # Singapore edge locations will serve SEA traffic
      Origins:
        - DomainName: !GetAtt ALB.DNSName
          Id: FastAPI-Singapore
          CustomOriginConfig:
            HTTPPort: 80
            HTTPSPort: 443
            OriginProtocolPolicy: https-only
```

### 6. Currency and Billing
```bash
# Monitor costs in local currencies
# Singapore Dollar (SGD): ~1.35 USD
# Malaysian Ringgit (MYR): ~4.7 USD  
# Thai Baht (THB): ~36 USD
# Indonesian Rupiah (IDR): ~15,700 USD

# Set up cost alerts in USD (AWS billing currency)
aws budgets create-budget \
    --budget '{
        "BudgetName": "FastAPI-SEA-SGD-Equivalent",
        "BudgetLimit": {
            "Amount": "270",
            "Unit": "USD"
        },
        "TimeUnit": "MONTHLY",
        "BudgetType": "COST"
    }'

echo "💰 Monthly budget: $270 USD ≈ $365 SGD ≈ RM1,269 ≈ ฿9,720"
```

## Troubleshooting

### Common Issues and Solutions

**1. Pod Startup Issues**
```bash
# Check pod events
kubectl describe pod <pod-name> -n fastapi-microservices

# Check logs
kubectl logs <pod-name> -n fastapi-microservices -f

# Debug with temporary pod
kubectl run debug --image=busybox -it --rm --restart=Never -- /bin/sh
```

**2. Database Connection Issues**
```bash
# Test RDS connectivity from EKS
kubectl run test-db --image=postgres:14 -it --rm --restart=Never -- psql -h your-rds-endpoint.amazonaws.com -U postgres -d users_db

# Check security groups
aws ec2 describe-security-groups --group-ids sg-12345678
```

**3. Load Balancer Issues**
```bash
# Check ALB status
kubectl get ingress -n fastapi-microservices

# Describe ingress for events
kubectl describe ingress fastapi-ingress -n fastapi-microservices

# Check target group health
aws elbv2 describe-target-health --target-group-arn arn:aws:elasticloadbalancing:us-west-2:123456789012:targetgroup/fastapi-users/1234567890
```

**4. High Costs**
```bash
# Check resource usage
kubectl top nodes
kubectl top pods -n fastapi-microservices

# Use AWS Cost Explorer
aws ce get-cost-and-usage --time-period Start=2023-01-01,End=2023-01-31 --granularity MONTHLY --metrics BlendedCost
```

### Monitoring Commands
```bash
# Check cluster health
kubectl get nodes
kubectl get pods -A

# Check application health
kubectl get pods -n fastapi-microservices
kubectl get svc -n fastapi-microservices

# Check resource usage
kubectl top nodes
kubectl top pods -n fastapi-microservices

# Check logs
kubectl logs -f deployment/users-deployment -n fastapi-microservices
kubectl logs -f deployment/users-worker-deployment -n fastapi-microservices
```

### Common Issues and Solutions

**1. Database "users_db" does not exist error**
This usually happens if the database creation step was skipped. Solution:
```bash
# Create the database manually
kubectl run postgres-client --image=postgres:14 -it --rm --restart=Never -n fastapi-microservices -- \
  psql -h YOUR_RDS_ENDPOINT -U postgres -c "CREATE DATABASE users_db;"
```

**2. Ingress fails with "ValidationError: A certificate must be specified for HTTPS listeners"**
This happens when HTTPS is configured without an SSL certificate. Solution:
- Either remove HTTPS configuration from ingress annotations
- Or create an SSL certificate in ACM and add the certificate ARN to ingress

**3. Load Balancer Controller permission errors**
If you see "User is not authorized to perform elasticloadbalancing:DescribeListenerAttributes":
```bash
# Update the IAM policy with missing permissions (already included in this guide)
aws iam create-policy-version --policy-arn "arn:aws:iam::ACCOUNT:policy/AWSLoadBalancerControllerIAMPolicy" \
  --policy-document file://iam_policy_updated.json --set-as-default
```

**4. Pods fail to start with database connection errors**
Check if:
- RDS instance is available: `aws rds describe-db-instances --db-instance-identifier fastapi-postgres`
- Security groups allow traffic on port 5432
- Database password in Kubernetes secret matches RDS password

This comprehensive guide covers deploying your FastAPI microservices to AWS using various approaches. Choose the deployment method that best fits your requirements:

- **EKS** for full Kubernetes features and flexibility
- **ECS Fargate** for serverless container deployment
- **App Runner** for simple, fully managed deployment

Start with the approach that matches your team's expertise and gradually incorporate more advanced features as needed.

## Cost Management: Cleanup and Quick Restoration

### 💰 Complete AWS Resource Cleanup (Stop All Charges)

**⚠️ IMPORTANT**: This will delete ALL your AWS resources. Make sure to backup any important data first!

**📊 Current Monthly Costs (Approximate)**:
- EKS Cluster: ~$73/month
- EC2 Nodes (2x t3.medium): ~$60/month
- RDS PostgreSQL (db.t3.micro): ~$15/month
- ElastiCache Redis (cache.t3.micro): ~$12/month
- Load Balancer: ~$18/month
- **Total**: ~$178/month

---

#### 🗑️ Step 1: Quick Cleanup Script

```bash
#!/bin/bash
# cleanup-aws-resources.sh - Complete cleanup script

set -e  # Exit on any error

export AWS_REGION=ap-southeast-1
export CLUSTER_NAME=fastapi-microservices

echo "🚨 AWS RESOURCE CLEANUP STARTING..."
echo "💰 This will stop ALL charges for FastAPI microservices"
echo ""
echo "⏰ Estimated cleanup time: 15-20 minutes"
echo "💾 Make sure you've backed up any important data!"
echo ""
read -p "Are you sure you want to proceed? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "❌ Cleanup cancelled"
    exit 1
fi

echo ""
echo "🗑️ Starting AWS resource cleanup..."

# Step 1: Delete Kubernetes resources (fastest)
echo "📦 Deleting Kubernetes applications..."
kubectl delete namespace fastapi-microservices --ignore-not-found=true
echo "✅ Kubernetes namespace deleted"

# Step 2: Delete EKS cluster (this also removes load balancers)
echo "🔧 Deleting EKS cluster (this takes 10-15 minutes)..."
eksctl delete cluster --name $CLUSTER_NAME --region $AWS_REGION --wait
echo "✅ EKS cluster deleted"

# Step 3: Delete RDS instance
echo "🗄️ Deleting RDS PostgreSQL instance..."
aws rds delete-db-instance \
    --db-instance-identifier fastapi-postgres \
    --skip-final-snapshot \
    --delete-automated-backups \
    --region $AWS_REGION 2>/dev/null || echo "RDS instance not found"

# Wait for RDS deletion to start
echo "⏳ Waiting for RDS deletion to start..."
sleep 10

# Step 4: Delete ElastiCache cluster
echo "📝 Deleting ElastiCache Redis cluster..."
aws elasticache delete-cache-cluster \
    --cache-cluster-id fastapi-redis \
    --region $AWS_REGION 2>/dev/null || echo "Redis cluster not found"

# Step 5: Delete subnet groups
echo "🌐 Deleting subnet groups..."
aws rds delete-db-subnet-group \
    --db-subnet-group-name fastapi-db-subnet-group \
    --region $AWS_REGION 2>/dev/null || echo "RDS subnet group not found"

aws elasticache delete-cache-subnet-group \
    --cache-subnet-group-name fastapi-redis-subnet-group \
    --region $AWS_REGION 2>/dev/null || echo "Redis subnet group not found"

# Step 6: Delete security groups (wait a bit for dependencies to clear)
echo "🔒 Deleting security groups..."
sleep 30

aws ec2 delete-security-group \
    --group-name fastapi-rds-sg \
    --region $AWS_REGION 2>/dev/null || echo "RDS security group not found or still in use"

aws ec2 delete-security-group \
    --group-name fastapi-redis-sg \
    --region $AWS_REGION 2>/dev/null || echo "Redis security group not found or still in use"

# Step 7: Delete ECR repositories (optional - keeps your images)
echo "📦 Deleting ECR repositories..."
read -p "Delete ECR repositories? This will remove your Docker images (yes/no): " delete_ecr

if [ "$delete_ecr" = "yes" ]; then
    aws ecr delete-repository \
        --repository-name fastapi-users \
        --force \
        --region $AWS_REGION 2>/dev/null || echo "ECR repository not found"
    
    aws ecr delete-repository \
        --repository-name fastapi-users-worker \
        --force \
        --region $AWS_REGION 2>/dev/null || echo "ECR worker repository not found"
    echo "✅ ECR repositories deleted"
else
    echo "📦 ECR repositories preserved"
fi

# Step 8: Delete IAM policies and roles
echo "🔐 Deleting IAM resources..."
aws iam detach-role-policy \
    --role-name AmazonEKSLoadBalancerControllerRole \
    --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/AWSLoadBalancerControllerIAMPolicy \
    2>/dev/null || echo "IAM policy not attached"

aws iam delete-role \
    --role-name AmazonEKSLoadBalancerControllerRole \
    2>/dev/null || echo "IAM role not found"

aws iam delete-policy \
    --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/AWSLoadBalancerControllerIAMPolicy \
    2>/dev/null || echo "IAM policy not found"

# Step 9: Clean up local files
echo "🧹 Cleaning up local configuration files..."
rm -f namespace.yaml postgres-aws.yaml redis-aws.yaml
rm -f users-deployment-aws.yaml users-worker-deployment-aws.yaml
rm -f eks-cluster-config.yaml iam_policy_updated.json
rm -f create-database-job.yaml db-migration-job.yaml

# Remove kubectl context
kubectl config delete-context arn:aws:eks:$AWS_REGION:$(aws sts get-caller-identity --query Account --output text):cluster/$CLUSTER_NAME 2>/dev/null || echo "kubectl context not found"

echo ""
echo "🎉 CLEANUP COMPLETED!"
echo "════════════════════════════════════════════════════════════"
echo "💰 AWS charges stopped for:"
echo "  ✅ EKS Cluster (~$73/month)"
echo "  ✅ EC2 Instances (~$60/month)" 
echo "  ✅ RDS PostgreSQL (~$15/month)"
echo "  ✅ ElastiCache Redis (~$12/month)"
echo "  ✅ Load Balancer (~$18/month)"
echo ""
echo "💾 Preserved (if chosen):"
echo "  📦 ECR Docker images (minimal cost ~$1/month)"
echo ""
echo "⏰ Final cleanup may take another 10-15 minutes in background"
echo "💡 Check AWS Console to verify all resources are deleted"
echo "════════════════════════════════════════════════════════════"
```

---

#### 🚀 Step 2: Quick Restoration Script

Save this script to quickly restore your environment when needed:

```bash
#!/bin/bash
# restore-aws-resources.sh - Quick restoration script

set -e  # Exit on any error

export AWS_REGION=ap-southeast-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "🚀 AWS FASTAPI RESTORATION STARTING..."
echo "⏰ Estimated time: 25-30 minutes"
echo "💰 This will resume AWS charges (~$178/month)"
echo ""
read -p "Proceed with restoration? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "❌ Restoration cancelled"
    exit 1
fi

echo ""
echo "🔄 Starting restoration process..."

# Step 1: Create EKS cluster (takes longest)
echo "🚀 Creating EKS cluster (15-20 minutes)..."
cat > eks-cluster-config.yaml << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: fastapi-microservices
  region: ap-southeast-1
  version: "1.28"

cloudWatch:
  clusterLogging:
    enableTypes: ["*"]

vpc:
  cidr: "10.0.0.0/16"

managedNodeGroups:
  - name: fastapi-nodes
    instanceType: t3.medium
    availabilityZones: ["ap-southeast-1a", "ap-southeast-1b", "ap-southeast-1c"]
    minSize: 1
    maxSize: 4
    desiredCapacity: 2
    volumeSize: 20
    volumeType: gp3
    amiFamily: AmazonLinux2
    iam:
      withAddonPolicies:
        ebs: true
        cloudWatch: true
        autoScaler: true
        loadBalancer: true
    labels:
      environment: production
      workload: fastapi-microservices

addons:
  - name: vpc-cni
    version: latest
  - name: coredns
    version: latest
  - name: kube-proxy
    version: latest
  - name: aws-ebs-csi-driver
    version: latest

iam:
  withOIDC: true
EOF

eksctl create cluster -f eks-cluster-config.yaml &
CLUSTER_PID=$!

# Step 2: Create RDS and Redis in parallel while EKS creates
echo "🗄️ Creating RDS PostgreSQL..."
# Get VPC info (will be available from EKS)
sleep 60  # Wait a bit for VPC to be created

VPC_ID=$(aws eks describe-cluster --name fastapi-microservices --region $AWS_REGION --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null || echo "")

# If VPC not ready, wait for cluster creation to complete first
if [ "$VPC_ID" = "" ]; then
    echo "⏳ Waiting for EKS cluster VPC to be ready..."
    wait $CLUSTER_PID
    VPC_ID=$(aws eks describe-cluster --name fastapi-microservices --region $AWS_REGION --query 'cluster.resourcesVpcConfig.vpcId' --output text)
fi

echo "📍 Using VPC: $VPC_ID"

# Create subnet groups and resources
echo "🔧 Setting up database infrastructure..."

# Get subnets
AVAILABLE_AZS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" --query 'Subnets[*].AvailabilityZone' --output text --region $AWS_REGION | tr '\t' '\n' | sort | uniq)

SUBNET_LIST=()
AZ_COUNT=0

for AZ in $AVAILABLE_AZS; do
    if [ $AZ_COUNT -lt 3 ]; then
        SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=availability-zone,Values=$AZ" "Name=state,Values=available" --query 'Subnets[0].SubnetId' --output text --region $AWS_REGION)
        if [ "$SUBNET_ID" != "None" ] && [ "$SUBNET_ID" != "" ]; then
            SUBNET_LIST+=("$SUBNET_ID")
            AZ_COUNT=$((AZ_COUNT + 1))
        fi
    fi
done

# Create subnet groups
aws rds create-db-subnet-group \
    --db-subnet-group-name fastapi-db-subnet-group \
    --db-subnet-group-description "Subnet group for FastAPI PostgreSQL" \
    --subnet-ids "${SUBNET_LIST[@]}" \
    --region $AWS_REGION

aws elasticache create-cache-subnet-group \
    --cache-subnet-group-name fastapi-redis-subnet-group \
    --cache-subnet-group-description "Subnet group for FastAPI Redis" \
    --subnet-ids "${SUBNET_LIST[@]}" \
    --region $AWS_REGION

# Create security groups
EKS_SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=eks-cluster-sg-fastapi-microservices-*" --query 'SecurityGroups[0].GroupId' --output text --region $AWS_REGION)

RDS_SG_ID=$(aws ec2 create-security-group \
    --group-name fastapi-rds-sg \
    --description "Security group for FastAPI RDS" \
    --vpc-id $VPC_ID \
    --region $AWS_REGION \
    --query 'GroupId' --output text)

REDIS_SG_ID=$(aws ec2 create-security-group \
    --group-name fastapi-redis-sg \
    --description "Security group for FastAPI Redis" \
    --vpc-id $VPC_ID \
    --region $AWS_REGION \
    --query 'GroupId' --output text)

# Configure security group rules
aws ec2 authorize-security-group-ingress --group-id $RDS_SG_ID --protocol tcp --port 5432 --source-group $EKS_SG_ID --region $AWS_REGION
aws ec2 authorize-security-group-ingress --group-id $REDIS_SG_ID --protocol tcp --port 6379 --source-group $EKS_SG_ID --region $AWS_REGION

# Create RDS instance
RDS_PASSWORD=$(openssl rand -base64 32)
echo "🔐 Generated new database password: $RDS_PASSWORD"

aws rds create-db-instance \
    --db-instance-identifier fastapi-postgres \
    --db-instance-class db.t3.micro \
    --engine postgres \
    --master-username postgres \
    --master-user-password "$RDS_PASSWORD" \
    --allocated-storage 20 \
    --vpc-security-group-ids $RDS_SG_ID \
    --db-subnet-group-name fastapi-db-subnet-group \
    --backup-retention-period 7 \
    --storage-encrypted \
    --region $AWS_REGION \
    --no-publicly-accessible &

# Create Redis cluster
aws elasticache create-cache-cluster \
    --cache-cluster-id fastapi-redis \
    --cache-node-type cache.t3.micro \
    --engine redis \
    --num-cache-nodes 1 \
    --cache-subnet-group-name fastapi-redis-subnet-group \
    --security-group-ids $REDIS_SG_ID \
    --region $AWS_REGION &

echo "⏳ Waiting for all services to be ready..."
# Wait for everything to be ready
aws rds wait db-instance-available --db-instance-identifier fastapi-postgres --region $AWS_REGION
aws elasticache wait cache-cluster-available --cache-cluster-id fastapi-redis --region $AWS_REGION

# Get endpoints
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier fastapi-postgres --region $AWS_REGION --query 'DBInstances[0].Endpoint.Address' --output text)
REDIS_ENDPOINT=$(aws elasticache describe-cache-clusters --cache-cluster-id fastapi-redis --show-cache-node-info --region $AWS_REGION --query 'CacheClusters[0].CacheNodes[0].Endpoint.Address' --output text)

# Step 3: Setup Kubernetes environment
echo "🔧 Setting up Kubernetes environment..."

# Update kubeconfig
aws eks update-kubeconfig --region $AWS_REGION --name fastapi-microservices

# Install AWS Load Balancer Controller
eksctl utils associate-iam-oidc-provider --region=$AWS_REGION --cluster=fastapi-microservices --approve

# Create IAM policy
cat > iam_policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iam:CreateServiceLinkedRole"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "iam:AWSServiceName": "elasticloadbalancing.amazonaws.com"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeAccountAttributes",
                "ec2:DescribeAddresses",
                "ec2:DescribeAvailabilityZones",
                "ec2:DescribeInternetGateways",
                "ec2:DescribeVpcs",
                "ec2:DescribeVpcPeeringConnections",
                "ec2:DescribeSubnets",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeInstances",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DescribeTags",
                "ec2:GetCoipPoolUsage",
                "ec2:DescribeCoipPools",
                "elasticloadbalancing:DescribeLoadBalancers",
                "elasticloadbalancing:DescribeLoadBalancerAttributes",
                "elasticloadbalancing:DescribeListeners",
                "elasticloadbalancing:DescribeListenerCertificates",
                "elasticloadbalancing:DescribeListenerAttributes",
                "elasticloadbalancing:DescribeSSLPolicies",
                "elasticloadbalancing:DescribeRules",
                "elasticloadbalancing:DescribeTargetGroups",
                "elasticloadbalancing:DescribeTargetGroupAttributes",
                "elasticloadbalancing:DescribeTargetHealth",
                "elasticloadbalancing:DescribeTags",
                "elasticloadbalancing:DescribeTrustStores"
            ],
            "Resource": "*"
        }
    ]
}
EOF

aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://iam_policy.json 2>/dev/null || echo "IAM policy already exists"

eksctl create iamserviceaccount \
  --cluster=fastapi-microservices \
  --region=$AWS_REGION \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve

helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=fastapi-microservices \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=$AWS_REGION \
  --set vpcId=$VPC_ID

echo ""
echo "🎉 RESTORATION COMPLETED!"
echo "════════════════════════════════════════════════════════════"
echo "✅ EKS Cluster: fastapi-microservices"
echo "✅ RDS PostgreSQL: $RDS_ENDPOINT"
echo "✅ ElastiCache Redis: $REDIS_ENDPOINT"
echo "✅ AWS Load Balancer Controller: Installed"
echo ""
echo "🔐 NEW Database Password: $RDS_PASSWORD"
echo ""
echo "🎯 Next Steps:"
echo "1. Push your Docker images to ECR (if deleted)"
echo "2. Deploy your FastAPI application (Step 5 in guide)"
echo "3. Run database migrations"
echo ""
echo "💰 Monthly charges resumed (~$178/month)"
echo "════════════════════════════════════════════════════════════"

# Store credentials
echo "export RDS_ENDPOINT='$RDS_ENDPOINT'" >> ~/.bashrc
echo "export REDIS_ENDPOINT='$REDIS_ENDPOINT'" >> ~/.bashrc
echo "export RDS_PASSWORD='$RDS_PASSWORD'" >> ~/.bashrc
```

---

#### 🔄 Step 3: Usage Instructions

**To save money (cleanup):**
```bash
# Make the script executable
chmod +x cleanup-aws-resources.sh

# Run cleanup
./cleanup-aws-resources.sh
```

**To restore when needed:**
```bash
# Make the script executable  
chmod +x restore-aws-resources.sh

# Run restoration
./restore-aws-resources.sh

# Then deploy your application
# (You'll need to rebuild/push Docker images if ECR was deleted)
```

---

#### 💡 Money-Saving Tips

**1. Use Spot Instances for Development (Save 50-70%)**
```bash
# Add to your eksctl config for dev environments
spot: true
instanceTypes: ["t3.medium", "t3a.medium", "t2.medium"]
```

**2. Schedule Automatic Shutdown/Startup**
```bash
# Create a cron job to shutdown during off-hours
# Example: Shutdown at 8 PM, restore at 8 AM (Mon-Fri)

# Add to crontab (crontab -e)
0 20 * * 1-5 /path/to/cleanup-aws-resources.sh
0 8 * * 1-5 /path/to/restore-aws-resources.sh
```

**3. Use Smaller Instance Types for Testing**
```bash
# For very light testing, use nano instances
# RDS: db.t3.nano (~$8/month instead of $15)
# ElastiCache: cache.t2.nano (~$6/month instead of $12)
```

**4. Regional Cost Optimization**
```bash
# Check costs in different regions
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=REGION
```

---

#### 📊 Cost Monitoring Setup

```bash
# Set up billing alerts
aws budgets create-budget \
    --account-id $AWS_ACCOUNT_ID \
    --budget '{
        "BudgetName": "FastAPI-Monthly-Limit",
        "BudgetLimit": {
            "Amount": "200",
            "Unit": "USD"
        },
        "TimeUnit": "MONTHLY",
        "BudgetType": "COST",
        "CostFilters": {
            "Service": ["Amazon Elastic Kubernetes Service", "Amazon Relational Database Service", "Amazon ElastiCache"]
        }
    }' \
    --notifications-with-subscribers '[
        {
            "Notification": {
                "NotificationType": "ACTUAL",
                "ComparisonOperator": "GREATER_THAN",
                "Threshold": 80
            },
            "Subscribers": [
                {
                    "SubscriptionType": "EMAIL",
                    "Address": "your-email@example.com"
                }
            ]
        }
    ]'

echo "💰 Billing alert set up - you'll be notified at 80% of $200/month"
```

**💡 Pro Tips:**
- Run cleanup on Friday evening, restore on Monday morning
- Use development/staging in cheaper regions like `us-east-1`
- Keep ECR images (minimal cost) for faster restoration
- Monitor costs weekly with AWS Cost Explorer
- Consider AWS Savings Plans for 30-40% savings on stable workloads

This approach can save you **$100-150/month** during downtime while keeping restoration under 30 minutes! 🚀