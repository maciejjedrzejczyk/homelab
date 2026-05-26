const express = require('express');
const http = require('http');
const { WebSocketServer } = require('ws');
const path = require('path');
const fs = require('fs');
const yaml = require('js-yaml');
const Docker = require('dockerode');

const PORT = process.env.PORT || 3009;
const COMPOSE_ROOT = process.env.COMPOSE_ROOT || path.resolve(__dirname, '../../docker-compose');
const NPM_API = process.env.NPM_API || 'http://localhost:17413';
const NPM_EMAIL = process.env.NPM_EMAIL || '';
const NPM_PASSWORD = process.env.NPM_PASSWORD || '';

const docker = new Docker({ socketPath: process.env.DOCKER_SOCKET || '/var/run/docker.sock' });
const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

app.use(express.static(path.join(__dirname, 'public')));

// --- NPM Integration ---
let npmToken = null;

async function npmLogin() {
  if (!NPM_EMAIL || !NPM_PASSWORD) return null;
  try {
    const res = await fetch(`${NPM_API}/api/tokens`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ identity: NPM_EMAIL, secret: NPM_PASSWORD }),
    });
    if (res.ok) {
      const data = await res.json();
      npmToken = data.token;
      return npmToken;
    }
  } catch (e) { /* NPM not available */ }
  return null;
}

async function getProxyHosts() {
  if (!npmToken) await npmLogin();
  if (!npmToken) return [];
  try {
    const res = await fetch(`${NPM_API}/api/nginx/proxy-hosts`, {
      headers: { Authorization: `Bearer ${npmToken}` },
    });
    if (res.status === 401) { npmToken = null; await npmLogin(); return getProxyHosts(); }
    if (res.ok) return await res.json();
  } catch (e) { /* NPM not reachable */ }
  return [];
}

// --- Update Detection ---
async function checkImageUpdates(containers) {
  const updates = {};
  for (const c of containers) {
    if (c.State !== 'running') continue;
    const imageName = c.Image;
    if (!imageName || imageName.startsWith('sha256:')) continue;
    try {
      const img = docker.getImage(imageName);
      const inspect = await img.inspect();
      const localDigest = inspect.RepoDigests?.[0]?.split('@')[1];
      if (localDigest) {
        updates[c.Id.slice(0, 12)] = { localDigest: localDigest.slice(0, 16), image: imageName };
      }
    } catch (e) { /* skip */ }
  }
  return updates;
}

// --- Compose Enrichment ---
function loadComposeSupplemental() {
  const supplemental = {};
  try {
    const files = fs.readdirSync(COMPOSE_ROOT, { recursive: true })
      .filter(f => f.endsWith('compose.yaml') || f.endsWith('compose.yml'));
    for (const file of files) {
      const fullPath = path.join(COMPOSE_ROOT, file);
      const content = yaml.load(fs.readFileSync(fullPath, 'utf8'));
      const projectName = content.name || path.dirname(file);
      supplemental[projectName] = { content, dir: path.dirname(fullPath) };
    }
  } catch (e) { /* optional */ }
  return supplemental;
}

