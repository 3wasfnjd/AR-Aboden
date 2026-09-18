const DEADZONE = 0.12;

export class MobileControls {
  constructor({ joyBase, joyKnob, gasBtn, brakeBtn, handbrakeBtn }) {
    this.joyBase = joyBase;
    this.joyKnob = joyKnob;
    this.gasBtn = gasBtn;
    this.brakeBtn = brakeBtn;
    this.handbrakeBtn = handbrakeBtn;

    this.pointerId = null;
    this.steer = 0;
    this.gas = false;
    this.brake = false;
    this.handbrake = false;

    this._bindJoystick();
    this._bindHoldButton(gasBtn, 'gas');
    this._bindHoldButton(brakeBtn, 'brake');
    this._bindHoldButton(handbrakeBtn, 'handbrake');

    const clear = () => this.reset();
    window.addEventListener('blur', clear);
    document.addEventListener('visibilitychange', () => {
      if (document.hidden) clear();
    });
  }

  _bindJoystick() {
    const update = (e) => {
      const r = this.joyBase.getBoundingClientRect();
      const cx = r.left + r.width / 2;
      const cy = r.top + r.height / 2;
      const max = r.width * 0.31;

      let dx = e.clientX - cx;
      let dy = e.clientY - cy;
      const len = Math.hypot(dx, dy);

      if (len > max) {
        dx = (dx / len) * max;
        dy = (dy / len) * max;
      }

      const normalized = dx / max;
      this.steer = Math.abs(normalized) > DEADZONE ? normalized : 0;
      this.joyKnob.style.transform = `translate(${dx}px,${dy}px)`;
    };

    const end = (e) => {
      if (e && this.pointerId !== null && e.pointerId !== this.pointerId) return;
      this.pointerId = null;
      this.steer = 0;
      this.joyKnob.style.transform = 'translate(0,0)';
    };

    this.joyBase.addEventListener('pointerdown', (e) => {
      if (this.pointerId !== null) return;
      e.preventDefault();
      this.pointerId = e.pointerId;
      this.joyBase.setPointerCapture?.(e.pointerId);
      update(e);
    });

    this.joyBase.addEventListener('pointermove', (e) => {
      if (e.pointerId !== this.pointerId) return;
      e.preventDefault();
      update(e);
    });

    this.joyBase.addEventListener('pointerup', end);
    this.joyBase.addEventListener('pointercancel', end);
    this.joyBase.addEventListener('lostpointercapture', end);
  }

  _bindHoldButton(button, property) {
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
    this.steer = 0;
    this.gas = false;
    this.brake = false;
    this.handbrake = false;
    this.joyKnob.style.transform = 'translate(0,0)';
    this.gasBtn.classList.remove('active');
    this.brakeBtn.classList.remove('active');
    this.handbrakeBtn.classList.remove('active');
  }

  update() {
    let z = 0;
    if (this.gas && !this.brake) z = 1;
    else if (this.brake && !this.gas) z = -1;

    return {
      x: this.steer,
      z,
      touchActive: false,
      handbrake: this.handbrake,
    };
  }
}
