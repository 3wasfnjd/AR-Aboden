// SPDX-License-Identifier: GPL-3.0-only
// Adapted from scottstts/Sandboard via Threejs-Awesome-Graphics-Agent-Skills.
// Revision d1cb23dcce6ea8ee4a60f6159daeb79d4b511dba; see js/sand/NOTICE.md.
export async function checkedShader(device, label, code) {
    const module = device.createShaderModule({
        label,
        code
    });
    const info = await module.getCompilationInfo();
    const errors = info.messages.filter((message)=>message.type === 'error');
    if (errors.length) throw new Error(`${label}: ${errors.map((message)=>`${message.lineNum}:${message.linePos} ${message.message}`).join('\n')}`);
    return module;
}
