const { S3Client, GetObjectCommand, PutObjectCommand } = require('@aws-sdk/client-s3');
const { v4: uuidv4 } = require('uuid');

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

// Helper function to save data to S3
async function saveS3Data(key, data) {
    const command = new PutObjectCommand({
        Bucket: BUCKET_NAME,
        Key: key,
        Body: JSON.stringify(data, null, 2),
        ContentType: 'application/json'
    });
    await s3Client.send(command);
}

// Validate admin password
function validateAdminPassword(event) {
    const password = event.headers?.['x-admin-password'] || 
                    event.headers?.['X-Admin-Password'] ||
                    (event.body ? JSON.parse(event.body).password : null);
    return password === ADMIN_PASSWORD;
}

// Get attendee count for each meeting
async function getAttendeeCountsForMeetings(meetings) {
    try {
        const bookings = await getS3Data('bookings.json') || [];
        
        return meetings.map(meeting => {
            const attendeeCount = bookings.filter(b => b.meetingId === meeting.id).length;
            return {
                ...meeting,
                currentAttendees: attendeeCount,
                spotsRemaining: meeting.maxAttendees ? meeting.maxAttendees - attendeeCount : null
            };
        });
    } catch (error) {
        console.error('Error getting attendee counts:', error);
        return meetings.map(meeting => ({
            ...meeting,
            currentAttendees: 0,
            spotsRemaining: meeting.maxAttendees || null
        }));
    }
}

// Get all meetings with attendee counts
async function getAllMeetings() {
    try {
        const meetings = await getS3Data('meetings.json') || [];
        const meetingsWithCounts = await getAttendeeCountsForMeetings(meetings);
        
        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify(meetingsWithCounts)
        };
    } catch (error) {
        console.error('Error getting meetings:', error);
        return {
            statusCode: 500,
            headers: corsHeaders,
            body: JSON.stringify({ error: 'Failed to get meetings' })
        };
    }
}

// Create a new meeting (admin only)
async function createMeeting(event) {
    if (!validateAdminPassword(event)) {
        return {
            statusCode: 401,
            headers: corsHeaders,
            body: JSON.stringify({ error: 'Invalid admin password' })
        };
    }

    try {
        const { title, description, date, time, duration, minAttendees, maxAttendees, location } = JSON.parse(event.body);
        
        // Validate required fields
        if (!title || !date || !time || !duration) {
            return {
                statusCode: 400,
                headers: corsHeaders,
                body: JSON.stringify({ 
                    error: 'Title, date, time, and duration are required' 
                })
            };
        }

        // Validate duration format (should be in minutes)
        if (isNaN(duration) || duration <= 0) {
            return {
                statusCode: 400,
                headers: corsHeaders,
                body: JSON.stringify({ 
                    error: 'Duration must be a positive number (in minutes)' 
                })
            };
        }

        // Validate min/max attendees
        if (minAttendees && maxAttendees && minAttendees > maxAttendees) {
            return {
                statusCode: 400,
                headers: corsHeaders,
                body: JSON.stringify({ 
                    error: 'Minimum attendees cannot be greater than maximum attendees' 
                })
            };
        }

        // Validate date format
        const meetingDate = new Date(`${date}T${time}`);
        if (isNaN(meetingDate.getTime())) {
            return {
                statusCode: 400,
                headers: corsHeaders,
                body: JSON.stringify({ 
                    error: 'Invalid date or time format' 
                })
            };
        }

        const meetings = await getS3Data('meetings.json') || [];
        
        // Create new meeting
        const newMeeting = {
            id: uuidv4(),
            title: title.trim(),
            description: description?.trim() || '',
            date,
            time,
            duration: parseInt(duration),
            minAttendees: minAttendees ? parseInt(minAttendees) : null,
            maxAttendees: maxAttendees ? parseInt(maxAttendees) : null,
            location: location?.trim() || '',
            createdAt: new Date().toISOString(),
            currentAttendees: 0
        };

        meetings.push(newMeeting);
        await saveS3Data('meetings.json', meetings);

        return {
            statusCode: 201,
            headers: corsHeaders,
            body: JSON.stringify({ 
                message: 'Meeting created successfully',
                meeting: newMeeting
            })
        };
    } catch (error) {
        console.error('Error creating meeting:', error);
        return {
            statusCode: 500,
            headers: corsHeaders,
            body: JSON.stringify({ error: 'Failed to create meeting: ' + error.message })
        };
    }
}

// Delete a meeting (admin only)
async function deleteMeeting(event) {
    if (!validateAdminPassword(event)) {
        return {
            statusCode: 401,
            headers: corsHeaders,
            body: JSON.stringify({ error: 'Invalid admin password' })
        };
    }

    try {
        const meetingId = event.pathParameters?.id;
        if (!meetingId) {
            return {
                statusCode: 400,
                headers: corsHeaders,
                body: JSON.stringify({ error: 'Meeting ID is required' })
            };
        }

        const meetings = await getS3Data('meetings.json') || [];
        const bookings = await getS3Data('bookings.json') || [];
        
        const meetingIndex = meetings.findIndex(m => m.id === meetingId);
        if (meetingIndex === -1) {
            return {
                statusCode: 404,
                headers: corsHeaders,
                body: JSON.stringify({ error: 'Meeting not found' })
            };
        }

        // Remove the meeting
        const deletedMeeting = meetings.splice(meetingIndex, 1)[0];
        
        // Remove all bookings for this meeting
        const updatedBookings = bookings.filter(b => b.meetingId !== meetingId);
        const removedBookingsCount = bookings.length - updatedBookings.length;

        // Save updated data
        await Promise.all([
            saveS3Data('meetings.json', meetings),
            saveS3Data('bookings.json', updatedBookings)
        ]);

        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify({ 
                message: 'Meeting deleted successfully',
                deletedMeeting,
                removedBookingsCount
            })
        };
    } catch (error) {
        console.error('Error deleting meeting:', error);
        return {
            statusCode: 500,
            headers: corsHeaders,
            body: JSON.stringify({ error: 'Failed to delete meeting' })
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
        switch (event.httpMethod) {
            case 'GET':
                return await getAllMeetings();
            case 'POST':
                return await createMeeting(event);
            case 'DELETE':
                return await deleteMeeting(event);
            default:
                return {
                    statusCode: 405,
                    headers: corsHeaders,
                    body: JSON.stringify({ error: 'Method not allowed' })
                };
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