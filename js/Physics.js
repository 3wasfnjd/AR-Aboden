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

  rigidBody.create(world, {
    shape: box.create({ halfExtents: [25, 0.01, 25] }),
    motionType: MotionType.STATIC,
    objectLayer: staticLayer,
    position: [0, -0.01, 0],
    friction: 5.0,
    restitution: 0.0,
  });

  return world;
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
