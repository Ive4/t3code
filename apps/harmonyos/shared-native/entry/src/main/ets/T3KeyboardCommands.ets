import inputDevice from '@ohos.multimodalInput.inputDevice';
import { KeyCode } from '@ohos.multimodalInput.keyCode';

type SendEvent = (name: string, value: string | boolean) => void;

let sendEvent: SendEvent | undefined;
let enabled = new Set<string>();
let composerId = '';
let composerMode = '';
const consumed = new Set<string>();

export function setT3KeyboardCommands(commands: string[], send: SendEvent): void {
  enabled = new Set(commands);
  sendEvent = send;
}

export function setT3ComposerKeyboard(id: string, mode: string, send: SendEvent): void {
  if (!mode && composerId !== id) return;
  composerId = mode ? id : '';
  composerMode = mode;
  sendEvent = send;
}

export function handleT3KeyboardEvent(event: KeyEvent): boolean {
  if (event.keySource !== KeySource.Keyboard || !sendEvent) return false;
  const code = event.keyCode;
  const isReturn = code === KeyCode.KEYCODE_ENTER || code === KeyCode.KEYCODE_NUMPAD_ENTER;
  if (!isReturn && code !== KeyCode.KEYCODE_C && code !== KeyCode.KEYCODE_H) return false;
  const key = event.deviceId + ':' + code;
  if (event.type !== KeyType.Down) return consumed.delete(key);
  if (consumed.has(key)) return true;
  if (!event.getModifierKeyState || event.metaKey || event.getModifierKeyState(['Alt'])) return false;
  const ctrl = event.getModifierKeyState(['Ctrl']);
  const shift = event.getModifierKeyState(['Shift']);
  if (!isReturn) {
    const command = code === KeyCode.KEYCODE_C ? 'copyThreadReference' : 'cycleHost';
    if (!ctrl || !shift || !enabled.has(command)) return false;
    consumed.add(key);
    sendEvent('T3KeyboardCommand', command);
    return true;
  }
  if (!composerId || (!ctrl && shift) || (composerMode === 'send' ? shift : !ctrl)) return false;
  try {
    if (inputDevice.getDeviceInfoSync(event.deviceId).isVirtual !== false ||
      inputDevice.getKeyboardTypeSync(event.deviceId) !== inputDevice.KeyboardType.ALPHABETIC_KEYBOARD) return false;
  } catch (_) {
    return false;
  }
  consumed.add(key);
  sendEvent('T3ComposerSubmit:' + composerId, composerMode === 'send' ? ctrl : shift);
  return true;
}
