#!/bin/bash
# cleanup-remaining-resources.sh - Clean up common leftover AWS resources

set -e

export AWS_REGION=ap-southeast-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "🧹 CLEANING UP REMAINING AWS RESOURCES..."
echo "📍 Region: $AWS_REGION"
echo "📍 Account: $AWS_ACCOUNT_ID"
echo ""
echo "⚠️  This will delete leftover resources that might be costing money!"
echo ""
read -p "Continue with cleanup? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "❌ Cleanup cancelled"
    exit 1
fi

echo ""
echo "🗑️ Starting cleanup of remaining resources..."

# Function to safely delete resources
safe_delete() {
    local service=$1
    local resource=$2
    local command=$3
    
    echo "🔍 Cleaning $service - $resource..."
    if eval $command 2>/dev/null; then
        echo "   ✅ Deleted: $service $resource"
    else
        echo "   ⚠️  Not found or already deleted: $service $resource"
    fi
}

echo ""
echo "🔥 DELETING HIGH-COST RESOURCES"
echo "════════════════════════════════════════════════════════════"

# Clean up Load Balancers
echo "🔍 Looking for Load Balancers..."
load_balancers=$(aws elbv2 describe-load-balancers --region $AWS_REGION --query 'LoadBalancers[*].LoadBalancerArn' --output text 2>/dev/null || echo "")
if [ ! -z "$load_balancers" ]; then
    for lb_arn in $load_balancers; do
        echo "💰 Deleting Load Balancer: $lb_arn"
        aws elbv2 delete-load-balancer --load-balancer-arn $lb_arn --region $AWS_REGION
        echo "   ✅ Load Balancer deletion initiated (saves ~$18/month)"
    done
else
    echo "   ✅ No Load Balancers found"
fi

# Clean up Classic Load Balancers
echo "🔍 Looking for Classic Load Balancers..."
classic_lbs=$(aws elb describe-load-balancers --region $AWS_REGION --query 'LoadBalancerDescriptions[*].LoadBalancerName' --output text 2>/dev/null || echo "")
if [ ! -z "$classic_lbs" ]; then
    for clb_name in $classic_lbs; do
        echo "💰 Deleting Classic Load Balancer: $clb_name"
        aws elb delete-load-balancer --load-balancer-name $clb_name --region $AWS_REGION
        echo "   ✅ Classic Load Balancer deleted (saves ~$18/month)"
    done
else
    echo "   ✅ No Classic Load Balancers found"
fi

# Clean up NAT Gateways
echo "🔍 Looking for NAT Gateways..."
nat_gateways=$(aws ec2 describe-nat-gateways --region $AWS_REGION --query 'NatGateways[?State!=`deleted`].NatGatewayId' --output text 2>/dev/null || echo "")
if [ ! -z "$nat_gateways" ]; then
    for nat_id in $nat_gateways; do
        echo "💰 Deleting NAT Gateway: $nat_id"
        aws ec2 delete-nat-gateway --nat-gateway-id $nat_id --region $AWS_REGION
        echo "   ✅ NAT Gateway deletion initiated (saves ~$45/month)"
    done
else
    echo "   ✅ No NAT Gateways found"
fi

# Clean up remaining RDS instances
echo "🔍 Looking for remaining RDS instances..."
rds_instances=$(aws rds describe-db-instances --region $AWS_REGION --query 'DBInstances[*].DBInstanceIdentifier' --output text 2>/dev/null || echo "")
if [ ! -z "$rds_instances" ]; then
    for rds_id in $rds_instances; do
        echo "💰 Deleting RDS Instance: $rds_id"
        aws rds delete-db-instance --db-instance-identifier $rds_id --skip-final-snapshot --delete-automated-backups --region $AWS_REGION
        echo "   ✅ RDS instance deletion initiated (saves ~$15-200/month)"
    done
else
    echo "   ✅ No RDS instances found"
fi

# Clean up remaining ElastiCache clusters
echo "🔍 Looking for remaining ElastiCache clusters..."
cache_clusters=$(aws elasticache describe-cache-clusters --region $AWS_REGION --query 'CacheClusters[*].CacheClusterId' --output text 2>/dev/null || echo "")
if [ ! -z "$cache_clusters" ]; then
    for cache_id in $cache_clusters; do
        echo "💰 Deleting ElastiCache Cluster: $cache_id"
        aws elasticache delete-cache-cluster --cache-cluster-id $cache_id --region $AWS_REGION
        echo "   ✅ ElastiCache cluster deletion initiated (saves ~$12-100/month)"
    done
else
    echo "   ✅ No ElastiCache clusters found"
fi

