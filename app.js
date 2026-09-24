import * as THREE from './vendor/three.module.min.js';
import { OrbitControls } from './vendor/OrbitControls.js';

// ---------- small math ----------
const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const mul = (a, s) => [a[0] * s, a[1] * s, a[2] * s];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const len = a => Math.hypot(a[0], a[1], a[2]);
const norm = a => { const l = len(a) || 1; return [a[0] / l, a[1] / l, a[2] / l]; };
const lerp3 = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
const UP = [0, 1, 0];
function rng(seed) { return () => { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let t = Math.imul(seed ^ seed >>> 15, 1 | seed); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
function hash(...n) { let h = 2166136261; for (const x of n) { h ^= x + 0x9e3779b9; h = Math.imul(h, 16777619); h ^= h >>> 13; } return ((h >>> 0) % 10000) / 10000; }

// ---------- irregular grid (hex -> random quads -> subdivide -> relax) ----------
const GRID_SEED = 11, R = 7, S = 2;
function buildGrid() {
  const rand = rng(GRID_SEED);
  const V = [], idx = new Map();
  for (let q = -R; q <= R; q++) for (let r = -R; r <= R; r++) {
    if (Math.abs(q + r) > R) continue;
    idx.set(q + ',' + r, V.length); V.push([S * (q + r / 2), S * (r * Math.sqrt(3) / 2)]);
  }
  const g = (q, r) => idx.get(q + ',' + r);
  const area = p => { let s = 0; for (let i = 0; i < p.length; i++) { const a = V[p[i]], b = V[p[(i + 1) % p.length]]; s += a[0] * b[1] - b[0] * a[1]; } return s; };
  const tris = [];
  for (let q = -R; q <= R; q++) for (let r = -R; r <= R; r++) {
    for (const t of [[g(q, r), g(q + 1, r), g(q, r + 1)], [g(q + 1, r), g(q + 1, r + 1), g(q, r + 1)]]) {
      if (t.some(x => x === undefined)) continue;
      if (area(t) < 0) t.reverse();
      tris.push(t);
    }
  }
  const ek = (a, b) => a < b ? a + '_' + b : b + '_' + a;
  const edgeT = new Map();
  tris.forEach((t, i) => { for (let j = 0; j < 3; j++) { const k = ek(t[j], t[(j + 1) % 3]); (edgeT.get(k) || edgeT.set(k, []).get(k)).push(i); } });
  const order = tris.map((_, i) => i); for (let i = order.length - 1; i > 0; i--) { const j = Math.floor(rand() * (i + 1)); [order[i], order[j]] = [order[j], order[i]]; }
  const used = new Array(tris.length).fill(false); const polys = [];
  for (const i of order) {
    if (used[i]) continue;
    const t = tris[i]; const opts = [];
    for (let j = 0; j < 3; j++) { const o = edgeT.get(ek(t[j], t[(j + 1) % 3])).find(x => x !== i && !used[x]); if (o !== undefined) opts.push([j, o]); }
    used[i] = true;
    if (!opts.length) { polys.push(t); continue; }
    const [j, o] = opts[Math.floor(rand() * opts.length)]; used[o] = true;
    const a = t[j], b = t[(j + 1) % 3], c = t[(j + 2) % 3];
    const opp = tris[o].find(x => x !== a && x !== b);
    polys.push([c, a, opp, b]); // CCW: c->a is t's edge, then around the far side
  }
  // subdivide
  const P = V.map(v => [v[0], v[1]]); const mid = new Map(); const quads = [];
  const m = (a, b) => { const k = ek(a, b); if (!mid.has(k)) { mid.set(k, P.length); P.push([(P[a][0] + P[b][0]) / 2, (P[a][1] + P[b][1]) / 2]); } return mid.get(k); };
  for (const p of polys) {
    const cx = p.reduce((s, i) => s + P[i][0], 0) / p.length, cz = p.reduce((s, i) => s + P[i][1], 0) / p.length;
    const ci = P.length; P.push([cx, cz]);
    for (let i = 0; i < p.length; i++) { const pr = p[(i + p.length - 1) % p.length], nx = p[(i + 1) % p.length]; quads.push([p[i], m(p[i], nx), ci, m(pr, p[i])]); }
  }
  // boundary
  const ec = new Map();
  for (const q of quads) for (let i = 0; i < 4; i++) { const k = ek(q[i], q[(i + 1) % 4]); ec.set(k, (ec.get(k) || 0) + 1); }
  const fixed = new Array(P.length).fill(false);
  for (const q of quads) for (let i = 0; i < 4; i++) if (ec.get(ek(q[i], q[(i + 1) % 4])) === 1) { fixed[q[i]] = fixed[q[(i + 1) % 4]] = true; }
  // relax toward squares
  const side = S / 2;
  for (let it = 0; it < 70; it++) {
    const d = P.map(() => [0, 0]);
    for (const q of quads) {
      const cx = (P[q[0]][0] + P[q[1]][0] + P[q[2]][0] + P[q[3]][0]) / 4, cz = (P[q[0]][1] + P[q[1]][1] + P[q[2]][1] + P[q[3]][1]) / 4;
      let fx = 0, fz = 0;
      for (let i = 0; i < 4; i++) { let x = P[q[i]][0] - cx, z = P[q[i]][1] - cz; for (let r = 0; r < i; r++) { const t = x; x = z; z = -t; } fx += x; fz += z; }
      fx /= 4; fz /= 4; const fl = Math.hypot(fx, fz) || 1, target = side * Math.SQRT1_2 * 1.0; fx *= target / fl; fz *= target / fl;
      for (let i = 0; i < 4; i++) { let x = fx, z = fz; for (let r = 0; r < i; r++) { const t = x; x = -z; z = t; } d[q[i]][0] += cx + x - P[q[i]][0]; d[q[i]][1] += cz + z - P[q[i]][1]; }
    }
    for (let i = 0; i < P.length; i++) if (!fixed[i]) { P[i][0] += d[i][0] * 0.12; P[i][1] += d[i][1] * 0.12; }
  }
  // cells
  const cells = quads.map(q => ({ v: q, c: [(P[q[0]][0] + P[q[1]][0] + P[q[2]][0] + P[q[3]][0]) / 4, (P[q[0]][1] + P[q[1]][1] + P[q[2]][1] + P[q[3]][1]) / 4], nb: [-1, -1, -1, -1] }));
  const em = new Map();
  cells.forEach((cl, ci) => { for (let i = 0; i < 4; i++) { const k = ek(cl.v[i], cl.v[(i + 1) % 4]); if (em.has(k)) { const [cj, j] = em.get(k); cl.nb[i] = cj; cells[cj].nb[j] = ci; } else em.set(k, [ci, i]); } });
  return { P, cells };
}
const { P, cells } = buildGrid();

// ---------- palette ----------
const PALETTE = ['#e95c5b', '#ee8a5a', '#f2cf63', '#d9e070', '#a9c07a', '#7fc466', '#48b977', '#46b8a0', '#48afc8', '#5b8fe0', '#7777c9', '#b25670', '#d6ae8e', '#b3a69c', '#ecebe6'];
const ROOFS = ['#e58a5c', '#d7654e', '#eaa865', '#c95f4c'];
const lin = hex => { const c = new THREE.Color(hex); return [c.r, c.g, c.b]; };
const PAL = PALETTE.map(lin), ROOF = ROOFS.map(lin);
const CAP = lin('#ecc27e'), COBBLE = lin('#c7b3a3'), STONE = lin('#b9aea6'), RAIL = lin('#34424f'), FRAME = lin('#f4f1ea'), PANE = lin('#34465f'), PANE_HI = lin('#6d8aa6'), DOOR = lin('#6e4b3b');

// ---------- state ----------
const MAXK = 30;
let blocks = new Map(); // key c*32+k -> color index
const key = (c, k) => c * 32 + k;
const has = (c, k) => c >= 0 && k >= 0 && blocks.has(key(c, k));
const colorOf = (c, k) => blocks.get(key(c, k));

// ---------- geometry building ----------
const G0 = 0.3, FH = 1.0;
const base = k => G0 + (k - 1) * FH;
const FRESH = { k: -1, t: 9 }; // block that pops in after placement
class GB {
  constructor(nofresh) { this.p = []; this.n = []; this.u = []; this.c = []; this.info = []; this.ctx = null; this.alt = nofresh ? null : new GB(true); }
  tri(a, b, c, ca, cb, cc, ua, ub, uc) {
    if (this.alt && this.ctx && FRESH.k === key(this.ctx.c, this.ctx.k)) { this.alt.ctx = this.ctx; return this.alt.tri(a, b, c, ca, cb, cc, ua, ub, uc); }
    const n = norm(cross(sub(b, a), sub(c, a)));
    this.p.push(...a, ...b, ...c); this.n.push(...n, ...n, ...n); this.c.push(...ca, ...cb, ...cc);
    this.u.push(...(ua || [0, 0]), ...(ub || [0, 0]), ...(uc || [0, 0])); this.info.push(this.ctx);
  }
  quad(a, b, c, d, col, uv, want) {
    const cs = Array.isArray(col[0]) ? col : [col, col, col, col];
    const us = uv || [[0, 0], [1, 0], [1, 1], [0, 1]];
    let V = [a, b, c, d], C = cs, U = us;
    if (want && dot(cross(sub(b, a), sub(c, a)), want) < 0) { V = [a, d, c, b]; C = [cs[0], cs[3], cs[2], cs[1]]; U = [us[0], us[3], us[2], us[1]]; }
    this.tri(V[0], V[1], V[2], C[0], C[1], C[2], U[0], U[1], U[2]);
    this.tri(V[0], V[2], V[3], C[0], C[2], C[3], U[0], U[2], U[3]);
  }
  box(ctr, t, n, hx, hy, hz, col) {
    const T = mul(t, hx), U2 = mul(UP, hy), N = mul(n, hz);
    const pt = (sx, sy, sz) => add(add(add(ctr, mul(T, sx)), mul(U2, sy)), mul(N, sz));
    const faces = [[t, [1, -1, -1], [1, 1, -1], [1, 1, 1], [1, -1, 1]], [mul(t, -1), [-1, -1, -1], [-1, -1, 1], [-1, 1, 1], [-1, 1, -1]],
      [UP, [-1, 1, -1], [-1, 1, 1], [1, 1, 1], [1, 1, -1]], [[0, -1, 0], [-1, -1, -1], [1, -1, -1], [1, -1, 1], [-1, -1, 1]],
      [n, [-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1]], [mul(n, -1), [-1, -1, -1], [-1, 1, -1], [1, 1, -1], [1, -1, -1]]];
    for (const [w, ...cs] of faces) this.quad(...cs.map(s => pt(...s)), col, null, w);
  }
  geometry() {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(this.p, 3));
    g.setAttribute('normal', new THREE.Float32BufferAttribute(this.n, 3));
    g.setAttribute('uv', new THREE.Float32BufferAttribute(this.u, 2));
    g.setAttribute('color', new THREE.Float32BufferAttribute(this.c, 3));
    return g;
  }
}
const vp = (i, y) => [P[i][0], y, P[i][1]];
function edgeData(c, i) {
  const cl = cells[c], a = P[cl.v[i]], b = P[cl.v[(i + 1) % 4]];
  const t = norm([b[0] - a[0], 0, b[1] - a[1]]); let n = [t[2], 0, -t[0]];
  const mx = (a[0] + b[0]) / 2, mz = (a[1] + b[1]) / 2;
  if (n[0] * (mx - cl.c[0]) + n[2] * (mz - cl.c[1]) < 0) n = mul(n, -1);
  return { a: cl.v[i], b: cl.v[(i + 1) % 4], t, n, m: [mx, mz], L: Math.hypot(b[0] - a[0], b[1] - a[1]) };
}
const shade = (col, f) => [col[0] * f, col[1] * f, col[2] * f];

const STEPS = [];
function buildTown() {
  STEPS.length = 0;
  const W = new GB(), RF = new GB(), GR = new GB(), ST = new GB(), PL = new GB();
  const lamps = [], bushes = [], finials = [];
  const list = [...blocks.keys()].map(k => [Math.floor(k / 32), k % 32]);
  // ridge choice pass
  const ridge = new Map();
  const conn = (c, k, i) => { const n = cells[c].nb[i]; return has(n, k) && !has(n, k + 1) ? 1 : 0; };
  for (const [c, k] of list) {
    if (k < 1 || has(c, k + 1)) continue;
    const cA = conn(c, k, 0) + conn(c, k, 2), cB = conn(c, k, 1) + conn(c, k, 3);
    let p;
    if (cA !== cB) p = cA > cB ? 0 : 1;
    else { const e = [0, 1, 2, 3].map(i => edgeData(c, i).m); const lA = Math.hypot(e[0][0] - e[2][0], e[0][1] - e[2][1]), lB = Math.hypot(e[1][0] - e[3][0], e[1][1] - e[3][1]); p = lA >= lB ? 0 : 1; }
    ridge.set(key(c, k), p);
  }
  const joined = (c, k, i) => { const n = cells[c].nb[i]; if (!conn(c, k, i)) return false; const j = cells[n].nb.indexOf(c); return ridge.get(key(n, k)) === j % 2; };
  const isTower = (c, k) => k >= 4 && has(c, k - 1) && has(c, k - 2) && has(c, k - 3) && [0, 1, 2, 3].every(i => !has(cells[c].nb[i], k));

  for (const [c, k] of list) {
    const cl = cells[c], ci = colorOf(c, k);
    if (k === 0) {
      // quay / land
      const top = !has(c, 1);
      if (top) {
        GR.ctx = { c, k: 0, t: 'top' };
        const q = cl.v.map(i => vp(i, G0));
        GR.quad(q[0], q[1], q[2], q[3], COBBLE, q.map(p => [p[0] * 0.9, p[2] * 0.9]), UP);
      }
      for (let i = 0; i < 4; i++) {
        const n = cl.nb[i]; if (has(n, 0)) continue;
        const e = edgeData(c, i);
        ST.ctx = { c, k: 0, t: 'side', e: i };
        const A = vp(e.a, -1.4), B = vp(e.b, -1.4), B2 = vp(e.b, G0 - 0.1), A2 = vp(e.a, G0 - 0.1);
        const dk = shade(STONE, 0.45);
        ST.quad(A, B, B2, A2, [dk, dk, STONE, STONE], [[0, -1.4], [e.L, -1.4], [e.L, G0], [0, G0]], e.n);
        // painted trim band
        PL.ctx = { c, k: 0, t: 'side', e: i };
        const col = PAL[ci], o = mul(e.n, 0.035);
        const a0 = add(vp(e.a, G0 - 0.12), o), b0 = add(vp(e.b, G0 - 0.12), o), b1 = add(vp(e.b, G0 + 0.03), o), a1 = add(vp(e.a, G0 + 0.03), o);
        PL.quad(a0, b0, b1, a1, col, null, e.n);
        PL.quad(a1, b1, vp(e.b, G0 + 0.03), vp(e.a, G0 + 0.03), shade(col, 1.08), null, UP);
        PL.quad(a0, b0, add(vp(e.b, G0 - 0.12), mul(e.n, -0.02)), add(vp(e.a, G0 - 0.12), mul(e.n, -0.02)), shade(col, 0.6), null, [0, -1, 0]);
        // landing steps: now and then an open quay edge gets stone steps down into the sea
        const steps = top && !has(n, 1) && e.L > 0.62 && hash(c, i, 21) < 0.16 && i === [0, 1, 2, 3].find(j => !has(cl.nb[j], 0) && edgeData(c, j).L > 0.62) && ![0, 1, 2, 3].some(j => has(cl.nb[j], 1));
        if (steps) {
          STEPS.push([e.m[0], e.m[1], e.n[0], e.n[2]]);
          ST.ctx = { c, k: 0, t: 'side', e: i };
          const N = 4, run = 0.16, w = Math.min(0.56, e.L * 0.6) / 2, M0 = [e.m[0], 0, e.m[1]];
          for (let j = 0; j < N; j++) {
            const yTop = G0 - j * ((G0 + 0.08) / N), out = 0.04 + run * (j + 0.5);
            const ctr = add([M0[0], (yTop - 0.8) / 2, M0[2]], mul(e.n, out));
            ST.box(ctr, e.t, e.n, w, (yTop + 0.8) / 2, run / 2, shade(STONE, 1.02 - j * 0.06));
          }
        }
        if (top) {
          // railing
          PL.ctx = { c, k: 0, t: 'rail' };
          const inset = mul(e.n, -0.06), a = add(vp(e.a, 0), inset), b = add(vp(e.b, 0), inset);
          const posts = Math.max(2, Math.round(e.L / 0.17)), gw = steps ? (Math.min(0.56, e.L * 0.6) / 2 + 0.02) / e.L : 0;
          for (let j = 0; j <= posts; j++) { const f = j / posts; if (steps && Math.abs(f - 0.5) < gw - 0.02) continue; const p = lerp3(a, b, f); p[1] = G0 + 0.17; PL.box(p, e.t, e.n, 0.011, 0.14, 0.011, RAIL); }
          if (!steps) { const mm = lerp3(a, b, 0.5); mm[1] = G0 + 0.32; PL.box(mm, e.t, e.n, e.L / 2 + 0.012, 0.016, 0.02, RAIL); }
          else for (const [f0, f1] of [[0, 0.5 - gw], [0.5 + gw, 1]]) { const mm = lerp3(a, b, (f0 + f1) / 2); mm[1] = G0 + 0.32; PL.box(mm, e.t, e.n, e.L * (f1 - f0) / 2 + 0.012, 0.016, 0.02, RAIL); }
          
        }
      }
      if (top) {
        const nbld = [0, 1, 2, 3].filter(i => has(cl.nb[i], 1));
        let covered = false; for (let kk = 2; kk < MAXK; kk++) if (has(c, kk)) { covered = true; break; }
        if (nbld.length && !covered && hash(c, 3) < 0.42) {
          const e = edgeData(c, nbld[Math.floor(hash(c, 4) * nbld.length)]);
          const s = 0.18 + hash(c, 5) * 0.1;
          bushes.push([cl.c[0] + (e.m[0] - cl.c[0]) * 0.55, G0 + s * 0.8, cl.c[1] + (e.m[1] - cl.c[1]) * 0.55, s, hash(c, 6)]);
        }
      }
      continue;
    }
    // building floor
    const yb = base(k), yt = yb + FH;
    const tint = 0.95 + hash(c, k, 1) * 0.08;
    const wc = shade(PAL[ci], tint);
    const roofTop = !has(c, k + 1);
    let doorDone = false;
    for (let i = 0; i < 4; i++) {
      const n = cl.nb[i]; if (has(n, k)) continue;
      const e = edgeData(c, i);
      W.ctx = { c, k, t: 'wall', e: i };
      const bf = (k === 1 || !has(c, k - 1)) ? 0.72 : 1, tf = roofTop ? 0.88 : 1;
      W.quad(vp(e.a, yb), vp(e.b, yb), vp(e.b, yt), vp(e.a, yt), [shade(wc, bf), shade(wc, bf), shade(wc, tf), shade(wc, tf)], [[0, yb], [e.L, yb], [e.L, yt], [0, yt]], e.n);
      // openings
      PL.ctx = { c, k, t: 'wall', e: i };
      const M = [e.m[0], 0, e.m[1]];
      const at = (dx, y, off) => add(add([M[0], y, M[2]], mul(e.t, dx)), mul(e.n, off));
      const rect = (cx, cy, w, h, off, col) => PL.quad(at(cx - w / 2, cy - h / 2, off), at(cx + w / 2, cy - h / 2, off), at(cx + w / 2, cy + h / 2, off), at(cx - w / 2, cy + h / 2, off), col, null, e.n);
      const doorOk = k === 1 && !doorDone && has(n, 0) && !has(n, 1) && e.L > 0.45;
      if (doorOk && hash(c, i, 7) < 0.7) {
        doorDone = true;
        const w = 0.26, h = 0.52;
        rect(0, yb + h / 2 + 0.01, w + 0.07, h + 0.05, 0.012, FRAME);
        rect(0, yb + h / 2, w, h, 0.02, DOOR);
        rect(0, yb + h - 0.08, w * 0.6, 0.1, 0.024, PANE_HI);
        lamps.push(at(w / 2 + 0.12, yb + 0.62, 0.06));
        continue;
      }
      if (e.L < 0.5 || hash(c, k, i, 9) > (isColumnTall(c) ? 0.95 : 0.8)) continue;
      const w = Math.min(0.3, e.L * 0.34), h = 0.34, cy = yb + FH * 0.55;
      rect(0, cy, w + 0.07, h + 0.07, 0.012, FRAME);
      rect(0, cy + h * 0.25, w - 0.02, h * 0.45, 0.02, PANE_HI);
      rect(0, cy - h * 0.25, w - 0.02, h * 0.45, 0.02, PANE);
      rect(0, cy, 0.025, h, 0.026, FRAME);
      rect(0, cy, w, 0.025, 0.026, FRAME);
      rect(0, cy - h / 2 - 0.045, w + 0.12, 0.035, 0.03, shade(FRAME, 0.92));
    }
    if (k > 1 && !has(c, k - 1)) {
      W.ctx = { c, k, t: 'under' };
      const q = cl.v.map(i => vp(i, yb));
      W.quad(q[0], q[1], q[2], q[3], shade(wc, 0.6), q.map(p => [p[0], p[2]]), [0, -1, 0]);
      // arcade: corner piers down to whatever is below, arched spandrels on every open side
      let kb = k - 1; while (kb > 0 && !has(c, kb)) kb--;
      const onWater = kb === 0 && !has(c, 0);
      if (onWater) {
        // stilts: slim timber posts straight into the sea, braced under the floor
        const post = shade(DOOR, 1.25), yw = -0.5;
        const inset = q => [cl.c[0] + (q[0] - cl.c[0]) * 0.86, cl.c[1] + (q[1] - cl.c[1]) * 0.86];
        const cs = cl.v.map(i => inset(P[i]));
        for (const p of cs) W.box([p[0], (yb + yw) / 2, p[1]], [1, 0, 0], [0, 0, 1], 0.045, (yb - yw) / 2, 0.045, post);
        for (let i = 0; i < 4; i++) { const p0 = cs[i], p1 = cs[(i + 1) % 4], m = [(p0[0] + p1[0]) / 2, yb - 0.12, (p0[1] + p1[1]) / 2], t = norm([p1[0] - p0[0], 0, p1[1] - p0[1]]); W.box(m, t, [t[2], 0, -t[0]], Math.hypot(p1[0] - p0[0], p1[1] - p0[1]) / 2, 0.035, 0.03, post); }
      }
      const ySup = kb === 0 ? G0 : base(kb) + FH, gap = yb - ySup;
      const d = Math.min(0.42, gap * 0.5), th = 0.1, pw = 0.055;
      for (let i = 0; i < 4 && !onWater; i++) {
        const e = edgeData(c, i); if (has(cl.nb[i], k - 1) && has(cl.nb[i], k)) continue;
        const A = P[e.a], Bp = P[e.b], N = 14, inw = mul(e.n, -th);
        const pt = (s, y, o) => { const p = [A[0] + (Bp[0] - A[0]) * s, y, A[1] + (Bp[1] - A[1]) * s]; return o ? add(p, o) : p; };
        const sp = pw / e.L; // arch springs just inside the piers
        const arcY = s => { const u = (s - sp) / (1 - 2 * sp); return u <= 0 || u >= 1 ? yb - d : yb - 0.07 - (d - 0.07) * (1 - Math.sin(Math.PI * u)); };
        for (let j = 0; j < N; j++) {
          const s0 = j / N, s1 = (j + 1) / N, y0 = arcY(s0), y1 = arcY(s1);
          const ca = shade(wc, 0.82), cb = shade(wc, 0.9);
          W.quad(pt(s0, y0), pt(s1, y1), pt(s1, yb), pt(s0, yb), [ca, ca, cb, cb], [[s0 * e.L, y0], [s1 * e.L, y1], [s1 * e.L, yb], [s0 * e.L, yb]], e.n);
          const so = shade(wc, 0.55);
          W.quad(pt(s0, y0), pt(s1, y1), pt(s1, y1, inw), pt(s0, y0, inw), so, null, [0, -1, 0]);
        }
        // piers at the two ends of this side, down to the support
        for (const s of [sp * 0.5, 1 - sp * 0.5]) {
          const cp = pt(s, 0, mul(e.n, -th / 2)); const h = (yb - d) - ySup;
          if (h > 0.02) W.box([cp[0], ySup + h / 2, cp[2]], e.t, e.n, pw * 0.5, h / 2, th / 2, shade(wc, 0.86));
        }
      }
    }
    if (!roofTop) continue;
    RF.ctx = { c, k, t: 'top' };
    if (isTower(c, k)) {
      PL.ctx = { c, k, t: 'top' };
      // octagonal bell cap + finial
      const ring = [];
      for (let i = 0; i < 4; i++) { const a = P[cl.v[i]], b = P[cl.v[(i + 1) % 4]]; for (const f of [0.2, 0.8]) ring.push([a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f]); }
      const C = cl.c, rp = (s, y) => ring.map(p => [C[0] + (p[0] - C[0]) * s, y, C[1] + (p[1] - C[1]) * s]);
      // bell profile: thin white eave, then a soft ogee in smooth gold up to the finial
      const prof = [[1.14, -0.02, FRAME], [1.1, 0.07, FRAME], [1.0, 0.09, CAP], [0.97, 0.3, CAP], [0.86, 0.52, CAP], [0.68, 0.74, CAP], [0.46, 0.94, CAP], [0.26, 1.1, CAP], [0.1, 1.22, CAP]];
      const rings = prof.map(([sc, dy]) => rp(sc, yt + dy)), apex = [C[0], yt + 1.3, C[1]];
      const q = cl.v.map(i => vp(i, yt)); PL.quad(q[0], q[1], q[2], q[3], CAP, null, UP);
      for (let r = 0; r < rings.length - 1; r++) {
        const A = rings[r], Bq = rings[r + 1], col = prof[r][2] === FRAME && prof[r + 1][2] === FRAME ? FRAME : null;
        const f0 = 0.84 + 0.2 * (r / rings.length), f1 = 0.84 + 0.2 * ((r + 1) / rings.length);
        for (let i = 0; i < 8; i++) {
          const j = (i + 1) % 8, out = norm([(A[i][0] + A[j][0]) / 2 - C[0], 0.5, (A[i][2] + A[j][2]) / 2 - C[1]]);
          const c0 = col || shade(CAP, f0), c1 = col || shade(CAP, f1);
          PL.quad(A[i], A[j], Bq[j], Bq[i], [c0, c0, c1, c1], null, out);
        }
      }
      const L8 = rings[rings.length - 1];
      for (let i = 0; i < 8; i++) { const j = (i + 1) % 8, out = norm([(L8[i][0] + L8[j][0]) / 2 - C[0], 0.8, (L8[i][2] + L8[j][2]) / 2 - C[1]]); let a0 = L8[i], b0 = L8[j]; if (dot(cross(sub(b0, a0), sub(apex, a0)), out) < 0) [a0, b0] = [b0, a0]; PL.tri(a0, b0, apex, CAP, CAP, shade(CAP, 1.05)); }
      finials.push([apex[0], apex[1], apex[2], ci]);
      continue;
    }
    const p = ridge.get(key(c, k));
    const rc = ROOF[(ci + (hash(c, 2) < 0.5 ? 0 : 1)) % ROOF.length];
    const E = [0, 1, 2, 3].map(i => edgeData(c, i));
    const rh = 0.72, oh = 0.13, drop = 0.08;
    const vi = i => cl.v[(p + i) % 4];
    let v0 = vp(vi(0), yt - drop), v1 = vp(vi(1), yt - drop), v2 = vp(vi(2), yt - drop), v3 = vp(vi(3), yt - drop);
    const eA = E[(p + 1) % 4], eB = E[(p + 3) % 4];
    v1 = add(v1, mul(eA.n, oh)); v2 = add(v2, mul(eA.n, oh)); v3 = add(v3, mul(eB.n, oh)); v0 = add(v0, mul(eB.n, oh));
    let R1 = [E[p].m[0], yt + rh, E[p].m[1]], R2 = [E[(p + 2) % 4].m[0], yt + rh, E[(p + 2) % 4].m[1]];
    const rd = norm(sub(R2, R1));
    const j1 = joined(c, k, p), j2 = joined(c, k, (p + 2) % 4);
    if (!j1) { const s = mul(rd, -0.1); R1 = add(R1, s); v0 = add(v0, s); v1 = add(v1, s); }
    if (!j2) { const s = mul(rd, 0.1); R2 = add(R2, s); v2 = add(v2, s); v3 = add(v3, s); }
    const ruv = pt => [pt[0] * rd[0] + pt[2] * rd[2], (pt[1] - yt) * 2.2];
    const upA = norm(add(eA.n, [0, 1.2, 0])), upB = norm(add(eB.n, [0, 1.2, 0]));
    RF.quad(v1, v2, R2, R1, [shade(rc, 0.9), shade(rc, 0.9), rc, rc], [v1, v2, R2, R1].map(ruv), upA);
    RF.quad(v3, v0, R1, R2, [shade(rc, 0.9), shade(rc, 0.9), rc, rc], [v3, v0, R1, R2].map(ruv), upB);
    // gables
    W.ctx = { c, k, t: 'wall', e: p };
    for (const [ei, jn, Rp] of [[p, j1, [E[p].m[0], yt + rh, E[p].m[1]]], [(p + 2) % 4, j2, [E[(p + 2) % 4].m[0], yt + rh, E[(p + 2) % 4].m[1]]]]) {
      if (jn) continue;
      const e = E[ei]; W.ctx = { c, k, t: 'wall', e: ei };
      const A = vp(e.a, yt), B = vp(e.b, yt);
      const nn = e.n; let a = A, b = B;
      if (dot(cross(sub(b, a), sub(Rp, a)), nn) < 0) [a, b] = [b, a];
      W.tri(a, b, Rp, shade(wc, 0.9), shade(wc, 0.9), shade(wc, 0.84), [0, yt], [e.L, yt], [e.L / 2, yt + rh]);
      if (e.L > 0.6 && hash(c, k, ei, 11) < 0.6) {
        PL.ctx = { c, k, t: 'wall', e: ei };
        const Mx = [e.m[0], yt + 0.26, e.m[1]], o = mul(nn, 0.015), tt = e.t;
        const sq = (w, h, off, col) => { const O = mul(nn, off); PL.quad(add(add(Mx, mul(tt, -w)), add([0, -h, 0], O)), add(add(Mx, mul(tt, w)), add([0, -h, 0], O)), add(add(Mx, mul(tt, w)), add([0, h, 0], O)), add(add(Mx, mul(tt, -w)), add([0, h, 0], O)), col, null, nn); };
        sq(0.08, 0.09, 0.012, FRAME); sq(0.055, 0.065, 0.02, PANE);
      }
    }
    // chimney
    if (hash(c, k, 13) < 0.28 && E[p].L > 0.5) {
      W.ctx = { c, k, t: 'top' };
      const eb = E[(p + 3) % 4];
      const mb = [eb.m[0], yt, eb.m[1]], mr = lerp3(R1, R2, 0.3);
      const pos = lerp3(mb, [mr[0], yt, mr[2]], 0.55); const hr = yt + rh * 0.55;
      const topY = yt + rh + 0.22, bot = hr - 0.1;
      W.box([pos[0], (topY + bot) / 2, pos[2]], rd, [rd[2], 0, -rd[0]], 0.08, (topY - bot) / 2, 0.08, shade(wc, 0.85));
    }
  }
  return { W, RF, GR, ST, PL, lamps, bushes, finials };
}
function isColumnTall(c) { let n = 0; for (let k = 1; k < MAXK; k++) if (has(c, k)) n++; return n >= 4; }

// ---------- textures ----------
function canvasTex(size, draw, repeat = 1) {
  const cv = document.createElement('canvas'); cv.width = cv.height = size; const g = cv.getContext('2d'); const r = rng(size + repeat * 7);
  draw(g, size, r); const t = new THREE.CanvasTexture(cv); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8; return t;
}
const texBrick = canvasTex(128, (g, s, r) => {
  g.fillStyle = '#d9d6d2'; g.fillRect(0, 0, s, s);
  const bh = 8, bw = 16;
  for (let y = 0; y < s; y += bh) for (let x = -bw; x < s; x += bw) { const ox = (y / bh) % 2 ? bw / 2 : 0; const v = 222 + r() * 33 | 0; g.fillStyle = `rgb(${v},${v},${v})`; g.fillRect(x + ox + 1, y + 1, bw - 1, bh - 1); }
});
const texTile = canvasTex(128, (g, s, r) => {
  g.fillStyle = '#a8a4a0'; g.fillRect(0, 0, s, s);
  const th = 12.8, tw = 14;
  for (let row = 0; row < 10; row++) { const y = row * th; for (let x = -tw; x < s + tw; x += tw) { const ox = row % 2 ? tw / 2 : 0; const v = 215 + r() * 40 | 0; const gr = g.createLinearGradient(0, y, 0, y + th); gr.addColorStop(0, `rgb(${v},${v},${v})`); gr.addColorStop(1, `rgb(${v - 45},${v - 45},${v - 45})`); g.fillStyle = gr; g.beginPath(); g.roundRect(x + ox + 0.5, y, tw - 1, th - 1, [0, 0, 5, 5]); g.fill(); } }
});
const texCobble = canvasTex(128, (g, s, r) => {
  g.fillStyle = '#a9a4a0'; g.fillRect(0, 0, s, s);
  for (let i = 0; i < 260; i++) { const x = r() * s, y = r() * s, rr = 3 + r() * 4, v = 200 + r() * 50 | 0; g.fillStyle = `rgb(${v},${v - 4},${v - 8})`; for (const dx of [-s, 0, s]) for (const dy of [-s, 0, s]) { g.beginPath(); g.ellipse(x + dx, y + dy, rr, rr * 0.8, r() * 3, 0, 7); g.fill(); } }
});
const texStone = canvasTex(128, (g, s, r) => {
  g.fillStyle = '#8f8a86'; g.fillRect(0, 0, s, s);
  for (let y = 0; y < s; y += 21.33) for (let x = -40; x < s; x += 32) { const ox = Math.round(y / 21.33) % 2 ? 16 : 0; const v = 190 + r() * 55 | 0; g.fillStyle = `rgb(${v},${v},${v})`; g.fillRect(x + ox + 1.5, y + 1.5, 29, 18.5); }
});
texBrick.repeat.set(1, 1); texTile.repeat.set(1.4, 1); texCobble.repeat.set(0.9, 0.9); texStone.repeat.set(1.3, 1.3);

// ---------- scene ----------
const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance', preserveDrawingBuffer: false });
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.setSize(innerWidth, innerHeight);
renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 1.28;
document.body.prepend(renderer.domElement);
const scene = new THREE.Scene();
const FOG = new THREE.Color('#4a898e');
scene.background = FOG; scene.fog = new THREE.Fog(FOG, 45, 120);
const camera = new THREE.PerspectiveCamera(30, innerWidth / innerHeight, 0.5, 400);
const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true; controls.dampingFactor = 0.08; controls.rotateSpeed = 0.55; controls.zoomSpeed = 0.8;
controls.minDistance = 7; controls.maxDistance = 75; controls.minPolarAngle = 0.25; controls.maxPolarAngle = 1.38;
controls.touches = { ONE: THREE.TOUCH.ROTATE, TWO: THREE.TOUCH.DOLLY_PAN };
controls.mouseButtons = { LEFT: THREE.MOUSE.ROTATE, MIDDLE: THREE.MOUSE.DOLLY, RIGHT: THREE.MOUSE.PAN };
controls.target.set(1.3, 3.3, -0.7);
let userFramed = false;
// frame the whole town (tower cap included) with breathing room, whatever the screen shape
function fitView() {
  let x0 = 1e9, x1 = -1e9, z0 = 1e9, z1 = -1e9, y1 = 2;
  for (const kk of blocks.keys()) { const c = Math.floor(kk / 32), k = kk % 32; for (const i of cells[c].v) { x0 = Math.min(x0, P[i][0]); x1 = Math.max(x1, P[i][0]); z0 = Math.min(z0, P[i][1]); z1 = Math.max(z1, P[i][1]); } y1 = Math.max(y1, k === 0 ? G0 + 0.5 : base(k) + FH + 1.4); }
  if (x0 > x1) { x0 = z0 = -3; x1 = z1 = 3; }
  const cx = (x0 + x1) / 2, cz = (z0 + z1) / 2, cy = y1 * 0.5;
  const az = 0.55, pol = 1.02, dir = new THREE.Vector3(Math.sin(pol) * Math.sin(az), Math.cos(pol), Math.sin(pol) * Math.cos(az));
  const corners = []; for (const x of [x0, x1]) for (const y of [-0.3, y1]) for (const z of [z0, z1]) corners.push(new THREE.Vector3(x, y, z));
  // project the town's bounding box and pick the closest distance that keeps it inside the safe area
  const mx = camera.aspect < 1 ? 0.72 : 0.8, my = 0.78, v = new THREE.Vector3();
  const fits = d => { camera.position.set(cx, cy, cz).addScaledVector(dir, d); camera.lookAt(cx, cy, cz); camera.updateMatrixWorld(); let lo = 1, hi = -1; for (const p of corners) { v.copy(p).project(camera); if (Math.abs(v.x) > mx) return false; lo = Math.min(lo, v.y); hi = Math.max(hi, v.y); } return hi - lo < 2 * my; };
  let lo = controls.minDistance, hi = controls.maxDistance; for (let i = 0; i < 24; i++) { const m = (lo + hi) / 2; fits(m) ? hi = m : lo = m; }
  fits(hi);
  // re-centre vertically on the projected box so the tower never clips
  let ylo = 1, yhi = -1; for (const p of corners) { v.copy(p).project(camera); ylo = Math.min(ylo, v.y); yhi = Math.max(yhi, v.y); }
  const shift = (ylo + yhi) / 2 * Math.tan(THREE.MathUtils.degToRad(camera.fov) / 2) * hi;
  const t = new THREE.Vector3(cx, cy + shift * Math.sin(pol), cz); camera.position.set(t.x, t.y, t.z).addScaledVector(dir, hi);
  controls.target.copy(t);
  controls.update();
}
controls.addEventListener('start', () => { userFramed = true; });

scene.add(new THREE.HemisphereLight('#e2f1ee', '#b89484', 1.6));
const sun = new THREE.DirectionalLight('#fff0d8', 2.4);
sun.position.set(-14, 22, 10); sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048); const sc = sun.shadow.camera; sc.left = -18; sc.right = 18; sc.top = 18; sc.bottom = -18; sc.near = 1; sc.far = 70;
sun.shadow.bias = -0.0006; sun.shadow.normalBias = 0.02; sun.shadow.radius = 3;
scene.add(sun); scene.add(sun.target);
const fill = new THREE.DirectionalLight('#ffd9c4', 0.55); fill.position.set(12, 8, -10); scene.add(fill);

