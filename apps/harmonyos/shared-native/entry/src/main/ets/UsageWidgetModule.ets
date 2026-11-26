import { formProvider } from '@kit.FormKit';
import { UITurboModule } from '@rnoh/react-native-openharmony';
import { saveUsageWidgetSnapshot, updateUsageWidget, USAGE_WIDGET_NAME } from './widgets/UsageWidgetData';

export class UsageWidgetModule extends UITurboModule {
  public async publish(payload: string): Promise<void> {
    if (!canIUse('SystemCapability.Ability.Form')) return;
    const context = this.ctx.uiAbilityContext;
    saveUsageWidgetSnapshot(context, payload);
    const forms = await formProvider.getPublishedRunningFormInfos();
    await Promise.all(forms
      .filter((form) => form.formName === USAGE_WIDGET_NAME)
      .map((form) => updateUsageWidget(context, form.formId)));
  }
}
