import {
  RNPackageContext,
  RNOHPackage,
  UITurboModule,
  UITurboModuleContext,
} from '@rnoh/react-native-openharmony';
import { ConnectionStoreModule } from './ConnectionStoreModule';
import { PairingScannerModule } from './PairingScannerModule';

type UITurboModuleFactory = (context: UITurboModuleContext) => UITurboModule;

class T3CodePackage extends RNOHPackage {
  override getUITurboModuleFactoryByNameMap(): Map<string, UITurboModuleFactory> {
    return new Map<string, UITurboModuleFactory>([
      ['T3ConnectionStore', (context: UITurboModuleContext) => new ConnectionStoreModule(context)],
      ['T3PairingScanner', (context: UITurboModuleContext) => new PairingScannerModule(context)],
    ]);
  }
}

export function createPackages(context: RNPackageContext): RNOHPackage[] {
  return [new T3CodePackage(context)];
}
