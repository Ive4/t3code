import { ComponentBuilderContext, RNApp, RNOHCoreContext, ResourceJSBundleProvider } from '@rnoh/react-native-openharmony';
import { buildT3ComposerPaste } from '../T3ComposerPaste';
import { buildT3InlineVideo } from '../T3InlineVideo';
import lazy { buildT3PdfPreview } from '../T3PdfPreview';
import { handleT3KeyboardEvent } from '../T3KeyboardCommands';
import lazy { buildT3WebView } from '../T3WebView';
import { createPackages } from '../PackageProvider';

@Builder
function buildT3Component(ctx: ComponentBuilderContext) {
  if (ctx.componentName === 'T3InlineVideo') {
    buildT3InlineVideo(ctx)
  } else if (ctx.componentName === 'T3PdfPreview') {
    buildT3PdfPreview(ctx)
  } else if (ctx.componentName === 'T3ComposerPaste') {
    buildT3ComposerPaste(ctx)
  } else {
    buildT3WebView(ctx)
  }
}

@Entry
@Component
struct Index {
  @StorageLink('RNOHCoreContext') private context: RNOHCoreContext | undefined = undefined;

  build() {
    Column() {
      if (this.context) {
        RNApp({
          appKey: 'main',
          wrappedCustomRNComponentBuilder: wrapBuilder(buildT3Component),
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
    .onKeyPreIme(handleT3KeyboardEvent)
  }
}
