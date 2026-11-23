import { setupRNOHWorker } from '@rnoh/react-native-openharmony/src/main/ets/setupRNOHWorker';
import { createPackages } from '../PackageProvider';

setupRNOHWorker({
  createWorkerRNInstanceConfig: () => ({ thirdPartyPackagesFactory: createPackages }),
});
