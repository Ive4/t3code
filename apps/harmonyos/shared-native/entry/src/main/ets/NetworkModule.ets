import connection from '@ohos.net.connection';
import { UITurboModule } from '@rnoh/react-native-openharmony';

interface NetworkState {
  type: string;
  isConnected: boolean;
  isInternetReachable: boolean;
}

export class NetworkModule extends UITurboModule {
  private networkConnection: connection.NetConnection | undefined;
  private networkUpdate = 0;

  public async getNetworkState(): Promise<NetworkState> {
    if (!(await connection.hasDefaultNet())) {
      return { type: 'NONE', isConnected: false, isInternetReachable: false };
    }
    const handle = await connection.getDefaultNet();
    const capabilities = await connection.getNetCapabilities(handle);
    const bearers = capabilities.bearerTypes;
    let type = 'UNKNOWN';
    if (bearers.includes(connection.NetBearType.BEARER_WIFI)) type = 'WIFI';
    else if (bearers.includes(connection.NetBearType.BEARER_CELLULAR)) type = 'CELLULAR';
    else if (bearers.includes(connection.NetBearType.BEARER_ETHERNET)) type = 'ETHERNET';
    return {
      type,
      isConnected: true,
      isInternetReachable: capabilities.networkCap?.includes(
        connection.NetCap.NET_CAPABILITY_VALIDATED,
      ) ?? false,
    };
  }

  public startWatching(): void {
    if (this.networkConnection !== undefined) return;
    const subscription = connection.createNetConnection();
    const update = (): void => {
      const generation = ++this.networkUpdate;
      void this.getNetworkState().then((state: NetworkState) => {
        if (this.networkConnection === subscription && this.networkUpdate === generation) {
          this.ctx.rnInstance.emitDeviceEvent('T3NetworkStateChanged', state);
        }
      }).catch((error: Error) => {
        this.ctx.logger.warn('Unable to read Harmony network state', error);
      });
    };
    subscription.on('netAvailable', update);
    subscription.on('netLost', update);
    subscription.on('netCapabilitiesChange', update);
    this.networkConnection = subscription;
    subscription.register((error) => {
      if (error) {
        this.networkConnection = undefined;
        this.ctx.logger.warn('Unable to watch Harmony network state', error);
      } else {
        update();
      }
    });
  }

  public override __onDestroy__(): void {
    const subscription = this.networkConnection;
    this.networkConnection = undefined;
    subscription?.unregister((error) => {
      if (error) this.ctx.logger.warn('Unable to stop watching Harmony network state', error);
    });
  }
}
