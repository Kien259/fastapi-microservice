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