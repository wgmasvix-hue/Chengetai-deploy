const express = require("express");
const cors = require("cors");
const helmet = require("helmet");
const morgan = require("morgan");

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(helmet());
app.use(morgan("dev"));
app.use(express.json());

app.get("/", (req, res) => {
  res.json({
    name: "ChengetAi Deploy API",
    version: "0.3.0",
    status: "running"
  });
});

app.get("/api/dashboard", (req, res) => {
  res.json({
    repositories: 5,
    containers: 8,
    cpu: 18,
    memory: 34,
    disk: 42,
    uptime: "15 days",
    server: "Healthy"
  });
});

app.listen(PORT, () => {
  console.log(`ChengetAi Deploy API running on port ${PORT}`);
});
