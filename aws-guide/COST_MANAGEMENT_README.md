# 💰 AWS Cost Management - Quick Reference

## 🚨 STOP ALL CHARGES (Save ~$178/month)

```bash
# Stop all AWS charges immediately
./cleanup-aws-resources.sh
```

**What gets deleted:**
- ✅ EKS Cluster (~$73/month)
- ✅ EC2 Instances (~$60/month) 
- ✅ RDS PostgreSQL (~$15/month)
- ✅ ElastiCache Redis (~$12/month)
- ✅ Load Balancer (~$18/month)
- ⚠️ **OPTIONAL**: ECR Docker images (~$1/month)

**Time**: 15-20 minutes

---

## 🚀 RESTORE WHEN NEEDED

```bash
# Restore everything quickly
./restore-aws-resources.sh
```

**What gets created:**
- ✅ EKS Cluster with load balancer controller
- ✅ RDS PostgreSQL with Multi-AZ
- ✅ ElastiCache Redis cluster  
- ✅ All security groups and networking
- ✅ New database password (auto-generated)

**Time**: 25-30 minutes

---

## 💡 Money-Saving Strategies

### 1. **Weekend Shutdown** (Save 50%+ costs)
```bash
# Friday evening
./cleanup-aws-resources.sh

# Monday morning  
./restore-aws-resources.sh
```

### 2. **Use Spot Instances** (Save 50-70%)
Edit `eks-cluster-config.yaml` in restore script:
```yaml
spot: true
instanceTypes: ["t3.medium", "t3a.medium", "t2.medium"]
```

### 3. **Smaller Instances for Testing**
- RDS: `db.t3.nano` (~$8/month instead of $15)
- Redis: `cache.t2.nano` (~$6/month instead of $12)
- EKS nodes: `t3.small` (~$30/month instead of $60)

### 4. **Automated Scheduling**
```bash
# Add to crontab (crontab -e)
# Shutdown at 8 PM weekdays
0 20 * * 1-5 /path/to/cleanup-aws-resources.sh

# Restore at 8 AM weekdays  
0 8 * * 1-5 /path/to/restore-aws-resources.sh
```

---

## 📊 Cost Monitoring

### Set up billing alerts:
```bash
# Get notified at 80% of $200/month
aws budgets create-budget \
    --account-id $(aws sts get-caller-identity --query Account --output text) \
    --budget '{
        "BudgetName": "FastAPI-Monthly-Limit",
        "BudgetLimit": {"Amount": "200", "Unit": "USD"},
        "TimeUnit": "MONTHLY",
        "BudgetType": "COST"
    }' \
    --notifications-with-subscribers '[{
        "Notification": {
            "NotificationType": "ACTUAL",
            "ComparisonOperator": "GREATER_THAN",
            "Threshold": 80
        },
        "Subscribers": [{
            "SubscriptionType": "EMAIL",
            "Address": "your-email@example.com"
        }]
    }]'
```

### Check current costs:
```bash
# View costs by service
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

---

## 🎯 After Restoration - Deploy Your App

1. **Push Docker images** (if ECR was deleted):
```bash
# Rebuild and push images
docker build -t fastapi-users -f users/docker/backend.dockerfile users/
docker tag fastapi-users:latest $AWS_ACCOUNT_ID.dkr.ecr.ap-southeast-1.amazonaws.com/fastapi-users:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.ap-southeast-1.amazonaws.com/fastapi-users:latest
```

2. **Follow Step 5** in the main deployment guide to deploy your FastAPI application

3. **Run database migrations** to set up your schema

---

## 🔐 Important Notes

- **Database passwords** are auto-generated during restoration
- **ECR images** are preserved by default (minimal cost)
- **All data** is deleted during cleanup - backup important data first
- **New deployments** will need fresh database migrations
- **SSL certificates** may need to be reconfigured

---

## 💸 Potential Savings

| Strategy | Monthly Savings | Setup Time |
|----------|----------------|------------|
| Weekend shutdown | ~$89 (50%) | 5 minutes |
| Spot instances | ~$30-42 (20-25%) | 10 minutes |
| Smaller instances | ~$20-30 (15%) | 5 minutes |
| Dev environment only | ~$150 (85%) | Ongoing |

**Best approach**: Weekend shutdown + spot instances = **60-70% cost savings**

---

**🎉 With these scripts, you can save $100-150/month while keeping restoration under 30 minutes!** 