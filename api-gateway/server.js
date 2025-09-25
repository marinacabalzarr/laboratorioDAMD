const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const { createProxyMiddleware } = require('http-proxy-middleware');
const jwt = require('jsonwebtoken');
const axios = require('axios');

const serviceRegistry = require('../shared/serviceRegistry'); // ajuste se seu shared estiver noutro lugar

const app = express();
const PORT = process.env.PORT || 3000;
const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret';

app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(morgan('combined'));

/* ------------------------- Service Discovery helpers ------------------------ */
const FALLBACKS = {
  'user-service': 'http://localhost:3001',
  'list-service': 'http://localhost:3002',
  'item-service': 'http://localhost:3003'
};

async function lookup(name) {
  try {
    const url = await serviceRegistry.lookup?.(name);
    return url || FALLBACKS[name];
  } catch {
    return FALLBACKS[name];
  }
}

/* ---------------------------- Circuit Breaker --------------------------------
 * Estados por serviço: { failures, openedAt }
 * - abre após 3 falhas;
 * - se aberto, retorna 503 até passar o cooldown (30s).
 * --------------------------------------------------------------------------- */
const breakers = {};
const MAX_FAILS = 3;
const COOLDOWN_MS = 30_000;

function canPass(name) {
  const b = breakers[name];
  if (!b) return true;
  if (b.failures < MAX_FAILS) return true;
  // aberto: espera cooldown
  const elapsed = Date.now() - (b.openedAt || 0);
  if (elapsed > COOLDOWN_MS) { breakers[name] = { failures: 0, openedAt: null }; return true; }
  return false;
}
function reportSuccess(name) { breakers[name] = { failures: 0, openedAt: null }; }
function reportFailure(name) {
  const prev = breakers[name]?.failures || 0;
  const failures = prev + 1;
  breakers[name] = { failures, openedAt: failures >= MAX_FAILS ? Date.now() : breakers[name]?.openedAt || null };
}

/* ------------------------------ Auth forwarder ------------------------------ */
function extractBearer(req) {
  const h = req.headers.authorization || '';
  return h.startsWith('Bearer ') ? h.slice(7) : null;
}

/* --------------------------------- Proxies ---------------------------------- */
async function makeProxy(targetName) {
  const target = await lookup(targetName);

  return createProxyMiddleware({
    target,
    changeOrigin: true,
    pathRewrite: (path) => {
      // remover prefixo /api/<area>
      // ex: /api/users/123 -> /users/123
      return path.replace(/^\/api\/(auth|users|items|lists)/, (m, g1) => `/${g1}`);
    },
    onProxyReq: (proxyReq, req) => {
      // repassa Authorization
      const token = extractBearer(req);
      if (token) proxyReq.setHeader('Authorization', `Bearer ${token}`);
    },
    selfHandleResponse: false,
    router: async () => ({ target: await lookup(targetName) }),
    onProxyRes: () => reportSuccess(targetName),
    onError: (_err, _req, res) => {
      reportFailure(targetName);
      res.status(502).json({ error: `Upstream ${targetName} indisponível` });
    }
  });
}

/* ------------------------------ Gate middlewares ---------------------------- */
async function guard(targetName, req, res, next) {
  if (!canPass(targetName)) {
    return res.status(503).json({ error: `Circuito aberto para ${targetName}` });
  }
  next();
}

/* ------------------------------- Route wiring ------------------------------- */
// /api/auth/*  & /api/users/*  -> user-service
app.use(['/api/auth', '/api/users'], async (req, res, next) => guard('user-service', req, res, next), async (req, res, next) => {
  const proxy = await makeProxy('user-service');
  proxy(req, res, next);
});

// /api/items/* -> item-service
app.use('/api/items', async (req, res, next) => guard('item-service', req, res, next), async (req, res, next) => {
  const proxy = await makeProxy('item-service');
  proxy(req, res, next);
});

// /api/lists/* -> list-service
app.use('/api/lists', async (req, res, next) => guard('list-service', req, res, next), async (req, res, next) => {
  const proxy = await makeProxy('list-service');
  proxy(req, res, next);
});

