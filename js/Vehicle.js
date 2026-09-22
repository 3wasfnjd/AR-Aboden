import * as THREE from 'three';
import { rigidBody } from 'crashcat';

const forward = new THREE.Vector3();
const right = new THREE.Vector3();
const up = new THREE.Vector3(0, 1, 0);
const temp = new THREE.Vector3();
const targetQuat = new THREE.Quaternion();

const LINEAR_DAMP = 0.1;
const MAX_SPEED = 1.18;
const REVERSE_SPEED_SCALE = 0.6;

function lerpAngle(a, b, t) {
  let diff = b - a;
  while (diff > Math.PI) diff -= Math.PI * 2;
  while (diff < -Math.PI) diff += Math.PI * 2;
  return a + diff * t;
}

function createPivot(node) {
  const parent = node.parent;
  const pivot = new THREE.Group();
  pivot.position.copy(node.position);
  pivot.rotation.order = 'YXZ';
  parent.add(pivot);
  pivot.add(node);
  node.position.set(0, 0, 0);
  return pivot;
}

export class Vehicle {
  constructor() {
    this.linearSpeed = 0;
    this.angularSpeed = 0;
    this.acceleration = 0;
    this.spherePos = new THREE.Vector3();
    this.sphereVel = new THREE.Vector3();
    this.sphereRadius = 0.13;
    this.spawnPos = new THREE.Vector3();
    this.spawnAngle = 0;
    this.rigidBody = null;
    this.physicsWorld = null;

    this.container = new THREE.Group();
    this.container.visible = false;

    this.bodyNode = null;
    this.wheels = [];
    this.wheelFL = null;
    this.wheelFR = null;
    this.wheelBL = null;
    this.wheelBR = null;
    this.modelVelocity = new THREE.Vector3();
    this.prevModelPos = new THREE.Vector3();

    this.inputX = 0;
    this.inputZ = 0;
    this.handbrake = false;
    this.driftIntensity = 0;

    this.headlightL = null;
    this.headlightR = null;
    this.headlightBeamL = null;
    this.headlightBeamR = null;
    this.taillightL = null;
    this.taillightR = null;
    this.brakeGlow = null;
    this._brakeGlowT = 0;
    this._taillightBaseColor = new THREE.Color(0x5a0000);
    this._taillightBrakeColor = new THREE.Color(0xff2a1a);
  }

  init(model) {
    const vehicleModel = model.clone(true);
    this.container.add(vehicleModel);

    let bodyChild = null;
    const wheelChildren = [];

    vehicleModel.traverse((child) => {
      const name = (child.name || '').toLowerCase();
      if (name === 'body') bodyChild = child;
      else if (name.includes('wheel')) wheelChildren.push(child);

      if (child.isMesh) {
        child.castShadow = true;
        child.receiveShadow = true;
      }
    });

    if (bodyChild) {
      this.bodyNode = createPivot(bodyChild);
      this._bodyRestY = this.bodyNode.position.y;
      this._bodySink = 0.025;
    }

    for (const child of wheelChildren) {
      const name = (child.name || '').toLowerCase();
      const pivot = createPivot(child);
      this.wheels.push(pivot);
      if (name.includes('front') && name.includes('left')) this.wheelFL = pivot;
      if (name.includes('front') && name.includes('right')) this.wheelFR = pivot;
      if ((name.includes('back') || name.includes('rear')) && name.includes('left')) this.wheelBL = pivot;
      if ((name.includes('back') || name.includes('rear')) && name.includes('right')) this.wheelBR = pivot;
    }

    vehicleModel.updateMatrixWorld(true);
    const box = new THREE.Box3().setFromObject(vehicleModel);
    const size = new THREE.Vector3();
    box.getSize(size);

    // Some imported GLB cars don't use predictable wheel node names.
    // DriftMarks/SmokeTrails need rear-wheel world positions, so create
    // invisible fallback anchors from the car's own bounding box.
    if (!this.wheelBL || !this.wheelBR) {
      const y = box.min.y + Math.max(0.012, size.y * 0.12);
      const rearZ = box.min.z + size.z * 0.23;
      const halfTrack = size.x * 0.31;

      if (!this.wheelBL) {
        this.wheelBL = new THREE.Group();
        this.wheelBL.name = 'fallback-wheel-back-left';
        this.wheelBL.position.set(-halfTrack, y, rearZ);
        this.container.add(this.wheelBL);
      }

      if (!this.wheelBR) {
        this.wheelBR = new THREE.Group();
        this.wheelBR.name = 'fallback-wheel-back-right';
        this.wheelBR.position.set(halfTrack, y, rearZ);
        this.container.add(this.wheelBR);
      }
    }

    this._addLights(box, size);

    return this.container;
  }