const mat = (map, extra = {}) => new THREE.MeshLambertMaterial({ vertexColors: true, map, ...extra });
const MAT = { W: mat(texBrick), RF: mat(texTile, { side: THREE.DoubleSide }), GR: mat(texCobble), ST: mat(texStone), PL: mat(null) };
const town = new THREE.Group(); scene.add(town);
const outlineMat = new THREE.LineBasicMaterial({ color: '#1f2d36', transparent: true, opacity: 0.5 });

// water with foam from a blurred land mask
const MS = 256, MB = 17;
const maskData = new Uint8Array(MS * MS);
const maskTex = new THREE.DataTexture(maskData, MS, MS, THREE.RedFormat); maskTex.magFilter = maskTex.minFilter = THREE.LinearFilter; maskTex.needsUpdate = true;
const waterU = { uMask: { value: maskTex }, uTime: { value: 0 }, uShallow: { value: new THREE.Color('#7db8ae') } };
const waterMat = new THREE.MeshLambertMaterial({ color: '#3a7e85' });
waterMat.onBeforeCompile = sh => {
  Object.assign(sh.uniforms, waterU);
  sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 vW;').replace('#include <begin_vertex>', '#include <begin_vertex>\nvW = (modelMatrix * vec4(position,1.0)).xyz;');
  sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nvarying vec3 vW; uniform sampler2D uMask; uniform float uTime; uniform vec3 uShallow;')
    .replace('#include <color_fragment>', `#include <color_fragment>
      vec2 muv = (vW.xz + ${MB.toFixed(1)}) / ${(2 * MB).toFixed(1)};
      float m = texture2D(uMask, vec2(muv.x, muv.y)).r;
      float n = sin(vW.x*0.35 + uTime*0.25)*sin(vW.z*0.3 - uTime*0.2);
      diffuseColor.rgb *= 0.97 + 0.05*n;
      diffuseColor.rgb = mix(diffuseColor.rgb, uShallow, smoothstep(0.08, 0.55, m)*0.6);
      float ring = 0.5 + 0.5*sin(m*26.0 - uTime*1.1 + n*0.6);
      float foam = smoothstep(0.8, 0.97, ring) * smoothstep(0.12, 0.26, m) * (1.0 - smoothstep(0.34, 0.44, m)) * 0.3;
      foam += smoothstep(0.47, 0.53, m)*0.5;
      diffuseColor.rgb = mix(diffuseColor.rgb, vec3(0.93,0.97,0.94), clamp(foam, 0.0, 1.0)*0.9);`);
};
const water = new THREE.Mesh(new THREE.PlaneGeometry(400, 400, 1, 1), waterMat);
water.rotation.x = -Math.PI / 2; water.receiveShadow = true; scene.add(water);

