import pasteboard from '@ohos.pasteboard';
import vibrator from '@ohos.vibrator';
import { UITurboModule } from '@rnoh/react-native-openharmony';
import { takeComposerPasteImages } from './ComposerPasteImages';
import { setT3ComposerKeyboard, setT3KeyboardCommands } from './T3KeyboardCommands';

export class InteractionModule extends UITurboModule {
  public async getClipboardText(): Promise<string> {
    const clipboard = pasteboard.getSystemPasteboard();
    if (!(await clipboard.hasData())) return '';
    return (await clipboard.getData()).getPrimaryText() ?? '';
  }

  public async setClipboardText(text: string): Promise<boolean> {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    await pasteboard.getSystemPasteboard().setData(data);
    return true;
  }

  public async writeComposerClipboard(text: string, html: string): Promise<void> {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    data.getRecord(0).addEntry(pasteboard.MIMETYPE_TEXT_HTML, html);
    await pasteboard.getSystemPasteboard().setData(data);
  }

  public async takeComposerPasteImages(token: string, materialize: boolean): Promise<string[]> {
    return takeComposerPasteImages(token, materialize);
  }

  public async setKeyboardCommands(commands: string[]): Promise<void> {
    setT3KeyboardCommands(commands, (name, value) => this.ctx.rnInstance.emitDeviceEvent(name, value));
  }

  public async setComposerKeyboard(id: string, mode: string): Promise<void> {
    setT3ComposerKeyboard(id, mode, (name, value) => this.ctx.rnInstance.emitDeviceEvent(name, value));
  }

  public async vibrate(duration: number): Promise<void> {
    await vibrator.startVibration({ type: 'time', duration }, { id: 0, usage: 'touch' });
  }
}
