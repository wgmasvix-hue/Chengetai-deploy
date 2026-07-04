const servers = [
  {
    id: 1,
    name: "Walter",
    host: "157.173.127.168",
    port: 22,
    username: "root",
    os: "Ubuntu 24.04",
    status: "online"
  }
];

exports.getServers = (req, res) => {
  res.json(servers);
};

exports.addServer = (req, res) => {
  const server = {
    id: Date.now(),
    ...req.body,
    status: "online"
  };

  servers.push(server);
  res.status(201).json(server);
};
