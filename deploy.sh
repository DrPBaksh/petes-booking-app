#!/bin/bash

# Pete's Booking App - Enhanced Deployment Script with CloudFront
# This script deploys the entire application to AWS with robust error handling

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
MAX_RETRIES=3

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

# Function to retry commands
retry() {
    local retries=$1
    shift
    local count=0
    until "$@"; do
        exit=$?
        wait=$((2 ** count))
        count=$((count + 1))
        if [ $count -lt $retries ]; then
            warning "Command failed. Retrying in ${wait}s... (attempt $count/$retries)"
            sleep $wait
        else
            error "Command failed after $retries attempts."
            return $exit
        fi
    done
    return 0
}

# Function to check if stack exists
stack_exists() {
    aws cloudformation describe-stacks --stack-name "$1" --region "$REGION" > /dev/null 2>&1
}

# Function to wait for stack operation to complete
wait_for_stack() {
    local stack_name=$1
    local operation=$2
    
    info "Waiting for stack $operation to complete..."
    
    while true; do
        local status=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --query 'Stacks[0].StackStatus' \
            --output text \
            --region "$REGION" 2>/dev/null || echo "NOT_FOUND")
        
        case $status in
            *_COMPLETE)
                success "Stack $operation completed successfully"
                return 0
                ;;
            *_FAILED|*ROLLBACK_COMPLETE)
                error "Stack $operation failed with status: $status"
                return 1
                ;;
            DELETE_IN_PROGRESS)
                info "Stack deletion in progress..."
                sleep 10
                ;;
            *_IN_PROGRESS)
                info "Stack operation in progress (status: $status)..."
                sleep 15
                ;;
            NOT_FOUND)
                if [ "$operation" = "deletion" ]; then
                    success "Stack deleted successfully"
                    return 0
                else
                    warning "Stack not found"
                    return 1
                fi
                ;;
            *)
                info "Current status: $status"
                sleep 10
                ;;
        esac
    done
}

# Function to clean up failed stack
cleanup_failed_stack() {
    if stack_exists "$STACK_NAME"; then
        local status=$(aws cloudformation describe-stacks \
            --stack-name "$STACK_NAME" \
            --query 'Stacks[0].StackStatus' \
            --output text \
            --region "$REGION")
        
        if [[ "$status" == *"FAILED"* ]] || [[ "$status" == "ROLLBACK_COMPLETE" ]]; then
            warning "Found failed stack with status: $status. Cleaning up..."
            aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION"
            wait_for_stack "$STACK_NAME" "deletion"
        fi
    fi
}

# Check prerequisites
check_prerequisites() {
    header "Checking Prerequisites"
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Installing it..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            brew install jq 2>/dev/null || {
                error "Failed to install jq via brew. Please install manually."
                exit 1
            }
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            sudo apt-get update && sudo apt-get install -y jq 2>/dev/null || {
                error "Failed to install jq. Please install manually."
                exit 1
            }
        else
            error "Please install jq manually and run the script again."
            exit 1
        fi
    fi
    
    # Check if zip is available
    if ! command -v zip &> /dev/null; then
        error "zip command is not available. Please install it."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Get AWS account ID and region
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_REGION=${AWS_REGION:-$REGION}
    
    success "Prerequisites check passed"
    info "AWS Account ID: $AWS_ACCOUNT_ID"
    info "AWS Region: $AWS_REGION"
}

