#!/usr/bin/env node
// Regenerate catalog and independent parity expectations directly from the pinned TypeScript source.
// Node 22.18+; no npm dependencies, transpilation, or Swift output involved.
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { source, upstreamVersion, upstreamRevision, examples, gallery, colors } from './sync-catalog.mjs';

const core = async (name) => import(pathToFileURL(join(source, `packages/core/src/${name}.ts`)));
const { computePose, hashString, noise, STATES, MOODS, resolveLook } = await core('motion');
const { avatarFrame, renderAvatarSvg } = await core('render');
const { createAnimator } = await core('animator');
const { validateAvatar } = await core('validate');
const { buildVolume } = await core('volume');

const definitions = [...examples, ...gallery];
const definition = (id) => {
  const result = definitions.find((d) => d.id === id);
  if (!result) throw new Error(`Unknown avatar ${id}`);
  return result;
};
// Primitive cases use the contract's existing path commands and the upstream validator.
const primitives = [
  { version: 1, id: 'test', name: 'Test', body: { path: 'M20 20H80V80H20Z' }, eyes: { x: 50, y: 50, spacing: 14, scale: 1 } },
  { version: 1, id: 'circle', name: 'Circle', body: { path: 'M50 15A35 35 0 1 1 50 85A35 35 0 1 1 50 15Z' }, eyes: { x: 50, y: 50, spacing: 14, scale: 1 } },
];
for (const d of primitives) {
  const result = validateAvatar(d);
  if (!result.ok) throw new Error(result.errors.join('; '));
}
const poses = [];
const pose = (name, input) => poses.push({ name, input, output: computePose(input) });
for (const seed of [0, 123, 4294967295]) {
  for (const state of STATES) for (const mood of MOODS) for (const reducedMotion of [false, true]) {
    pose(`${seed}/${state}/${mood}/${reducedMotion}`, { seed, time: 1.234, state, mood, stateAge: 2.3, reducedMotion });
  }
}
// Entry, wind-up, steady sweep, draw-in, rest, reverse cycle, and the absent/negative clock.
for (const state of ['working', 'done']) {
  const seed = hashString('mug');
  const firstWork = 1.2 + 1.2 * noise(seed, 41);
  const cycle = 6.2 * (1 + 0.15 * noise(seed, 31));
  const ages = state === 'working'
    ? [undefined, -1, 0, firstWork - 0.001, firstWork, firstWork + 0.08, firstWork + 0.4, firstWork + 1.25, firstWork + 1.5, 9.9]
    : [undefined, -1, 0, 0.12, 0.24, 0.4, 0.54, 1.7, 2.54, 3.37, 3.6, 3.79, 3.87, cycle + 0.54, cycle + 1.7];
  for (const stateAge of ages) pose(`${state}/age/${stateAge ?? 'absent'}`, { seed, time: 12.345, state, mood: 'neutral', stateAge, reducedMotion: false });
}
for (const motion of ['idle', 'thinking', 'happy']) {
  for (const reducedMotion of [false, true]) pose(`legacy/${motion}/${reducedMotion}`, { seed: 123, time: 2.1, motion, reducedMotion });
}
pose('explicit-state-over-legacy', { seed: 123, time: 2.1, motion: 'thinking', state: 'working', mood: 'happy', stateAge: 2.3, reducedMotion: false });
for (const t of [-0.2, 0, 0.17, 0.5, 1, 1.2]) {
  pose(`legacy-blend/${t}`, { seed: 123, time: 2.1, motion: 'happy', reducedMotion: false, blend: { from: 'thinking', t } });
  pose(`state-blend/${t}`, {
    seed: hashString('mug'), time: 9.1, state: 'waiting', mood: 'neutral', stateAge: 0.25, reducedMotion: false,
    blend: { from: { state: 'done', mood: 'happy', age: 1.7, blend: { from: { state: 'working', mood: 'neutral', age: 2.3 }, t: 0.7 } }, t },
  });
}
pose('mood-change-keeps-done-clock', { seed: 123, time: 12, state: 'done', mood: 'happy', stateAge: 1.7, reducedMotion: false, blend: { from: { state: 'done', mood: 'neutral', age: 0.4 }, t: 0.35 } });
pose('gaze-and-view', { seed: 123, time: -1.5, state: 'waiting', mood: 'happy', reducedMotion: false, gaze: { x: 2, y: -2, weight: 0.7 }, view: { yaw: 1.2, pitch: -0.4 } });
pose('reduced-gaze-and-view', { seed: 123, time: 90, state: 'done', mood: 'happy', stateAge: 1.7, reducedMotion: true, gaze: { x: -0.8, y: 0.6, weight: 0.35 }, view: { yaw: 0.9, pitch: -0.2 } });

