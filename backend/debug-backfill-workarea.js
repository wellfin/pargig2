// One-shot backfill — make sure every user has the full subdoc shape
// (type / coordinates / address / city / state / pincode / label) on
// location, workArea, and currentLocation. Safe to re-run: each $set
// is guarded by a presence filter so we never overwrite existing data.
//
// Run with:  node debug-backfill-workarea.js

require('dotenv').config();
const mongoose = require('mongoose');
const User = require('./models/userModel');

async function main() {
  await mongoose.connect(process.env.MONGO_URI);

  const blankGeo = {
    type: 'Point',
    coordinates: [0, 0],
    address: '',
    city: '',
    state: '',
    pincode: '',
    label: '',
  };

  // 1) Backfill the WHOLE subdoc for users where it's completely missing.
  const r1 = await User.collection.updateMany(
    { workArea: { $exists: false } },
    { $set: { workArea: blankGeo } },
  );
  const r2 = await User.collection.updateMany(
    { currentLocation: { $exists: false } },
    { $set: { currentLocation: { ...blankGeo, updatedAt: null } } },
  );
  const r3 = await User.collection.updateMany(
    { location: { $exists: false } },
    { $set: { location: blankGeo } },
  );
  console.log(`whole-subdoc backfill: workArea ${r1.modifiedCount}, currentLocation ${r2.modifiedCount}, location ${r3.modifiedCount}`);

  // 2) Backfill INDIVIDUAL missing sub-fields on users that already have
  //    the parent subdoc but are missing the new fields (label, address
  //    parts). $set with $exists:false is the safe per-field guard.
  const subFields = ['address', 'city', 'state', 'pincode', 'label'];
  for (const subdoc of ['location', 'workArea', 'currentLocation']) {
    for (const field of subFields) {
      const path = `${subdoc}.${field}`;
      const res = await User.collection.updateMany(
        { [subdoc]: { $exists: true }, [path]: { $exists: false } },
        { $set: { [path]: '' } },
      );
      if (res.modifiedCount > 0) {
        console.log(`  + ${path}: ${res.modifiedCount} users updated`);
      }
    }
  }

  // 3) Verify.
  const total = await User.countDocuments({});
  const withWa = await User.countDocuments({ 'workArea.label': { $exists: true } });
  const withCl = await User.countDocuments({ 'currentLocation.label': { $exists: true } });
  const withLoc = await User.countDocuments({ 'location.label': { $exists: true } });
  console.log(`\ntotal users                  = ${total}`);
  console.log(`with workArea.label          = ${withWa}`);
  console.log(`with currentLocation.label   = ${withCl}`);
  console.log(`with location.label          = ${withLoc}`);

  await mongoose.connection.close();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
