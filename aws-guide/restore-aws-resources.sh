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