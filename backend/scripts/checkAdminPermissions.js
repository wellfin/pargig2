/**
 * End-to-end check of admin roles, permissions and the lockout guards.
 *
 *   npm run check:permissions
 *
 * Runs the real Express app against a THROWAWAY database and drops it
 * afterwards. It never touches the configured MONGO_URI.
 *
 * What this is really testing is that the panel's hiding is not the
 * security. Every assertion below calls the endpoint directly with a
 * valid token for a role that should not have it — which is exactly
 * what someone would do with the browser devtools open.
 */
process.env.MONGO_URI =
  process.env.CHECK_MONGO_URI ||
  'mongodb://127.0.0.1:27017/pargig_permcheck_tmp';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'testsecret';
process.env.NODE_ENV = 'test';

const http = require('http');
const Admin = require('../models/adminModel');
// The models' own Mongoose instance — see scripts/checkAdminReset.js.
const mongoose = Admin.base;
const app = require('../app');
const perms = require('../utils/adminPermissions');
const generateToken = require('../utils/generateToken');

const out = [];
const ck = (l, c, d) =>
  out.push((c ? '  + ' : '  - FAIL ') + l + (d !== undefined ? ' -> ' + d : ''));

function call(port, method, path, token, body) {
  return new Promise((resolve) => {
    const data = body === undefined ? null : JSON.stringify(body);
    const headers = {};
    if (token) headers.Authorization = `Bearer ${token}`;
    if (data) {
      headers['Content-Type'] = 'application/json';
      headers['Content-Length'] = Buffer.byteLength(data);
    }
    const req = http.request({ port, path: '/api' + path, method, headers }, (res) => {
      let b = '';
      res.on('data', (c) => (b += c));
      res.on('end', () => {
        let p = {};
        try { p = JSON.parse(b || '{}'); } catch { p = { raw: b }; }
        resolve({ status: res.statusCode, body: p });
      });
    });
    if (data) req.write(data);
    req.end();
  });
}

const PW = 'x'.repeat(12);

