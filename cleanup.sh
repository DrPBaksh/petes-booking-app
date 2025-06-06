#!/bin/bash

# Pete's Booking App - Enhanced Cleanup Script
# This script removes all AWS resources including CloudFront distribution

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STACK_NAME="petes-booking-app"
ENVIRONMENT="dev"
REGION="us-east-1"

# Functions for colored output
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

header() {
    echo -e "\n${BLUE}🚀 $1${NC}\n"
}

# Function to check if stack exists
stack_exists() {
    aws cloudformation describe-stacks --stack-name "$1" --region "$REGION" > /dev/null 2>&1
}

# Function to wait for stack deletion
wait_for_stack_deletion() {
    local stack_name=$1
    
    info "Waiting for stack deletion to complete..."
    
    while stack_exists "$stack_name"; do
        local status=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --query 'Stacks[0].StackStatus' \
            --output text \
            --region "$REGION" 2>/dev/null || echo "NOT_FOUND")
        
        case $status in
            DELETE_COMPLETE)
                success "Stack deleted successfully"
                return 0
                ;;
            DELETE_FAILED)
                error "Stack deletion failed"
                return 1
                ;;
            DELETE_IN_PROGRESS)
                info "Stack deletion in progress..."
                sleep 15
                ;;
            NOT_FOUND)
                success "Stack not found (already deleted)"
                return 0
                ;;
            *)
                info "Current status: $status"
                sleep 10
                ;;
        esac
    done
    
    success "Stack deleted successfully"
    return 0
}

# Function to wait for CloudFront distribution deletion
wait_for_cloudfront_deletion() {
    local distribution_id=$1
    
    if [ -z "$distribution_id" ] || [ "$distribution_id" = "None" ]; then
        return 0
    fi
    
    info "Waiting for CloudFront distribution deletion to complete..."
    
    while true; do
        local status=$(aws cloudfront get-distribution \
            --id "$distribution_id" \
            --query 'Distribution.Status' \
            --output text 2>/dev/null || echo "NOT_FOUND")
        
        case $status in
            "NOT_FOUND")
                success "CloudFront distribution deleted"
                return 0
                ;;
            "InProgress")
                info "CloudFront distribution deletion in progress..."
                sleep 30
                ;;
            *)
                info "CloudFront status: $status"
                sleep 20
                ;;
        esac
    done
}

# Function to empty and delete S3 buckets
cleanup_s3_buckets() {
    header "Cleaning Up S3 Buckets"
    
    # Get AWS Account ID
    local AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
    
    # List of potential bucket names (both old and new patterns)
    local buckets=(
        "petes-booking-data-${ENVIRONMENT}-${AWS_ACCOUNT_ID}"
        "petes-booking-frontend-${ENVIRONMENT}-${AWS_ACCOUNT_ID}"
        "${STACK_NAME}-frontend-${AWS_ACCOUNT_ID}-${ENVIRONMENT}"
    )
    
    for bucket in "${buckets[@]}"; do
        if aws s3api head-bucket --bucket "$bucket" --region "$REGION" 2>/dev/null; then
            info "Found bucket: $bucket"
            
            # Empty the bucket first
            info "Emptying bucket contents..."
            aws s3 rm s3://"$bucket" --recursive 2>/dev/null || {
                warning "Could not empty bucket $bucket (may already be empty)"
            }
            
            # Delete bucket versioning objects if any
            info "Removing versioned objects..."
            aws s3api list-object-versions --bucket "$bucket" --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null | \
            while read key version_id; do
                if [ -n "$key" ] && [ -n "$version_id" ] && [ "$key" != "None" ] && [ "$version_id" != "None" ]; then
                    aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version_id" 2>/dev/null || true
                fi
            done
            
            # Delete delete markers
            aws s3api list-object-versions --bucket "$bucket" --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null | \
            while read key version_id; do
                if [ -n "$key" ] && [ -n "$version_id" ] && [ "$key" != "None" ] && [ "$version_id" != "None" ]; then
                    aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version_id" 2>/dev/null || true
                fi
            done
            
            success "Bucket $bucket emptied"
        else
            info "Bucket $bucket not found (may already be deleted)"
        fi
    done
}

