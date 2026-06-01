// Dump workArea + currentLocation for every user — used to verify
// they're not being silently stripped by save().
require('dotenv').config();
const mongoose = require('mongoose');

(async () => {
  await mongoose.connect(process.env.MONGO_URI);
  const users = await mongoose.connection
    .collection('users')
    .find({})
    .sort({ updatedAt: -1 })
    .toArray();

  for (const u of users) {
    console.log(`\n--- ${u.mobile}  ${u.name || '(no name)'}  updated=${u.updatedAt?.toISOString?.()?.slice(0, 19)} ---`);
    console.log('  workArea        :', u.workArea === undefined ? '❌ FIELD MISSING' : JSON.stringify(u.workArea));
    console.log('  currentLocation :', u.currentLocation === undefined ? '❌ FIELD MISSING' : JSON.stringify(u.currentLocation));
    console.log('  workAreaLabel   :', u.workAreaLabel);
    console.log('  currentLocLabel :', u.currentLocationLabel);
  }
  await mongoose.connection.close();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
