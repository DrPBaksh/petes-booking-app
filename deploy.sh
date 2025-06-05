#!/bin/bash

# Pete's Booking App - One Command Deploy Script
# This script deploys the entire application to AWS

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
            brew install jq
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            sudo apt-get update && sudo apt-get install -y jq
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
        npm install --production
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
    
    info "Deploying CloudFormation stack: $STACK_NAME"
    
    # Deploy the stack
    aws cloudformation deploy \
        --template-file cloudformation/infrastructure.yaml \
        --stack-name $STACK_NAME \
        --parameter-overrides Environment=$ENVIRONMENT \
        --capabilities CAPABILITY_NAMED_IAM \
        --region $AWS_REGION
    
    if [ $? -eq 0 ]; then
        success "CloudFormation stack deployed successfully"
    else
        error "Failed to deploy CloudFormation stack"
        exit 1
    fi
    
    # Get stack outputs
    info "Retrieving stack outputs..."
    export API_URL=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' \
        --output text \
        --region $AWS_REGION)
    
    export BUCKET_NAME=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
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
    info "S3 Bucket: $BUCKET_NAME"
}

# Update Lambda functions with actual code
update_lambda_functions() {
    header "Updating Lambda Functions"
    
    # Update bookings function
    info "Updating bookings Lambda function..."
    aws lambda update-function-code \
        --function-name $BOOKINGS_FUNCTION \
        --zip-file fileb://.deploy/lambda/bookings.zip \
        --region $AWS_REGION > /dev/null
    
    # Update meetings function
    info "Updating meetings Lambda function..."
    aws lambda update-function-code \
        --function-name $MEETINGS_FUNCTION \
        --zip-file fileb://.deploy/lambda/meetings.zip \
        --region $AWS_REGION > /dev/null
    
    # Update admin function
    info "Updating admin Lambda function..."
    aws lambda update-function-code \
        --function-name $ADMIN_FUNCTION \
        --zip-file fileb://.deploy/lambda/admin.zip \
        --region $AWS_REGION > /dev/null
    
    success "All Lambda functions updated"
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

# Create S3 bucket for frontend hosting (optional)
setup_frontend_hosting() {
    header "Setting up Frontend Hosting"
    
    # Create a unique bucket name for frontend
    FRONTEND_BUCKET="${STACK_NAME}-frontend-${AWS_ACCOUNT_ID}-${ENVIRONMENT}"
    
    info "Creating S3 bucket for frontend hosting: $FRONTEND_BUCKET"
    
    # Create bucket
    aws s3 mb s3://$FRONTEND_BUCKET --region $AWS_REGION 2>/dev/null || true
    
    # Configure bucket for static website hosting
    aws s3 website s3://$FRONTEND_BUCKET \
        --index-document index.html \
        --error-document index.html
    
    # Upload frontend
    aws s3 cp .deploy/frontend/index.html s3://$FRONTEND_BUCKET/index.html \
        --content-type "text/html"
    
    # Make bucket public for website hosting
    cat > .deploy/bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::$FRONTEND_BUCKET/*"
        }
    ]
}
EOF
    
    aws s3api put-bucket-policy \
        --bucket $FRONTEND_BUCKET \
        --policy file://.deploy/bucket-policy.json
    
    # Get website URL
    export WEBSITE_URL="http://${FRONTEND_BUCKET}.s3-website-${AWS_REGION}.amazonaws.com"
    
    success "Frontend deployed to S3"
    info "Website URL: $WEBSITE_URL"
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

# Admin Configuration
ADMIN_PASSWORD=Skiing12!
EOF
    
    success "Environment file created: .env"
}

# Initialize with sample data
initialize_sample_data() {
    header "Initializing Sample Data"
    
    info "Creating sample meeting..."
    
    # Create a sample meeting
    curl -X POST "$API_URL/meetings" \
        -H "Content-Type: application/json" \
        -H "X-Admin-Password: Skiing12!" \
        -d '{
            "title": "Welcome Meeting",
            "description": "Introduction to Pete'\''s Booking System",
            "date": "'$(date -d "+7 days" +%Y-%m-%d)'",
            "time": "14:00",
            "duration": 60,
            "location": "Conference Room A",
            "minAttendees": 1,
            "maxAttendees": 10
        }' > /dev/null 2>&1
    
    success "Sample meeting created"
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
    echo "║               One Command Deployment                         ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    check_prerequisites
    prepare_lambda_packages
    deploy_infrastructure
    update_lambda_functions
    prepare_frontend
    setup_frontend_hosting
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
    echo -e "   • Frontend deployed to S3 bucket"
    echo -e "   • All AWS resources provisioned"
    
    echo -e "\n${YELLOW}💡 Tips:${NC}"
    echo -e "   • All configuration is stored in the .env file"
    echo -e "   • The frontend automatically connects to your API"
    echo -e "   • Admin password is 'Skiing12!' (configurable in CloudFormation)"
    echo -e "   • Data is stored in S3 bucket: $BUCKET_NAME"
    
    echo -e "\n${GREEN}✨ Your Pete's Booking App is ready to use! ✨${NC}\n"
}

# Run the main function
main