# Function to disable and delete CloudFront distribution
cleanup_cloudfront() {
    header "Cleaning Up CloudFront Distribution"
    
    # Try to get CloudFront distribution from stack outputs first
    local CLOUDFRONT_URL=""
    if stack_exists "$STACK_NAME"; then
        CLOUDFRONT_URL=$(aws cloudformation describe-stacks \
            --stack-name $STACK_NAME \
            --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontUrl`].OutputValue' \
            --output text \
            --region $REGION 2>/dev/null || echo "")
    fi
    
    if [ -n "$CLOUDFRONT_URL" ] && [ "$CLOUDFRONT_URL" != "None" ]; then
        # Extract distribution ID from URL
        local DISTRIBUTION_ID=$(echo "$CLOUDFRONT_URL" | sed 's|https://||' | sed 's|\.cloudfront\.net||')
        
        if [ -n "$DISTRIBUTION_ID" ]; then
            info "Found CloudFront distribution: $DISTRIBUTION_ID"
            
            # Get current distribution config
            local ETAG=$(aws cloudfront get-distribution \
                --id "$DISTRIBUTION_ID" \
                --query 'ETag' \
                --output text 2>/dev/null || echo "")
            
            if [ -n "$ETAG" ] && [ "$ETAG" != "None" ]; then
                info "Disabling CloudFront distribution..."
                
                # Get distribution config and disable it
                aws cloudfront get-distribution-config \
                    --id "$DISTRIBUTION_ID" \
                    --query 'DistributionConfig' \
                    --output json > /tmp/dist-config.json 2>/dev/null || {
                    warning "Could not get distribution config"
                    return
                }
                
                # Modify config to disable distribution
                jq '.Enabled = false' /tmp/dist-config.json > /tmp/dist-config-disabled.json
                
                # Update distribution
                aws cloudfront update-distribution \
                    --id "$DISTRIBUTION_ID" \
                    --distribution-config file:///tmp/dist-config-disabled.json \
                    --if-match "$ETAG" > /dev/null 2>&1 && {
                    success "CloudFront distribution disabled"
                    
                    # Wait for distribution to be disabled before stack deletion
                    info "Waiting for CloudFront distribution to be disabled..."
                    sleep 60
                } || {
                    warning "Could not disable CloudFront distribution"
                }
                
                # Clean up temp files
                rm -f /tmp/dist-config.json /tmp/dist-config-disabled.json
            fi
        fi
    else
        info "No CloudFront distribution found in stack outputs"
    fi
}

# Function to delete Lambda functions manually (in case they're not deleted by stack)
cleanup_lambda_functions() {
    header "Cleaning Up Lambda Functions"
    
    local functions=(
        "petes-booking-handler-${ENVIRONMENT}"
        "petes-meetings-handler-${ENVIRONMENT}"
        "petes-admin-handler-${ENVIRONMENT}"
    )
    
    for func in "${functions[@]}"; do
        if aws lambda get-function --function-name "$func" --region "$REGION" > /dev/null 2>&1; then
            info "Found Lambda function: $func"
            aws lambda delete-function --function-name "$func" --region "$REGION" 2>/dev/null && {
                success "Deleted Lambda function: $func"
            } || {
                warning "Could not delete Lambda function: $func"
            }
        else
            info "Lambda function $func not found (may already be deleted)"
        fi
    done
}

# Function to delete IAM roles manually (in case they're not deleted by stack)
cleanup_iam_roles() {
    header "Cleaning Up IAM Roles"
    
    local role_name="petes-booking-lambda-role-${ENVIRONMENT}"
    
    if aws iam get-role --role-name "$role_name" > /dev/null 2>&1; then
        info "Found IAM role: $role_name"
        
        # Detach managed policies
        aws iam list-attached-role-policies --role-name "$role_name" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null | \
        while read policy_arn; do
            if [ -n "$policy_arn" ] && [ "$policy_arn" != "None" ]; then
                aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" 2>/dev/null && {
                    info "Detached policy: $policy_arn"
                } || true
            fi
        done
        
        # Delete inline policies
        aws iam list-role-policies --role-name "$role_name" --query 'PolicyNames' --output text 2>/dev/null | \
        while read policy_name; do
            if [ -n "$policy_name" ] && [ "$policy_name" != "None" ]; then
                aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name" 2>/dev/null && {
                    info "Deleted inline policy: $policy_name"
                } || true
            fi
        done
        
        # Delete the role
        aws iam delete-role --role-name "$role_name" 2>/dev/null && {
            success "Deleted IAM role: $role_name"
        } || {
            warning "Could not delete IAM role: $role_name"
        }
    else
        info "IAM role $role_name not found (may already be deleted)"
    fi
}

# Function to show resources before deletion
show_resources() {
    header "Current AWS Resources"
    
    info "Checking for CloudFormation stack..."
    if stack_exists "$STACK_NAME"; then
        local status=$(aws cloudformation describe-stacks \
            --stack-name "$STACK_NAME" \
            --query 'Stacks[0].StackStatus' \
            --output text \
            --region "$REGION")
        echo "  📦 CloudFormation Stack: $STACK_NAME (Status: $status)"
        
        # Show CloudFront distribution
        local CLOUDFRONT_URL=$(aws cloudformation describe-stacks \
            --stack-name $STACK_NAME \
            --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontUrl`].OutputValue' \
            --output text \
            --region $REGION 2>/dev/null || echo "None")
        
        if [ -n "$CLOUDFRONT_URL" ] && [ "$CLOUDFRONT_URL" != "None" ]; then
            echo "  ☁️  CloudFront Distribution: $CLOUDFRONT_URL"
        fi
        
        # Show stack resources
        info "Stack resources:"
        aws cloudformation describe-stack-resources \
            --stack-name "$STACK_NAME" \
            --query 'StackResources[].[ResourceType,LogicalResourceId,ResourceStatus]' \
            --output table \
            --region "$REGION" 2>/dev/null || echo "  Could not list stack resources"
    else
        echo "  📦 CloudFormation Stack: Not found"
    fi
    
    info "Checking for S3 buckets..."
    local AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
    local buckets=(
        "petes-booking-data-${ENVIRONMENT}-${AWS_ACCOUNT_ID}"
        "petes-booking-frontend-${ENVIRONMENT}-${AWS_ACCOUNT_ID}"
        "${STACK_NAME}-frontend-${AWS_ACCOUNT_ID}-${ENVIRONMENT}"
    )
    
    for bucket in "${buckets[@]}"; do
        if aws s3api head-bucket --bucket "$bucket" --region "$REGION" 2>/dev/null; then
            local size=$(aws s3 ls s3://"$bucket" --recursive --summarize 2>/dev/null | grep "Total Size" | awk '{print $3}' || echo "unknown")
            echo "  🪣 S3 Bucket: $bucket (Size: $size bytes)"
        fi
    done
    
    info "Checking for Lambda functions..."
    local functions=(
        "petes-booking-handler-${ENVIRONMENT}"
        "petes-meetings-handler-${ENVIRONMENT}"
        "petes-admin-handler-${ENVIRONMENT}"
    )
    
    for func in "${functions[@]}"; do
        if aws lambda get-function --function-name "$func" --region "$REGION" > /dev/null 2>&1; then
            echo "  λ Lambda Function: $func"
        fi
    done
    
    echo ""
}

# Function to estimate costs saved
estimate_cost_savings() {
    header "Estimated Monthly Cost Savings"
    
    echo "  💰 CloudFront CDN: ~\$1-5/month (depending on traffic)"
    echo "  💰 API Gateway: ~\$3-10/month (depending on usage)"
    echo "  💰 Lambda Functions: ~\$0-5/month (pay per request)"
    echo "  💰 S3 Storage: ~\$0.50-2/month (depending on data size)"
    echo "  💰 CloudFormation: Free"
    echo "  💰 IAM: Free"
    echo ""
    echo "  💵 Total Estimated Savings: ~\$4.50-22/month"
    echo ""
    warning "Note: Actual costs depend on usage patterns"
}

# Main cleanup function
main() {
    echo -e "${RED}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                   Pete's Booking App                         ║"
    echo "║              Enhanced Cleanup Script                         ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    show_resources
    estimate_cost_savings
    
    # Confirmation prompt
    echo -e "${YELLOW}⚠️  This will DELETE ALL Pete's Booking App resources from AWS!${NC}"
    echo -e "${YELLOW}⚠️  Including CloudFront distribution, S3 buckets, and Lambda functions!${NC}"
    echo -e "${YELLOW}⚠️  This action CANNOT be undone!${NC}"
    echo ""
    read -p "Are you sure you want to continue? (type 'DELETE' to confirm): " confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    header "Starting Enhanced Cleanup Process"
    
    # Step 1: Disable CloudFront distribution (must be done before stack deletion)
    cleanup_cloudfront
    
    # Step 2: Empty S3 buckets (must be done before CloudFormation deletion)
    cleanup_s3_buckets
    
    # Step 3: Delete CloudFormation stack
    if stack_exists "$STACK_NAME"; then
        header "Deleting CloudFormation Stack"
        info "Deleting stack: $STACK_NAME"
        
        aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION"
        wait_for_stack_deletion "$STACK_NAME"
    else
        info "CloudFormation stack not found"
    fi
    
    # Step 4: Manual cleanup of any remaining resources
    cleanup_lambda_functions
    cleanup_iam_roles
    
    # Step 5: Clean up local files
    header "Cleaning Up Local Files"
    
    if [ -f ".env" ]; then
        rm .env
        success "Removed .env file"
    fi
    
    if [ -d ".deploy" ]; then
        rm -rf .deploy
        success "Removed .deploy directory"
    fi
    
    # Final verification
    header "Cleanup Verification"
    
    local remaining_resources=0
    
    if stack_exists "$STACK_NAME"; then
        error "CloudFormation stack still exists"
        remaining_resources=$((remaining_resources + 1))
    else
        success "CloudFormation stack deleted"
    fi
    
    # Check for remaining S3 buckets
    local AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
    local buckets=(
        "petes-booking-data-${ENVIRONMENT}-${AWS_ACCOUNT_ID}"
        "petes-booking-frontend-${ENVIRONMENT}-${AWS_ACCOUNT_ID}"
        "${STACK_NAME}-frontend-${AWS_ACCOUNT_ID}-${ENVIRONMENT}"
    )
    
    for bucket in "${buckets[@]}"; do
        if aws s3api head-bucket --bucket "$bucket" --region "$REGION" 2>/dev/null; then
            error "S3 bucket still exists: $bucket"
            remaining_resources=$((remaining_resources + 1))
        fi
    done
    
    if [ $remaining_resources -eq 0 ]; then
        echo -e "\n${GREEN}🎉 CLEANUP COMPLETED SUCCESSFULLY! 🎉${NC}\n"
        
        echo -e "${BLUE}📋 Summary:${NC}"
        echo -e "   • All Pete's Booking App resources have been removed"
        echo -e "   • CloudFront distribution deleted"
        echo -e "   • S3 buckets emptied and removed"
        echo -e "   • Lambda functions deleted"
        echo -e "   • AWS resources are no longer incurring costs"
        echo -e "   • Local configuration files cleaned up"
        
        echo -e "\n${BLUE}🚀 Next Steps:${NC}"
        echo -e "   • Run ${GREEN}./deploy.sh${NC} to redeploy the application"
        echo -e "   • The enhanced application code remains in this directory"
        echo -e "   • All deployment scripts are ready for reuse"
        echo -e "   • New deployment will include CloudFront and improved design"
        
        echo -e "\n${GREEN}✨ Cleanup completed successfully! ✨${NC}\n"
    else
        echo -e "\n${YELLOW}⚠️  CLEANUP PARTIALLY COMPLETED${NC}\n"
        
        echo -e "${YELLOW}📋 Manual Action Required:${NC}"
        echo -e "   • $remaining_resources resource(s) still exist"
        echo -e "   • Check the AWS Console for any remaining resources"
        echo -e "   • CloudFront distributions may take up to 15 minutes to delete"
        echo -e "   • Manually delete any resources that couldn't be removed"
        
        echo -e "\n${BLUE}🔍 Troubleshooting:${NC}"
        echo -e "   • CloudFront distributions take time to disable and delete"
        echo -e "   • Some resources may have dependencies"
        echo -e "   • Check CloudFormation stack events for details"
        echo -e "   • Wait a few minutes and run this script again"
        
        exit 1
    fi
}

# Handle script interruption
trap 'error "Cleanup interrupted"; exit 1' INT TERM

# Run the main function
main