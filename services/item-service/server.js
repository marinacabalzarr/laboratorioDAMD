const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const path = require('path');

const JsonDatabase = require('../../shared/JsonDatabase');
const serviceRegistry = require('../../shared/serviceRegistry');

const app = express();
const PORT = process.env.PORT || 3003;
const SERVICE_NAME = 'item-service';
const SERVICE_URL = `http://localhost:${PORT}`;

const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret';
const JWT_EXPIRES = process.env.JWT_EXPIRES || '2h';

app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(morgan('dev'));

function auth(req, res, next) {
  const h = req.headers.authorization || '';
  const token = h.startsWith('Bearer ') ? h.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Token ausente' });
  try {
    req.user = jwt.verify(token, JWT_SECRET);
    next();
  } catch {
    return res.status(401).json({ error: 'Token inválido' });
  }
}

const dbPath = path.join(__dirname, 'database'); // ./services/item-services/database
const itemsDb = new JsonDatabase(dbPath, 'items');

function matches(term, value) {
  return String(value || '').toLowerCase().includes(String(term || '').toLowerCase());
}

/**
 * Esquema do Item:
 * {
 *   id, name, category, brand, unit, averagePrice, barcode, description, active, createdAt
 * }
 */

// GET /items?category=...&name=...&active=true|false
app.get('/items', async (req, res) => {
  const { category, name, active } = req.query;
  const all = await itemsDb.find();

  let data = all;
  if (category) data = data.filter(i => (i.category || '').toLowerCase() === String(category).toLowerCase());
  if (name)     data = data.filter(i => matches(name, i.name));
  if (active !== undefined) {
    const want = String(active).toLowerCase() === 'true';
    data = data.filter(i => Boolean(i.active) === want);
  }

  res.json(data);
});

// GET /items/:id
app.get('/items/:id', async (req, res) => {
  const item = await itemsDb.findById(req.params.id);
  if (!item) return res.status(404).json({ error: 'Item não encontrado' });
  res.json(item);
});

// POST /items  (requer auth)
app.post('/items', auth, async (req, res) => {
  try {
    const {
      name, category, brand = '', unit = 'un',
      averagePrice = 0, barcode = '', description = '',
      active = true
    } = req.body || {};

    if (!name || !category) {
      return res.status(400).json({ error: 'name e category são obrigatórios' });
    }

    const now = new Date().toISOString();
    const doc = await itemsDb.create({
      id: uuidv4(),
      name,
      category,
      brand,
      unit,               // "kg" | "un" | "litro"
      averagePrice: Number(averagePrice) || 0,
      barcode,
      description,
      active: Boolean(active),
      createdAt: now
    });

    res.status(201).json(doc);
  } catch (e) {
    res.status(500).json({ error: 'Falha ao criar item', details: String(e) });
  }
});

// PUT /items/:id  (requer auth)
app.put('/items/:id', auth, async (req, res) => {
  const current = await itemsDb.findById(req.params.id);
  if (!current) return res.status(404).json({ error: 'Item não encontrado' });

  const {
    name, category, brand, unit, averagePrice, barcode, description, active
  } = req.body || {};

  const updated = await itemsDb.update(req.params.id, {
    ...current,
    name: name ?? current.name,
    category: category ?? current.category,
    brand: brand ?? current.brand,
    unit: unit ?? current.unit,
    averagePrice: averagePrice !== undefined ? Number(averagePrice) : current.averagePrice,
    barcode: barcode ?? current.barcode,
    description: description ?? current.description,
    active: active !== undefined ? Boolean(active) : current.active
  });

  res.json(updated);
});

// GET /categories
app.get('/categories', async (_req, res) => {
  const all = await itemsDb.find();
  const cats = [...new Set(all.map(i => i.category).filter(Boolean))].sort((a, b) => a.localeCompare(b));
  res.json(cats);
});

// GET /search?q=termo
app.get('/search', async (req, res) => {
  const q = String(req.query.q || '').trim();
  if (!q) return res.json([]);
  const all = await itemsDb.find();
  const data = all.filter(i =>
    matches(q, i.name) || matches(q, i.brand) || matches(q, i.description) || matches(q, i.barcode)
  );
  res.json(data);
});

// health
app.get('/health', (_req, res) => res.json({ status: 'ok', service: SERVICE_NAME }));

// ----- seed inicial: ~20 itens em categorias diversas -----
async function seedItems() {
  const all = await itemsDb.find();
  if (all.length > 0) return;

  const now = new Date().toISOString();
  const base = [
    // Alimentos
    ['Arroz', 'Alimentos', 'Tio João', 'kg', 6.99, '', 'Arroz branco tipo 1'],
    ['Feijão', 'Alimentos', 'Camil', 'kg', 8.49, '', 'Feijão carioca'],
    ['Macarrão', 'Alimentos', 'Renata', 'un', 4.49, '', 'Espaguete 500g'],
    ['Açúcar', 'Alimentos', 'União', 'kg', 5.99, '', 'Açúcar refinado'],
    // Higiene
    ['Sabonete', 'Higiene', 'Dove', 'un', 3.99, '', 'Sabonete hidratante'],
    ['Shampoo', 'Higiene', 'Elseve', 'un', 16.9, '', 'Shampoo 200ml'],
    ['Pasta de Dente', 'Higiene', 'Colgate', 'un', 7.5, '', 'Total 12 90g'],
    ['Papel Higiênico', 'Higiene', 'Neve', 'un', 15.9, '', 'Pacote 12 rolos'],
    // Limpeza
    ['Detergente', 'Limpeza', 'Ypê', 'un', 2.99, '', 'Detergente neutro 500ml'],
    ['Sabão em Pó', 'Limpeza', 'Omo', 'un', 25.9, '', 'Pacote 1,6kg'],
    ['Desinfetante', 'Limpeza', 'Veja', 'un', 8.9, '', 'Lavanda 1L'],
    // Bebidas
    ['Água Mineral', 'Bebidas', 'Crystal', 'litro', 2.5, '', 'Garrafa 1,5L'],
    ['Refrigerante', 'Bebidas', 'Coca-Cola', 'litro', 8.9, '', 'PET 2L'],
    ['Suco de Laranja', 'Bebidas', 'Del Valle', 'litro', 7.9, '', '1L'],
    ['Café', 'Bebidas', 'Pilão', 'un', 12.9, '', '250g torrado e moído'],
    // Padaria
    ['Pão Francês', 'Padaria', 'Padaria Local', 'kg', 15.0, '', 'Fresco do dia'],
    ['Bolo de Fubá', 'Padaria', 'Padaria Local', 'un', 18.0, '', '800g'],
    ['Pão de Forma', 'Padaria', 'Wickbold', 'un', 9.9, '', 'Tradicional 450g'],
    ['Queijo Minas', 'Padaria', 'Fazenda', 'kg', 42.0, '', 'Queijo minas padrão']
  ];

  for (const [name, category, brand, unit, averagePrice, barcode, description] of base) {
    await itemsDb.create({
      id: uuidv4(),
      name, category, brand, unit,
      averagePrice,
      barcode,
      description,
      active: true,
      createdAt: now
    });
  }
  console.log('[seed] items criados:', base.length);
}

// ----- service registry -----
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

// ----- start -----
app.listen(PORT, async () => {
  await seedItems();
  await register();
  console.log(`Item Service ouvindo em http://localhost:${PORT}`);
});