  // The Camaro GLB has no separate headlight/taillight nodes worth trusting
  // across different car models, so real light sources + small glowing
  // lamp meshes are placed from the car's own bounding box instead —
  // front-facing white headlights (with a forward beam) and rear red
  // taillights that flare brighter under the handbrake.
  _addLights(box, size) {
    const lampY = box.min.y + size.y * 0.42;
    const lampHalfTrack = size.x * 0.34;
    const frontZ = box.max.z - size.z * 0.04;
    const rearZ = box.min.z + size.z * 0.04;
    const lampRadius = Math.max(0.008, size.x * 0.045);
    const lampGeo = new THREE.SphereGeometry(lampRadius, 10, 8);

    this.headlightL = new THREE.Mesh(lampGeo, new THREE.MeshBasicMaterial({ color: 0xfff2c8 }));
    this.headlightL.position.set(-lampHalfTrack, lampY, frontZ);
    this.container.add(this.headlightL);

    this.headlightR = new THREE.Mesh(lampGeo, new THREE.MeshBasicMaterial({ color: 0xfff2c8 }));
    this.headlightR.position.set(lampHalfTrack, lampY, frontZ);
    this.container.add(this.headlightR);

    this.taillightL = new THREE.Mesh(lampGeo, new THREE.MeshBasicMaterial({ color: this._taillightBaseColor.clone() }));
    this.taillightL.position.set(-lampHalfTrack, lampY, rearZ);
    this.container.add(this.taillightL);

    this.taillightR = new THREE.Mesh(lampGeo, new THREE.MeshBasicMaterial({ color: this._taillightBaseColor.clone() }));
    this.taillightR.position.set(lampHalfTrack, lampY, rearZ);
    this.container.add(this.taillightR);

    const beamTargetY = lampY - size.y * 0.3;

    this.headlightBeamL = new THREE.SpotLight(0xfff2c8, 2.2, 2.4, Math.PI / 7, 0.55, 1.4);
    this.headlightBeamL.castShadow = false;
    this.headlightBeamL.position.copy(this.headlightL.position);
    this.headlightBeamL.target.position.set(-lampHalfTrack * 0.6, beamTargetY, frontZ + 1.4);
    this.container.add(this.headlightBeamL, this.headlightBeamL.target);

    this.headlightBeamR = new THREE.SpotLight(0xfff2c8, 2.2, 2.4, Math.PI / 7, 0.55, 1.4);
    this.headlightBeamR.castShadow = false;
    this.headlightBeamR.position.copy(this.headlightR.position);
    this.headlightBeamR.target.position.set(lampHalfTrack * 0.6, beamTargetY, frontZ + 1.4);
    this.container.add(this.headlightBeamR, this.headlightBeamR.target);

    // Soft ambient glow behind the car; brightens sharply under braking.
    this.brakeGlow = new THREE.PointLight(0xff2a1a, 0.15, 0.6, 2);
    this.brakeGlow.position.set(0, lampY, rearZ - 0.02);
    this.container.add(this.brakeGlow);
  }

  attachPhysics(world, body, radius) {
    this.physicsWorld = world;
    this.rigidBody = body;
    this.sphereRadius = radius;
  }

  place(position, angle = 0) {
    this.spawnPos.copy(position);
    this.spawnAngle = angle;
    this.spherePos.copy(position);
    this.prevModelPos.set(position.x, position.y - this.sphereRadius, position.z);
    this.linearSpeed = 0;
    this.angularSpeed = 0;
    this.acceleration = 0;
    this.container.position.copy(this.prevModelPos);
    this.container.rotation.set(0, angle, 0);
    this.container.visible = true;
  }

