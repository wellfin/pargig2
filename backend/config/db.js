const mongoose = require('mongoose');

/**
 * Refuse to start if the models are built on a different Mongoose.
 *
 * require('mongoose') resolves from the CALLING file's folder upwards.
 * A stray node_modules anywhere under backend/ — one `npm i` run from
 * inside the wrong directory is enough — gives the files beside it
 * their own copy of the library. connect() then opens a real
 * connection on this file's instance, while every model sits on the
 * other one with no connection at all.
 *
 * The symptom is the worst kind: the server prints "MongoDB
 * Connected", looks healthy, and then every single query buffers for
 * ten seconds and fails with a timeout that reads like the database
 * is down. It is not. The database was never asked.
 *
 * So it is checked here, before the connection, and it exits rather
 * than warns — a server that answers nothing is not usefully up.
 */
function assertOneMongoose() {
    const User = require('../models/userModel');
    if (User.base === mongoose) return;

    console.error('\nThe models are using a different copy of Mongoose than');
    console.error('this file is. Every query would buffer and time out after');
    console.error('ten seconds, while the server still reported a healthy');
    console.error('connection.\n');
    console.error('  this file :', require.resolve('mongoose'));
    console.error('  the models: a second copy, usually backend/models/node_modules\n');
    console.error('Find the stray tree and remove it:\n');
    console.error('  find backend -name node_modules -type d -prune\n');
    console.error('Only backend/node_modules belongs there. Any folder without');
    console.error('its own package.json beside it is the stray one.\n');
    process.exit(1);
}

const connectDB = async () => {
    try {
        assertOneMongoose();

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