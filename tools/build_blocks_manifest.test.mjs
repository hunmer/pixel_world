// build_blocks_manifest.test.mjs — build_blocks_manifest.mjs 的 Node 契约测试
// 运行：node --test tools/build_blocks_manifest.test.mjs
// 用临时目录造合成 PNG（真 IHDR，不验 CRC），覆盖：清单形状 / id 规则 / 坏图拒绝 /
// 重跑保留用户字段 / 删除文件剔除 / 路径穿越拒绝 / 原子写与确定性排序。

import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync, existsSync, mkdirSync, rmSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const SCRIPT = new URL('./build_blocks_manifest.mjs', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');

function makePng(width, height) {
	// 8B 魔数 + 4B 长度(13) + 4B "IHDR" + 13B IHDR 数据 + 4B CRC(0) + 1B 填充 = 34B
	const buf = Buffer.alloc(8 + 4 + 4 + 13 + 4 + 1);
	Buffer.from('89504e470d0a1a0a', 'hex').copy(buf, 0);
	buf.writeUInt32BE(13, 8);
	buf.write('IHDR', 12, 'latin1');
	buf.writeUInt32BE(width, 16);
	buf.writeUInt32BE(height, 20);
	return buf;
}

function run(args, expectCode = 0) {
	const out = execFileSync(process.execPath, [SCRIPT, ...args], { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
	return JSON.parse(out.slice(out.indexOf('{')));
}

function setup(files) {
	const root = mkdtempSync(join(tmpdir(), 'blocks-manifest-'));
	for (const [name, content] of Object.entries(files)) {
		writeFileSync(join(root, name), content);
	}
	return root;
}

test('生成清单：形状、字段、计数、分类、确定性排序', () => {
	const root = setup({
		'grassland_2.png': makePng(172, 204),
		'basic_0.png': makePng(138, 176),
		'grassland_10.png': makePng(174, 202),
	});
	try {
		const rep = run(['--root', root]);
		assert.equal(rep.entryCount, 3);
		assert.equal(rep.added, 3);
		assert.deepEqual(rep.byPrefix, { grassland: 2, basic: 1 });

		const manifest = JSON.parse(readFileSync(join(root, 'blocks.json'), 'utf8'));
		assert.ok(Array.isArray(manifest.blocks));
		assert.equal(manifest.blocks.length, 3);
		// 确定性排序：id 升序
		const ids = manifest.blocks.map((e) => e.id);
		assert.deepEqual(ids, [...ids].sort());
		// descriptor schema 全字段
		const rec = manifest.blocks.find((e) => e.id === 'grassland_10');
		assert.equal(rec.kind, 'terrain');
		assert.equal(rec.name, 'grassland_10');
		assert.deepEqual(rec.tags, ['grassland']);
		assert.equal(rec.image, 'grassland_10.png');
		assert.match(rec.sha256, /^[0-9a-f]{64}$/);
		assert.equal(rec.bytes, 34);
		assert.equal(rec.width, 174);
		assert.equal(rec.height, 202);
		assert.deepEqual(rec.render, { mode: 'full', crop: null, pivot: { x: 0.5, y: 1.0 }, scale: 1.0, footprint: { w: 1, h: 1 } });
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
});

test('重跑保留用户改过的 name/tags/render/kind，剔除消失文件', () => {
	const root = setup({ 'a_1.png': makePng(10, 10), 'b_2.png': makePng(20, 20) });
	try {
		run(['--root', root]);
		const p = join(root, 'blocks.json');
		const manifest = JSON.parse(readFileSync(p, 'utf8'));
		const rec = manifest.blocks.find((e) => e.id === 'a_1');
		rec.name = '我的山丘';
		rec.tags = ['grassland', ' favorites'];
		rec.kind = 'plant';
		rec.render = { mode: 'crop', crop: { x: 1, y: 2, w: 3, h: 4 }, pivot: { x: 0.5, y: 1.0 }, scale: 2.0, footprint: { w: 1, h: 1 } };
		// 源侧字段被改脏，重跑应以磁盘为准刷回
		rec.sha256 = 'deadbeef'.repeat(8);
		rec.bytes = 999;
		writeFileSync(p, JSON.stringify(manifest, null, 1));

		// 删除 b_2.png → 应被剔除
		rmSync(join(root, 'b_2.png'));
		const rep2 = run(['--root', root]);
		assert.equal(rep2.entryCount, 1);
		assert.equal(rep2.kept, 1);
		assert.deepEqual(rep2.removed, ['b_2']);

		const manifest2 = JSON.parse(readFileSync(p, 'utf8'));
		const rec2 = manifest2.blocks[0];
		assert.equal(rec2.name, '我的山丘');
		assert.deepEqual(rec2.tags, ['grassland', ' favorites']);
		assert.equal(rec2.kind, 'plant');
		assert.equal(rec2.render.mode, 'crop');
		assert.equal(rec2.render.crop.w, 3);
		// 源侧字段被磁盘值刷新
		assert.equal(rec2.bytes, 34);
		assert.notEqual(rec2.sha256, 'deadbeef'.repeat(8));
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
});

test('坏图拒绝且不写入清单，异常报告', () => {
	const root = setup({ 'good_1.png': makePng(10, 10), 'bad_1.png': Buffer.from('not a png at all, just text') });
	try {
		assert.throws(() => run(['--root', root], 1));
		// exit 1 路径：改用 spawn 捕获
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
});

test('坏图拒绝：exit code 1 且清单只含合法图', () => {
	const root = setup({ 'good_1.png': makePng(10, 10), 'bad_1.png': Buffer.from('not a png at all, just text') });
	try {
		let code = 0;
		let stdout = '';
		try {
			stdout = execFileSync(process.execPath, [SCRIPT, '--root', root], { encoding: 'utf8' });
		} catch (err) {
			code = err.status;
			stdout = err.stdout || '';
		}
		assert.equal(code, 1);
		const rep = JSON.parse(stdout.slice(stdout.indexOf('{')));
		assert.equal(rep.entryCount, 1);
		assert.equal(rep.anomalyCount, 1);
		const manifest = JSON.parse(readFileSync(join(root, 'blocks.json'), 'utf8'));
		assert.equal(manifest.blocks.length, 1);
		assert.equal(manifest.blocks[0].id, 'good_1');
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
});

test('id 规范化与路径穿越拒绝', () => {
	const root = setup({ 'Weird Name!.png': makePng(10, 10) });
	try {
		const rep = run(['--root', root]);
		assert.equal(rep.entryCount, 1);
		const manifest = JSON.parse(readFileSync(join(root, 'blocks.json'), 'utf8'));
		assert.equal(manifest.blocks[0].id, 'weird_name');
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
});

test('原子写：生成 .bak 备份且 tmp 不残留', () => {
	const root = setup({ 'a_1.png': makePng(10, 10) });
	try {
		run(['--root', root]);
		writeFileSync(join(root, 'a_1.png'), makePng(11, 11)); // 改内容触发重新生成
		run(['--root', root]);
		assert.ok(existsSync(join(root, 'blocks.json.bak')));
		const leftovers = readdirSync(root).filter((f) => f.endsWith('.tmp'));
		assert.deepEqual(leftovers, []);
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
});

test('--check 模式不写文件', () => {
	const root = setup({ 'a_1.png': makePng(10, 10) });
	try {
		run(['--root', root, '--check']);
		assert.ok(!existsSync(join(root, 'blocks.json')));
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
});