// --- Graph Builder ---
async function buildGraph() {
  const nodes = [];
  const edges = [];
  const seen = new Set();

  const addNode = (id, label, type, data) => {
    if (!seen.has(id)) { seen.add(id); nodes.push({ id, label, type, data }); }
  };
  const addEdge = (source, target, relation) => {
    if (seen.has(source) || nodes.find(n => n.id === source))
      edges.push({ source, target, relation });
  };

  const [containers, networks, volumes] = await Promise.all([
    docker.listContainers({ all: true }),
    docker.listNetworks(),
    docker.listVolumes(),
  ]);

  const supplemental = loadComposeSupplemental();
  const [proxyHosts, imageUpdates] = await Promise.all([
    getProxyHosts(),
    checkImageUpdates(containers),
  ]);

  // Projects
  const projects = new Map();
  for (const c of containers) {
    const project = c.Labels?.['com.docker.compose.project'] || '_standalone';
    if (!projects.has(project)) projects.set(project, []);
    projects.get(project).push(c);
  }
  for (const [project] of projects) {
    addNode(`project:${project}`, project, 'project', { containerCount: projects.get(project).length });
  }

  // Containers
  for (const c of containers) {
    const name = c.Names[0]?.replace(/^\//, '') || c.Id.slice(0, 12);
    const project = c.Labels?.['com.docker.compose.project'] || '_standalone';
    const cId = `container:${c.Id.slice(0, 12)}`;
    const health = c.Status?.includes('healthy') ? 'healthy' : c.Status?.includes('unhealthy') ? 'unhealthy' : c.State;
    const update = imageUpdates[c.Id.slice(0, 12)];

    addNode(cId, name, 'container', {
      image: c.Image,
      state: c.State,
      health,
      status: c.Status,
      project,
      updateAvailable: !!update,
      localDigest: update?.localDigest,
    });
    addEdge(`project:${project}`, cId, 'contains');

    for (const m of c.Mounts || []) {
      if (m.Type === 'volume') {
        const vId = `volume:${m.Name}`;
        addNode(vId, m.Name, 'volume');
        addEdge(cId, vId, 'mounts');
      } else if (m.Type === 'bind') {
        const fId = `file:${m.Source}`;
        addNode(fId, m.Source.split('/').slice(-2).join('/'), 'file', { path: m.Source });
        addEdge(cId, fId, 'bind_mount');
      }
    }

    for (const p of c.Ports || []) {
      if (p.PublicPort) {
        const portLabel = `${p.PublicPort}:${p.PrivatePort}/${p.Type}`;
        const pId = `port:${cId}:${portLabel}`;
        addNode(pId, portLabel, 'port');
        addEdge(cId, pId, 'exposes');
      }
    }

    if (c.NetworkSettings?.Networks) {
      for (const netName of Object.keys(c.NetworkSettings.Networks)) {
        const nId = `network:${netName}`;
        addNode(nId, netName, 'network');
        addEdge(cId, nId, 'connected_to');
      }
    }
  }

  // Unused volumes
  for (const v of (volumes.Volumes || [])) {
    addNode(`volume:${v.Name}`, v.Name, 'volume', { driver: v.Driver });
  }

  // Networks (skip defaults)
  for (const n of networks) {
    if (['bridge', 'host', 'none'].includes(n.Name)) continue;
    addNode(`network:${n.Name}`, n.Name, 'network', { driver: n.Driver });
  }

  // Compose enrichment
  for (const [projectName, { content, dir }] of Object.entries(supplemental)) {
    for (const [svcName, svc] of Object.entries(content.services || {})) {
      const cNode = nodes.find(n =>
        n.type === 'container' && (n.label === svcName || n.label === `${projectName}-${svcName}-1`)
      );
      if (!cNode) continue;

      if (svc.environment) {
        const envs = Array.isArray(svc.environment)
          ? svc.environment.map(e => e.split('=')[0])
          : Object.keys(svc.environment);
        for (const env of envs) {
          const eId = `env:${projectName}/${env}`;
          addNode(eId, env, 'env');
          addEdge(cNode.id, eId, 'uses_env');
        }
      }

      for (const secret of svc.secrets || []) {
        const secretName = typeof secret === 'string' ? secret : secret.source;
        const sId = `secret:${secretName}`;
        addNode(sId, secretName, 'secret');
        addEdge(cNode.id, sId, 'uses_secret');
      }
    }

    for (const [secretName, def] of Object.entries(content.secrets || {})) {
      if (def?.file) {
        const sId = `secret:${secretName}`;
        const fId = `file:${path.resolve(dir, def.file)}`;
        addNode(sId, secretName, 'secret');
        addNode(fId, def.file, 'file', { path: path.resolve(dir, def.file) });
        addEdge(sId, fId, 'reads_from');
      }
    }

    const envPath = path.join(dir, '.env');
    if (fs.existsSync(envPath)) {
      const fId = `file:${envPath}`;
      addNode(fId, `${projectName}/.env`, 'file');
      addEdge(`project:${projectName}`, fId, 'loads_env_from');
    }
  }

  // Proxy hosts → domain nodes
  for (const ph of proxyHosts) {
    for (const domain of ph.domain_names || []) {
      const dId = `domain:${domain}`;
      addNode(dId, domain, 'domain', { ssl: ph.ssl_forced, enabled: ph.enabled });
      // Match proxy target to container
      const host = ph.forward_host;
      const port = ph.forward_port;
      const matched = nodes.find(n =>
        n.type === 'container' && (n.label === host || n.label.includes(host))
      );
      if (matched) {
        addEdge(dId, matched.id, 'routes_to');
      }
      // Link domain to NPM
      const npmNode = nodes.find(n => n.type === 'container' && n.label.includes('nginx-proxy-manager'));
      if (npmNode) addEdge(npmNode.id, dId, 'proxies');
    }
  }

  return { nodes, edges };
}

// --- WebSocket: stream Docker events ---
function broadcastGraph() {
  buildGraph().then(graph => {
    const msg = JSON.stringify({ type: 'graph', data: graph });
    wss.clients.forEach(client => {
      if (client.readyState === 1) client.send(msg);
    });
  }).catch(() => {});
}

// Docker event stream
function watchDockerEvents() {
  docker.getEvents({}, (err, stream) => {
    if (err || !stream) {
      console.error('Failed to connect to Docker events, retrying in 5s...');
      setTimeout(watchDockerEvents, 5000);
      return;
    }
    let debounce = null;
    stream.on('data', () => {
      clearTimeout(debounce);
      debounce = setTimeout(broadcastGraph, 500);
    });
    stream.on('error', () => setTimeout(watchDockerEvents, 5000));
  });
}

wss.on('connection', ws => {
  // Send initial graph immediately
  buildGraph().then(graph => {
    ws.send(JSON.stringify({ type: 'graph', data: graph }));
  }).catch(e => ws.send(JSON.stringify({ type: 'error', data: e.message })));
});

// REST fallback
app.get('/api/graph', async (req, res) => {
  try { res.json(await buildGraph()); }
  catch (err) { res.status(500).json({ error: err.message }); }
});

server.listen(PORT, () => {
  console.log(`Docker Map running at http://localhost:${PORT}`);
  console.log(`WebSocket on ws://localhost:${PORT}`);
  console.log(`Docker socket: ${process.env.DOCKER_SOCKET || '/var/run/docker.sock'}`);
  console.log(`NPM API: ${NPM_API}`);
  watchDockerEvents();
});
