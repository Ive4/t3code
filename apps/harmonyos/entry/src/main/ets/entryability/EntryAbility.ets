import { RNAbility } from '@rnoh/react-native-openharmony';

export default class EntryAbility extends RNAbility {
  override getPagePath(): string {
    return 'pages/Index';
  }

  override getRNOHWorkerScriptUrl(): string {
    return 'entry/ets/workers/RNOHWorker.ets';
  }
}
