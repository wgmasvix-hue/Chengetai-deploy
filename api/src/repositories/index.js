// Repository facade: PostgreSQL when DATABASE_URL is configured,
// otherwise the JSON-file store. Controllers/services depend only on
// this interface.
const config = require('../config');

module.exports = config.databaseUrl
  ? require('./pg')
  : require('./store');