# Terminate any remaining EC2 instances
echo "🔍 Looking for running EC2 instances..."
ec2_instances=$(aws ec2 describe-instances --region $AWS_REGION --query 'Reservations[*].Instances[?State.Name==`running`].InstanceId' --output text 2>/dev/null || echo "")
if [ ! -z "$ec2_instances" ]; then
    echo "💰 Found running EC2 instances: $ec2_instances"
    read -p "⚠️  Terminate these EC2 instances? (yes/no): " terminate_ec2
    if [ "$terminate_ec2" = "yes" ]; then
        aws ec2 terminate-instances --instance-ids $ec2_instances --region $AWS_REGION
        echo "   ✅ EC2 instances termination initiated (saves ~$15-60/month per instance)"
    else
        echo "   ⏭️  Skipped EC2 termination"
    fi
else
    echo "   ✅ No running EC2 instances found"
fi

echo ""
echo "💸 DELETING MODERATE-COST RESOURCES"
echo "════════════════════════════════════════════════════════════"

# Wait a bit for dependencies to clear
sleep 10

# Clean up unattached EBS volumes
echo "🔍 Looking for unattached EBS volumes..."
ebs_volumes=$(aws ec2 describe-volumes --region $AWS_REGION --query 'Volumes[?State==`available`].VolumeId' --output text 2>/dev/null || echo "")
if [ ! -z "$ebs_volumes" ]; then
    for vol_id in $ebs_volumes; do
        echo "💸 Deleting EBS Volume: $vol_id"
        aws ec2 delete-volume --volume-id $vol_id --region $AWS_REGION 2>/dev/null || echo "   ⚠️  Volume may be in use: $vol_id"
    done
    echo "   ✅ Unattached EBS volumes cleaned up (saves ~$0.10/GB/month)"
else
    echo "   ✅ No unattached EBS volumes found"
fi

# Clean up unattached Elastic IPs
echo "🔍 Looking for unattached Elastic IPs..."
elastic_ips=$(aws ec2 describe-addresses --region $AWS_REGION --query 'Addresses[?!AssociationId].PublicIp' --output text 2>/dev/null || echo "")
if [ ! -z "$elastic_ips" ]; then
    for eip in $elastic_ips; do
        echo "💸 Releasing Elastic IP: $eip"
        aws ec2 release-address --public-ip $eip --region $AWS_REGION
        echo "   ✅ Elastic IP released (saves ~$3.65/month)"
    done
else
    echo "   ✅ No unattached Elastic IPs found"
fi

# Clean up old EBS snapshots (owned by your account)
echo "🔍 Looking for your EBS snapshots..."
ebs_snapshots=$(aws ec2 describe-snapshots --owner-ids $AWS_ACCOUNT_ID --region $AWS_REGION --query 'Snapshots[*].SnapshotId' --output text 2>/dev/null || echo "")
if [ ! -z "$ebs_snapshots" ]; then
    echo "💡 Found $(echo $ebs_snapshots | wc -w) EBS snapshots"
    read -p "⚠️  Delete all your EBS snapshots? This cannot be undone! (yes/no): " delete_snapshots
    if [ "$delete_snapshots" = "yes" ]; then
        for snap_id in $ebs_snapshots; do
            echo "💸 Deleting snapshot: $snap_id"
            aws ec2 delete-snapshot --snapshot-id $snap_id --region $AWS_REGION 2>/dev/null || echo "   ⚠️  Cannot delete: $snap_id (may be in use)"
        done
        echo "   ✅ EBS snapshots cleanup attempted (saves ~$0.05/GB/month)"
    else
        echo "   ⏭️  Skipped snapshot deletion"
    fi
else
    echo "   ✅ No EBS snapshots found"
fi

echo ""
echo "🧹 DELETING LOW-COST BUT UNNECESSARY RESOURCES"
echo "════════════════════════════════════════════════════════════"

# Wait for dependencies to clear
sleep 15

# Clean up security groups
echo "🔍 Looking for custom security groups..."
security_groups=$(aws ec2 describe-security-groups --region $AWS_REGION --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || echo "")
if [ ! -z "$security_groups" ]; then
    for sg_id in $security_groups; do
        echo "🧹 Deleting Security Group: $sg_id"
        aws ec2 delete-security-group --group-id $sg_id --region $AWS_REGION 2>/dev/null || echo "   ⚠️  Cannot delete (may be in use): $sg_id"
    done
    echo "   ✅ Security groups cleanup attempted"
else
    echo "   ✅ No custom security groups found"
fi