  // Spectator-only pose adapter. Normal player physics below is unchanged.
  updateAutonomous(pose, dt) {
    this.container.position.set(pose.x,pose.y,pose.z);
    this.container.rotation.set(0,pose.heading,0);
    this.spherePos.set(pose.x,pose.y+this.sphereRadius,pose.z);
    this.sphereVel.set(pose.vx,0,pose.vz);
    this.modelVelocity.copy(this.sphereVel);
    this.prevModelPos.copy(this.container.position);
    const scale=this.container.scale.x || 1;
    this.linearSpeed=pose.speed/scale;
    this.acceleration=this.linearSpeed;
    this.inputX=pose.steer;this.inputZ=1;
    this.handbrake=pose.handbrake;this.driftIntensity=pose.driftIntensity;
    // Reuse the body lean and countersteer, with frame-rate independent wheels.
    const wheelAngles=this.wheels.map(w=>w.rotation.x);
    this._animateVisuals(dt);
    this.wheels.forEach((wheel,i)=>{wheel.rotation.x=wheelAngles[i]+pose.speed*dt/(.05*scale);});
  }

  update(dt, input = {}) {
    this.inputX = THREE.MathUtils.clamp(input.x || 0, -1, 1);
    this.inputZ = THREE.MathUtils.clamp(input.z || 0, -1, 1);
    this.handbrake = !!input.handbrake;

    if (input.touchActive && (this.inputX !== 0 || this.inputZ !== 0)) {
      // Same touch-driving model as Hajwala:
      // joystick selects a world-space heading and the car auto-accelerates.
      const targetAngle = Math.atan2(this.inputX, this.inputZ);
      targetQuat.setFromAxisAngle(up, targetAngle);
      const touchTurnRate = this.handbrake ? 6 : 3;
      this.container.quaternion.slerp(
        targetQuat,
        1 - Math.exp(-touchTurnRate * dt)
      );

      forward.set(0, 0, 1).applyQuaternion(this.container.quaternion);
      forward.y = 0;
      forward.normalize();

      const cross = forward.x * this.inputZ - forward.z * this.inputX;
      this.inputX = THREE.MathUtils.clamp(-cross * 2, -1, 1);

      this.linearSpeed = THREE.MathUtils.lerp(
        this.linearSpeed,
        MAX_SPEED,
        Math.min(1, dt * 2.2)
      );
    } else {
      let direction = Math.sign(this.linearSpeed);
      if (direction === 0) direction = Math.abs(this.inputZ) > 0.1 ? Math.sign(this.inputZ) : 1;

      const steeringGrip = THREE.MathUtils.clamp(Math.abs(this.linearSpeed), 0.2, 1.0);
      const effectiveGrip = this.handbrake ? 1.0 : steeringGrip;
      const turnMultiplier = this.handbrake ? 6.5 : 4.0;
      const targetAngular = -this.inputX * effectiveGrip * turnMultiplier * direction;

      this.angularSpeed = THREE.MathUtils.lerp(this.angularSpeed, targetAngular, Math.min(1, dt * 4));
      this.container.rotateY(this.angularSpeed * dt);

      const targetSpeed = this.inputZ;

      if (targetSpeed < 0 && this.linearSpeed > 0.01) {
        this.linearSpeed = THREE.MathUtils.lerp(this.linearSpeed, 0, Math.min(1, dt * 8));
      } else if (targetSpeed < 0) {
        this.linearSpeed = THREE.MathUtils.lerp(
          this.linearSpeed,
          targetSpeed * MAX_SPEED * REVERSE_SPEED_SCALE,
          Math.min(1, dt * 2)
        );
      } else {
        this.linearSpeed = THREE.MathUtils.lerp(
          this.linearSpeed,
          targetSpeed * MAX_SPEED,
          Math.min(1, dt * 2.2)
        );
      }
    }

    this.linearSpeed *= Math.max(0, 1 - LINEAR_DAMP * dt);
    if (this.handbrake) this.linearSpeed *= Math.max(0, 1 - 1.2 * dt);

    if (this.rigidBody) {
      forward.set(0, 0, 1).applyQuaternion(this.container.quaternion);
      forward.y = 0;
      forward.normalize();

      right.set(1, 0, 0).applyQuaternion(this.container.quaternion);
      right.y = 0;
      right.normalize();

      const angvel = this.rigidBody.motionProperties.angularVelocity;
      const radiusRatio = 0.5 / Math.max(this.sphereRadius, 0.001);
      const drive = this.linearSpeed * 100 * dt * radiusRatio;

      rigidBody.setAngularVelocity(this.physicsWorld, this.rigidBody, [
        angvel[0] + right.x * drive,
        angvel[1],
        angvel[2] + right.z * drive,
      ]);

      const p = this.rigidBody.position;
      this.spherePos.set(p[0], p[1], p[2]);

      const v = this.rigidBody.motionProperties.linearVelocity;
      this.sphereVel.set(v[0], v[1], v[2]);

      // Safety net: if the physics body ever tunnels through the AR floor,
      // restore it to the latest placement point instead of letting it fall forever.
      const fallLimit = this.spawnPos.y - Math.max(1.0, this.sphereRadius * 8);
      if (this.spherePos.y < fallLimit) {
        rigidBody.setPosition(
          this.physicsWorld,
          this.rigidBody,
          [this.spawnPos.x, this.spawnPos.y, this.spawnPos.z],
          false
        );
        rigidBody.setLinearVelocity(this.physicsWorld, this.rigidBody, [0, 0, 0]);
        rigidBody.setAngularVelocity(this.physicsWorld, this.rigidBody, [0, 0, 0]);

        this.spherePos.copy(this.spawnPos);
        this.sphereVel.set(0, 0, 0);
        this.linearSpeed = 0;
        this.angularSpeed = 0;
        this.acceleration = 0;
        this.container.rotation.set(0, this.spawnAngle, 0);
      }
    }

    this.acceleration = THREE.MathUtils.lerp(
      this.acceleration,
      this.linearSpeed + 0.25 * this.linearSpeed * Math.abs(this.linearSpeed),
      Math.min(1, dt)
    );

    this.container.position.set(
      this.spherePos.x,
      this.spherePos.y - this.sphereRadius,
      this.spherePos.z
    );

    if (dt > 0) {
      this.modelVelocity.subVectors(this.container.position, this.prevModelPos).divideScalar(dt);
      this.prevModelPos.copy(this.container.position);
    }

    this._animateVisuals(dt);

    const normalizedSpeed = Math.abs(this.linearSpeed / MAX_SPEED);
    this.driftIntensity =
      Math.abs(this.inputX) * normalizedSpeed * 0.6 +
      (this.handbrake ? 0.7 : 0);
  }

