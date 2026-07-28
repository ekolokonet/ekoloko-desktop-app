// Webpack 4 hashes modules with MD4, which OpenSSL 3 (Node 17+) no longer
// ships. Redirect md4 to sha256 so builds run on modern Node without
// --openssl-legacy-provider (which Electron refuses to accept in NODE_OPTIONS).
const crypto = require('crypto')
const { createHash } = crypto
crypto.createHash = (algorithm, options) =>
	createHash(algorithm === 'md4' ? 'sha256' : algorithm, options)

module.exports = {}
