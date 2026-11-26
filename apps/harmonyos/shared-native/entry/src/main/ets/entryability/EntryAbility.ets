import { RNAbility } from '@rnoh/react-native-openharmony';

import { AbilityConstant, Want } from '@kit.AbilityKit';
import { formInfo } from '@kit.FormKit';
import { captureAgentNotification, setAgentPushAbility } from '../AgentNotificationsModule';
import { captureIncomingShare } from '../SharingModule';

function withLauncherShortcut(want: Want): Want {
  if (want.uri) return want;
  const formId = want.parameters?.[formInfo.FormParam.IDENTITY_KEY];
  const formParams = want.parameters?.['params'];
  if (typeof formId === 'string' && formParams === '{"t3Widget":"usage"}') {
    return { uri: 't3code://settings/usage?tab=limits' };
  }
  const shortcut = want.parameters?.['t3LauncherShortcut'];
  if (shortcut === 'new') return { uri: 't3code://new' };
  if (shortcut === 'pair') return { uri: 't3code://pair' };
  return want;
}

export default class EntryAbility extends RNAbility {
  override onCreate(want: Want, launchParam?: AbilityConstant.LaunchParam): void {
    setAgentPushAbility(this);
    const emptyLaunch: Want = {};
    const consumed = captureIncomingShare(want, this.context) || captureAgentNotification(want);
    super.onCreate(consumed ? emptyLaunch : withLauncherShortcut(want), launchParam);
  }

  override onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (!captureIncomingShare(want, this.context) && !captureAgentNotification(want)) {
      super.onNewWant(withLauncherShortcut(want), launchParam);
    }
  }

  override getPagePath(): string {
    return 'pages/Index';
  }

  override getRNOHWorkerScriptUrl(): string {
    return 'entry/ets/workers/RNOHWorker.ets';
  }
}
