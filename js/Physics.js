import {
  createWorldSettings,
  createWorld,
  addBroadphaseLayer,
  addObjectLayer,
  enableCollision,
  registerAll,
  rigidBody,
  box,
  sphere,
  MotionType,
  MotionQuality,
} from 'crashcat';

let registered = false;

export function createVehicleWorld() {
  if (!registered) {
    registerAll();
    registered = true;
  }

  const settings = createWorldSettings();
  settings.gravity = [0, -9.81, 0];

  const movingBroadphase = addBroadphaseLayer(settings);
  const staticBroadphase = addBroadphaseLayer(settings);
  const movingLayer = addObjectLayer(settings, movingBroadphase);
  const staticLayer = addObjectLayer(settings, staticBroadphase);

  enableCollision(settings, movingLayer, staticLayer);
  enableCollision(settings, movingLayer, movingLayer);

  const world = createWorld(settings);
  world._OL_MOVING = movingLayer;
  world._OL_STATIC = staticLayer;

  return world;
}

export function createArenaPhysics(world, centerX = 0, centerZ = 0, options = {}) {
  const radius = options.radius || 2.0;
  const segments = options.segments || 28;
  const wallThickness = options.wallThickness || 0.09;
  const wallHeight = options.wallHeight || 0.22;
  const floorMargin = options.floorMargin || 0.35;
  const floorY = options.floorY ?? 0;

  const arena = {
    world,
    radius,
    segments,
    wallThickness,
    wallHeight,
    floorMargin,
    floorY,
    centerX,
    centerZ,
    floor: null,
    walls: [],
  };

  arena.floor = rigidBody.create(world, {
    shape: box.create({
      halfExtents: [radius + floorMargin, 0.025, radius + floorMargin],
    }),
    motionType: MotionType.STATIC,
    objectLayer: world._OL_STATIC,
    position: [centerX, floorY - 0.025, centerZ],
    friction: 5.0,
    restitution: 0.0,
  });

  const circumference = Math.PI * 2 * radius;
  const segmentLength = circumference / segments;
  const wallHalfLength = segmentLength * 0.56; // slight overlap, no gaps

  for (let i = 0; i < segments; i++) {
    const a = (i / segments) * Math.PI * 2;
    const x = centerX + Math.cos(a) * radius;
    const z = centerZ + Math.sin(a) * radius;
    const yaw = -a;

    const body = rigidBody.create(world, {
      shape: box.create({
        halfExtents: [wallThickness * 0.5, wallHeight * 0.5, wallHalfLength],
      }),
      motionType: MotionType.STATIC,
      objectLayer: world._OL_STATIC,
      position: [x, floorY + wallHeight * 0.5, z],
      quaternion: [0, Math.sin(yaw * 0.5), 0, Math.cos(yaw * 0.5)],
      friction: 0.45,
      restitution: 0.12,
    });

    arena.walls.push(body);
  }

  return arena;
}

export function moveArenaPhysics(arena, centerX, centerZ) {
  if (!arena) return;

  arena.centerX = centerX;
  arena.centerZ = centerZ;

  rigidBody.setPosition(
    arena.world,
    arena.floor,
    [centerX, (arena.floorY ?? 0) - 0.025, centerZ],
    false
  );

  for (let i = 0; i < arena.walls.length; i++) {
    const a = (i / arena.segments) * Math.PI * 2;
    const x = centerX + Math.cos(a) * arena.radius;
    const z = centerZ + Math.sin(a) * arena.radius;

    rigidBody.setPosition(
      arena.world,
      arena.walls[i],
      [x, (arena.floorY ?? 0) + arena.wallHeight * 0.5, z],
      false
    );
  }
}

export function createVehicleBody(world, position, radius = 0.13) {
  const defaultMaxAngularVelocity = 0.25 * Math.PI * 60.0;
  const maxAngularVelocity =
    defaultMaxAngularVelocity * (0.5 / Math.max(radius, 0.001));

  return rigidBody.create(world, {
    shape: sphere.create({ radius }),
    motionType: MotionType.DYNAMIC,
    objectLayer: world._OL_MOVING,
    position,
    mass: Math.max(1000 * Math.pow(radius / 0.5, 3), 2),
    friction: 5.0,
    restitution: 0.05,
    linearDamping: 0.12,
    angularDamping: 4.0,
    gravityFactor: 1.2,
    motionQuality: MotionQuality.LINEAR_CAST,
    maxAngularVelocity,
  });
}

export function resetVehicleBody(world, body, position) {
  rigidBody.setPosition(world, body, position, false);
  rigidBody.setLinearVelocity(world, body, [0, 0, 0]);
  rigidBody.setAngularVelocity(world, body, [0, 0, 0]);
}
