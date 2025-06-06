const { S3Client, GetObjectCommand, PutObjectCommand } = require('@aws-sdk/client-s3');

const s3Client = new S3Client({ region: process.env.AWS_REGION || 'us-east-1' });
const BUCKET_NAME = process.env.BUCKET_NAME;
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD;

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Admin-Password',
};

// Helper function to get data from S3
async function getS3Data(key) {
    try {
        const command = new GetObjectCommand({
            Bucket: BUCKET_NAME,
            Key: key
        });
        const result = await s3Client.send(command);
        const bodyContents = await result.Body.transformToString();
        return JSON.parse(bodyContents);
    } catch (error) {
        if (error.name === 'NoSuchKey') {
            return null;
        }
        throw error;
    }
}

// Validate admin password
function validateAdminPassword(event) {
    const password = event.headers?.['x-admin-password'] || 
                    event.headers?.['X-Admin-Password'] ||
                    event.queryStringParameters?.password;
    return password === ADMIN_PASSWORD;
}

// Convert array of objects to CSV string
function arrayToCSV(data) {
    if (!data || data.length === 0) {
        return '';
    }

    const headers = Object.keys(data[0]);
    const csvContent = [
        headers.join(','),
        ...data.map(row => 
            headers.map(header => {
                const value = row[header] || '';
                // Escape commas and quotes in CSV
                if (typeof value === 'string' && (value.includes(',') || value.includes('"'))) {
                    return `"${value.replace(/"/g, '""')}"`;
                }
                return value;
            }).join(',')
        )
    ].join('\n');

    return csvContent;
}

// Generate comprehensive booking report
async function generateBookingReport() {
    try {
        const [bookings, meetings] = await Promise.all([
            getS3Data('bookings.json') || [],
            getS3Data('meetings.json') || []
        ]);

        // Create a map of meeting details for quick lookup
        const meetingMap = meetings.reduce((map, meeting) => {
            map[meeting.id] = meeting;
            return map;
        }, {});

        // Enrich bookings with meeting details
        const enrichedBookings = bookings.map(booking => {
            const meeting = meetingMap[booking.meetingId] || {};
            return {
                'Booking ID': booking.id,
                'Email': booking.email,
                'Meeting Title': meeting.title || booking.meetingTitle || 'Unknown',
                'Meeting Date': meeting.date || 'Unknown',
                'Meeting Time': meeting.time || 'Unknown',
                'Meeting Duration (minutes)': meeting.duration || 'Unknown',
                'Meeting Location': meeting.location || '',
                'Booked At': booking.bookedAt,
                'Meeting Max Attendees': meeting.maxAttendees || 'Unlimited',
                'Meeting Min Attendees': meeting.minAttendees || 'None'
            };
        });

        // Sort by booking date (most recent first)
        enrichedBookings.sort((a, b) => new Date(b['Booked At']) - new Date(a['Booked At']));

        return enrichedBookings;
    } catch (error) {
        console.error('Error generating booking report:', error);
        throw new Error('Failed to generate booking report');
    }
}

// Generate meetings summary report
async function generateMeetingsSummary() {
    try {
        const [bookings, meetings] = await Promise.all([
            getS3Data('bookings.json') || [],
            getS3Data('meetings.json') || []
        ]);

        // Calculate attendee counts for each meeting
        const attendeeCounts = bookings.reduce((counts, booking) => {
            counts[booking.meetingId] = (counts[booking.meetingId] || 0) + 1;
            return counts;
        }, {});

        // Create meetings summary
        const meetingsSummary = meetings.map(meeting => {
            const currentAttendees = attendeeCounts[meeting.id] || 0;
            const spotsRemaining = meeting.maxAttendees ? meeting.maxAttendees - currentAttendees : 'Unlimited';
            
            return {
                'Meeting ID': meeting.id,
                'Title': meeting.title,
                'Description': meeting.description || '',
                'Date': meeting.date,
                'Time': meeting.time,
                'Duration (minutes)': meeting.duration,
                'Location': meeting.location || '',
                'Current Attendees': currentAttendees,
                'Max Attendees': meeting.maxAttendees || 'Unlimited',
                'Min Attendees': meeting.minAttendees || 'None',
                'Spots Remaining': spotsRemaining,
                'Created At': meeting.createdAt,
                'Updated At': meeting.updatedAt || ''
            };
        });

        // Sort by date and time
        meetingsSummary.sort((a, b) => {
            const dateA = new Date(`${a.Date}T${a.Time}`);
            const dateB = new Date(`${b.Date}T${b.Time}`);
            return dateA - dateB;
        });

        return meetingsSummary;
    } catch (error) {
        console.error('Error generating meetings summary:', error);
        throw new Error('Failed to generate meetings summary');
    }
}

