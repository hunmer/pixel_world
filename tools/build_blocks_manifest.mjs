// build_blocks_manifest.mjs — 扫描 F:/blocks（或 --root 指定目录）的 PNG 方块图，
// 生成 blocks.json 素材清单（user_asset_service.gd 的 extract_manifest_entries 可直接消费）。
//
// 用法：
//   node tools/build_blocks_manifest.mjs [--root F:/blocks] [--out blocks.json] [--check]
//   --check 只校验不写入（返回码 0=全部合法，1=有坏图）。
//
// 契约（对齐 scripts/assets/user_asset_catalog.gd descriptor schema）：
//   - 顶层 { "blocks": [...] }（service 也接受 assets/images/items/files/entries 或裸数组）
//   - 每条：id / kind=terrain / name / tags=[前缀] / image=相对文件名 / sha256 / bytes / width / height / render
//   - id 规则 ^[a-z0-9][a-z0-9_.-]{0,63}$；前缀只作 tags，不进 id 之外的字段
//   - 默认 render = UserAssetCatalog.default_render()（整图 full 模式，footprint 1x1）
// 重跑幂等：
//   - 读取既有清单，按 id 保留用户改过的 name/tags/render/kind（service._merge_net_descriptor 同款语义）
//   - 磁盘上已消失的图剔除并报告；新图追加
//   - 原子写：blocks.json.tmp → 校验 → 备份旧 blocks.json.bak → rename
// 安全：拒绝路径穿越（id 含 .. / \ / 斜杠）、拒绝坏 PNG（魔数 + IHDR 校验），异常报告不静默。

import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, renameSync, copyFileSync, existsSync, readdirSync } from 'node:fs';
import { join, basename } from 'node:path';

const PNG_SIG = Buffer.from('89504e470d0a1a0a', 'hex');
const ID_RE = /^[a-z0-9][a-z0-9_.-]{0,63}$/;

function parseArgs(argv) {
	const opts = { root: 'F:/blocks', out: null, check: false };
	for (let i = 2; i < argv.length; i++) {
		const a = argv[i];
		if (a === '--root') opts.root = argv[++i];
		else if (a === '--out') opts.out = argv[++i];
		else if (a === '--check') opts.check = true;
		else if (a.startsWith('--root=')) opts.root = a.slice(7);
		else if (a.startsWith('--out=')) opts.out = a.slice(6);
		else { console.error('未知参数: ' + a); process.exit(2); }
	}
	if (!opts.out) opts.out = join(opts.root, 'blocks.json');
	return opts;
}

function slugifyId(stem) {
	// 文件名去扩展名后规范化：小写、非法字符转 _、压缩重复 _、去首尾 _
	return String(stem).toLowerCase()
		.replace(/[^a-z0-9_.-]+/g, '_')
		.replace(/_{2,}/g, '_')
		.replace(/^[_.-]+|[_.-]+$/g, '');
}

function validateId(id) {
	if (!ID_RE.test(id)) return 'id 不合法: ' + id;
	if (id.includes('..') || id.includes('\\') || id.includes('/')) return 'id 含路径穿越字符: ' + id;
	return '';
}

function parsePng(buf) {
	if (buf.length < 33) return { ok: false, error: '文件过小（<33B），不是 PNG' };
	if (!buf.subarray(0, 8).equals(PNG_SIG)) return { ok: false, error: '魔数不符，不是 PNG' };
	// IHDR 是首个 chunk：长度(4) type(4) data(13) crc(4)
	if (buf.toString('latin1', 12, 16) !== 'IHDR') return { ok: false, error: '首个 chunk 非 IHDR' };
	const width = buf.readUInt32BE(16);
	const height = buf.readUInt32BE(20);
	if (width < 1 || height < 1 || width > 8192 || height > 8192)
		return { ok: false, error: 'IHDR 尺寸非法: ' + width + 'x' + height };
	return { ok: true, width, height };
}

function defaultRender() {
	return { mode: 'full', crop: null, pivot: { x: 0.5, y: 1.0 }, scale: 1.0, footprint: { w: 1, h: 1 } };
}

function extractEntries(parsed) {
	// 与 service.extract_manifest_entries 同款宽容形态
	if (Array.isArray(parsed)) return parsed;
	if (parsed && typeof parsed === 'object') {
		for (const key of ['blocks', 'assets', 'images', 'items', 'files', 'entries']) {
			if (Array.isArray(parsed[key])) return parsed[key];
		}
	}
	return null;
}

function loadExistingManifest(outPath) {
	if (!existsSync(outPath)) return { entries: new Map(), hadFile: false };
	try {
		const parsed = JSON.parse(readFileSync(outPath, 'utf8'));
		const arr = extractEntries(parsed);
		const map = new Map();
		if (arr) {
			for (const e of arr) {
				if (e && typeof e === 'object' && typeof e.id === 'string') map.set(e.id, e);
			}
		}
		return { entries: map, hadFile: true };
	} catch (err) {
		console.error('警告: 既有清单解析失败，视为全新生成（' + err.message + '）');
		return { entries: new Map(), hadFile: true };
	}
}