  _animateVisuals(dt) {
    if (this.bodyNode) {
      this.bodyNode.rotation.x = lerpAngle(
        this.bodyNode.rotation.x,
        -(this.linearSpeed - this.acceleration) / 6,
        Math.min(1, dt * 10)
      );
      this.bodyNode.rotation.z = lerpAngle(
        this.bodyNode.rotation.z,
        -(this.inputX / 5) * this.linearSpeed,
        Math.min(1, dt * 5)
      );
      this.bodyNode.position.y = THREE.MathUtils.lerp(
        this.bodyNode.position.y,
        this._bodyRestY - this._bodySink,
        Math.min(1, dt * 5)
      );
    }

    for (const wheel of this.wheels) {
      wheel.rotation.x += this.acceleration;
    }

    if (this.wheelFL) {
      this.wheelFL.rotation.y = lerpAngle(
        this.wheelFL.rotation.y,
        -this.inputX / 1.5,
        Math.min(1, dt * 10)
      );
    }

    if (this.wheelFR) {
      this.wheelFR.rotation.y = lerpAngle(
        this.wheelFR.rotation.y,
        -this.inputX / 1.5,
        Math.min(1, dt * 10)
      );
    }

    if (this.taillightL || this.taillightR || this.brakeGlow) {
      const brakeTarget = this.handbrake ? 1 : 0;
      this._brakeGlowT = THREE.MathUtils.lerp(this._brakeGlowT, brakeTarget, Math.min(1, dt * 10));

      const tailColor = this._taillightBaseColor.clone().lerp(this._taillightBrakeColor, this._brakeGlowT);
      if (this.taillightL) this.taillightL.material.color.copy(tailColor);
      if (this.taillightR) this.taillightR.material.color.copy(tailColor);
      if (this.brakeGlow) this.brakeGlow.intensity = THREE.MathUtils.lerp(0.15, 1.6, this._brakeGlowT);
    }
  }
}
