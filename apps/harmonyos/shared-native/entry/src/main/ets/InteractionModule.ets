import pasteboard from '@ohos.pasteboard';
import vibrator from '@ohos.vibrator';
import { UITurboModule } from '@rnoh/react-native-openharmony';

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

  public async vibrate(duration: number): Promise<void> {
    await vibrator.startVibration({ type: 'time', duration }, { id: 0, usage: 'touch' });
  }
}
