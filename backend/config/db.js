const mongoose = require('mongoose');

const connectDB = async () => {
    try {
        const conn = await mongoose.connect(process.env.MONGO_URI);

        console.log(`MongoDB Connected: ${conn.connection.host}`);

        await dropLegacyIndexes();
    } catch (error) {
        console.error("Database connection failed:", error.message);
        process.exit(1);
    }
};

// One-shot cleanup of stale unique indexes that older deploys created
// and that now block valid writes. Add new entries here whenever a
// model's index definition changes incompatibly. Failures are
// swallowed because the indexes may not exist on a fresh DB.
async function dropLegacyIndexes() {
    // Old chatrooms index — { participants: 1, job: 1 } unique. Now
    // that direct (job-less) rooms exist, two different direct rooms
    // sharing a participant collide on the (userId, null) multikey
    // entry. App-level findOne-before-create gives us the uniqueness
    // we need without an index, so just drop the legacy one if present.
    const ChatRoom = require('../models/chatModel');
    try {
        await ChatRoom.collection.dropIndex('participants_1_job_1');
        console.log('Dropped legacy chatrooms participants_1_job_1 index.');
    } catch (e) {
        if (e && e.codeName !== 'IndexNotFound') {
            console.warn('dropLegacyIndexes (chatrooms):', e.message);
        }
    }
}

module.exports = connectDB;