function rebuildMask() {
  const cv = document.createElement('canvas'); cv.width = cv.height = MS; const g = cv.getContext('2d');
  g.fillStyle = '#000'; g.fillRect(0, 0, MS, MS); g.fillStyle = '#fff';
  const tp = (x, z) => [(x + MB) / (2 * MB) * MS, (z + MB) / (2 * MB) * MS];
  cells.forEach((cl, c) => { if (!has(c, 0)) return; g.beginPath(); cl.v.forEach((i, j) => { const [x, y] = tp(P[i][0], P[i][1]); j ? g.lineTo(x, y) : g.moveTo(x, y); }); g.closePath(); g.fill(); });
  const img = g.getImageData(0, 0, MS, MS).data; let a = new Float32Array(MS * MS), b = new Float32Array(MS * MS);
  for (let i = 0; i < MS * MS; i++) a[i] = img[i * 4] / 255;
  const r = 5;
  for (let pass = 0; pass < 3; pass++) {
    for (let y = 0; y < MS; y++) { let s = 0; for (let x = -r; x <= r; x++) s += a[y * MS + Math.min(MS - 1, Math.max(0, x))]; for (let x = 0; x < MS; x++) { b[y * MS + x] = s / (2 * r + 1); s += a[y * MS + Math.min(MS - 1, x + r + 1)] - a[y * MS + Math.max(0, x - r)]; } }
    for (let x = 0; x < MS; x++) { let s = 0; for (let y = -r; y <= r; y++) s += b[Math.min(MS - 1, Math.max(0, y)) * MS + x]; for (let y = 0; y < MS; y++) { a[y * MS + x] = s / (2 * r + 1); s += b[Math.min(MS - 1, y + r + 1) * MS + x] - b[Math.max(0, y - r) * MS + x]; } }
  }
  for (let i = 0; i < MS * MS; i++) maskData[i] = Math.min(255, a[i] * 255);
  maskTex.needsUpdate = true;
}

