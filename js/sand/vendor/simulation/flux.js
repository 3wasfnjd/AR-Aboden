// SPDX-License-Identifier: GPL-3.0-only
// Adapted from scottstts/Sandboard via Threejs-Awesome-Graphics-Agent-Skills.
// Revision d1cb23dcce6ea8ee4a60f6159daeb79d4b511dba; see js/sand/NOTICE.md.
export const fluxLayout = `
struct Flux { axial: vec4f, diagonal: vec4f }
const neighbors = array<vec2i, 8>(
  vec2i(-1, 0), vec2i(1, 0), vec2i(0, -1), vec2i(0, 1),
  vec2i(-1, -1), vec2i(1, 1), vec2i(1, -1), vec2i(-1, 1)
);
fn totalFlux(flow: Flux) -> f32 {
  return dot(flow.axial + flow.diagonal, vec4f(1.0));
}
fn fluxVector(flow: Flux) -> vec2f {
  return vec2f(flow.axial.y - flow.axial.x - flow.diagonal.x + flow.diagonal.y + flow.diagonal.z - flow.diagonal.w,
    flow.axial.w - flow.axial.z - flow.diagonal.x + flow.diagonal.y - flow.diagonal.z + flow.diagonal.w);
}
fn component(flow: Flux, direction: u32) -> f32 {
  if (direction < 4u) { return flow.axial[direction]; }
  return flow.diagonal[direction - 4u];
}
`;
