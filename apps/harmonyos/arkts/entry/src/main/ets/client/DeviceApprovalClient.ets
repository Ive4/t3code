import type { EnvironmentRequest } from './NativeRelay';
import type { DeviceApprovalOutcome, DeviceApprovalRequest } from './RelayProtocol';
import { normalizeDeviceVerificationCode, readDeviceApprovalOutcome, readDeviceApprovalSnapshot } from './RelayProtocol';

export type { DeviceApprovalOutcome, DeviceApprovalRequest } from './RelayProtocol';

interface ApproveDeviceBody {
  pairingLinkId: string;
}

interface DenyDeviceBody {
  id: string;
}

export class DeviceApprovalClient {
  private readonly readSnapshot: () => Promise<Object>;
  private readonly request: EnvironmentRequest;

  constructor(readSnapshot: () => Promise<Object>, request: EnvironmentRequest) {
    this.readSnapshot = readSnapshot;
    this.request = request;
  }

  async list(): Promise<DeviceApprovalRequest[]> {
    return readDeviceApprovalSnapshot(await this.readSnapshot());
  }

  async lookup(code: string): Promise<DeviceApprovalRequest[]> {
    const expected = normalizeDeviceVerificationCode(code);
    return (await this.list()).filter((row: DeviceApprovalRequest) =>
      normalizeDeviceVerificationCode(row.verificationCode) === expected);
  }

  async approve(pairingLinkId: string): Promise<DeviceApprovalOutcome> {
    if (!pairingLinkId || pairingLinkId.trim() !== pairingLinkId) throw new Error('设备申请标识无效。');
    const body: ApproveDeviceBody = { pairingLinkId };
    return readDeviceApprovalOutcome(await this.request('/api/auth/connect-devices/approve', 'POST',
      JSON.stringify(body)), true);
  }

  async deny(pairingLinkId: string): Promise<DeviceApprovalOutcome> {
    if (!pairingLinkId || pairingLinkId.trim() !== pairingLinkId) throw new Error('设备申请标识无效。');
    const body: DenyDeviceBody = { id: pairingLinkId };
    return readDeviceApprovalOutcome(await this.request('/api/auth/pairing-links/revoke', 'POST',
      JSON.stringify(body)), false);
  }
}
