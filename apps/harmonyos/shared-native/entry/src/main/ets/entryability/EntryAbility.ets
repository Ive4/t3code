import { RNAbility } from '@rnoh/react-native-openharmony';

import { AbilityConstant, Want } from '@kit.AbilityKit';
import { captureIncomingShare } from '../SharingModule';

export default class EntryAbility extends RNAbility {
  override onCreate(want: Want, launchParam?: AbilityConstant.LaunchParam): void {
    const emptyLaunch: Want = {};
    const isShare = captureIncomingShare(want, this.context);
    super.onCreate(isShare ? emptyLaunch : want, launchParam);
  }

  override onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (!captureIncomingShare(want, this.context)) {
      super.onNewWant(want, launchParam);
    }
  }

  override getPagePath(): string {
    return 'pages/Index';
  }

  override getRNOHWorkerScriptUrl(): string {
    return 'entry/ets/workers/RNOHWorker.ets';
  }
}
