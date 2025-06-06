#!/bin/bash

# Enhanced deployment script for Pete's Booking App with CloudFront
# This script deploys the complete serverless booking application

set -e

STACK_NAME="petes-booking-app"
REGION="us-east-1"
TEMPLATE_FILE="infrastructure/cloudformation.yaml"

echo "🚀 Deploying Pete's Booking App to AWS"
echo "   Stack: $STACK_NAME"
echo "   Region: $REGION"
echo ""

# Function to check if stack exists
check_stack_exists() {
    aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" >/dev/null 2>&1
}

# Function to delete stack if in ROLLBACK_COMPLETE state
handle_rollback_complete() {
    local status=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].StackStatus' \
        --output text 2>/dev/null || echo "NONE")
    
    if [ "$status" = "ROLLBACK_COMPLETE" ]; then
        echo "⚠️  Stack is in ROLLBACK_COMPLETE state. Deleting it first..."
        aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION"
        
        echo "⏳ Waiting for stack deletion to complete..."
        aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION"
        echo "✅ Previous stack deleted successfully"
    fi
}

# Function to deploy CloudFormation stack
deploy_stack() {
    echo "📋 Deploying CloudFormation stack..."
    
    # Handle any existing rollback state
    if check_stack_exists; then
        handle_rollback_complete
    fi
    
    # Deploy the stack
    if check_stack_exists; then
        echo "🔄 Updating existing stack..."
        aws cloudformation deploy \
            --template-file "$TEMPLATE_FILE" \
            --stack-name "$STACK_NAME" \
            --region "$REGION" \
            --capabilities CAPABILITY_IAM \
            --no-fail-on-empty-changeset
    else
        echo "🆕 Creating new stack..."
        aws cloudformation deploy \
            --template-file "$TEMPLATE_FILE" \
            --stack-name "$STACK_NAME" \
            --region "$REGION" \
            --capabilities CAPABILITY_IAM
    fi
}

# Function to get stack outputs
get_stack_outputs() {
    echo "📊 Retrieving stack outputs..."
    
    local outputs=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs' \
        --output json)
    
    echo "$outputs" | jq -r '.[] | "\(.OutputKey): \(.OutputValue)"'
}

# Function to upload website files
upload_website_files() {
    echo "📁 Uploading website files to S3..."
    
    # Get the S3 bucket name from stack outputs
    local bucket_name=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`WebsiteBucket`].OutputValue' \
        --output text)
    
    if [ -z "$bucket_name" ]; then
        echo "❌ Could not retrieve S3 bucket name from stack outputs"
        return 1
    fi
    
    echo "   Bucket: $bucket_name"
    
    # Get API Gateway URL for the frontend
    local api_url=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`APIGatewayURL`].OutputValue' \
        --output text)
    
    # Create a temporary directory for processed files
    mkdir -p .deploy
    cp -r frontend/* .deploy/
    
    # Update the API URL in the frontend files
    if [ -n "$api_url" ]; then
        echo "   Updating API URL in frontend: $api_url"
        # Update the API URL in index.html and admin.html
        sed -i.bak "s|https://your-api-id.execute-api.us-east-1.amazonaws.com/prod|$api_url|g" .deploy/index.html || true
        sed -i.bak "s|https://your-api-id.execute-api.us-east-1.amazonaws.com/prod|$api_url|g" .deploy/admin.html || true
        rm -f .deploy/*.bak
    fi
    
    # Upload files to S3
    aws s3 sync .deploy/ "s3://$bucket_name" \
        --delete \
        --region "$REGION" \
        --exclude "*.bak"
    
    # Clean up
    rm -rf .deploy
    
    echo "✅ Website files uploaded successfully"
}

# Function to wait for CloudFront distribution
wait_for_cloudfront() {
    echo "🌐 Waiting for CloudFront distribution to deploy..."
    
    # Get CloudFront distribution ID
    local distribution_id=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionId`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$distribution_id" ]; then
        echo "   Distribution ID: $distribution_id"
        echo "   This may take 10-15 minutes..."
        
        # Wait for deployment (with timeout)
        local attempts=0
        local max_attempts=60  # 30 minutes max
        
        while [ $attempts -lt $max_attempts ]; do
            local status=$(aws cloudfront get-distribution \
                --id "$distribution_id" \
                --query 'Distribution.Status' \
                --output text 2>/dev/null || echo "Unknown")
            
            if [ "$status" = "Deployed" ]; then
                echo "✅ CloudFront distribution is ready!"
                break
            fi
            
            echo "   Status: $status (attempt $((attempts + 1))/$max_attempts)"
            sleep 30
            attempts=$((attempts + 1))
        done
        
        if [ $attempts -eq $max_attempts ]; then
            echo "⚠️  CloudFront distribution is still deploying. It will be ready soon."
        fi
    fi
}

# Main deployment process
main() {
    # Check dependencies
    if ! command -v aws >/dev/null 2>&1; then
        echo "❌ AWS CLI is required but not installed."
        exit 1
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        echo "❌ jq is required but not installed."
        exit 1
    fi
    
    # Check if template file exists
    if [ ! -f "$TEMPLATE_FILE" ]; then
        echo "❌ CloudFormation template not found: $TEMPLATE_FILE"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        echo "❌ AWS credentials not configured or invalid."
        echo "   Run: aws configure"
        exit 1
    fi
    
    echo "✅ Prerequisites check passed"
    echo ""
    
    # Deploy the infrastructure
    deploy_stack
    
    # Upload website files
    upload_website_files
    
    # Wait for CloudFront (optional, runs in background)
    wait_for_cloudfront &
    
    echo ""
    echo "🎉 Deployment completed successfully!"
    echo ""
    echo "📋 Application URLs:"
    get_stack_outputs
    echo ""
    echo "🔗 Quick Access:"
    
    # Get URLs for easy access
    local cloudfront_url=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontURL`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    local s3_url=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`WebsiteURL`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$cloudfront_url" ]; then
        echo "   🌍 Public Booking: $cloudfront_url"
        echo "   🔧 Admin Panel:   $cloudfront_url/admin.html"
    fi
    
    if [ -n "$s3_url" ]; then
        echo "   📦 S3 Direct:     $s3_url"
    fi
    
    echo ""
    echo "⚡ Your booking application is now live!"
    echo "   • CloudFront distribution may take 10-15 minutes to fully deploy"
    echo "   • S3 website URL is available immediately"
    echo "   • Test the booking system and admin panel"
    echo ""
    echo "🧹 To remove everything: ./scripts/cleanup.sh"
}

# Run main function
main "$@"