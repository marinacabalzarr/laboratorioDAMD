const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const jwt = require('jsonwebtoken');
const axios = require('axios');
const { v4: uuidv4 } = require('uuid');
const path = require('path');

const JsonDatabase = require('../../shared/JsonDatabase');
const serviceRegistry = require('../../shared/serviceRegistry');

// -------------------- config --------------------
const app = express();
const PORT = process.env.PORT || 3002;
const SERVICE_NAME = 'list-service';
const SERVICE_URL = `http://localhost:${PORT}`;

const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret';

app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(morgan('dev'));

// -------------------- auth middleware --------------------
function auth(req, res, next) {
  const h = req.headers.authorization || '';
  const token = h.startsWith('Bearer ') ? h.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Token ausente' });
  try {
    req.user = jwt.verify(token, JWT_SECRET); // { id, email, role }
    next();
  } catch {
    return res.status(401).json({ error: 'Token inválido' });
  }
}

// -------------------- DB --------------------
const dbPath = path.join(__dirname, 'database');
const listsDb = new JsonDatabase(dbPath, 'lists');

// -------------------- helpers --------------------
async function getItemServiceBaseUrl() {
  // tenta pelo service registry; se falhar, assume localhost:3003
  try {
    const url = await serviceRegistry.lookup?.('item-service');
    if (url) return url;
  } catch (_) {}
  return 'http://localhost:3003';
}

function canAccess(list, userId) {
  return list && list.userId === userId;
}

function recomputeSummary(list) {
  const totals = list.items.length;
  const purchasedItems = list.items.filter(i => i.purchased).length;
  const estimatedTotal = list.items.reduce((acc, i) => {
    const q = Number(i.quantity) || 0;
    const p = Number(i.estimatedPrice) || 0;
    return acc + q * p;
  }, 0);
  list.summary = { totals, purchasedItems, estimatedTotal };
  list.updatedAt = new Date().toISOString();
  return list.summary;
}

// -------------------- endpoints --------------------

// POST /lists - criar nova lista
app.post('/lists', auth, async (req, res) => {
  try {
    const { name, description = '' } = req.body || {};
    if (!name) return res.status(400).json({ error: 'name é obrigatório' });

    const now = new Date().toISOString();
    const doc = await listsDb.create({
      id: uuidv4(),
      userId: req.user.id,
      name,
      description,
      status: 'active', // active|completed|archived
      items: [],
      summary: { totals: 0, purchasedItems: 0, estimatedTotal: 0 },
      createdAt: now,
      updatedAt: now
    });

    res.status(201).json(doc);
  } catch (e) {
    res.status(500).json({ error: 'Falha ao criar lista', details: String(e) });
  }
});

// GET /lists - listar listas do usuário
app.get('/lists', auth, async (req, res) => {
  const all = await listsDb.find();
  res.json(all.filter(l => l.userId === req.user.id));
});

// GET /lists/:id - buscar lista específica
app.get('/lists/:id', auth, async (req, res) => {
  const list = await listsDb.findById(req.params.id);
  if (!canAccess(list, req.user.id)) return res.status(404).json({ error: 'Lista não encontrada' });
  res.json(list);
});

// PUT /lists/:id - atualizar nome, descrição, status
app.put('/lists/:id', auth, async (req, res) => {
  const current = await listsDb.findById(req.params.id);
  if (!canAccess(current, req.user.id)) return res.status(404).json({ error: 'Lista não encontrada' });

  const { name, description, status } = req.body || {};
  const updated = await listsDb.update(req.params.id, {
    ...current,
    name: name ?? current.name,
    description: description ?? current.description,
    status: status ?? current.status,
    updatedAt: new Date().toISOString()
  });
  res.json(updated);
});

// DELETE /lists/:id - deletar lista
app.delete('/lists/:id', auth, async (req, res) => {
  const current = await listsDb.findById(req.params.id);
  if (!canAccess(current, req.user.id)) return res.status(404).json({ error: 'Lista não encontrada' });
  await listsDb.delete(req.params.id);
  res.status(204).end();
});

