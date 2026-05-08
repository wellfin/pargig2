const calculatePlatformFee = (amount, freeJobsRemaining = 0) => {
  if (freeJobsRemaining > 0) return 0;
  const flat = parseFloat(process.env.PLATFORM_FEE_FLAT || '10');
  const pct = parseFloat(process.env.PLATFORM_FEE_PERCENT || '5');
  return Math.max(flat, (amount * pct) / 100);
};

module.exports = { calculatePlatformFee };