// instanced details
const bushGeo = new THREE.IcosahedronGeometry(1, 1);
const bushMat = new THREE.MeshLambertMaterial({ color: '#ffffff' });
const lampMat = new THREE.MeshBasicMaterial({ color: '#ffe6a3' });
const lampGeo = new THREE.SphereGeometry(0.045, 10, 8);
const finGeo = new THREE.LatheGeometry([[0, 0], [0.05, 0.02], [0.09, 0.12], [0.05, 0.2], [0.025, 0.24], [0.025, 0.3], [0.05, 0.36], [0.012, 0.52], [0, 0.56]].map(p => new THREE.Vector2(p[0], p[1])), 10);
const finMat = new THREE.MeshLambertMaterial({ color: '#ffffff' });

let pickables = [], popGroup = null;
// spring overshoot: 0 -> 1 with one soft bounce, like a block settling into place
function popCurve(t) { if (t >= 1) return 1; return 1 - Math.exp(-7 * t) * Math.cos(9.5 * t); }
function applyPop(t) { if (!popGroup) return; const u = popCurve(t / 0.42); const sy = Math.max(0.02, u), sx = 0.72 + 0.28 * Math.min(1.15, u); popGroup.scale.set(sx, sy, sx); if (t >= 0.42) { popGroup.scale.set(1, 1, 1); popGroup = null; } }
function rebuild() {
  for (const o of [...town.children]) { town.remove(o); o.traverse(x => x.geometry?.dispose()); }
  popGroup = null;
  const B = buildTown(); pickables = [];
  const outlineGeos = [];
  const pop = new THREE.Group(), popOutl = [];
  for (const k of ['W', 'RF', 'GR', 'ST', 'PL']) {
    for (const [gb, parent, outl] of [[B[k], town, outlineGeos], [B[k].alt, pop, popOutl]]) {
      if (!gb.p.length) continue;
      const geo = gb.geometry(); const m = new THREE.Mesh(geo, MAT[k]);
      m.castShadow = k !== 'GR'; m.receiveShadow = true; m.userData.info = gb.info; parent.add(m); pickables.push(m);
      if (k !== 'PL') outl.push(new THREE.EdgesGeometry(geo, 28));
    }
  }
  for (const eg of outlineGeos) town.add(new THREE.LineSegments(eg, outlineMat));
  for (const eg of popOutl) pop.add(new THREE.LineSegments(eg, outlineMat));
  if (pop.children.length) {
    // pivot the popping block around its base centre so it springs up out of its footprint
    const c = Math.floor(FRESH.k / 32), k = FRESH.k % 32, cl = cells[c];
    const px = cl.c[0], py = k === 0 ? -0.2 : base(k), pz = cl.c[1];
    pop.position.set(px, py, pz); for (const ch of pop.children) ch.position.set(-px, -py, -pz);
    pop.userData.pop = true; town.add(pop); popGroup = pop; FRESH.t = 0; applyPop(0);
  }
  const inst = (geo, material, arr, fn) => { if (!arr.length) return; const im = new THREE.InstancedMesh(geo, material, arr.length); const M = new THREE.Matrix4(), col = new THREE.Color(); arr.forEach((a, i) => { fn(M, col, a); im.setMatrixAt(i, M); im.setColorAt(i, col); }); im.castShadow = true; im.receiveShadow = true; town.add(im); };
  const greens = ['#3f7a4f', '#4d8a4a', '#35684a'];
  inst(bushGeo, bushMat, B.bushes, (M, col, b) => { M.compose(new THREE.Vector3(b[0], b[1], b[2]), new THREE.Quaternion().setFromEuler(new THREE.Euler(b[4] * 3, b[4] * 5, 0)), new THREE.Vector3(b[3], b[3] * 1.05, b[3])); col.set(greens[Math.floor(b[4] * 3)]); });
  inst(lampGeo, lampMat, B.lamps, (M, col, p) => { M.makeTranslation(p[0], p[1], p[2]); col.set('#ffe6a3'); });
  inst(finGeo, finMat, B.finials, (M, col, f) => { M.makeTranslation(f[0], f[1] - 0.04, f[2]); col.setRGB(...shade(PAL[f[3]], 0.7)); });
  rebuildMask();
}

