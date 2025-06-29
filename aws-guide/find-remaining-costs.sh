#!/bin/bash
# find-remaining-costs.sh - Find all AWS resources that might be costing money

set -e

export AWS_REGION=ap-southeast-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "🔍 SCANNING FOR REMAINING AWS COSTS..."
echo "📍 Region: $AWS_REGION"
echo "📍 Account: $AWS_ACCOUNT_ID"
echo ""

# Function to check if a resource exists and show cost estimate
check_resource() {
    local service=$1
    local resource_type=$2
    local command=$3
    local cost_estimate=$4
    
    echo "🔍 Checking $service - $resource_type..."
    result=$(eval $command 2>/dev/null || echo "NONE")
    
    if [ "$result" != "NONE" ] && [ "$result" != "[]" ] && [ ! -z "$result" ]; then
        echo "💰 FOUND: $service - $resource_type"
        echo "   💸 Estimated cost: $cost_estimate"
        echo "   📋 Details: $result"
        echo ""
    else
        echo "   ✅ Clean: No $resource_type found"
    fi
}

echo "════════════════════════════════════════════════════════════"
echo "🔍 SCANNING COMPUTE RESOURCES"
echo "════════════════════════════════════════════════════════════"

# EKS Clusters
check_resource "EKS" "clusters" \
    "aws eks list-clusters --region $AWS_REGION --query 'clusters[*]' --output text" \
    "~$73/month per cluster"

# EC2 Instances
check_resource "EC2" "instances" \
    "aws ec2 describe-instances --region $AWS_REGION --query 'Reservations[*].Instances[?State.Name!=\`terminated\`].[InstanceId,InstanceType,State.Name]' --output table" \
    "~$15-60/month per instance"

# Auto Scaling Groups
check_resource "Auto Scaling" "groups" \
    "aws autoscaling describe-auto-scaling-groups --region $AWS_REGION --query 'AutoScalingGroups[*].[AutoScalingGroupName,DesiredCapacity]' --output table" \
    "Variable based on instance count"

# Launch Templates
check_resource "EC2" "launch templates" \
    "aws ec2 describe-launch-templates --region $AWS_REGION --query 'LaunchTemplates[*].[LaunchTemplateName,LaunchTemplateId]' --output table" \
    "No direct cost, but enables instance creation"

echo ""
echo "════════════════════════════════════════════════════════════"
echo "🔍 SCANNING DATABASE RESOURCES"
echo "════════════════════════════════════════════════════════════"

# RDS Instances
check_resource "RDS" "instances" \
    "aws rds describe-db-instances --region $AWS_REGION --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceClass,DBInstanceStatus]' --output table" \
    "~$15-200/month per instance"

# RDS Snapshots
check_resource "RDS" "snapshots" \
    "aws rds describe-db-snapshots --region $AWS_REGION --query 'DBSnapshots[?SnapshotType==\`manual\`].[DBSnapshotIdentifier,AllocatedStorage]' --output table" \
    "~$0.095/GB/month"

# ElastiCache Clusters
check_resource "ElastiCache" "clusters" \
    "aws elasticache describe-cache-clusters --region $AWS_REGION --query 'CacheClusters[*].[CacheClusterId,CacheNodeType,CacheClusterStatus]' --output table" \
    "~$12-100/month per cluster"

echo ""
echo "════════════════════════════════════════════════════════════"
echo "🔍 SCANNING STORAGE RESOURCES"
echo "════════════════════════════════════════════════════════════"

# EBS Volumes
check_resource "EBS" "volumes" \
    "aws ec2 describe-volumes --region $AWS_REGION --query 'Volumes[?State!=\`deleting\`].[VolumeId,Size,VolumeType,State]' --output table" \
    "~$0.10/GB/month (gp2/gp3)"

# EBS Snapshots
check_resource "EBS" "snapshots" \
    "aws ec2 describe-snapshots --owner-ids $AWS_ACCOUNT_ID --region $AWS_REGION --query 'Snapshots[*].[SnapshotId,VolumeSize,Description]' --output table" \
    "~$0.05/GB/month"

# S3 Buckets
check_resource "S3" "buckets" \
    "aws s3api list-buckets --query 'Buckets[*].Name' --output text" \
    "~$0.023/GB/month + requests"

# ECR Repositories
check_resource "ECR" "repositories" \
    "aws ecr describe-repositories --region $AWS_REGION --query 'repositories[*].[repositoryName,repositoryUri]' --output table" \
    "~$0.10/GB/month"

echo ""
echo "════════════════════════════════════════════════════════════"
echo "🔍 SCANNING NETWORK RESOURCES"
echo "════════════════════════════════════════════════════════════"

# Load Balancers (ALB/NLB)
check_resource "ELB" "load balancers" \
    "aws elbv2 describe-load-balancers --region $AWS_REGION --query 'LoadBalancers[*].[LoadBalancerName,Type,State.Code]' --output table" \
    "~$18-23/month per ALB"

# Classic Load Balancers
check_resource "ELB" "classic load balancers" \
    "aws elb describe-load-balancers --region $AWS_REGION --query 'LoadBalancerDescriptions[*].[LoadBalancerName,DNSName]' --output table" \
    "~$18/month per CLB"

# Elastic IPs
check_resource "EC2" "elastic IPs" \
    "aws ec2 describe-addresses --region $AWS_REGION --query 'Addresses[*].[PublicIp,AssociationId]' --output table" \
    "~$3.65/month if unattached"

