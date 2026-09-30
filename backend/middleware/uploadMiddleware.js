const multer = require('multer');
const multerS3 = require('multer-s3');
const path = require('path');
const fs = require('fs');

const { s3Client, bucket, isEnabled, publicBase, acl } = require('../config/s3');

// Everything lands under one prefix so a bucket policy can grant public
// read to exactly these objects and nothing else.
const KEY_PREFIX = 'uploads';

const uploadDir = path.join(__dirname, '..', 'uploads');
if (!isEnabled && !fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}

/** Collision-proof name, keeping the extension so content type sniffing
 *  and "save as" both behave. */
const filenameFor = (file) => {
  const unique = Date.now() + '-' + Math.round(Math.random() * 1e9);
  return unique + path.extname(file.originalname || '');
};

const diskStorage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, uploadDir),
  filename: (req, file, cb) => cb(null, filenameFor(file)),
});

const s3Storage = isEnabled
  ? multerS3({
      s3: s3Client,
      bucket,
      // Without this every object is stored as application/octet-stream,
      // which makes browsers download photos instead of showing them and
      // stops the mobile player from streaming voice notes at all.
      contentType: multerS3.AUTO_CONTENT_TYPE,
      // Long cache: keys are unique per upload, so a stored object is
      // never replaced and can safely be cached forever.
      cacheControl: 'public, max-age=31536000, immutable',
      // multer-s3 defaults opts.acl to 'private' when omitted, and still
      // puts an x-amz-acl header on every PUT. Buckets with ACLs disabled
      // ("Bucket owner enforced" — the default since April 2023) reject
      // requests carrying one. Returning undefined drops the header
      // entirely, which both ACL-enabled and ACL-disabled buckets accept.
      acl: acl || ((req, file, cb) => cb(null, undefined)),
      key: (req, file, cb) => cb(null, `${KEY_PREFIX}/${filenameFor(file)}`),
    })
  : null;

const upload = multer({
  storage: s3Storage || diskStorage,
  limits: { fileSize: 10 * 1024 * 1024 },
});

/**
 * The public URL for a just-uploaded file, whichever backend stored it.
 *
 * S3 gives an absolute URL; disk gives a host-relative /uploads/ path.
 * Both are safe to hand to the clients as-is — every call site in the
 * mobile app and admin panel already passes absolute URLs through
 * untouched and only prefixes the API host onto relative ones.
 */
const fileUrl = (file) => {
  if (!file) return null;
  if (isEnabled) {
    // publicBase wins so a CloudFront/custom domain is honoured; file.location
    // is multer-s3's own bucket URL and is the fallback.
    return file.key ? `${publicBase}/${file.key}` : file.location;
  }
  return `/uploads/${file.filename}`;
};

module.exports = upload;
module.exports.upload = upload;
module.exports.fileUrl = fileUrl;
module.exports.isS3 = isEnabled;