// POST /lists/:id/items - adicionar item à lista (busca dados no Item Service)
app.post('/lists/:id/items', auth, async (req, res) => {
  const list = await listsDb.findById(req.params.id);
  if (!canAccess(list, req.user.id)) return res.status(404).json({ error: 'Lista não encontrada' });

  const { itemId, quantity = 1 } = req.body || {};
  if (!itemId) return res.status(400).json({ error: 'itemId é obrigatório' });

  // evitar duplicatas → se já existir, só soma quantidade
  const existingIdx = list.items.findIndex(i => i.itemId === itemId);
  if (existingIdx >= 0) {
    list.items[existingIdx].quantity = (Number(list.items[existingIdx].quantity) || 0) + Number(quantity || 0);
    recomputeSummary(list);
    await listsDb.update(list.id, list);
    return res.json(list);
  }

  // buscar dados do catálago de itens
  try {
    const base = await getItemServiceBaseUrl();
    const { data: item } = await axios.get(`${base}/items/${itemId}`);
    const now = new Date().toISOString();
    list.items.push({
      itemId,
      itemName: item?.name || '',
      quantity: Number(quantity) || 1,
      unit: item?.unit || 'un',
      estimatedPrice: Number(item?.averagePrice) || 0,
      purchased: false,
      addedAt: now
    });
    recomputeSummary(list);
    await listsDb.update(list.id, list);
    res.status(201).json(list);
  } catch (e) {
    return res.status(400).json({ error: 'Item inválido ou Item Service indisponível' });
  }
});

// PUT /lists/:id/items/:itemId - atualizar item (quantidade, purchased, override de preço)
app.put('/lists/:id/items/:itemId', auth, async (req, res) => {
  const list = await listsDb.findById(req.params.id);
  if (!canAccess(list, req.user.id)) return res.status(404).json({ error: 'Lista não encontrada' });

  const idx = list.items.findIndex(i => i.itemId === req.params.itemId);
  if (idx < 0) return res.status(404).json({ error: 'Item não está na lista' });

  const { quantity, purchased, estimatedPrice } = req.body || {};
  if (quantity !== undefined) list.items[idx].quantity = Number(quantity);
  if (purchased !== undefined) list.items[idx].purchased = Boolean(purchased);
  if (estimatedPrice !== undefined) list.items[idx].estimatedPrice = Number(estimatedPrice);

  recomputeSummary(list);
  await listsDb.update(list.id, list);
  res.json(list);
});

// DELETE /lists/:id/items/:itemId - remover item da lista
app.delete('/lists/:id/items/:itemId', auth, async (req, res) => {
  const list = await listsDb.findById(req.params.id);
  if (!canAccess(list, req.user.id)) return res.status(404).json({ error: 'Lista não encontrada' });

  const before = list.items.length;
  list.items = list.items.filter(i => i.itemId !== req.params.itemId);
  if (list.items.length === before) return res.status(404).json({ error: 'Item não está na lista' });

  recomputeSummary(list);
  await listsDb.update(list.id, list);
  res.status(204).end();
});

// GET /lists/:id/summary - retornar somente o resumo
app.get('/lists/:id/summary', auth, async (req, res) => {
  const list = await listsDb.findById(req.params.id);
  if (!canAccess(list, req.user.id)) return res.status(404).json({ error: 'Lista não encontrada' });
  const summary = recomputeSummary(list);
  await listsDb.update(list.id, list);
  res.json(summary);
});

// health
app.get('/health', (_req, res) => res.json({ status: 'ok', service: SERVICE_NAME }));

// -------------------- service registry --------------------
async function register() {
  try {
    await serviceRegistry.register(SERVICE_NAME, SERVICE_URL);
    console.log(`[registry] ${SERVICE_NAME} registrado em ${SERVICE_URL}`);
  } catch (e) {
    console.error('[registry] falha ao registrar:', e);
  }
}
async function deregister() {
  try {
    await serviceRegistry.deregister(SERVICE_NAME, SERVICE_URL);
    console.log(`[registry] ${SERVICE_NAME} removido do registry`);
  } catch (e) {
    console.error('[registry] falha ao remover:', e);
  }
}
process.on('SIGINT', async () => { await deregister(); process.exit(0); });
process.on('SIGTERM', async () => { await deregister(); process.exit(0); });

// -------------------- start --------------------
app.listen(PORT, async () => {
  await register();
  console.log(`List Service ouvindo em http://localhost:${PORT}`);
});