# NAT Gateways
check_resource "VPC" "NAT gateways" \
    "aws ec2 describe-nat-gateways --region $AWS_REGION --query 'NatGateways[?State!=\`deleted\`].[NatGatewayId,State,VpcId]' --output table" \
    "~$45/month per NAT gateway"

# VPC Endpoints
check_resource "VPC" "endpoints" \
    "aws ec2 describe-vpc-endpoints --region $AWS_REGION --query 'VpcEndpoints[*].[VpcEndpointId,ServiceName,State]' --output table" \
    "~$7-45/month depending on type"

echo ""
echo "════════════════════════════════════════════════════════════"
echo "🔍 SCANNING SECURITY & IAM RESOURCES"
echo "════════════════════════════════════════════════════════════"

# Security Groups (no cost, but check for cleanup)
check_resource "EC2" "security groups" \
    "aws ec2 describe-security-groups --region $AWS_REGION --query 'SecurityGroups[?GroupName!=\`default\`].[GroupName,GroupId]' --output table" \
    "No cost - but should be cleaned up"

# IAM Roles with policies (check for unused)
echo "🔍 Checking IAM - roles..."
iam_roles=$(aws iam list-roles --query 'Roles[?contains(RoleName, `fastapi`) || contains(RoleName, `EKS`) || contains(RoleName, `LoadBalancer`)].[RoleName]' --output text)
if [ ! -z "$iam_roles" ]; then
    echo "💡 FOUND: IAM roles that might be leftover"
    echo "   📋 Details: $iam_roles"
    echo "   💸 No direct cost, but should be cleaned up for security"
else
    echo "   ✅ Clean: No relevant IAM roles found"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "🔍 SCANNING MONITORING & LOGGING"
echo "════════════════════════════════════════════════════════════"

# CloudWatch Log Groups
check_resource "CloudWatch" "log groups" \
    "aws logs describe-log-groups --region $AWS_REGION --query 'logGroups[*].[logGroupName,storedBytes]' --output table" \
    "~$0.50/GB/month"

# CloudWatch Alarms
check_resource "CloudWatch" "alarms" \
    "aws cloudwatch describe-alarms --region $AWS_REGION --query 'MetricAlarms[*].[AlarmName,StateValue]' --output table" \
    "~$0.10/alarm/month"

echo ""
echo "════════════════════════════════════════════════════════════"
echo "🔍 SCANNING KUBERNETES RESOURCES"
echo "════════════════════════════════════════════════════════════"

# Check if kubectl is still configured
echo "🔍 Checking kubectl configuration..."
kubectl_contexts=$(kubectl config get-contexts --no-headers 2>/dev/null | grep -v "^\*" | wc -l || echo "0")
if [ "$kubectl_contexts" -gt 0 ]; then
    echo "💡 FOUND: kubectl contexts still configured"
    echo "   📋 Run: kubectl config get-contexts"
    echo "   🧹 Cleanup: kubectl config delete-context CONTEXT_NAME"
else
    echo "   ✅ Clean: No kubectl contexts found"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "💰 CHECKING CURRENT COSTS"
echo "════════════════════════════════════════════════════════════"

# Get current month costs
echo "🔍 Getting current month costs..."
current_month=$(date +%Y-%m-01)
next_month=$(date -d "$current_month +1 month" +%Y-%m-01)

echo "📊 Current month costs ($(date +%B)):"
aws ce get-cost-and-usage \
    --time-period Start=$current_month,End=$next_month \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE \
    --query 'ResultsByTime[0].Groups[?Metrics.BlendedCost.Amount>`0.01`].[Keys[0],Metrics.BlendedCost.Amount]' \
    --output table 2>/dev/null || echo "Unable to fetch cost data (may need permissions)"

echo ""
echo "════════════════════════════════════════════════════════════"
echo "🎯 SUMMARY AND RECOMMENDATIONS"
echo "════════════════════════════════════════════════════════════"

echo "✅ Scan completed!"
echo ""
echo "🧹 If you found resources above, here's how to clean them up:"
echo ""
echo "💰 HIGH COST ITEMS TO DELETE IMMEDIATELY:"
echo "   • Load Balancers: aws elbv2 delete-load-balancer --load-balancer-arn ARN"
echo "   • NAT Gateways: aws ec2 delete-nat-gateway --nat-gateway-id ID"
echo "   • RDS Instances: aws rds delete-db-instance --db-instance-identifier ID --skip-final-snapshot"
echo "   • ElastiCache: aws elasticache delete-cache-cluster --cache-cluster-id ID"
echo "   • EC2 Instances: aws ec2 terminate-instances --instance-ids ID"
echo ""
echo "💸 MODERATE COST ITEMS:"
echo "   • EBS Volumes: aws ec2 delete-volume --volume-id ID"
echo "   • Elastic IPs: aws ec2 release-address --public-ip IP"
echo "   • EBS Snapshots: aws ec2 delete-snapshot --snapshot-id ID"
echo ""
echo "🧹 CLEANUP ITEMS (low/no cost):"
echo "   • Security Groups: aws ec2 delete-security-group --group-id ID"
echo "   • CloudWatch Logs: aws logs delete-log-group --log-group-name NAME"
echo "   • IAM Roles: aws iam delete-role --role-name NAME"
echo ""
echo "⚠️  IMPORTANT: Always verify what you're deleting before running delete commands!"
echo ""
echo "🔄 To run an automated cleanup of common leftover resources:"
echo "   ./cleanup-remaining-resources.sh" 