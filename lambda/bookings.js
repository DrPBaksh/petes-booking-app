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

// Get all bookings (admin only)
async function getAllBookings(event) {
    if (!validateAdminPassword(event)) {
        return {
            statusCode: 401,
            headers: corsHeaders,
            body: JSON.stringify({ error: 'Invalid admin password' })
        };
    }

    try {
        const bookings = await getS3Data('bookings.json') || [];
        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify(bookings)
        };
    } catch (error) {
        console.error('Error getting bookings:', error);
        return {
            statusCode: 500,
            headers: corsHeaders,
            body: JSON.stringify({ error: 'Failed to get bookings' })
        };
    }
}

// Create a new booking
async function createBooking(event) {
    try {
        const { email, meetingId } = JSON.parse(event.body);
        
        if (!email || !meetingId) {
            return {
                statusCode: 400,
                headers: corsHeaders,
                body: JSON.stringify({ error: 'Email and meetingId are required' })
            };
        }

        // Validate email format
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailRegex.test(email)) {
            return {
                statusCode: 400,
                headers: corsHeaders,
                body: JSON.stringify({ error: 'Invalid email format' })
            };
        }

        // Get existing bookings and meetings
        const bookings = await getS3Data('bookings.json') || [];
        const meetings = await getS3Data('meetings.json') || [];
        
        // Find the meeting
        const meeting = meetings.find(m => m.id === meetingId);
        if (!meeting) {
            return {
                statusCode: 404,
                headers: corsHeaders,
                body: JSON.stringify({ error: 'Meeting not found' })
            };
        }

        // Check if user already booked this meeting
        const existingBooking = bookings.find(b => b.email === email && b.meetingId === meetingId);
        if (existingBooking) {
            return {
                statusCode: 400,
                headers: corsHeaders,
                body: JSON.stringify({ error: 'You have already booked this meeting' })
            };
        }

        // Count current attendees for this meeting
        const currentAttendees = bookings.filter(b => b.meetingId === meetingId).length;
        
        // Check maximum capacity
        if (meeting.maxAttendees && currentAttendees >= meeting.maxAttendees) {
            return {
                statusCode: 400,
                headers: corsHeaders,
                body: JSON.stringify({ error: 'Meeting is at maximum capacity' })
            };
        }

        // Create new booking
        const newBooking = {
            id: uuidv4(),
            email,
            meetingId,
            bookedAt: new Date().toISOString(),
            meetingTitle: meeting.title
        };

        bookings.push(newBooking);
        await saveS3Data('bookings.json', bookings);

        return {
            statusCode: 201,
            headers: corsHeaders,
            body: JSON.stringify({ 
                message: 'Thank you! An invite will be sent for this meeting nearer the event date. Thanks for submitting.',
                booking: newBooking,
                attendeeCount: currentAttendees + 1
            })
        };
    } catch (error) {
        console.error('Error creating booking:', error);
        return {
            statusCode: 500,
            headers: corsHeaders,
            body: JSON.stringify({ error: 'Failed to create booking: ' + error.message })
        };
    }
}

// Delete a booking (admin only)
async function deleteBooking(event) {
    if (!validateAdminPassword(event)) {
        return {
            statusCode: 401,
            headers: corsHeaders,
            body: JSON.stringify({ error: 'Invalid admin password' })
        };
    }

    try {
        const bookingId = event.pathParameters.id;
        const bookings = await getS3Data('bookings.json') || [];
        
        const bookingIndex = bookings.findIndex(b => b.id === bookingId);
        if (bookingIndex === -1) {
            return {
                statusCode: 404,
                headers: corsHeaders,
                body: JSON.stringify({ error: 'Booking not found' })
            };
        }

        const deletedBooking = bookings.splice(bookingIndex, 1)[0];
        await saveS3Data('bookings.json', bookings);

        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify({ 
                message: 'Booking deleted successfully',
                deletedBooking
            })
        };
    } catch (error) {
        console.error('Error deleting booking:', error);
        return {
            statusCode: 500,
            headers: corsHeaders,
            body: JSON.stringify({ error: 'Failed to delete booking' })
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
                return await getAllBookings(event);
            case 'POST':
                return await createBooking(event);
            case 'DELETE':
                return await deleteBooking(event);
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