// ---------- gulls ----------
const gulls = [];
{
  const wing = new THREE.BufferGeometry(); wing.setAttribute('position', new THREE.Float32BufferAttribute([0, 0, -0.07, 0, 0, 0.07, 0.42, 0.02, 0.0], 3)); wing.computeVertexNormals();
  const gm = new THREE.MeshLambertMaterial({ color: '#f7f7f2', side: THREE.DoubleSide });
  for (let i = 0; i < 4; i++) {
    const g = new THREE.Group(); const l = new THREE.Mesh(wing, gm), r = new THREE.Mesh(wing, gm); r.scale.x = -1; g.add(l, r);
    const body = new THREE.Mesh(new THREE.SphereGeometry(0.06, 8, 6), gm); body.scale.set(1, 0.8, 2.2); g.add(body);
    g.userData = { l, r, rad: 4 + i * 1.6, h: 7 + i * 1.3, sp: 0.18 + i * 0.05, ph: i * 1.7 }; scene.add(g); gulls.push(g);
  }
}

// ---------- ripples ----------
const ripples = [];
const rippleGeo = new THREE.RingGeometry(0.9, 1, 48); rippleGeo.rotateX(-Math.PI / 2);
function ripple(p) { const m = new THREE.Mesh(rippleGeo, new THREE.MeshBasicMaterial({ color: '#ffffff', transparent: true, opacity: 0.8, depthWrite: false })); m.position.set(p.x, p.y + 0.02, p.z); m.scale.setScalar(0.2); scene.add(m); ripples.push({ m, t: 0 }); }

