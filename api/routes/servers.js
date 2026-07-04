const express = require('express');
const router = express.Router();

const {
  getServers,
  addServer
} = require('../controllers/servers');

router.get('/', getServers);
router.post('/', addServer);

module.exports = router;