const animators = [];
const sequence = (name, inputs) => {
  const animator = createAnimator();
  const steps = inputs.map((input) => {
    if (input.reset) animator.reset();
    const { reset: _, ...given } = input;
    const output = animator.step(given);
    const look = resolveLook(given);
    return { input, output, pose: computePose({ seed: 123, time: 1.25, ...look, stateAge: output.stateAge, blend: output.motionBlend, gaze: output.gaze, reducedMotion: input.reducedMotion }) };
  });
  animators.push({ name, steps });
};
const a = (now, state, mood = 'neutral', extra = {}) => ({ now, state, mood, target: null, reducedMotion: false, ...extra });
sequence('state-and-mood-clocks', [
  a(1000, 'idle'), a(1100, 'done'), a(1250, 'done'), a(1400, 'done', 'happy'), a(1500, 'done', 'happy'),
  a(1600, 'working'), a(1660, 'waiting'), a(1710, 'blocked'), a(1760, 'thinking'), a(1810, 'idle'), a(2300, 'idle'),
]);
sequence('mount-done-reset-and-reduced', [
  a(5000, 'done'), a(5100, 'done'), a(5300, 'working', 'happy', { reducedMotion: true }),
  a(5400, 'done', 'happy', { reducedMotion: true }), a(5600, 'done', 'happy'), a(6000, 'done', 'neutral', { reset: true }),
]);
sequence('gaze-hold-and-release', [
  a(0, 'idle'), a(16, 'working', 'neutral', { target: { x: 0.8, y: -0.5 } }),
  a(32, 'working', 'neutral', { target: { x: 0.8, y: -0.5 } }), a(96, 'working', 'happy', { hold: true }),
  a(112, 'working'), a(1000, 'working', 'neutral', { target: { x: -0.7, y: 0.3 }, reducedMotion: true }),
  a(1100, 'idle', 'neutral', { reducedMotion: true }),
]);
sequence('legacy', ['idle', 'thinking', 'happy', 'idle'].map((motion, i) => ({ now: i * 200, motion, target: null, reducedMotion: false })));

const frames = [];
const frame = (name, d, options, svg = false) => {
  frames.push({ name, definition: d, options, output: avatarFrame(d, options), ...(svg ? { svg: renderAvatarSvg(d, options) } : {}) });
};
for (const id of ['controller', 'mug', 'barbell', 'chat', 'egg']) {
  frame(`${id}/front`, definition(id), { time: 1.234, reducedMotion: true, gaze: { x: 0.35, y: -0.2 }, color: colors[id] });
  frame(`${id}/side`, definition(id), { time: 1.234, reducedMotion: true, view: { yaw: 1.6, pitch: -0.35 } });
}
for (const d of primitives) frame(`${d.id}/primitive`, d, { time: 1.234, reducedMotion: true });
frame('mug/waiting-slit', definition('mug'), { state: 'waiting', mood: 'neutral', time: 1.1, depth: 0, eyeColor: '#abc' }, true);
frame('controller/happy-arc', definition('controller'), { mood: 'happy', time: 1.1, depth: 0, size: 128 }, true);
frame('mug/thinking-dots', definition('mug'), { state: 'thinking', time: 1.1 }, true);
frame('barbell/blocked-mark', definition('barbell'), { state: 'blocked', time: 1.1, size: 96 }, true);
frame('egg/done-ribbons', definition('egg'), { state: 'done', mood: 'happy', stateAge: 1.7, time: 1.1, depth: 0, color: '#1fbf68' }, true);
const workAge = 1.2 + 1.2 * noise(hashString('controller'), 41) + 0.4;
frame('controller/working-ribbons', definition('controller'), { state: 'working', stateAge: workAge, time: 1.1, depth: 0, color: '#000' }, true);
frame('egg/white-ribbons', definition('egg'), { state: 'done', stateAge: 0.8, time: 1.1, depth: 0, color: '#fff' });
frame('mug/partial-mark', definition('mug'), { state: 'thinking', mood: 'happy', time: 1.1, motionBlend: { from: { state: 'idle', mood: 'neutral' }, t: 0.43 } });
frame('mug/eye-morph', definition('mug'), { state: 'waiting', mood: 'happy', time: 1.1, depth: 0, motionBlend: { from: { state: 'waiting', mood: 'neutral' }, t: 0.43 } });
for (const state of STATES) frame(`reduced/${state}`, definition('mug'), { state, mood: 'happy', stateAge: 1.7, time: 90, reducedMotion: true, depth: 0, gaze: { x: -0.6, y: 0.25 } });

// Sample every part's core and several refined sections, including the smoother inflated rims.
// The full stacks stay out of the fixture to avoid duplicating thousands of nearly identical paths.
const volumes = ['controller', 'mug', 'barbell', 'chat', 'egg'].map((id) => {
  const d = definition(id), vol = buildVolume(d);
  return {
    definition: d,
    parts: vol.parts.map((part) => ({
      depth: part.depth, center: part.center,
      stacks: ['zSlices', 'xSlices'].map((stack) => {
        const slices = part[stack];
        const indices = [...new Set([0, Math.floor(slices.length / 4), Math.floor(slices.length / 2), Math.floor(3 * slices.length / 4), slices.length - 1])];
        return { name: stack, count: slices.length, slices: indices.map((index) => ({ index, ...slices[index] })) };
      }),
    })),
  };
});

const fixture = {
  origin: { repository: 'https://github.com/DominikScholz/open-bot-avatar', version: upstreamVersion, revision: upstreamRevision, generator: 'scripts/sync-upstream.mjs' },
  catalog: { examples, gallery, colors, validated: definitions.map((d) => validateAvatar(d).value) }, poses, animators, frames, volumes,
};
const target = join(dirname(fileURLToPath(import.meta.url)), '../Tests/OpenBotAvatarTests/Fixtures');
mkdirSync(target, { recursive: true });
const json = JSON.stringify(fixture);
writeFileSync(join(target, 'upstream-0.3.0.json'), `${json}\n`);
console.log(`Generated ${poses.length} poses, ${animators.length} animator sequences, ${frames.length} frames, ${volumes.length} sampled volumes (${Buffer.byteLength(json)} bytes) from ${upstreamRevision}`);