function main() {
	const opts = parseArgs(process.argv);
	const { root, out } = opts;
	const anomalies = [];   // 坏图 / 非法 id 报告
	const removed = [];     // 磁盘消失被剔除的 id
	const added = [];       // 新增 id
	const kept = [];        // 沿用（保留用户字段）或原样再确认的 id

	const old = loadExistingManifest(out);

	let files;
	try {
		files = readdirSync(root, { withFileTypes: true })
			.filter((d) => d.isFile() && d.name.toLowerCase().endsWith('.png'))
			.map((d) => d.name);
	} catch (err) {
		console.error('无法读取 root: ' + root + ' — ' + err.message);
		process.exit(2);
	}
	files.sort(); // 确定性排序（按文件名，等价于按 id 前缀排序）

	const seen = new Set();
	const entries = [];
	for (const fname of files) {
		const stem = basename(fname, '.png');
		const id = slugifyId(stem);
		const idErr = validateId(id);
		if (idErr) { anomalies.push(fname + ': ' + idErr); continue; }
		if (seen.has(id)) { anomalies.push(fname + ': id 与前面文件冲突 ' + id); continue; }
		seen.add(id);

		let buf;
		try {
			buf = readFileSync(join(root, fname));
		} catch (err) {
			anomalies.push(fname + ': 读取失败 ' + err.message);
			continue;
		}
		const png = parsePng(buf);
		if (!png.ok) { anomalies.push(fname + ': ' + png.error); continue; }

		const sha256 = createHash('sha256').update(buf).digest('hex');
		const prefix = stem.includes('_') ? slugifyId(stem.split('_')[0]) : 'misc';

		const prev = old.entries.get(id);
		const rec = {
			id,
			kind: 'terrain',
			name: stem,
			tags: [prefix],
			image: fname,
			sha256,
			bytes: buf.length,
			width: png.width,
			height: png.height,
			render: defaultRender(),
		};
		if (prev && typeof prev === 'object') {
			// 保留用户人工改过的字段（service._merge_net_descriptor 语义：源侧 image/sha256/bytes/width/height 以磁盘为准，
			// name/tags/render/kind 以库为准）
			if (typeof prev.kind === 'string') rec.kind = prev.kind;
			if (typeof prev.name === 'string' && prev.name) rec.name = prev.name;
			if (Array.isArray(prev.tags)) rec.tags = prev.tags.filter((t) => typeof t === 'string');
			if (prev.render && typeof prev.render === 'object') {
				rec.render = Object.assign(defaultRender(), prev.render);
				if (prev.render.crop && typeof prev.render.crop === 'object') rec.render.crop = prev.render.crop;
				else rec.render.crop = null;
			}
			kept.push(id);
		} else {
			added.push(id);
		}
		old.entries.delete(id);
		entries.push(rec);
	}
	for (const gone of old.entries.keys()) removed.push(gone);

	entries.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));

	const report = {
		generatedAt: new Date().toISOString(),
		root,
		entryCount: entries.length,
		byPrefix: {},
		added: added.length,
		kept: kept.length,
		removed,
		anomalies,
		blocks: entries,
	};
	for (const e of entries) {
		const p = e.tags[0] || 'misc';
		report.byPrefix[p] = (report.byPrefix[p] || 0) + 1;
	}

	const json = JSON.stringify({ blocks: entries }, null, 1);

	if (!opts.check) {
		const tmpPath = out + '.tmp';
		writeFileSync(tmpPath, json, 'utf8');
		// 回读校验（与 battlefield_doc.save_model 同款 tmp→校验→bak→rename）
		const reread = JSON.parse(readFileSync(tmpPath, 'utf8'));
		const reEntries = extractEntries(reread);
		if (!reEntries || reEntries.length !== entries.length) {
			console.error('回读校验失败，拒绝替换 ' + out);
			process.exit(2);
		}
		if (old.hadFile && existsSync(out)) {
			try { copyFileSync(out, out + '.bak'); } catch (err) { console.error('备份失败: ' + err.message); }
		}
		try {
			renameSync(tmpPath, out);
		} catch (err) {
			console.error('原子替换失败: ' + err.message);
			process.exit(2);
		}
	}

	console.log(JSON.stringify({
		out: opts.check ? '(check 模式未写入)' : out,
		entryCount: report.entryCount,
		added: report.added,
		kept: report.kept,
		removedCount: report.removed.length,
		removed: report.removed.slice(0, 20),
		anomalyCount: report.anomalies.length,
		anomalies: report.anomalies.slice(0, 20),
		byPrefix: report.byPrefix,
	}, null, 1));

	if (anomalies.length > 0) process.exit(1);
	process.exit(0);
}

main();
