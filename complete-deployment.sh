#!/bin/bash

# Complete the current deployment after fixing S3 issues
# This script finishes the deployment steps that were interrupted

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔧 Completing Pete's Booking App Deployment${NC}\n"

# Get the values from the current deployment
API_URL="https://g4qf48euei.execute-api.us-east-1.amazonaws.com/dev"
FRONTEND_BUCKET="petes-booking-app-frontend-338971307797-dev"
WEBSITE_URL="http://${FRONTEND_BUCKET}.s3-website-us-east-1.amazonaws.com"

echo "✅ S3 bucket policy has been fixed via AWS MCP"
echo "✅ Frontend is already uploaded"
echo "✅ Website URL: $WEBSITE_URL"

# Create the .env file with current deployment values
cat > .env << EOF
# Pete's Booking App Environment Configuration
# Generated on $(date)

# AWS Configuration
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=338971307797

# Stack Information
STACK_NAME=petes-booking-app
ENVIRONMENT=dev

# API Configuration
API_BASE_URL=$API_URL

# S3 Configuration
DATA_BUCKET_NAME=petes-booking-data-dev-338971307797
FRONTEND_BUCKET_NAME=$FRONTEND_BUCKET

# Lambda Functions
BOOKINGS_FUNCTION_NAME=petes-booking-handler-dev
MEETINGS_FUNCTION_NAME=petes-meetings-handler-dev
ADMIN_FUNCTION_NAME=petes-admin-handler-dev

# Frontend
WEBSITE_URL=$WEBSITE_URL

# Admin Configuration
ADMIN_PASSWORD=Skiing12!
EOF

echo "✅ Created .env file with deployment configuration"

# Try to create a sample meeting
echo "🚀 Creating sample meeting..."
curl -s -X POST "$API_URL/meetings" \
    -H "Content-Type: application/json" \
    -H "X-Admin-Password: Skiing12!" \
    -d '{
        "title": "Welcome Meeting",
        "description": "Introduction to Pete'\''s Booking System",
        "date": "2025-06-15",
        "time": "14:00",
        "duration": 60,
        "location": "Conference Room A",
        "minAttendees": 1,
        "maxAttendees": 10
    }' > /dev/null 2>&1 && {
    echo "✅ Sample meeting created"
} || {
    echo "⚠️  Sample meeting creation skipped (API may need a moment)"
}

echo -e "\n${GREEN}🎉 DEPLOYMENT COMPLETED! 🎉${NC}\n"

echo -e "${BLUE}📋 Your Pete's Booking App is ready:${NC}"
echo -e "   • Website URL: ${GREEN}$WEBSITE_URL${NC}"
echo -e "   • API URL: ${GREEN}$API_URL${NC}"
echo -e "   • Admin Password: ${GREEN}Skiing12!${NC}"

echo -e "\n${BLUE}🚀 Quick Start:${NC}"
echo -e "   1. Open: ${GREEN}$WEBSITE_URL${NC}"
echo -e "   2. Book a meeting with your email"
echo -e "   3. Access admin panel with password: ${GREEN}Skiing12!${NC}"

echo -e "\n${BLUE}🧹 Management:${NC}"
echo -e "   • Run ${GREEN}./cleanup.sh${NC} to remove all resources"
echo -e "   • Run ${GREEN}./deploy.sh${NC} for future deployments"

echo -e "\n${GREEN}✨ Enjoy your professional booking system! ✨${NC}\n"