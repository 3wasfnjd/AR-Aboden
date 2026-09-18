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

export function createRollingGround(world, centerX = 0, centerZ = 0, options = {}) {
  const tileSize = options.tileSize || 8;
  const radius = options.radius || 1; // 1 = 3x3 tiles
  const overlap = options.overlap ?? 0.35;

  const manager = {
    world,
    tileSize,
    radius,
    overlap,
    cellX: Number.NaN,
    cellZ: Number.NaN,
    tiles: [],
  };

  const half = tileSize * 0.5 + overlap;

  for (let gz = -radius; gz <= radius; gz++) {
    for (let gx = -radius; gx <= radius; gx++) {
      const body = rigidBody.create(world, {
        shape: box.create({ halfExtents: [half, 0.02, half] }),
        motionType: MotionType.STATIC,
        objectLayer: world._OL_STATIC,
        position: [0, -0.02, 0],
        friction: 5.0,
        restitution: 0.0,
      });

      manager.tiles.push({ gx, gz, body });
    }
  }

  updateRollingGround(manager, centerX, centerZ, true);
  return manager;
}

export function updateRollingGround(manager, x, z, force = false) {
  if (!manager) return false;

  const { world, tileSize, radius } = manager;
  const cellX = Math.floor(x / tileSize);
  const cellZ = Math.floor(z / tileSize);

  if (!force && cellX === manager.cellX && cellZ === manager.cellZ) {
    return false;
  }

  manager.cellX = cellX;
  manager.cellZ = cellZ;

  for (const tile of manager.tiles) {
    const tx = (cellX + tile.gx) * tileSize + tileSize * 0.5;
    const tz = (cellZ + tile.gz) * tileSize + tileSize * 0.5;

    rigidBody.setPosition(
      world,
      tile.body,
      [tx, -0.02, tz],
      false
    );

    rigidBody.setLinearVelocity?.(world, tile.body, [0, 0, 0]);
    rigidBody.setAngularVelocity?.(world, tile.body, [0, 0, 0]);
  }

  return true;
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
