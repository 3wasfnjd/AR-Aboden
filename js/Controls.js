import * as THREE from 'three';

const DEADZONE = 0.15;

export class MobileControls {
  constructor({ steerZone, joyBase, joyKnob, handbrakeBtn }) {
    this.steerZone = steerZone || joyBase;
    this.joyBase = joyBase;
    this.joyKnob = joyKnob;
    this.handbrakeBtn = handbrakeBtn;

    this.pointerId = null;
    this.touchActive = false;
    this.touchDirX = 0;
    this.touchDirY = 0;
    this.handbrake = false;

    this._bindJoystick();
    this._bindHoldButton(handbrakeBtn, 'handbrake');

    const clear = () => this.reset();
    window.addEventListener('blur', clear);
    document.addEventListener('visibilitychange', () => {
      if (document.hidden) clear();
    });
  }

  _bindJoystick() {
    const steerRange = 40;

    const update = (e) => {
      const rect = this.joyBase.getBoundingClientRect();
      const cx = rect.left + rect.width / 2;
      const cy = rect.top + rect.height / 2;

      let dx = (e.clientX - cx) / steerRange;
      let dy = (e.clientY - cy) / steerRange;
      const mag = Math.hypot(dx, dy);

      if (mag > 1) {
        dx /= mag;
        dy /= mag;
      }

      this.touchDirX = dx;
      this.touchDirY = dy;
      this.joyKnob.style.transform =
        `translate(${this.touchDirX * 60}px,${this.touchDirY * 60}px)`;
    };

    const resetSteer = () => {
      this.pointerId = null;
      this.touchActive = false;
      this.touchDirX = 0;
      this.touchDirY = 0;
      this.joyKnob.style.transform = '';
      this.joyBase.classList.remove('active');
    };

    const end = (e) => {
      if (e && this.pointerId !== null && e.pointerId !== this.pointerId) return;
      resetSteer();
    };

    this.steerZone.addEventListener('pointerdown', (e) => {
      if (e.target.closest('button,.game-hud')) return;
      if (this.pointerId !== null) return;

      e.preventDefault();
      this.steerZone.setPointerCapture?.(e.pointerId);
      this.pointerId = e.pointerId;
      this.touchActive = true;
      this.touchDirX = 0;
      this.touchDirY = 0;
      this.joyBase.classList.add('active');
      update(e);
    });

    this.steerZone.addEventListener('pointermove', (e) => {
      if (e.pointerId !== this.pointerId) return;
      e.preventDefault();
      update(e);
    });

    this.steerZone.addEventListener('pointerup', end);
    this.steerZone.addEventListener('pointercancel', end);
    this.steerZone.addEventListener('lostpointercapture', end);
  }

  _bindHoldButton(button, property) {
    if (!button) return;

    const press = (e) => {
      e.preventDefault();
      e.stopPropagation();
      this[property] = true;
      button.classList.add('active');
      button.setPointerCapture?.(e.pointerId);
    };

    const release = (e) => {
      e.preventDefault();
      e.stopPropagation();
      this[property] = false;
      button.classList.remove('active');
    };

    button.addEventListener('pointerdown', press);
    button.addEventListener('pointerup', release);
    button.addEventListener('pointercancel', release);
    button.addEventListener('lostpointercapture', () => {
      this[property] = false;
      button.classList.remove('active');
    });
  }

  reset() {
    this.pointerId = null;
    this.touchActive = false;
    this.touchDirX = 0;
    this.touchDirY = 0;
    this.handbrake = false;

    this.joyKnob.style.transform = '';
    this.joyBase.classList.remove('active');
    this.handbrakeBtn?.classList.remove('active');
  }

  update(worldAngle = Math.PI / 4) {
    let x = 0;
    let z = 0;

    if (this.touchActive) {
      const jx = this.touchDirX;
      const jy = this.touchDirY;
      const mag = Math.hypot(jx, jy);

      if (mag > DEADZONE) {
        // Same mapping used by Hajwala: the joystick is a world-space
        // direction selector. Vehicle.js handles touch as auto-gas.
        const cosA = Math.cos(worldAngle);
        const sinA = Math.sin(worldAngle);
        x = (jx * cosA + jy * sinA) / mag;
        z = (-jx * sinA + jy * cosA) / mag;
      }
    }

    return {
      x,
      z,
      touchActive: this.touchActive,
      handbrake: this.handbrake,
    };
  }}
