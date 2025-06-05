# 🚀 Quick Start Guide

Get Pete's Booking Page running in under 5 minutes!

## ⚡ One-Command Setup

```bash
git clone https://github.com/DrPBaksh/petes-booking-app.git
cd petes-booking-app
chmod +x deploy.sh
./deploy.sh
```

## 📋 Prerequisites Checklist

- [ ] AWS CLI installed and configured
- [ ] AWS credentials with admin permissions
- [ ] Node.js installed (for Lambda dependencies)
- [ ] Basic terminal access

## 🎯 What the Deploy Script Does

1. **Checks Prerequisites** - Validates AWS CLI, credentials, etc.
2. **Builds Lambda Packages** - Installs dependencies and creates ZIP files
3. **Deploys Infrastructure** - Creates all AWS resources via CloudFormation
4. **Updates Functions** - Uploads actual Lambda code
5. **Configures Frontend** - Injects API URLs and deploys to S3
6. **Creates Sample Data** - Adds a demo meeting to get you started

## 🌐 After Deployment

You'll see output like this:

```
🎉 DEPLOYMENT SUCCESSFUL! 🎉

📋 Application Details:
   • Website URL: http://your-bucket.s3-website-us-east-1.amazonaws.com
   • API URL: https://abcd1234.execute-api.us-east-1.amazonaws.com/dev
   • Admin Password: Skiing12!
   • Environment: dev
   • AWS Region: us-east-1
```

## 📱 Using Your App

### For Users (Booking Meetings)
1. Open the Website URL
2. Browse available meetings
3. Enter your email and click "Book"
4. Get instant confirmation

### For Admins (Managing Meetings)
1. Click "Admin Panel" tab
2. Enter password: `Skiing12!`
3. Create new meetings with the form
4. View booking statistics
5. Export data as CSV
6. Remove attendees if needed

## 🔧 Common Commands

```bash
# Check deployment status
aws cloudformation describe-stacks --stack-name petes-booking-app

# View Lambda function logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/petes

# Update just the Lambda code (after making changes)
cd lambda && zip ../bookings.zip bookings.js package.json node_modules/
aws lambda update-function-code --function-name petes-booking-handler-dev --zip-file fileb://../bookings.zip
```

## 🗂️ File Structure

```
petes-booking-app/
├── 📁 cloudformation/     # AWS infrastructure
├── 📁 lambda/            # Backend functions
├── 📁 frontend/          # React application
├── deploy.sh             # One-command deployment
├── .env                  # Generated configuration
└── README.md            # Full documentation
```

## 🎨 Customization

### Change Admin Password
1. Edit `cloudformation/infrastructure.yaml`
2. Update the `ADMIN_PASSWORD` environment variable
3. Redeploy: `./deploy.sh`

### Modify Colors/Design
1. Edit `frontend/index.html`
2. Update CSS variables and styles
3. Redeploy: `./deploy.sh`

### Add Features
1. Modify Lambda functions in `lambda/` directory
2. Update CloudFormation if new resources needed
3. Redeploy: `./deploy.sh`

## ❌ Troubleshooting

### "AWS credentials not configured"
```bash
aws configure
# Enter your AWS Access Key ID, Secret, Region, and Output format
```

### "Permission denied" on deploy.sh
```bash
chmod +x deploy.sh
```

### "Stack already exists" error
```bash
# Delete existing stack first
aws cloudformation delete-stack --stack-name petes-booking-app
# Wait for deletion to complete, then redeploy
./deploy.sh
```

### Frontend shows "Failed to load meetings"
- Check the API URL in your browser's console
- Verify Lambda functions deployed correctly
- Check CloudWatch logs for errors

## 🆘 Need Help?

1. **Check the logs**: CloudWatch logs for each Lambda function
2. **Verify resources**: AWS Console → CloudFormation → petes-booking-app
3. **Test API**: Use the API URL directly in your browser
4. **Check .env**: All your configuration is saved there

## 🎯 Next Steps

- **Share your URL** with potential meeting attendees
- **Create meetings** using the admin panel
- **Monitor usage** via AWS CloudWatch
- **Export data** regularly for backup
- **Customize design** to match your brand

---

**🎉 That's it! Your professional booking system is live!**

For detailed documentation, see [README.md](README.md)