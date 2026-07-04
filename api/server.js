require('dotenv').config();

const { createApp } = require('./src/app');
const config = require('./src/config');
const { seedAdmin } = require('./src/controllers/auth');

async function main() {
  await seedAdmin();
  const app = createApp();
  app.listen(config.port, () => {
    console.log(`ChengetAi Deploy API running on port ${config.port}`);
  });
}

main().catch((err) => {
  console.error('Fatal startup error:', err);
  process.exit(1);
});