# Clean up subnet groups
echo "🔍 Looking for DB subnet groups..."
db_subnet_groups=$(aws rds describe-db-subnet-groups --region $AWS_REGION --query 'DBSubnetGroups[?DBSubnetGroupName!=`default`].DBSubnetGroupName' --output text 2>/dev/null || echo "")
if [ ! -z "$db_subnet_groups" ]; then
    for group_name in $db_subnet_groups; do
        echo "🧹 Deleting DB Subnet Group: $group_name"
        aws rds delete-db-subnet-group --db-subnet-group-name $group_name --region $AWS_REGION 2>/dev/null || echo "   ⚠️  Cannot delete: $group_name"
    done
else
    echo "   ✅ No custom DB subnet groups found"
fi

echo "🔍 Looking for ElastiCache subnet groups..."
cache_subnet_groups=$(aws elasticache describe-cache-subnet-groups --region $AWS_REGION --query 'CacheSubnetGroups[?CacheSubnetGroupName!=`default`].CacheSubnetGroupName' --output text 2>/dev/null || echo "")
if [ ! -z "$cache_subnet_groups" ]; then
    for group_name in $cache_subnet_groups; do
        echo "🧹 Deleting Cache Subnet Group: $group_name"
        aws elasticache delete-cache-subnet-group --cache-subnet-group-name $group_name --region $AWS_REGION 2>/dev/null || echo "   ⚠️  Cannot delete: $group_name"
    done
else
    echo "   ✅ No custom cache subnet groups found"
fi

# Clean up CloudWatch Log Groups
echo "🔍 Looking for CloudWatch Log Groups..."
log_groups=$(aws logs describe-log-groups --region $AWS_REGION --query 'logGroups[?contains(logGroupName, `fastapi`) || contains(logGroupName, `eks`) || contains(logGroupName, `/aws/`)].logGroupName' --output text 2>/dev/null || echo "")
if [ ! -z "$log_groups" ]; then
    echo "💡 Found CloudWatch log groups"
    read -p "⚠️  Delete CloudWatch log groups? (may contain useful logs) (yes/no): " delete_logs
    if [ "$delete_logs" = "yes" ]; then
        for log_group in $log_groups; do
            echo "🧹 Deleting Log Group: $log_group"
            aws logs delete-log-group --log-group-name "$log_group" --region $AWS_REGION 2>/dev/null || echo "   ⚠️  Cannot delete: $log_group"
        done
        echo "   ✅ Log groups cleanup attempted (saves ~$0.50/GB/month)"
    else
        echo "   ⏭️  Skipped log group deletion"
    fi
else
    echo "   ✅ No relevant log groups found"
fi

# Clean up IAM roles
echo "🔍 Looking for FastAPI/EKS related IAM roles..."
iam_roles=$(aws iam list-roles --query 'Roles[?contains(RoleName, `fastapi`) || contains(RoleName, `EKS`) || contains(RoleName, `LoadBalancer`)].RoleName' --output text 2>/dev/null || echo "")
if [ ! -z "$iam_roles" ]; then
    echo "💡 Found IAM roles: $iam_roles"
    read -p "⚠️  Delete these IAM roles? (yes/no): " delete_iam
    if [ "$delete_iam" = "yes" ]; then
        for role_name in $iam_roles; do
            echo "🧹 Cleaning up IAM Role: $role_name"
            # First detach policies
            policies=$(aws iam list-attached-role-policies --role-name "$role_name" --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null || echo "")
            for policy_arn in $policies; do
                aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" 2>/dev/null || true
            done
            # Delete role
            aws iam delete-role --role-name "$role_name" 2>/dev/null || echo "   ⚠️  Cannot delete role: $role_name"
        done
    else
        echo "   ⏭️  Skipped IAM role deletion"
    fi
else
    echo "   ✅ No relevant IAM roles found"
fi

echo ""
echo "🎉 CLEANUP COMPLETED!"
echo "════════════════════════════════════════════════════════════"
echo "✅ Finished cleaning up remaining resources"
echo ""
echo "💰 ESTIMATED SAVINGS:"
echo "   • Load Balancers: ~$18-23/month each"
echo "   • NAT Gateways: ~$45/month each"
echo "   • RDS Instances: ~$15-200/month each"
echo "   • ElastiCache: ~$12-100/month each"
echo "   • EC2 Instances: ~$15-60/month each"
echo "   • EBS Volumes: ~$0.10/GB/month"
echo "   • Elastic IPs: ~$3.65/month each"
echo ""
echo "🔍 To verify everything is clean, run:"
echo "   ./find-remaining-costs.sh"
echo ""
echo "📊 To check your current AWS costs:"
echo "   aws ce get-cost-and-usage --time-period Start=$(date +%Y-%m-01),End=$(date -d 'next month' +%Y-%m-01) --granularity MONTHLY --metrics BlendedCost"
echo ""
echo "⚠️  Note: Some resources may take a few minutes to fully delete."
echo "💡 Check your AWS console in 10-15 minutes to confirm all deletions." 