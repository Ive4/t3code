import { sensor } from '@kit.SensorServiceKit';
import { UITurboModule } from '@rnoh/react-native-openharmony';

type AccelerometerListener = (sample: sensor.AccelerometerResponse) => void;

export class AccelerometerModule extends UITurboModule {
  private readonly listeners = new Map<string, AccelerometerListener>();

  public startWatching(event: string, intervalMs: number): boolean {
    const listener = (sample: sensor.AccelerometerResponse): void => {
      this.ctx.rnInstance.emitDeviceEvent(event, sample);
    };
    try {
      sensor.on(sensor.SensorId.ACCELEROMETER, listener, { interval: intervalMs * 1_000_000 });
      this.listeners.set(event, listener);
      return true;
    } catch (error) {
      this.ctx.logger.warn('Unable to start the Harmony accelerometer', error);
      return false;
    }
  }

  public stopWatching(event: string): void {
    const listener = this.listeners.get(event);
    if (listener === undefined) return;
    try {
      sensor.off(sensor.SensorId.ACCELEROMETER, listener);
      this.listeners.delete(event);
    } catch (error) {
      this.ctx.logger.warn('Unable to stop the Harmony accelerometer', error);
    }
  }

  public override __onDestroy__(): void {
    this.listeners.forEach((_, event) => this.stopWatching(event));
  }
}