// ---------- sound ----------
let AC = null;
function tone(k, remove) {
  try {
    AC = AC || new (window.AudioContext || window.webkitAudioContext)();
    const scale = [0, 2, 4, 7, 9]; const n = remove ? -5 : scale[k % 5] + 12 * Math.floor(k / 5);
    const f = 392 * Math.pow(2, Math.min(n, 24) / 12), t = AC.currentTime;
    const o = AC.createOscillator(), g = AC.createGain(); o.type = 'triangle'; o.frequency.value = f;
    g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.09, t + 0.01); g.gain.exponentialRampToValueAtTime(0.0001, t + (remove ? 0.25 : 0.6));
    o.connect(g).connect(AC.destination); o.start(t); o.stop(t + 0.7);
  } catch (e) { }
}

// ---------- save / share ----------
const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
function encode() {
  const out = []; for (const [k, col] of [...blocks].sort((a, b) => a[0] - b[0])) { const c = Math.floor(k / 32), lv = k % 32; const v = (c << 12) | (lv << 6) | col; out.push(B64[(v >> 18) & 63], B64[(v >> 12) & 63], B64[(v >> 6) & 63], B64[v & 63]); }
  return 'g' + GRID_SEED + '.' + out.join('');
}
function decode(s) {
  const m = /^g(\d+)\.([A-Za-z0-9_-]*)$/.exec(s || ''); if (!m || +m[1] !== GRID_SEED) return null;
  const d = m[2], res = new Map();
  for (let i = 0; i + 3 < d.length; i += 4) { const v = (B64.indexOf(d[i]) << 18) | (B64.indexOf(d[i + 1]) << 12) | (B64.indexOf(d[i + 2]) << 6) | B64.indexOf(d[i + 3]); const c = v >> 12, lv = (v >> 6) & 63, col = v & 63; if (c < cells.length && lv < MAXK && col < PALETTE.length) res.set(key(c, lv), col); }
  return res;
}
function save() { const s = encode(); try { localStorage.setItem('tidemill.town.v3', s); } catch (e) { } history.replaceState(null, '', '#' + s); }

