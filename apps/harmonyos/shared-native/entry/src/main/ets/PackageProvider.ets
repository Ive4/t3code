import KeyboardControllerPackage from '@react-native-ohos/react-native-keyboard-controller';
import ScreensPackage from '@react-native-ohos/react-native-screens';
import SVGPackage from '@react-native-ohos/react-native-svg';
import SafeAreaViewPackage from '@react-native-ohos/react-native-safe-area-context';
import {
  RNPackageContext,
  RNOHPackage,
  UITurboModule,
  UITurboModuleContext,
} from '@rnoh/react-native-openharmony';
import GestureHandlerPackage from '@react-native-ohos/react-native-gesture-handler';
import WorkletsPackage from '@react-native-ohos/react-native-worklets';
import ReanimatedPackage from '@react-native-ohos/react-native-reanimated';
import { AccelerometerModule } from './AccelerometerModule';
import { ScreenAwakeModule } from './ScreenAwakeModule';
import { AttachmentPickerModule } from './AttachmentPickerModule';
import { ImageManipulatorModule } from './ImageManipulatorModule';
import { DateTimePickerModule } from './DateTimePickerModule';
import { FileActionsModule } from './FileActionsModule';
import { AgentNotificationsModule } from './AgentNotificationsModule';
import { FoldPostureModule } from './FoldPostureModule';
import { UsageWidgetModule } from './UsageWidgetModule';
import { AppGalleryUpdatesModule } from './AppGalleryUpdatesModule';
import { AudioModule } from './AudioModule';
import { ConnectionStoreModule } from './ConnectionStoreModule';
import { PairingScannerModule } from './PairingScannerModule';
import { CryptoModule } from './CryptoModule';
import { SecureStorageModule } from './SecureStorageModule';
import { NetworkModule } from './NetworkModule';
import { MetadataModule } from './MetadataModule';
import { SQLiteModule } from './SQLiteModule';
import { SharingModule } from './SharingModule';
import { FileSystemModule } from './FileSystemModule';
import { HarmonyVideoModule } from './HarmonyVideoModule';
import { InteractionModule } from './InteractionModule';
import { LocalizationModule } from './LocalizationModule';

type UITurboModuleFactory = (context: UITurboModuleContext) => UITurboModule;

class T3CodePackage extends RNOHPackage {
  override getUITurboModuleFactoryByNameMap(): Map<string, UITurboModuleFactory> {
    return new Map<string, UITurboModuleFactory>([
      ['T3Accelerometer', (context: UITurboModuleContext) => new AccelerometerModule(context)],
      ['T3ScreenAwake', (context: UITurboModuleContext) => new ScreenAwakeModule(context)],
      ['T3AttachmentPicker', (context: UITurboModuleContext) => new AttachmentPickerModule(context)],
      ['T3ImageManipulator', (context: UITurboModuleContext) => new ImageManipulatorModule(context)],
      ['T3DateTimePicker', (context: UITurboModuleContext) => new DateTimePickerModule(context)],
      ['T3FileActions', (context: UITurboModuleContext) => new FileActionsModule(context)],
      ['T3AgentNotifications', (context: UITurboModuleContext) => new AgentNotificationsModule(context)],
      ['T3FoldPosture', (context: UITurboModuleContext) => new FoldPostureModule(context)],
      ['T3UsageWidget', (context: UITurboModuleContext) => new UsageWidgetModule(context)],
      ['T3AppGalleryUpdates', (context: UITurboModuleContext) => new AppGalleryUpdatesModule(context)],
      ['T3Audio', (context: UITurboModuleContext) => new AudioModule(context)],
      ['T3ConnectionStore', (context: UITurboModuleContext) => new ConnectionStoreModule(context)],
      ['T3PairingScanner', (context: UITurboModuleContext) => new PairingScannerModule(context)],
      ['T3Crypto', (context: UITurboModuleContext) => new CryptoModule(context)],
      ['T3SecureStorage', (context: UITurboModuleContext) => new SecureStorageModule(context)],
      ['T3Network', (context: UITurboModuleContext) => new NetworkModule(context)],
      ['T3Metadata', (context: UITurboModuleContext) => new MetadataModule(context)],
      ['T3SQLite', (context: UITurboModuleContext) => new SQLiteModule(context)],
      ['T3Sharing', (context: UITurboModuleContext) => new SharingModule(context)],
      ['T3FileSystem', (context: UITurboModuleContext) => new FileSystemModule(context)],
      ['T3Video', (context: UITurboModuleContext) => new HarmonyVideoModule(context)],
      ['T3Interaction', (context: UITurboModuleContext) => new InteractionModule(context)],
      ['GtReactNative', (context: UITurboModuleContext) => new LocalizationModule(context)],
    ]);
  }
}

export function createPackages(context: RNPackageContext): RNOHPackage[] {
  return [
    new T3CodePackage(context),
    new GestureHandlerPackage(context),
    new WorkletsPackage(context),
    new ReanimatedPackage(context),
    new KeyboardControllerPackage(context),
    new ScreensPackage(context),
    new SVGPackage(context),
    new SafeAreaViewPackage(context),
  ];
}