(async () => {
  await mongoose.connect(process.env.MONGO_URI);
  await mongoose.connection.dropDatabase();

  const boss = await Admin.create({
    name: 'Boss', email: 'boss@pargig.test', password: PW, role: 'superadmin',
  });
  const sup = await Admin.create({
    name: 'Sup', email: 'sup@pargig.test', password: PW, role: 'support',
  });
  const fin = await Admin.create({
    name: 'Fin', email: 'fin@pargig.test', password: PW, role: 'finance',
  });

  const server = http.createServer(app).listen(0);
  await new Promise((r) => server.on('listening', r));
  const port = server.address().port;

  const bTok = generateToken(boss._id, 'admin');
  const sTok = generateToken(sup._id, 'admin');
  const fTok = generateToken(fin._id, 'admin');

  // ------------------------------------------------- 1. the defaults
  const meB = await call(port, 'GET', '/admin/me', bTok);
  ck('1. superadmin sees itself', meB.status === 200 && meB.body.role === 'superadmin',
    meB.status);
  ck('1. superadmin holds every permission',
    meB.body.permissions?.length === perms.ALL_KEYS.length,
    `${meB.body.permissions?.length}/${perms.ALL_KEYS.length}`);
  const roleList = await call(port, 'GET', '/admin/admins', bTok);
  ck('1. roles arrive with their label and meaning',
    roleList.body.roles.every((r) => r.key && r.label),
    roleList.body.roles.map((r) => r.key).join(','));
  ck('1. superadmin is marked built-in',
    roleList.body.roles.find((r) => r.key === 'superadmin')?.builtIn === true);

  const meS = await call(port, 'GET', '/admin/me', sTok);
  ck('1. support does NOT hold admins', !meS.body.permissions.includes('admins'));
  ck('1. support does NOT hold payment keys',
    !meS.body.permissions.includes('payment_settings'));
  ck('1. support DOES hold disputes', meS.body.permissions.includes('disputes'));

  const meF = await call(port, 'GET', '/admin/me', fTok);
  ck('1. finance holds payments', meF.body.permissions.includes('payments'));
  ck('1. finance does NOT hold disputes', !meF.body.permissions.includes('disputes'));
  // Reading the ledger and holding the keys that charge cards are
  // different jobs. The keys are superadmin-only.
  ck('1. finance does NOT hold the payment keys either',
    !meF.body.permissions.includes('payment_settings'));

  // ------------------------------------------- 2. the routes enforce
  ck('2. support can read disputes',
    (await call(port, 'GET', '/admin/issues', sTok)).status === 200);
  const finIssues = await call(port, 'GET', '/admin/issues', fTok);
  ck('2. finance is refused disputes -> 403', finIssues.status === 403, finIssues.status);
  ck('2. and told which permission it lacks',
    /disputes/i.test(finIssues.body.message || ''), finIssues.body.message);

  ck('2. finance can read payments',
    (await call(port, 'GET', '/admin/payments', fTok)).status === 200);
  ck('2. support is refused payments -> 403',
    (await call(port, 'GET', '/admin/payments', sTok)).status === 403);

  ck('2. support is refused the payment keys -> 403',
    (await call(port, 'GET', '/admin/settings/payment', sTok)).status === 403);
  ck('2. finance is refused the payment keys too -> 403',
    (await call(port, 'GET', '/admin/settings/payment', fTok)).status === 403);
  ck('2. only superadmin reaches them',
    (await call(port, 'GET', '/admin/settings/payment', bTok)).status === 200);

  ck('2. support is refused the admin list -> 403',
    (await call(port, 'GET', '/admin/admins', sTok)).status === 403);
  ck('2. finance is refused the admin list -> 403',
    (await call(port, 'GET', '/admin/admins', fTok)).status === 403);
  ck('2. superadmin can read the admin list',
    (await call(port, 'GET', '/admin/admins', bTok)).status === 200);

  ck('2. support is refused the permission grid -> 403',
    (await call(port, 'PUT', '/admin/permissions', sTok,
      { roles: [{ key: 'support', permissions: perms.GRANTABLE_KEYS }] })).status === 403);

  // --------------------------------------------- 3. editing the grid
  const permsOf = (body, key) =>
    body.roles.find((r) => r.key === key)?.permissions || [];

  const grant = await call(port, 'PUT', '/admin/permissions', bTok, {
    roles: [
      { key: 'support', label: 'Support', permissions: ['dashboard', 'disputes', 'support', 'payments'] },
      { key: 'finance', label: 'Finance', permissions: ['dashboard', 'payments'] },
    ],
  });
  ck('3. superadmin can save the grid', grant.status === 200, grant.status);
  ck('3. support gained payments', permsOf(grant.body, 'support').includes('payments'));
  ck('3. support now reaches payments -> 200',
    (await call(port, 'GET', '/admin/payments', sTok)).status === 200);
  ck('3. support lost users, so the route closes -> 403',
    (await call(port, 'GET', '/admin/users', sTok)).status === 403);
  ck('3. finance lost disputes and analytics',
    !permsOf(grant.body, 'finance').includes('analytics'));

  // The two rules that exist to stop a lockout.
  const esc = await call(port, 'PUT', '/admin/permissions', bTok, {
    roles: [
      { key: 'support', label: 'Support', permissions: ['dashboard', 'admins'] },
      { key: 'finance', label: 'Finance', permissions: ['payments', 'payment_settings'] },
    ],
  });
  ck('3. "admins" CAN be delegated now',
    permsOf(esc.body, 'support').includes('admins'),
    JSON.stringify(permsOf(esc.body, 'support')));
  ck('3. so support reaches the admin list -> 200',
    (await call(port, 'GET', '/admin/admins', sTok)).status === 200);
  ck('3. the payment keys cannot be granted either',
    !permsOf(esc.body, 'finance').includes('payment_settings'),
    JSON.stringify(permsOf(esc.body, 'finance')));
  ck('3. so finance still cannot reach them -> 403',
    (await call(port, 'GET', '/admin/settings/payment', fTok)).status === 403);

  const strip = await call(port, 'PUT', '/admin/permissions', bTok, {
    roles: [
      { key: 'superadmin', label: 'Nope', permissions: [] },
      { key: 'support', label: 'Support', permissions: ['dashboard'] },
      { key: 'finance', label: 'Finance', permissions: ['payments'] },
    ],
  });
  ck('3. superadmin cannot be stripped',
    permsOf(strip.body, 'superadmin').length === perms.ALL_KEYS.length,
    permsOf(strip.body, 'superadmin').length);
  ck('3. and is not duplicated by sending it',
    strip.body.roles.filter((r) => r.key === 'superadmin').length === 1,
    strip.body.roles.filter((r) => r.key === 'superadmin').length);

  const empty = await call(port, 'PUT', '/admin/permissions', bTok, {
    roles: [
      { key: 'support', label: 'Support', permissions: [] },
      { key: 'finance', label: 'Finance', permissions: ['payments'] },
    ],
  });
  ck('3. an empty list is honoured, not read as "use the defaults"',
    permsOf(empty.body, 'support').length === 0,
    JSON.stringify(permsOf(empty.body, 'support')));
  ck('3. so support can reach nothing at all -> 403',
    (await call(port, 'GET', '/admin/issues', sTok)).status === 403);

  // ------------------------------- 3a. a delegated admin cannot climb
  //
  // support now holds `admins` from the save above, plus dashboard.
  // Everything below is the escalation that makes delegation safe or
  // not: if any one of these passes, `admins` is a synonym for
  // "everything" and the owner gave away more than they meant to.
  {
    const deleg = await call(port, 'PUT', '/admin/permissions', bTok, {
      roles: [
        { key: 'support', label: 'Support', permissions: ['dashboard', 'disputes', 'admins'] },
        { key: 'finance', label: 'Finance', permissions: ['dashboard', 'payments'] },
      ],
    });
    ck('3a. the delegate holds admins + disputes, nothing else',
      permsOf(deleg.body, 'support').sort().join(',') === 'admins,dashboard,disputes',
      permsOf(deleg.body, 'support').sort().join(','));

    // ...cannot create a superadmin.
    const mint = await call(port, 'POST', '/admin/admins', sTok, {
      name: 'Mint', email: 'mint@pargig.test', password: PW, role: 'superadmin',
    });
    ck('3a. cannot create a superadmin -> 403', mint.status === 403, mint.status);

    // ...cannot promote anyone to superadmin.
    const promote = await call(port, 'PUT', `/admin/admins/${fin._id}`, sTok, {
      role: 'superadmin',
    });
    ck('3a. cannot promote anyone to superadmin -> 403', promote.status === 403,
      promote.status);

    // ...cannot touch the owner's account, in any of the four ways.
    ck('3a. cannot edit a superadmin -> 403',
      (await call(port, 'PUT', `/admin/admins/${boss._id}`, sTok, { name: 'Hi' })).status === 403);
    ck('3a. cannot deactivate a superadmin -> 403',
      (await call(port, 'PUT', `/admin/admins/${boss._id}`, sTok, { isActive: false })).status === 403);
    ck('3a. cannot re-password a superadmin -> 403',
      (await call(port, 'PUT', `/admin/admins/${boss._id}/password`, sTok, {
        password: 'q'.repeat(14),
      })).status === 403);
    ck('3a. cannot delete a superadmin -> 403',
      (await call(port, 'DELETE', `/admin/admins/${boss._id}`, sTok)).status === 403);

    // ...cannot hand out what they do not hold.
    const climb = await call(port, 'PUT', '/admin/permissions', sTok, {
      roles: [
        { key: 'support', label: 'Support', permissions: ['dashboard', 'disputes', 'admins', 'payments', 'users'] },
        { key: 'finance', label: 'Finance', permissions: ['dashboard', 'payments'] },
      ],
    });
    ck('3a. the save is accepted', climb.status === 200, climb.status);
    ck('3a. but payments and users were not granted',
      permsOf(climb.body, 'support').sort().join(',') === 'admins,dashboard,disputes',
      permsOf(climb.body, 'support').sort().join(','));
    ck('3a. so the route stays shut -> 403',
      (await call(port, 'GET', '/admin/payments', sTok)).status === 403);

    // ...and cannot strip what they cannot see either. finance keeps
    // its payments even though the delegate does not hold it.
    const strip2 = await call(port, 'PUT', '/admin/permissions', sTok, {
      roles: [
        { key: 'support', label: 'Support', permissions: ['dashboard', 'disputes', 'admins'] },
        { key: 'finance', label: 'Finance', permissions: ['dashboard'] },
      ],
    });
    ck('3a. nor quietly remove a permission it was never shown',
      permsOf(strip2.body, 'finance').includes('payments'),
      JSON.stringify(permsOf(strip2.body, 'finance')));

    // ...and a new role it invents is capped the same way.
    const invent = await call(port, 'PUT', '/admin/permissions', sTok, {
      roles: [
        { key: 'support', label: 'Support', permissions: ['dashboard', 'disputes', 'admins'] },
        { key: 'finance', label: 'Finance', permissions: ['dashboard', 'payments'] },
        { key: 'backdoor', label: 'Backdoor', permissions: perms.ALL_KEYS },
      ],
    });
    const back = invent.body.roles.find((r) => r.key === 'backdoor');
    ck('3a. a role it invents cannot exceed it either',
      back.permissions.sort().join(',') === 'admins,dashboard,disputes',
      back.permissions.sort().join(','));

    // The grid tells the panel the same thing the server enforces.
    const grid = await call(port, 'GET', '/admin/permissions', sTok);
    ck('3a. the grid reports it is not the owner', grid.body.isOwner === false);
    ck('3a. and lists only what it may grant',
      grid.body.canGrant.sort().join(',') === 'admins,dashboard,disputes',
      grid.body.canGrant.sort().join(','));

    // What it CAN do, which is the point of delegating at all.
    const made = await call(port, 'POST', '/admin/admins', sTok, {
      name: 'Helper', email: 'helper@pargig.test', password: PW, role: 'finance',
    });
    ck('3a. but it CAN create an ordinary admin -> 201', made.status === 201,
      made.status);
    const helper = await Admin.findOne({ email: 'helper@pargig.test' });
    await call(port, 'DELETE', `/admin/admins/${helper._id}`, sTok);
    ck('3a. and delete one again',
      (await Admin.countDocuments({ email: 'helper@pargig.test' })) === 0);

    // Put it back before the rest of the run.
    await call(port, 'PUT', '/admin/permissions', bTok, {
      roles: perms.DEFAULT_ROLES,
    });
  }

  // ------------------------------------------ 3b. roles are data
  const added = await call(port, 'PUT', '/admin/permissions', bTok, {
    roles: [
      ...perms.DEFAULT_ROLES,
      {
        key: 'operations',
        label: 'Operations',
        hint: 'Jobs and verifications',
        permissions: ['dashboard', 'jobs', 'verifications'],
      },
    ],
  });
  ck('3b. a new role can be added from the panel',
    added.body.roles.some((r) => r.key === 'operations'),
    added.body.roles.map((r) => r.key).join(','));
  ck('3b. it keeps its label and meaning',
    added.body.roles.find((r) => r.key === 'operations')?.hint === 'Jobs and verifications');

  const opAdmin = await call(port, 'POST', '/admin/admins', bTok, {
    name: 'Ops', email: 'ops@pargig.test', password: PW, role: 'operations',
  });
  ck('3b. an admin can be created with it -> 201', opAdmin.status === 201,
    opAdmin.status);
  const ops = await Admin.findOne({ email: 'ops@pargig.test' });
  const oTok = generateToken(ops._id, 'admin');
  ck('3b. and it actually grants what was ticked',
    (await call(port, 'GET', '/admin/jobs', oTok)).status === 200);
  ck('3b. and nothing that was not -> 403',
    (await call(port, 'GET', '/admin/payments', oTok)).status === 403);

  const rejectUnknown = await call(port, 'POST', '/admin/admins', bTok, {
    name: 'Ghost', email: 'ghost@pargig.test', password: PW, role: 'wizard',
  });
  ck('3b. a role nobody defined is refused -> 400', rejectUnknown.status === 400,
    rejectUnknown.status);

  const deleteHeld = await call(port, 'PUT', '/admin/permissions', bTok, {
    roles: perms.DEFAULT_ROLES,
  });
  ck('3b. a role somebody holds cannot be deleted -> 400',
    deleteHeld.status === 400, deleteHeld.status);
  ck('3b. and the refusal says who is in the way',
    /operations/i.test(deleteHeld.body.message || ''), deleteHeld.body.message);

  await call(port, 'PUT', `/admin/admins/${ops._id}`, bTok, { role: 'support' });
  const deleteFree = await call(port, 'PUT', '/admin/permissions', bTok, {
    roles: perms.DEFAULT_ROLES,
  });
  ck('3b. once nobody holds it, it can be deleted', deleteFree.status === 200,
    deleteFree.status);
  ck('3b. and it is gone',
    !deleteFree.body.roles.some((r) => r.key === 'operations'),
    deleteFree.body.roles.map((r) => r.key).join(','));
  await call(port, 'DELETE', `/admin/admins/${ops._id}`, bTok);

  // Put the defaults back for the rest of the run.
  await call(port, 'PUT', '/admin/permissions', bTok, {
    roles: perms.DEFAULT_ROLES,
  });

  // ----------------------------------------- 4. creating an admin
  const bad = await call(port, 'POST', '/admin/admins', bTok, {
    name: 'Short', email: 'short@pargig.test', password: 'abc', role: 'support',
  });
  ck('4. a short password is refused -> 400', bad.status === 400, bad.status);

  const dup = await call(port, 'POST', '/admin/admins', bTok, {
    name: 'Dup', email: 'sup@pargig.test', password: PW, role: 'support',
  });
  ck('4. a duplicate email is refused -> 409', dup.status === 409, dup.status);

  const made = await call(port, 'POST', '/admin/admins', bTok, {
    name: 'New Desk', email: 'desk@pargig.test', password: PW, role: 'support',
  });
  ck('4. created -> 201', made.status === 201, made.status);
  ck('4. the password never comes back', made.body.admin?.password === undefined);
  const deskLogin = await call(port, 'POST', '/auth/admin/login', null, {
    email: 'desk@pargig.test', password: PW,
  });
  ck('4. and the new admin can actually sign in', deskLogin.status === 200,
    deskLogin.status);

  const desk = await Admin.findOne({ email: 'desk@pargig.test' });
  const dTok = generateToken(desk._id, 'admin');

  // -------------------------------------------- 5. lockout guards
  const selfRole = await call(port, 'PUT', `/admin/admins/${boss._id}`, bTok, {
    role: 'support',
  });
  ck('5. you cannot change your own role -> 400', selfRole.status === 400,
    selfRole.status);

  const selfOff = await call(port, 'PUT', `/admin/admins/${boss._id}`, bTok, {
    isActive: false,
  });
  ck('5. you cannot deactivate yourself -> 400', selfOff.status === 400,
    selfOff.status);

  const selfDel = await call(port, 'DELETE', `/admin/admins/${boss._id}`, bTok);
  ck('5. you cannot delete yourself -> 400', selfDel.status === 400, selfDel.status);

  // Promote the desk, then the last-superadmin rule should relax.
  await call(port, 'PUT', `/admin/admins/${desk._id}`, bTok, { role: 'superadmin' });
  const nowTwo = await Admin.countDocuments({ role: 'superadmin', isActive: true });
  ck('5. a second superadmin exists', nowTwo === 2, nowTwo);

  const demoteOther = await call(port, 'PUT', `/admin/admins/${desk._id}`, bTok, {
    role: 'support',
  });
  ck('5. demoting the OTHER superadmin is allowed', demoteOther.status === 200,
    demoteOther.status);

  // Back to superadmin, then try to demote the original - allowed,
  // because one other active superadmin remains.
  await call(port, 'PUT', `/admin/admins/${desk._id}`, bTok, { role: 'superadmin' });
  await call(port, 'PUT', `/admin/admins/${desk._id}`, bTok, { isActive: false });
  const lastOne = await call(port, 'PUT', `/admin/admins/${desk._id}`, bTok, {
    role: 'support',
  });
  ck('5. a DEACTIVATED superadmin may still be demoted', lastOne.status === 200,
    lastOne.status);

  // ------------------------------- 6. a deactivated admin is out now
  await call(port, 'PUT', `/admin/admins/${sup._id}`, bTok, { isActive: false });
  const deadToken = await call(port, 'GET', '/admin/issues', sTok);
  ck('6. an existing token stops working the moment the account is off -> 401',
    deadToken.status === 401, deadToken.status);
  const deadLogin = await call(port, 'POST', '/auth/admin/login', null, {
    email: 'sup@pargig.test', password: PW,
  });
  ck('6. and it cannot sign in again',
    deadLogin.status !== 200, deadLogin.status);

  await call(port, 'PUT', `/admin/admins/${sup._id}`, bTok, { isActive: true });
  ck('6. switching it back on restores access',
    (await call(port, 'GET', '/admin/issues', sTok)).status === 200);

  // ------------------------------------------- 7. password + delete
  const pwBad = await call(port, 'PUT', `/admin/admins/${sup._id}/password`, bTok, {
    password: 'short',
  });
  ck('7. a short replacement password is refused -> 400', pwBad.status === 400,
    pwBad.status);

  const pwOk = await call(port, 'PUT', `/admin/admins/${sup._id}/password`, bTok, {
    password: 'y'.repeat(14),
  });
  ck('7. superadmin can set another admin’s password', pwOk.status === 200,
    pwOk.status);
  ck('7. and the new password works',
    (await call(port, 'POST', '/auth/admin/login', null, {
      email: 'sup@pargig.test', password: 'y'.repeat(14),
    })).status === 200);
  ck('7. while the old one does not',
    (await call(port, 'POST', '/auth/admin/login', null, {
      email: 'sup@pargig.test', password: PW,
    })).status !== 200);

  ck('7. support cannot set anyone’s password -> 403',
    (await call(port, 'PUT', `/admin/admins/${fin._id}/password`, sTok, {
      password: 'z'.repeat(14),
    })).status === 403);
  // dTok belongs to the desk account, which was switched off in 5 and
  // never switched back on. It is turned away one step earlier than a
  // permission check, which is the stronger of the two answers.
  ck('7. a deactivated admin is refused before permissions are even read -> 401',
    (await call(port, 'PUT', `/admin/admins/${fin._id}/password`, dTok, {
      password: 'z'.repeat(14),
    })).status === 401);

  const del = await call(port, 'DELETE', `/admin/admins/${desk._id}`, bTok);
  ck('7. superadmin can delete another admin', del.status === 200, del.status);
  ck('7. and it is gone', (await Admin.countDocuments({ email: 'desk@pargig.test' })) === 0);

  console.log(out.join('\n'));
  server.close();
  await mongoose.connection.dropDatabase();
  await mongoose.disconnect();
  const bad2 = out.filter((r) => r.includes('FAIL'));
  console.log(`\n${out.length - bad2.length}/${out.length} passed`);
  console.log(bad2.length ? 'RESULT: FAILURES' : 'RESULT: all good (temp db dropped)');
  process.exit(bad2.length ? 1 : 0);
})().catch(async (e) => {
  console.error('ERROR', e);
  try { await mongoose.connection.dropDatabase(); await mongoose.disconnect(); } catch { /* down */ }
  process.exit(1);
});
