import { RNApp, RNOHCoreContext, ResourceJSBundleProvider } from '@rnoh/react-native-openharmony';
import { createPackages } from '../PackageProvider';

@Entry
@Component
struct Index {
  @StorageLink('RNOHCoreContext') private context: RNOHCoreContext | undefined = undefined;

  build() {
    Column() {
      if (this.context) {
        RNApp({
          appKey: 'main',
          rnInstanceConfig: {
            name: 'T3Code',
            createRNPackages: createPackages,
            fontResourceByFontFamily: {},
          },
          jsBundleProvider: new ResourceJSBundleProvider(
            this.context.uiAbilityContext.resourceManager,
            'bundle.harmony.hbc',
          ),
        });
      }
    }
    .width('100%')
    .height('100%')
  }
}
