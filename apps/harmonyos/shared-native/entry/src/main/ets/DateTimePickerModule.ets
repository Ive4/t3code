import { window } from '@kit.ArkUI';
import { i18n } from '@kit.LocalizationKit';
import { UITurboModule } from '@rnoh/react-native-openharmony';

export class DateTimePickerModule extends UITurboModule {
  public async pick(mode: string, localTimestamp: number): Promise<number | null> {
    if ((mode !== 'date' && mode !== 'time') || !Number.isFinite(localTimestamp)) {
      throw new RangeError('Invalid date or time selection');
    }
    const selected = new Date(localTimestamp);
    const uiContext = (await window.getLastWindow(this.ctx.uiAbilityContext)).getUIContext();
    return new Promise<number | null>((resolve) => {
      let result: number | null = null;
      const onDidDisappear = (): void => resolve(result);
      if (mode === 'date') {
        uiContext.showDatePickerDialog({
          selected,
          start: new Date(1900, 0, 31),
          end: new Date(2100, 11, 31),
          onDateAccept: (date: Date): void => {
            result = date.getFullYear() * 10000 + (date.getMonth() + 1) * 100 + date.getDate();
          },
          onDidDisappear,
        });
      } else {
        uiContext.showTimePickerDialog({
          selected,
          useMilitaryTime: i18n.System.is24HourClock(),
          onAccept: (time: TimePickerResult): void => {
            result = time.hour * 60 + time.minute;
          },
          onDidDisappear,
        });
      }
    });
  }
}