/* ------------------------------- Aggregations ------------------------------- */
// GET /api/dashboard  -> estatísticas do usuário (precisa JWT)
app.get('/api/dashboard', async (req, res) => {
  const token = extractBearer(req);
  if (!token) return res.status(401).json({ error: 'Token ausente' });

  let payload;
  try { payload = jwt.verify(token, JWT_SECRET); } catch { return res.status(401).json({ error: 'Token inválido' }); }

  try {
    const listBase = await lookup('list-service');
    const itemBase = await lookup('item-service');

    // listas do usuário
    const { data: lists } = await axios.get(`${listBase}/lists`, { headers: { Authorization: `Bearer ${token}` } });

    // sumariza
    let totalLists = lists.length;
    let totalItems = 0;
    let purchased = 0;
    let estimatedTotal = 0;

    lists.forEach(l => {
      totalItems += l.items?.length || 0;
      purchased += (l.items || []).filter(i => i.purchased).length;
      estimatedTotal += l.summary?.estimatedTotal || 0;
    });

    // contagem de itens disponíveis no catálogo (opcional para painel)
    let catalogCount = 0;
    try {
      const { data: items } = await axios.get(`${itemBase}/items`);
      catalogCount = Array.isArray(items) ? items.length : 0;
    } catch (_) {}

    res.json({
      userId: payload.id,
      totalLists,
      totalItems,
      purchasedItems: purchased,
      estimatedTotal,
      catalogCount
    });
  } catch (e) {
    res.status(502).json({ error: 'Falha ao montar dashboard', details: String(e) });
  }
});

// GET /api/search?q=termo  -> busca global (listas por nome + itens por nome)
app.get('/api/search', async (req, res) => {
  const q = String(req.query.q || '').trim();
  if (!q) return res.json({ items: [], lists: [] });

  const token = extractBearer(req);
  const listBase = await lookup('list-service');
  const itemBase = await lookup('item-service');

  const [itemsRes, listsRes] = await Promise.allSettled([
    axios.get(`${itemBase}/search`, { params: { q } }),
    token
      ? axios.get(`${listBase}/lists`, { headers: { Authorization: `Bearer ${token}` } })
      : Promise.resolve({ status: 'fulfilled', value: { data: [] } })
  ]);

  const items = itemsRes.status === 'fulfilled' ? itemsRes.value.data : [];
  let lists = listsRes.status === 'fulfilled' ? listsRes.value.data : [];
  lists = lists.filter(l => (l.name || '').toLowerCase().includes(q.toLowerCase()));

  res.json({ items, lists });
});

// GET /health  -> consolidado dos serviços
app.get('/health', async (_req, res) => {
  const names = ['user-service', 'list-service', 'item-service'];
  const checks = await Promise.all(names.map(async n => {
    const base = await lookup(n);
    try {
      const { data } = await axios.get(`${base}/health`, { timeout: 3000 });
      return { service: n, ok: true, data };
    } catch {
      return { service: n, ok: false };
    }
  }));
  res.json({ gateway: 'ok', services: checks });
});

// GET /registry  -> conteúdo do service registry
app.get('/registry', async (_req, res) => {
  try {
    const data = await serviceRegistry.dump?.();
    res.json(data || {});
  } catch {
    res.json({});
  }
});

/* ------------------------------ Background HC ------------------------------- */
async function periodicHealth() {
  // apenas força lookups e fecha circuitos quando voltar
  const names = ['user-service', 'list-service', 'item-service'];
  for (const n of names) {
    const base = await lookup(n);
    try {
      await axios.get(`${base}/health`, { timeout: 3000 });
      reportSuccess(n);
    } catch {
      reportFailure(n);
    }
  }
}
setInterval(periodicHealth, 30_000);

/* --------------------------------- Start ------------------------------------ */
app.listen(PORT, () => {
  console.log(`API Gateway ouvindo em http://localhost:${PORT}`);
});
