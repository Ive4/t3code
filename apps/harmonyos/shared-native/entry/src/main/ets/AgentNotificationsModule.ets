import { UIAbility, Want, wantAgent } from '@kit.AbilityKit';
import { authentication } from '@kit.AccountKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { pushService } from '@kit.PushKit';
import bundleManager from '@ohos.bundle.bundleManager';
import { UITurboModule } from '@rnoh/react-native-openharmony';

const ACTION_PREFIX = 'com.t3tools.t3code.agent-notification.';
const TAP_EVENT = 'T3AgentNotificationTapped';
const PUSH_TOKEN_EVENT = 'T3AgentPushTokenUpdated';

interface AgentNotificationLink {
  environmentId: string;
  threadId: string;
}

let pendingLink: AgentNotificationLink | null = null;
let notifyTap: (() => void) | undefined;
let pushAbility: UIAbility | undefined;

export function setAgentPushAbility(ability: UIAbility): void {
  pushAbility = ability;
}

export function captureAgentNotification(want: Want): boolean {
  const remote = want.parameters?.['t3AgentNotification'] === true;
  if (!remote && !want.action?.startsWith(ACTION_PREFIX)) return false;
  const environmentId = want.parameters?.[remote ? 'environmentId' : 't3NotificationEnvironment'];
  const threadId = want.parameters?.[remote ? 'threadId' : 't3NotificationThread'];
  if (typeof environmentId !== 'string' || !environmentId || typeof threadId !== 'string' || !threadId) {
    return false;
  }
  pendingLink = { environmentId, threadId };
  notifyTap?.();
  return true;
}

export class AgentNotificationsModule extends UITurboModule {
  private observingPushToken = false;
  private readonly onTap = (): void => {
    this.ctx.rnInstance.emitDeviceEvent(TAP_EVENT, null);
  };
  private readonly onPushToken = (token: string): void => {
    this.ctx.rnInstance.emitDeviceEvent(PUSH_TOKEN_EVENT, token);
  };

  public async getPushToken(): Promise<string> {
    return pushService.getToken();
  }

  public async isHuaweiAccountAvailable(): Promise<boolean> {
    if (!canIUse('SystemCapability.AuthenticationServices.HuaweiID.Auth')) return false;
    const bundle = await bundleManager.getBundleInfoForSelf(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_HAP_MODULE |
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_METADATA,
    );
    return bundle.hapModulesInfo.some((module) =>
      module.name === this.ctx.uiAbilityContext.abilityInfo.moduleName &&
      module.metadata.some((item) => item.name === 'client_id' && item.value.length > 0),
    );
  }

  public async signInHuaweiAccount(): Promise<string | null> {
    const request = new authentication.HuaweiIDProvider().createLoginWithHuaweiIDRequest();
    request.forceLogin = true;
    request.state = util.generateRandomUUID();
    const controller = new authentication.AuthenticationController(this.ctx.uiAbilityContext);
    try {
      const response = await controller.executeRequest(request) as authentication.LoginWithHuaweiIDResponse;
      const code = response.data?.authorizationCode;
      if (response.state !== request.state || !code) throw new Error('Huawei authorization failed.');
      return code;
    } catch (error) {
      if ((error as BusinessError).code === 1001502012) return null;
      throw new Error('Huawei sign-in failed.');
    }
  }

  public async observePushToken(): Promise<void> {
    if (!pushAbility || this.observingPushToken) return;
    pushService.on('tokenUpdate', pushAbility, this.onPushToken);
    this.observingPushToken = true;
  }

  public async deletePushToken(): Promise<void> {
    await pushService.deleteToken();
  }

  public async isEnabled(): Promise<boolean> {
    return notificationManager.isNotificationEnabled();
  }

  public async openSettings(): Promise<boolean> {
    const settings = await notificationManager.openNotificationSettingsWithResult(this.ctx.uiAbilityContext);
    return settings.notificationEnabled ?? this.isEnabled();
  }

  public async publish(title: string, text: string, environmentId: string, threadId: string): Promise<void> {
    const label = JSON.stringify([environmentId, threadId]);
    const ability = this.ctx.uiAbilityContext.abilityInfo;
    const tap = await wantAgent.getWantAgent({
      wants: [{
        bundleName: ability.bundleName,
        abilityName: ability.name,
        action: ACTION_PREFIX + label,
        parameters: { t3NotificationEnvironment: environmentId, t3NotificationThread: threadId },
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 1,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
    });
    await notificationManager.publish({
      id: 1,
      label,
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      tapDismissed: true,
      wantAgent: tap,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title, text },
      },
    });
  }

  public async takePendingLink(): Promise<AgentNotificationLink | null> {
    notifyTap = this.onTap;
    const link = pendingLink;
    pendingLink = null;
    return link;
  }

  public override __onDestroy__(): void {
    if (notifyTap === this.onTap) notifyTap = undefined;
    if (this.observingPushToken) pushService.off('tokenUpdate', this.onPushToken);
  }
}
