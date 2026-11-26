import bundleManager from '@ohos.bundle.bundleManager';
import deviceInfo from '@ohos.deviceInfo';
import i18n from '@ohos.i18n';
import { UITurboModule } from '@rnoh/react-native-openharmony';

interface ApplicationMetadata {
  nativeApplicationVersion: string;
  nativeBuildVersion: string;
  applicationName: string;
  applicationId: string;
}

interface DeviceMetadata {
  deviceType: string;
  manufacturer: string;
  modelName: string;
  osVersion: string;
  timeZone: string;
}

export class MetadataModule extends UITurboModule {
  public is24HourFormat(): boolean {
    return i18n.System.is24HourClock();
  }

  public application(): ApplicationMetadata {
    const bundle = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    return {
      nativeApplicationVersion: bundle.versionName,
      nativeBuildVersion: bundle.versionCode.toString(),
      applicationName: this.ctx.uiAbilityContext.resourceManager.getStringSync(bundle.appInfo.labelId),
      applicationId: bundle.name,
    };
  }

  public device(): DeviceMetadata {
    return {
      deviceType: deviceInfo.deviceType,
      manufacturer: deviceInfo.manufacture,
      modelName: deviceInfo.productModel,
      timeZone: i18n.getTimeZone().getID(),
      osVersion: [deviceInfo.majorVersion, deviceInfo.seniorVersion, deviceInfo.featureVersion].join('.'),
    };
  }
}
