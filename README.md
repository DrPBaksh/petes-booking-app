# 🏥 Pete's Booking App

A **professional, modern booking application** built with AWS serverless architecture. Perfect for healthcare practices, consultations, or any appointment-based business.

![AWS](https://img.shields.io/badge/AWS-232F3E?style=for-the-badge&logo=amazon-aws&logoColor=white)
![CloudFront](https://img.shields.io/badge/CloudFront-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white)
![Lambda](https://img.shields.io/badge/Lambda-FF9900?style=for-the-badge&logo=aws-lambda&logoColor=white)
![DynamoDB](https://img.shields.io/badge/DynamoDB-4053D6?style=for-the-badge&logo=amazon-dynamodb&logoColor=white)

## ✨ Features

### 🎯 **Core Functionality**
- **Smart Booking System**: Real-time availability checking with conflict prevention
- **Professional Design**: Clean, modern interface with responsive layout
- **Admin Dashboard**: Comprehensive booking management and analytics
- **Global CDN**: CloudFront distribution for lightning-fast worldwide access

### 🛡️ **Enterprise Ready**
- **Serverless Architecture**: Auto-scaling, pay-per-use AWS infrastructure
- **High Availability**: Multi-AZ deployment with 99.99% uptime SLA
- **Security First**: IAM roles, API Gateway throttling, and secure data handling
- **Professional Domain**: Custom CloudFront distribution ready for your domain

### 📊 **Advanced Features**
- **Real-time Updates**: Instant booking confirmations and conflict detection
- **Analytics Dashboard**: Booking trends and performance metrics
- **Mobile Optimized**: Fully responsive design for all devices
- **Easy Deployment**: One-command deployment with comprehensive cleanup

## 🚀 Quick Start

### Prerequisites
- AWS CLI configured with appropriate permissions
- Node.js 18+ (for local development)
- `jq` installed (for cleanup script)

### 🔥 One-Command Deployment

```bash
# Clone the repository
git clone https://github.com/DrPBaksh/petes-booking-app.git
cd petes-booking-app

# Make scripts executable
chmod +x scripts/*.sh

# Deploy everything
./scripts/deploy.sh
```

That's it! 🎉 Your app will be live with a CloudFront URL in ~10 minutes.

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   CloudFront    │    │   API Gateway   │    │   Lambda Fns    │
│   (Global CDN)  │───▶│  (REST API)     │───▶│ (Node.js 18.x)  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   S3 Bucket     │    │   CloudWatch    │    │   DynamoDB      │
│  (Static Web)   │    │    (Logs)       │    │ (Bookings DB)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 📦 What Gets Deployed

### **Infrastructure**
- **CloudFront Distribution**: Global CDN with custom domain support
- **S3 Bucket**: Static website hosting with proper CORS
- **API Gateway**: RESTful API with throttling and caching
- **Lambda Functions**: Serverless compute (Node.js 18.x with AWS SDK v3)
- **DynamoDB Table**: NoSQL database with on-demand scaling
- **IAM Roles**: Least-privilege security policies

### **Features**
- **Public Booking Interface**: Clean, professional booking form
- **Admin Dashboard**: Comprehensive booking management
- **Real-time Validation**: Prevents double-bookings automatically
- **Responsive Design**: Works perfectly on desktop and mobile

## 🎨 Design Philosophy

The application features a **clean, professional design** optimized for:
- **User Experience**: Intuitive booking flow with clear visual feedback
- **Performance**: Optimized assets and CloudFront acceleration
- **Accessibility**: WCAG compliant with proper contrast and navigation
- **Modern Aesthetics**: Subtle gradients, clean typography, and micro-interactions

## 🔧 Configuration

### Environment Variables (Set in Lambda)
```javascript
// Automatically configured during deployment
process.env.DYNAMODB_TABLE = 'petes-booking-app-BookingsTable'
process.env.AWS_REGION = 'us-east-1'
```

### Customization Options
- **Time Slots**: Modify available booking times in `frontend/index.html`
- **Business Info**: Update contact details and services
- **Styling**: Customize colors and branding in CSS sections
- **Domain**: Point your custom domain to the CloudFront distribution

## 📚 API Reference

### Booking Endpoints
```bash
# Create a new booking
POST /bookings
{
  "name": "John Doe",
  "email": "john@example.com",
  "phone": "555-0123",
  "service": "Consultation",
  "date": "2025-06-15",
  "time": "10:00"
}

# Get all bookings (Admin)
GET /admin/bookings

# Delete a booking (Admin)
DELETE /admin/bookings/{id}
```

### Response Format
```json
{
  "success": true,
  "message": "Booking created successfully",
  "booking": {
    "id": "uuid-here",
    "name": "John Doe",
    "date": "2025-06-15",
    "time": "10:00",
    "status": "confirmed"
  }
}
```

## 🛠️ Development

### Local Development
```bash
# Install dependencies
npm install

# Run local development server
npm start

# Deploy changes
./scripts/deploy.sh
```

### Testing Lambda Functions Locally
```bash
# Test booking function
npm run test:booking

# Test admin function  
npm run test:admin
```

## 📊 Monitoring & Analytics

### CloudWatch Metrics
- **API Gateway**: Request count, latency, errors
- **Lambda**: Duration, memory usage, cold starts
- **DynamoDB**: Read/write capacity, throttles
- **CloudFront**: Cache hit ratio, origin requests

### Access Logs
- **CloudFront Logs**: Detailed visitor analytics
- **API Gateway Logs**: Request/response debugging
- **Lambda Logs**: Function execution details

## 🔒 Security Features

- **IAM Roles**: Least-privilege access for all resources
- **API Throttling**: Rate limiting to prevent abuse
- **CORS Configuration**: Secure cross-origin requests
- **Input Validation**: Sanitized user inputs
- **Encryption**: Data encrypted at rest and in transit

## 💰 Cost Optimization

### Estimated Monthly Costs (Low Traffic)
- **Lambda**: $0.20 (1M requests)
- **DynamoDB**: $1.25 (on-demand)
- **CloudFront**: $1.00 (10GB transfer)
- **API Gateway**: $3.50 (1M requests)
- **S3**: $0.50 (storage + requests)

**Total**: ~$6.45/month for typical small business usage

### Cost Scaling
- **Pay-per-use**: Only pay for actual usage
- **Auto-scaling**: Handles traffic spikes automatically
- **Free Tier**: Eligible for AWS free tier benefits

## 🧹 Cleanup

To completely remove all AWS resources:

```bash
./scripts/cleanup.sh
```

This will:
- Disable and delete CloudFront distribution
- Empty and delete S3 buckets
- Delete Lambda functions and API Gateway
- Remove DynamoDB table and all data
- Clean up IAM roles and CloudWatch logs

⚠️ **Warning**: This action is irreversible and will delete all booking data.

## 🚨 Troubleshooting

### Common Issues

**Deployment Fails**
```bash
# Check AWS credentials
aws sts get-caller-identity

# Verify region setting
aws configure get region
```

**Lambda Function Errors**
```bash
# Check logs
aws logs tail /aws/lambda/petes-booking-app-BookingFunction --follow
```

**CloudFront Not Working**
- Wait 10-15 minutes for distribution deployment
- Check S3 bucket permissions
- Verify CloudFront origin settings

### Support
- 📧 **Issues**: Open a GitHub issue
- 📖 **Documentation**: Check the `/docs` folder
- 🐛 **Bugs**: Include CloudWatch logs in reports

## 🎯 Roadmap

### Upcoming Features
- [ ] **SMS Notifications**: Twilio integration for booking confirmations
- [ ] **Calendar Integration**: Google Calendar sync
- [ ] **Payment Processing**: Stripe integration for paid bookings
- [ ] **Multi-language Support**: Internationalization
- [ ] **Advanced Analytics**: Custom dashboards and reporting

### Customization Requests
Want a feature? Open an issue with the `enhancement` label!

## 📄 License

MIT License - feel free to use this for your business or modify as needed.

## 🏆 Acknowledgments

Built with ❤️ using:
- **AWS Serverless Stack**: Lambda, API Gateway, DynamoDB, CloudFront
- **Modern Web Standards**: HTML5, CSS3, ES6+
- **Professional Design**: Clean, accessible, and responsive

---

**Ready to deploy?** Run `./scripts/deploy.sh` and you'll have a professional booking system live in minutes! 🚀

## 📞 Demo

After deployment, you'll get two URLs:
- **🌍 Public Booking**: `https://your-cloudfront-id.cloudfront.net/`
- **🔧 Admin Dashboard**: `https://your-cloudfront-id.cloudfront.net/admin.html`

*Test it out and start taking bookings immediately!*