const test = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const checkAuth = require('../middleware/localCheckAuth');

function response() {
  return {
    statusCode: 200,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };
}

test('local auth rejects a missing bearer token', () => {
  const res = response();
  let continued = false;
  checkAuth({ headers: {} }, res, () => { continued = true; });
  assert.equal(res.statusCode, 401);
  assert.equal(continued, false);
});

test('local auth attaches the verified token identity', () => {
  const token = jwt.sign({ sub: 'user-123', email: 'person@example.com' }, 'checkmate-local-development-secret-change-me');
  const req = { headers: { authorization: `Bearer ${token}` } };
  const res = response();
  let continued = false;
  checkAuth(req, res, () => { continued = true; });
  assert.equal(continued, true);
  assert.deepEqual(req.userData, { userId: 'user-123', email: 'person@example.com' });
});

test('local auth rejects an invalid bearer token', () => {
  const res = response();
  let continued = false;
  checkAuth({ headers: { authorization: 'Bearer invalid' } }, res, () => { continued = true; });
  assert.equal(res.statusCode, 401);
  assert.equal(continued, false);
});