// ---------- default town: a tall red tower on a small quay ----------
function defaultTown() {
  const bm = new Map();
  const near = (x, z, excl = []) => { let best = -1, bd = 1e9; cells.forEach((cl, i) => { if (excl.includes(i)) return; const d = Math.hypot(cl.c[0] - x, cl.c[1] - z); if (d < bd) { bd = d; best = i; } }); return best; };
  const c0 = near(0, 0), C = cells[c0].c;
  const land = c => bm.set(key(c, 0), 0);
  cells.forEach((cl, i) => { if (Math.hypot(cl.c[0] - C[0], cl.c[1] - C[1]) < 1.55) land(i); });
  const th = -0.5, dir = [Math.cos(th), Math.sin(th)], perp = [-dir[1], dir[0]];
  const seg = (ax, az, bx, bz) => cells.forEach((cl, i) => { const px = cl.c[0] - ax, pz = cl.c[1] - az, vx = bx - ax, vz = bz - az; const t = Math.max(0, Math.min(1, (px * vx + pz * vz) / (vx * vx + vz * vz))); if (Math.hypot(px - vx * t, pz - vz * t) < 0.5) land(i); });
  seg(C[0], C[1], C[0] + dir[0] * 4.4, C[1] + dir[1] * 4.4);
  const jx = C[0] + dir[0] * 2.6, jz = C[1] + dir[1] * 2.6; seg(jx - perp[0] * 1.9, jz - perp[1] * 1.9, jx + perp[0] * 2.1, jz + perp[1] * 2.1);
  for (let k = 1; k <= 10; k++) bm.set(key(c0, k), 0);
  const back = [-dir[0], -dir[1]];
  const put = (x, z, h, col) => { const c = near(x, z, [c0]); bm.set(key(c, 0), 0); for (let k = 1; k <= h; k++) bm.set(key(c, k), col); return c; };
  const rot = (v, a) => [v[0] * Math.cos(a) - v[1] * Math.sin(a), v[0] * Math.sin(a) + v[1] * Math.cos(a)];
  const h1 = rot(back, 1.1), h2 = rot(back, -1.2), h3 = rot(back, 2.3);
  put(C[0] + h1[0] * 1.25, C[1] + h1[1] * 1.25, 3, 0);
  put(C[0] + h2[0] * 1.3, C[1] + h2[1] * 1.3, 2, 0);
  const y1 = put(C[0] + h3[0] * 1.35, C[1] + h3[1] * 1.35, 1, 2);
  const yc = cells[y1].c, y2 = cells[y1].nb.find(n => n >= 0 && !bm.has(key(n, 1)) && Math.hypot(cells[n].c[0] - C[0], cells[n].c[1] - C[1]) > 1.3);
  if (y2 >= 0 && y2 !== undefined) { bm.set(key(y2, 0), 0); bm.set(key(y2, 1), 2); }
  return bm;
}