# Prepare Lambda deployment packages
prepare_lambda_packages() {
    header "Preparing Lambda Deployment Packages"
    
    # Create temp directory for lambda packages
    mkdir -p .deploy/lambda
    
    # Install Lambda dependencies
    cd lambda
    if [ -f package.json ]; then
        info "Installing Lambda dependencies..."
        retry $MAX_RETRIES npm install --production
    fi
    cd ..
    
    # Create deployment packages for each Lambda function
    for lambda_file in lambda/*.js; do
        if [ -f "$lambda_file" ]; then
            lambda_name=$(basename "$lambda_file" .js)
            info "Creating deployment package for $lambda_name..."
            
            # Create a temporary directory for this lambda
            mkdir -p ".deploy/lambda/$lambda_name"
            
            # Copy the lambda file and dependencies
            cp "$lambda_file" ".deploy/lambda/$lambda_name/"
            if [ -d "lambda/node_modules" ]; then
                cp -r lambda/node_modules ".deploy/lambda/$lambda_name/"
            fi
            if [ -f "lambda/package.json" ]; then
                cp lambda/package.json ".deploy/lambda/$lambda_name/"
            fi
            
            # Create ZIP file
            cd ".deploy/lambda/$lambda_name"
            zip -r "../${lambda_name}.zip" . > /dev/null
            cd ../../..
            
            success "Created ${lambda_name}.zip"
        fi
    done
}

# Deploy CloudFormation stack
deploy_infrastructure() {
    header "Deploying AWS Infrastructure"
    
    # Clean up any failed stacks first
    cleanup_failed_stack
    
    info "Deploying CloudFormation stack: $STACK_NAME"
    
    # Deploy the stack with retry
    retry $MAX_RETRIES aws cloudformation deploy \
        --template-file cloudformation/infrastructure.yaml \
        --stack-name $STACK_NAME \
        --parameter-overrides Environment=$ENVIRONMENT \
        --capabilities CAPABILITY_NAMED_IAM \
        --region $AWS_REGION
    
    if [ $? -eq 0 ]; then
        success "CloudFormation stack deployed successfully"
    else
        error "Failed to deploy CloudFormation stack"
        
        # Show stack events on failure
        if stack_exists "$STACK_NAME"; then
            warning "Showing recent stack events..."
            aws cloudformation describe-stack-events \
                --stack-name $STACK_NAME \
                --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
                --output table \
                --region $AWS_REGION 2>/dev/null || true
        fi
        exit 1
    fi
    
    # Get stack outputs
    info "Retrieving stack outputs..."
    export API_URL=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' \
        --output text \
        --region $AWS_REGION)
    
    export CLOUDFRONT_URL=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontUrl`].OutputValue' \
        --output text \
        --region $AWS_REGION)
    
    export BUCKET_NAME=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
        --output text \
        --region $AWS_REGION)
    
    export FRONTEND_BUCKET=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`FrontendBucketName`].OutputValue' \
        --output text \
        --region $AWS_REGION)
    
    export BOOKINGS_FUNCTION=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`BookingsFunctionName`].OutputValue' \
        --output text \
        --region $AWS_REGION)
    
    export MEETINGS_FUNCTION=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`MeetingsFunctionName`].OutputValue' \
        --output text \
        --region $AWS_REGION)
    
    export ADMIN_FUNCTION=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`AdminFunctionName`].OutputValue' \
        --output text \
        --region $AWS_REGION)
    
    success "Stack outputs retrieved"
    info "API URL: $API_URL"
    info "CloudFront URL: $CLOUDFRONT_URL"
    info "Data Bucket: $BUCKET_NAME"
    info "Frontend Bucket: $FRONTEND_BUCKET"
}

# Update Lambda functions with actual code
update_lambda_functions() {
    header "Updating Lambda Functions"
    
    # Update bookings function
    info "Updating bookings Lambda function..."
    retry $MAX_RETRIES aws lambda update-function-code \
        --function-name $BOOKINGS_FUNCTION \
        --zip-file fileb://.deploy/lambda/bookings.zip \
        --region $AWS_REGION > /dev/null
    
    # Update meetings function
    info "Updating meetings Lambda function..."
    retry $MAX_RETRIES aws lambda update-function-code \
        --function-name $MEETINGS_FUNCTION \
        --zip-file fileb://.deploy/lambda/meetings.zip \
        --region $AWS_REGION > /dev/null
    
    # Update admin function
    info "Updating admin Lambda function..."
    retry $MAX_RETRIES aws lambda update-function-code \
        --function-name $ADMIN_FUNCTION \
        --zip-file fileb://.deploy/lambda/admin.zip \
        --region $AWS_REGION > /dev/null
    
    success "All Lambda functions updated"
    
    # Wait for functions to be ready
    info "Waiting for Lambda functions to be ready..."
    sleep 10
}

# Prepare frontend with API URL
prepare_frontend() {
    header "Preparing Frontend"
    
    # Create a copy of the frontend with the API URL injected
    mkdir -p .deploy/frontend
    
    # Replace the API URL placeholder in the frontend
    sed "s|%API_BASE_URL%|$API_URL|g" frontend/index.html > .deploy/frontend/index.html
    
    success "Frontend prepared with API URL: $API_URL"
}

# Deploy frontend to S3 and CloudFront
deploy_frontend() {
    header "Deploying Frontend to CloudFront"
    
    info "Uploading frontend to S3 bucket: $FRONTEND_BUCKET"
    
    # Upload frontend with proper content type and caching headers
    retry $MAX_RETRIES aws s3 cp .deploy/frontend/index.html s3://$FRONTEND_BUCKET/index.html \
        --content-type "text/html" \
        --cache-control "max-age=300" \
        --region $AWS_REGION
    
    success "Frontend uploaded to S3"
    
    # Get CloudFront distribution ID
    local DISTRIBUTION_ID=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontUrl`].OutputValue' \
        --output text \
        --region $AWS_REGION | sed 's|https://||' | sed 's|\.cloudfront\.net||')
    
    if [ ! -z "$DISTRIBUTION_ID" ] && [ "$DISTRIBUTION_ID" != "None" ]; then
        info "Creating CloudFront invalidation..."
        local INVALIDATION_ID=$(aws cloudfront create-invalidation \
            --distribution-id $DISTRIBUTION_ID \
            --paths "/*" \
            --query 'Invalidation.Id' \
            --output text 2>/dev/null || echo "failed")
        
        if [ "$INVALIDATION_ID" != "failed" ]; then
            success "CloudFront invalidation created: $INVALIDATION_ID"
            info "Frontend will be available at: $CLOUDFRONT_URL"
        else
            warning "Could not create CloudFront invalidation"
        fi
    else
        warning "Could not determine CloudFront distribution ID"
    fi
    
    export WEBSITE_URL=$CLOUDFRONT_URL
    success "Frontend deployed to CloudFront"
}

# Test Lambda function functionality
test_lambda_functions() {
    header "Testing Lambda Functions"
    
    info "Testing meetings Lambda function..."
    
    # Test creating a meeting
    local test_response=$(curl -s -X POST "$API_URL/meetings" \
        -H "Content-Type: application/json" \
        -H "X-Admin-Password: Skiing12!" \
        -d '{
            "title": "Test Meeting",
            "description": "Deployment test meeting",
            "date": "'$(date -d "+7 days" +%Y-%m-%d 2>/dev/null || date -v+7d +%Y-%m-%d 2>/dev/null || echo "2025-06-15")'",
            "time": "14:00",
            "duration": 60,
            "location": "Test Room",
            "minAttendees": 1,
            "maxAttendees": 5
        }' 2>/dev/null || echo '{"error":"Failed to connect"}')
    
    if echo "$test_response" | grep -q "Meeting created successfully"; then
        success "Lambda functions are working correctly"
        info "Test meeting created successfully"
    else
        warning "Lambda function test failed or returned unexpected response"
        info "Response: $test_response"
    fi
}

# Create environment file
create_env_file() {
    header "Creating Environment Configuration"
    
    cat > .env << EOF
# Pete's Booking App Environment Configuration
# Generated on $(date)

# AWS Configuration
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID

# Stack Information
STACK_NAME=$STACK_NAME
ENVIRONMENT=$ENVIRONMENT

# API Configuration
API_BASE_URL=$API_URL

# S3 Configuration
DATA_BUCKET_NAME=$BUCKET_NAME
FRONTEND_BUCKET_NAME=$FRONTEND_BUCKET

# Lambda Functions
BOOKINGS_FUNCTION_NAME=$BOOKINGS_FUNCTION
MEETINGS_FUNCTION_NAME=$MEETINGS_FUNCTION
ADMIN_FUNCTION_NAME=$ADMIN_FUNCTION

# Frontend
WEBSITE_URL=$WEBSITE_URL
CLOUDFRONT_URL=$CLOUDFRONT_URL

# Admin Configuration
ADMIN_PASSWORD=Skiing12!
EOF
    
    success "Environment file created: .env"
}

# Initialize with sample data
initialize_sample_data() {
    header "Initializing Sample Data"
    
    info "Creating welcome meeting..."
    
    # Wait a moment for the API to be ready
    sleep 5
    
    # Create a sample meeting with proper error handling
    local sample_date=$(date -d "+7 days" +%Y-%m-%d 2>/dev/null || date -v+7d +%Y-%m-%d 2>/dev/null || echo "2025-06-15")
    
    local response=$(curl -s -w "%{http_code}" -X POST "$API_URL/meetings" \
        -H "Content-Type: application/json" \
        -H "X-Admin-Password: Skiing12!" \
        -d "{
            \"title\": \"Welcome to Pete's Booking System\",
            \"description\": \"Introduction meeting for new users\",
            \"date\": \"$sample_date\",
            \"time\": \"14:00\",
            \"duration\": 60,
            \"location\": \"Main Conference Room\",
            \"minAttendees\": 1,
            \"maxAttendees\": 10
        }")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [ "$http_code" = "201" ]; then
        success "Sample meeting created successfully"
    else
        warning "Could not create sample meeting (HTTP: $http_code)"
        info "API may need a moment to initialize"
    fi
}

# Cleanup temporary files
cleanup() {
    header "Cleaning Up"
    
    rm -rf .deploy
    
    success "Cleanup completed"
}

# Main deployment function
main() {
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                   Pete's Booking App                         ║"
    echo "║         Professional CloudFront Deployment                   ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    check_prerequisites
    prepare_lambda_packages
    deploy_infrastructure
    update_lambda_functions
    prepare_frontend
    deploy_frontend
    test_lambda_functions
    create_env_file
    initialize_sample_data
    cleanup
    
    echo -e "\n${GREEN}🎉 DEPLOYMENT SUCCESSFUL! 🎉${NC}\n"
    
    echo -e "${BLUE}📋 Application Details:${NC}"
    echo -e "   • Website URL: ${GREEN}$WEBSITE_URL${NC}"
    echo -e "   • API URL: ${GREEN}$API_URL${NC}"
    echo -e "   • Admin Password: ${GREEN}Skiing12!${NC}"
    echo -e "   • Environment: ${GREEN}$ENVIRONMENT${NC}"
    echo -e "   • AWS Region: ${GREEN}$AWS_REGION${NC}"
    
    echo -e "\n${BLUE}🚀 Quick Start:${NC}"
    echo -e "   1. Open your browser and go to: ${GREEN}$WEBSITE_URL${NC}"
    echo -e "   2. Book a meeting by entering your email"
    echo -e "   3. Click 'Admin Panel' and use password: ${GREEN}Skiing12!${NC}"
    echo -e "   4. Create new meetings and manage bookings"
    echo -e "   5. Export data as CSV from the admin panel"
    
    echo -e "\n${BLUE}📁 Files Created:${NC}"
    echo -e "   • ${GREEN}.env${NC} - Environment configuration"
    echo -e "   • Frontend deployed to CloudFront CDN"
    echo -e "   • All AWS resources provisioned"
    
    echo -e "\n${BLUE}🧹 Cleanup:${NC}"
    echo -e "   • Run ${GREEN}./cleanup.sh${NC} to remove all AWS resources"
    echo -e "   • Run ${GREEN}./deploy.sh${NC} again to redeploy if needed"
    
    echo -e "\n${BLUE}✨ Features:${NC}"
    echo -e "   • Professional black/white design with green accents"
    echo -e "   • CloudFront CDN for global performance"
    echo -e "   • Fixed Lambda functions with AWS SDK v3"
    echo -e "   • Real-time meeting booking and management"
    
    echo -e "\n${GREEN}✨ Your Pete's Booking App is ready to use! ✨${NC}\n"
}

# Handle script interruption
trap 'error "Deployment interrupted"; cleanup; exit 1' INT TERM

# Run the main function
main