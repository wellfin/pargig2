const { S3Client } = require('@aws-sdk/client-s3');

/**
 * S3 storage for user uploads (job photos, voice notes, profile photos,
 * KYC documents).
 *
 * Uploads used to land on the EC2 box's own disk under /uploads. That
 * works until it doesn't: the files die with the instance, don't survive a
 * redeploy that rebuilds the machine, aren't shared if a second instance
 * is ever added, and grow the root volume until it fills.
 *
 * Credentials come from the environment only — never from source. The
 * bucket is optional: with the variables unset the app falls back to disk
 * storage, so local development needs no AWS account.
 */

const bucket = (process.env.AWS_S3_BUCKET || '').trim();
const region = (process.env.AWS_REGION || '').trim();
const accessKeyId = (process.env.AWS_ACCESS_KEY_ID || '').trim();
const secretAccessKey = (process.env.AWS_SECRET_ACCESS_KEY || '').trim();

/** True only when every piece needed to talk to S3 is present. */
const isEnabled = Boolean(bucket && region && accessKeyId && secretAccessKey);

/**
 * Where objects are publicly readable from.
 *
 * Defaults to the bucket's own virtual-hosted endpoint. Set
 * AWS_S3_PUBLIC_BASE to serve through CloudFront or a custom domain — the
 * URL is stored on the document, so changing this later does NOT rewrite
 * the rows already written.
 */
const publicBase = (process.env.AWS_S3_PUBLIC_BASE || '').trim().replace(/\/+$/, '') ||
  (isEnabled ? `https://${bucket}.s3.${region}.amazonaws.com` : '');

/**
 * Object ACLs are rejected outright by buckets created since April 2023
 * (Object Ownership = "Bucket owner enforced"), which is the default —
 * sending acl:'public-read' there fails every upload with
 * AccessControlListNotSupported. Public read belongs in a bucket policy
 * instead, so no ACL is sent unless this is explicitly turned on.
 */
const acl = (process.env.AWS_S3_ACL || '').trim();

const s3Client = isEnabled
  ? new S3Client({
      region,
      credentials: { accessKeyId, secretAccessKey },
    })
  : null;

module.exports = { s3Client, bucket, region, isEnabled, publicBase, acl };