// ---------- interaction ----------
let color = 0, erase = false; const undoStack = [];
const pal = document.getElementById('pal');
PALETTE.forEach((h, i) => { const b = document.createElement('button'); b.style.background = h; b.ariaLabel = 'Colour ' + (i + 1); b.onclick = () => { color = i; setErase(false); [...pal.children].forEach((x, j) => x.classList.toggle('on', j === i)); }; pal.appendChild(b); });
pal.children[0].classList.add('on');
const eraseBtn = document.getElementById('erase');
function setErase(v) { erase = v; eraseBtn.classList.toggle('on', v); }
eraseBtn.onclick = () => setErase(!erase);
document.getElementById('undo').onclick = () => { if (!undoStack.length) return; blocks = undoStack.pop(); rebuild(); save(); tone(0, true); };
const toast = document.getElementById('toast');
function say(t) { toast.textContent = t; toast.classList.add('show'); clearTimeout(say.t); say.t = setTimeout(() => toast.classList.remove('show'), 1800); }
document.getElementById('share').onclick = async () => {
  save(); const url = location.href;
  try { if (navigator.share) { await navigator.share({ title: 'My Tidemill town', url }); return; } await navigator.clipboard.writeText(url); say('Link copied'); } catch (e) { say('Link is in the address bar'); }
};

const ray = new THREE.Raycaster(), ndc = new THREE.Vector2(), plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
function cellAt(x, z) {
  for (let c = 0; c < cells.length; c++) { const v = cells[c].v; let inside = false; for (let i = 0, j = 3; i < 4; j = i++) { const a = P[v[i]], b = P[v[j]]; if ((a[1] > z) !== (b[1] > z) && x < (b[0] - a[0]) * (z - a[1]) / (b[1] - a[1]) + a[0]) inside = !inside; } if (inside) return c; }
  return -1;
}
function pick(cx, cy) {
  ndc.set(cx / innerWidth * 2 - 1, -(cy / innerHeight) * 2 + 1); ray.setFromCamera(ndc, camera);
  const hit = ray.intersectObjects(pickables, false)[0];
  if (hit) return { info: hit.object.userData.info[hit.faceIndex], point: hit.point };
  const p = new THREE.Vector3(); if (!ray.ray.intersectPlane(plane, p)) return null;
  const c = cellAt(p.x, p.z); return c < 0 ? null : { info: { c, k: -1, t: 'water' }, point: p };
}
function snapshot() { undoStack.push(new Map(blocks)); if (undoStack.length > 120) undoStack.shift(); }
function act(cx, cy, forceErase) {
  const h = pick(cx, cy); if (!h || !h.info) return;
  const { c, k, t, e } = h.info; const rem = forceErase || erase;
  let target = null;
  if (rem) { if (t !== 'water') target = [c, k]; }
  else if (t === 'water') target = [c, 0];
  else if (t === 'top') target = [c, k + 1];
  else if (t === 'rail') target = [c, 1];
  else if (t === 'under') target = [c, k - 1];
  else if (t === 'side') target = [cells[c].nb[e], 0];
  else if (t === 'wall') { const n = cells[c].nb[e]; target = n >= 0 ? [n, k] : null; }
  if (!target || target[0] < 0 || target[1] < 0 || target[1] >= MAXK) return;
  const [tc, tk] = target;
  snapshot();
  if (rem) { if (!has(tc, tk)) { undoStack.pop(); return; } blocks.delete(key(tc, tk)); }
  else {
    if (has(tc, tk)) { undoStack.pop(); return; }
    blocks.set(key(tc, tk), color);
    const stilt = t === 'wall' && tk >= 2 && !has(tc, 0);
    if (tk >= 1 && !has(tc, 0) && !stilt) blocks.set(key(tc, 0), color);
  }
  FRESH.k = rem ? -1 : key(tc, tk); FRESH.t = 0;
  tone(tk, rem); ripple(h.point); rebuild(); FRESH.k = -1; save(); hideHint();
  if (navigator.vibrate) navigator.vibrate(rem ? 18 : 8);
}
let hintGone = false; function hideHint() { if (hintGone) return; hintGone = true; document.getElementById('hint').classList.add('fade'); document.getElementById('title').classList.add('fade'); }
setTimeout(() => document.getElementById('title').classList.add('fade'), 5000);

const el = renderer.domElement; let down = null, pointers = 0, lpTimer = 0, lastInteract = performance.now();
el.addEventListener('pointerdown', ev => {
  pointers++; lastInteract = performance.now(); controls.autoRotate = false;
  if (pointers > 1) { down = null; clearTimeout(lpTimer); return; }
  down = { x: ev.clientX, y: ev.clientY, t: performance.now(), btn: ev.button, used: false };
  if (ev.pointerType !== 'mouse') lpTimer = setTimeout(() => { if (down && !down.moved) { down.used = true; act(down.x, down.y, true); } }, 480);
});
el.addEventListener('pointermove', ev => { if (down && Math.hypot(ev.clientX - down.x, ev.clientY - down.y) > 8) { down.moved = true; clearTimeout(lpTimer); } });
const up = ev => {
  pointers = Math.max(0, pointers - 1); clearTimeout(lpTimer);
  if (down && !down.moved && !down.used && performance.now() - down.t < 450) act(down.x, down.y, down.btn === 2);
  down = null; lastInteract = performance.now();
};
el.addEventListener('pointerup', up); el.addEventListener('pointercancel', () => { pointers = Math.max(0, pointers - 1); down = null; clearTimeout(lpTimer); });
el.addEventListener('contextmenu', e => e.preventDefault());
addEventListener('resize', () => { camera.aspect = innerWidth / innerHeight; camera.updateProjectionMatrix(); renderer.setSize(innerWidth, innerHeight); if (!userFramed) fitView(); });

// ---------- boot ----------
blocks = decode(location.hash.slice(1)) || decode((() => { try { return localStorage.getItem('tidemill.town.v3'); } catch (e) { return null; } })()) || defaultTown();
rebuild(); save(); fitView();
controls.autoRotateSpeed = 0.35;
const clock = new THREE.Clock();
renderer.setAnimationLoop(() => {
  const dt = Math.min(clock.getDelta(), 0.05), t = clock.elapsedTime;
  waterU.uTime.value = t;
  if (popGroup) { FRESH.t += dt; applyPop(FRESH.t); }
  if (performance.now() - lastInteract > 14000) controls.autoRotate = true;
  controls.update();
  for (const g of gulls) { const u = g.userData, a = t * u.sp + u.ph; g.position.set(Math.cos(a) * u.rad, u.h + Math.sin(t * 0.7 + u.ph) * 0.4, Math.sin(a) * u.rad); g.rotation.y = -a; const f = Math.sin(t * 6 + u.ph) * 0.5; u.l.rotation.z = f; u.r.rotation.z = -f; }
  for (let i = ripples.length - 1; i >= 0; i--) { const r = ripples[i]; r.t += dt; r.m.scale.setScalar(0.2 + r.t * 1.6); r.m.material.opacity = Math.max(0, 0.8 - r.t * 1.2); if (r.t > 0.7) { scene.remove(r.m); r.m.material.dispose(); ripples.splice(i, 1); } }
  renderer.render(scene, camera);
});
window.__tm = { STEPS, act, fitView, rebuild, FRESH, key, pop: () => popGroup && popGroup.scale.y, cells, blocks: () => blocks, camera, controls, encode, setColor: i => { color = i; } };
