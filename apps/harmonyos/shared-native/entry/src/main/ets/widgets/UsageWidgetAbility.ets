import type { Want } from '@kit.AbilityKit';
import { FormExtensionAbility, formBindingData, formInfo } from '@kit.FormKit';
import { updateUsageWidget, usageWidgetBinding } from './UsageWidgetData';

export default class UsageWidgetAbility extends FormExtensionAbility {
  override onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = want.parameters?.[formInfo.FormParam.IDENTITY_KEY];
    return usageWidgetBinding(this.context, typeof formId === 'string' ? formId : undefined);
  }

  override onCastToNormalForm(formId: string): void {
    this.onUpdateForm(formId);
  }

  override onUpdateForm(formId: string): void {
    void updateUsageWidget(this.context, formId).catch(() => {
      console.warn('[t3-usage-widget] Could not refresh quota readings.');
    });
  }
}
