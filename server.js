const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const path = require('path');

// shared utils
const JsonDatabase = require('../shared/JsonDatabase');
const serviceRegistry = require('../shared/serviceRegistry');

// -------------------- config --------------------
const app = express();
const PORT = process.env.PORT || 3001;
const SERVICE_NAME = 'user-service';
const SERVICE_URL = `http://localhost:${PORT}`;
const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret';
const JWT_EXPIRES = process.env.JWT_EXPIRES || '2h';
const SALT_ROUNDS = Number(process.env.SALT_ROUNDS || 10);

// middlewares
app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(morgan('dev'));

// -------------------- DB --------------------
const dbPath = path.join(__dirname, 'database'); // ./services/user-services/database
const usersDb = new JsonDatabase(dbPath, 'users');

// helper: retira campos sensíveis
function sanitize(user) {
  if (!user) return null;
  const { password, ...rest } = user;
  return rest;
}

// helper: auth middleware
function auth(req, res, next) {
  const h = req.headers.authorization || '';
  const token = h.startsWith('Bearer ') ? h.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Token ausente' });
  try {
    const payload = jwt.verify(token, JWT_SECRET);
    req.user = payload; // { id, email, role }
    next();
  } catch {
    return res.status(401).json({ error: 'Token inválido' });
  }
}

// -------------------- ENDPOINTS --------------------
// POST /auth/register  (cadastro)
app.post('/auth/register', async (req, res) => {
  try {
    const {
      email,
      username,
      password,
      firstName = '',
      lastName = '',
      preferences = {}
    } = req.body || {};

    if (!email || !password || !username) {
      return res.status(400).json({ error: 'email, username e password são obrigatórios' });
    }

    const all = await usersDb.find();
    const emailExists = all.some(u => (u.email || '').toLowerCase() === String(email).toLowerCase());
    if (emailExists) return res.status(409).json({ error: 'Email já cadastrado' });

    const now = new Date().toISOString();
    const hash = await bcrypt.hash(password, SALT_ROUNDS);

    const user = {
      id: uuidv4(),
      email,
      username,
      password: hash, // hash armazenado
      firstName,
      lastName,
      preferences: {
        defaultStore: preferences.defaultStore || '',
        currency: preferences.currency || 'BRL'
      },
      createdAt: now,
      updatedAt: now
    };

    const saved = await usersDb.create(user);

    // gera token já no cadastro (opcional)
    const token = jwt.sign({ id: saved.id, email: saved.email, role: 'user' }, JWT_SECRET, { expiresIn: JWT_EXPIRES });
    return res.status(201).json({ user: sanitize(saved), token });
  } catch (e) {
    console.error('register error', e);
    return res.status(500).json({ error: 'Falha ao registrar usuário' });
  }
});

// POST /auth/login  (email/username + senha)
app.post('/auth/login', async (req, res) => {
  try {
    const { email, username, password } = req.body || {};
    if ((!email && !username) || !password) {
      return res.status(400).json({ error: 'Informe email ou username e a senha' });
    }

    const all = await usersDb.find();
    const user = all.find(u =>
      (email && (u.email || '').toLowerCase() === String(email).toLowerCase()) ||
      (username && (u.username || '').toLowerCase() === String(username).toLowerCase())
    );

    if (!user) return res.status(401).json({ error: 'Credenciais inválidas' });
    const ok = await bcrypt.compare(password, user.password || '');
    if (!ok) return res.status(401).json({ error: 'Credenciais inválidas' });

    const token = jwt.sign({ id: user.id, email: user.email, role: 'user' }, JWT_SECRET, { expiresIn: JWT_EXPIRES });
    return res.json({ user: sanitize(user), token });
  } catch (e) {
    console.error('login error', e);
    return res.status(500).json({ error: 'Falha ao autenticar' });
  }
});

// GET /users/:id  (dados do usuário autenticado)
app.get('/users/:id', auth, async (req, res) => {
  try {
    // regra simples: usuário só lê o próprio perfil
    if (req.user.id !== req.params.id) return res.status(403).json({ error: 'Acesso negado' });
    const user = await usersDb.findById(req.params.id);
    if (!user) return res.status(404).json({ error: 'Usuário não encontrado' });
    return res.json(sanitize(user));
  } catch (e) {
    console.error('get user error', e);
    return res.status(500).json({ error: 'Falha ao buscar usuário' });
  }
});

// PUT /users/:id  (atualizar perfil)
app.put('/users/:id', auth, async (req, res) => {
  try {
    if (req.user.id !== req.params.id) return res.status(403).json({ error: 'Acesso negado' });

    const current = await usersDb.findById(req.params.id);
    if (!current) return res.status(404).json({ error: 'Usuário não encontrado' });

    const { firstName, lastName, preferences } = req.body || {};
    const updated = await usersDb.update(req.params.id, {
      ...current,
      firstName: firstName ?? current.firstName,
      lastName: lastName ?? current.lastName,
      preferences: {
        defaultStore: preferences?.defaultStore ?? current.preferences?.defaultStore ?? '',
        currency: preferences?.currency ?? current.preferences?.currency ?? 'BRL'
      },
      updatedAt: new Date().toISOString()
    });

    return res.json(sanitize(updated));
  } catch (e) {
    console.error('update user error', e);
    return res.status(500).json({ error: 'Falha ao atualizar usuário' });
  }
});

// healthcheck
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
    console.log(`[registry] ${SERVICE_NAME} removido`);
  } catch (e) {
    console.error('[registry] falha ao remover:', e);
  }
}
process.on('SIGINT', async () => { await deregister(); process.exit(0); });
process.on('SIGTERM', async () => { await deregister(); process.exit(0); });

// -------------------- seed opcional: admin --------------------
(async () => {
  try {
    const all = await usersDb.find();
    if (all.length === 0) {
      const now = new Date().toISOString();
      const admin = {
        id: uuidv4(),
        email: 'admin@demo.com',
        username: 'admin',
        password: await bcrypt.hash('admin123', SALT_ROUNDS),
        firstName: 'Admin',
        lastName: 'User',
        preferences: { defaultStore: '', currency: 'BRL' },
        createdAt: now,
        updatedAt: now
      };
      await usersDb.create(admin);
      console.log('[seed] usuário admin criado (admin@demo.com / admin123)');
    }
  } catch (e) {
    console.error('[seed] erro:', e);
  }
})();

// -------------------- start --------------------
app.listen(PORT, async () => {
  await register();
  console.log(`User Service ouvindo em http://localhost:${PORT}`);
});