// Export bookings data as CSV
async function exportBookings(event) {
    if (!validateAdminPassword(event)) {
        return {
            statusCode: 401,
            headers: corsHeaders,
            body: JSON.stringify({ error: 'Invalid admin password' })
        };
    }

    try {
        const reportType = event.queryStringParameters?.type || 'bookings';
        let csvData;
        let filename;

        switch (reportType) {
            case 'bookings':
                const bookingReport = await generateBookingReport();
                csvData = arrayToCSV(bookingReport);
                filename = `bookings-export-${new Date().toISOString().split('T')[0]}.csv`;
                break;
            
            case 'meetings':
                const meetingsSummary = await generateMeetingsSummary();
                csvData = arrayToCSV(meetingsSummary);
                filename = `meetings-summary-${new Date().toISOString().split('T')[0]}.csv`;
                break;
            
            case 'combined':
                const [bookings, meetings] = await Promise.all([
                    generateBookingReport(),
                    generateMeetingsSummary()
                ]);
                
                const combinedData = [
                    '=== BOOKINGS REPORT ===',
                    arrayToCSV(bookings),
                    '',
                    '',
                    '=== MEETINGS SUMMARY ===',
                    arrayToCSV(meetings)
                ].join('\n');
                
                csvData = combinedData;
                filename = `complete-export-${new Date().toISOString().split('T')[0]}.csv`;
                break;
            
            default:
                return {
                    statusCode: 400,
                    headers: corsHeaders,
                    body: JSON.stringify({ 
                        error: 'Invalid report type. Use: bookings, meetings, or combined' 
                    })
                };
        }

        // Return CSV data with appropriate headers
        return {
            statusCode: 200,
            headers: {
                ...corsHeaders,
                'Content-Type': 'text/csv',
                'Content-Disposition': `attachment; filename="${filename}"`,
                'Cache-Control': 'no-cache'
            },
            body: csvData
        };

    } catch (error) {
        console.error('Error exporting data:', error);
        return {
            statusCode: 500,
            headers: corsHeaders,
            body: JSON.stringify({ error: 'Failed to export data' })
        };
    }
}

// Get admin dashboard statistics
async function getAdminStats(event) {
    if (!validateAdminPassword(event)) {
        return {
            statusCode: 401,
            headers: corsHeaders,
            body: JSON.stringify({ error: 'Invalid admin password' })
        };
    }

    try {
        const [bookings, meetings] = await Promise.all([
            getS3Data('bookings.json') || [],
            getS3Data('meetings.json') || []
        ]);

        // Calculate statistics
        const totalBookings = bookings.length;
        const totalMeetings = meetings.length;
        const uniqueAttendees = new Set(bookings.map(b => b.email)).size;
        
        // Meetings by status
        const now = new Date();
        const upcomingMeetings = meetings.filter(m => {
            const meetingDate = new Date(`${m.date}T${m.time}`);
            return meetingDate > now;
        }).length;
        
        const pastMeetings = totalMeetings - upcomingMeetings;
        
        // Most popular meetings
        const meetingBookingCounts = bookings.reduce((counts, booking) => {
            counts[booking.meetingId] = (counts[booking.meetingId] || 0) + 1;
            return counts;
        }, {});
        
        const popularMeetings = meetings
            .map(meeting => ({
                title: meeting.title,
                date: meeting.date,
                time: meeting.time,
                bookingCount: meetingBookingCounts[meeting.id] || 0
            }))
            .sort((a, b) => b.bookingCount - a.bookingCount)
            .slice(0, 5);

        // Recent bookings
        const recentBookings = bookings
            .sort((a, b) => new Date(b.bookedAt) - new Date(a.bookedAt))
            .slice(0, 10)
            .map(booking => {
                const meeting = meetings.find(m => m.id === booking.meetingId);
                return {
                    email: booking.email,
                    meetingTitle: meeting?.title || booking.meetingTitle,
                    bookedAt: booking.bookedAt
                };
            });

        const stats = {
            overview: {
                totalBookings,
                totalMeetings,
                uniqueAttendees,
                upcomingMeetings,
                pastMeetings
            },
            popularMeetings,
            recentBookings,
            lastUpdated: new Date().toISOString()
        };

        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify(stats)
        };

    } catch (error) {
        console.error('Error getting admin stats:', error);
        return {
            statusCode: 500,
            headers: corsHeaders,
            body: JSON.stringify({ error: 'Failed to get admin statistics' })
        };
    }
}

exports.handler = async (event) => {
    console.log('Event:', JSON.stringify(event, null, 2));

    // Handle CORS preflight
    if (event.httpMethod === 'OPTIONS') {
        return {
            statusCode: 200,
            headers: corsHeaders,
            body: ''
        };
    }

    try {
        const path = event.path || event.requestContext?.path || '';
        
        if (path.includes('/export')) {
            return await exportBookings(event);
        } else {
            // Default to admin stats
            return await getAdminStats(event);
        }
    } catch (error) {
        console.error('Handler error:', error);
        return {
            statusCode: 500,
            headers: corsHeaders,
            body: JSON.stringify({ error: 'Internal server error: ' + error.message })
        };
    }
};