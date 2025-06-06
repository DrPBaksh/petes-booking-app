#!/bin/bash

# Enhanced cleanup script for Pete's Booking App with CloudFront support
# This script safely removes all AWS resources created by the booking app

set -e

STACK_NAME="petes-booking-app"
REGION="us-east-1"

echo "🧹 Starting cleanup of Pete's Booking App resources..."

# Function to check if stack exists
check_stack_exists() {
    aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" >/dev/null 2>&1
}

# Function to wait for CloudFront distribution to be disabled
wait_for_cloudfront_disabled() {
    local distribution_id=$1
    echo "⏳ Waiting for CloudFront distribution to be disabled..."
    
    while true; do
        local status=$(aws cloudfront get-distribution --id "$distribution_id" --query 'Distribution.Status' --output text 2>/dev/null || echo "NotFound")
        if [ "$status" = "NotFound" ]; then
            echo "✅ CloudFront distribution no longer exists"
            break
        elif [ "$status" = "Deployed" ]; then
            local enabled=$(aws cloudfront get-distribution --id "$distribution_id" --query 'Distribution.DistributionConfig.Enabled' --output text 2>/dev/null || echo "false")
            if [ "$enabled" = "false" ]; then
                echo "✅ CloudFront distribution is disabled"
                break
            fi
        fi
        echo "   Status: $status, waiting..."
        sleep 30
    done
}

# Function to disable CloudFront distribution
disable_cloudfront() {
    echo "🌐 Checking for CloudFront distribution..."
    
    # Get distribution ID from stack outputs
    local distribution_id=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionId`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$distribution_id" ] && [ "$distribution_id" != "None" ]; then
        echo "📍 Found CloudFront distribution: $distribution_id"
        
        # Get current distribution config
        local etag=$(aws cloudfront get-distribution --id "$distribution_id" --query 'ETag' --output text 2>/dev/null || echo "")
        
        if [ -n "$etag" ]; then
            echo "🚫 Disabling CloudFront distribution..."
            
            # Get current config and disable it
            aws cloudfront get-distribution-config --id "$distribution_id" > /tmp/distribution-config.json
            
            # Update the config to disable the distribution
            jq '.DistributionConfig.Enabled = false' /tmp/distribution-config.json > /tmp/distribution-config-disabled.json
            
            # Update the distribution
            aws cloudfront update-distribution \
                --id "$distribution_id" \
                --distribution-config file:///tmp/distribution-config-disabled.json \
                --if-match "$etag" >/dev/null
            
            echo "⏳ Waiting for CloudFront distribution to be disabled (this may take 10-15 minutes)..."
            wait_for_cloudfront_disabled "$distribution_id"
            
            # Clean up temp files
            rm -f /tmp/distribution-config.json /tmp/distribution-config-disabled.json
        fi
    else
        echo "ℹ️  No CloudFront distribution found in stack"
    fi
}

# Function to empty S3 buckets
empty_s3_buckets() {
    echo "🪣 Emptying S3 buckets..."
    
    # Get bucket names from stack
    local website_bucket=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`WebsiteBucket`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    local logs_bucket=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontLogsBucket`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    # Empty website bucket
    if [ -n "$website_bucket" ] && [ "$website_bucket" != "None" ]; then
        echo "🗑️  Emptying website bucket: $website_bucket"
        aws s3 rm "s3://$website_bucket" --recursive 2>/dev/null || echo "   Bucket already empty or doesn't exist"
    fi
    
    # Empty logs bucket
    if [ -n "$logs_bucket" ] && [ "$logs_bucket" != "None" ]; then
        echo "🗑️  Emptying CloudFront logs bucket: $logs_bucket"
        aws s3 rm "s3://$logs_bucket" --recursive 2>/dev/null || echo "   Bucket already empty or doesn't exist"
    fi
}

# Function to delete CloudWatch logs
cleanup_logs() {
    echo "📊 Cleaning up CloudWatch logs..."
    
    # Delete log groups for Lambda functions
    for function in "BookingFunction" "AdminFunction"; do
        local log_group="/aws/lambda/petes-booking-app-$function"
        if aws logs describe-log-groups --log-group-name-prefix "$log_group" --region "$REGION" --query 'logGroups[0]' --output text >/dev/null 2>&1; then
            echo "🗑️  Deleting log group: $log_group"
            aws logs delete-log-group --log-group-name "$log_group" --region "$REGION" 2>/dev/null || echo "   Log group already deleted"
        fi
    done
}

# Main cleanup process
main() {
    # Check if stack exists
    if ! check_stack_exists; then
        echo "ℹ️  Stack '$STACK_NAME' not found. Nothing to clean up."
        exit 0
    fi
    
    echo "📍 Found stack '$STACK_NAME' in region '$REGION'"
    
    # Disable CloudFront distribution first (this takes the longest)
    disable_cloudfront
    
    # Empty S3 buckets
    empty_s3_buckets
    
    # Clean up CloudWatch logs
    cleanup_logs
    
    # Delete the CloudFormation stack
    echo "🗑️  Deleting CloudFormation stack..."
    aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION"
    
    echo "⏳ Waiting for stack deletion to complete..."
    aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION"
    
    echo "✅ Cleanup completed successfully!"
    echo ""
    echo "📋 Summary of cleaned up resources:"
    echo "   • CloudFront distribution (disabled and deleted)"
    echo "   • S3 buckets (emptied and deleted)"
    echo "   • Lambda functions (deleted)"
    echo "   • API Gateway (deleted)"
    echo "   • DynamoDB table (deleted)"
    echo "   • IAM roles and policies (deleted)"
    echo "   • CloudWatch logs (deleted)"
    echo ""
    echo "🎉 Pete's Booking App has been completely removed from your AWS account."
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v aws >/dev/null 2>&1; then
        missing_deps+=("aws-cli")
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        missing_deps+=("jq")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "❌ Missing required dependencies: ${missing_deps[*]}"
        echo "Please install the missing dependencies and try again."
        exit 1
    fi
}

# Check dependencies first
check_dependencies

# Confirm with user
echo "⚠️  This will permanently delete all Pete's Booking App resources from AWS."
echo "   This action cannot be undone!"
echo ""
read -p "Are you sure you want to continue? (yes/no): " -r
echo ""

if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    main
else
    echo "❌ Cleanup cancelled."
    exit 1
fi