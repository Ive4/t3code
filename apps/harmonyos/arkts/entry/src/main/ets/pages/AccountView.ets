import {
  AccountDeviceSession, AccountEmailAction, AccountEmailStep, AccountIdentity, AccountMode, AccountNameUpdate,
} from '../client/AccountProtocol';
import { RelayEnvironment } from '../client/RelayProtocol';
import { workspaceForegroundColor, workspaceHeaderColor, workspaceMutedColor, workspaceSurfaceColor } from './WorkspaceChrome';

interface AccountNameDraft {
  identity: AccountIdentity;
  firstName: string;
  lastName: string;
}

@Component
struct AccountSessions {
  @Prop @Watch('identityChanged') identity: AccountIdentity | undefined = undefined;
  @Prop dark: boolean = false;
  @State private sessions: AccountDeviceSession[] = [];
  @State private loading: boolean = false;
  @State private loadError: string = '';
  @State private revokeError: string = '';
  @State private revokingId: string = '';
  private active: boolean = false;
  private confirming: boolean = false;
  private sessionIdentity: AccountIdentity | undefined;
  private epoch: number = 0;
  onListSessions: (identity: AccountIdentity) => Promise<AccountDeviceSession[]> = async () => [];
  onRevokeSession: (identity: AccountIdentity, sessionId: string) => Promise<void> = async () => {};

  aboutToAppear(): void {
    this.active = true;
    this.identityChanged();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.sessionIdentity = undefined;
    this.epoch++;
  }

  private identityChanged(): void {
    if (this.sessionIdentity?.sessionId === this.identity?.sessionId &&
      this.sessionIdentity?.userId === this.identity?.userId) return;
    this.sessionIdentity = this.identity;
    this.epoch++;
    this.sessions = [];
    this.loading = false;
    this.loadError = '';
    this.revokeError = '';
    this.revokingId = '';
    if (this.active) void this.refresh();
  }

  private async refresh(): Promise<void> {
    const identity = this.identity;
    if (!this.active || !identity || this.loading || this.revokingId) return;
    const epoch = this.epoch;
    this.loading = true;
    this.loadError = '';
    this.revokeError = '';
    try {
      const sessions = await this.onListSessions(identity);
      if (epoch === this.epoch) this.sessions = sessions;
    } catch (error) {
      if (epoch === this.epoch) this.loadError = (error as Error).message || '无法加载活动会话。';
    } finally {
      if (epoch === this.epoch) this.loading = false;
    }
  }

  private sessionLabel(session: AccountDeviceSession): string {
    return [session.deviceType, session.browserName].filter(Boolean).join(' · ') || '未知设备';
  }

  private sessionDetails(session: AccountDeviceSession): string {
    const lastActive = new Date(session.lastActiveAt);
    const time = session.lastActiveAt && !Number.isNaN(lastActive.getTime())
      ? `最近活跃于 ${lastActive.toLocaleString()}` : '';
    return session.id === this.identity?.sessionId ? ['当前会话', time].filter(Boolean).join(' · ') : time;
  }

  private async confirmRevoke(session: AccountDeviceSession): Promise<void> {
    const identity = this.identity;
    if (!this.active || !identity || identity.sessionId === session.id || this.loading || this.loadError ||
      this.revokingId || this.confirming) return;
    const epoch = this.epoch;
    this.confirming = true;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '退出此会话？',
        message: `将退出“${this.sessionLabel(session)}”上的 T3 账号会话。`,
        buttons: [{ text: '取消', color: '#5070a1' }, { text: '退出会话', color: '#c8353c' }],
      });
      if (result.index !== 1 || epoch !== this.epoch || this.loading || this.loadError ||
        !this.sessions.some((row: AccountDeviceSession) => row.id === session.id)) return;
    } catch (_) {
      return;
    } finally {
      this.confirming = false;
    }

    this.revokingId = session.id;
    this.revokeError = '';
    try {
      await this.onRevokeSession(identity, session.id);
      if (epoch === this.epoch) {
        this.sessions = this.sessions.filter((row: AccountDeviceSession) => row.id !== session.id);
      }
    } catch (error) {
      if (epoch === this.epoch) this.revokeError = (error as Error).message || '无法退出该会话，请重试。';
    } finally {
      if (epoch === this.epoch) this.revokingId = '';
    }
  }

  build() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text('活动会话')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(workspaceForegroundColor(this.dark))
          .layoutWeight(1)
        if (this.loading) {
          LoadingProgress().width(20).height(20).accessibilityText('正在加载活动会话')
        }
        Button(this.loadError ? '重试' : '刷新', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(44)
          .accessibilityText(this.loadError ? '重试加载活动会话' : '刷新活动会话')
          .enabled(!this.loading && !this.revokingId)
          .onClick(() => { void this.refresh(); })
      }.width('100%')
      if (this.loadError) {
        Text(this.loadError)
          .fontSize(15)
          .fontColor(workspaceForegroundColor(this.dark))
      } else {
        ForEach(this.sessions, (session: AccountDeviceSession) => {
          Row({ space: 8 }) {
            Column({ space: 4 }) {
              Text(this.sessionLabel(session))
                .fontSize(16)
                .fontColor(workspaceForegroundColor(this.dark))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (this.sessionDetails(session)) {
                Text(this.sessionDetails(session))
                  .fontSize(13)
                  .fontColor(workspaceMutedColor(this.dark))
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            if (this.revokingId === session.id) {
              LoadingProgress().width(20).height(20).accessibilityText('正在退出会话')
            } else if (session.id !== this.identity?.sessionId) {
              Button('退出会话', { buttonStyle: ButtonStyleMode.TEXTUAL })
                .height(44)
                .fontColor('#c8353c')
                .accessibilityText('退出会话 ' + this.sessionLabel(session))
                .enabled(!this.loading && !this.revokingId)
                .onClick(() => { void this.confirmRevoke(session); })
            }
          }.width('100%')
        }, (session: AccountDeviceSession) =>
          `${session.id}\n${session.lastActiveAt}\n${session.deviceType}\n${session.browserName}`)
      }
      if (this.revokeError) {
        Text(this.revokeError)
          .fontSize(15)
          .fontColor($r('sys.color.font_primary'))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct AccountView {
  @Prop configured: boolean = false;
  @Prop @Watch('profileIdentityChanged') identity: AccountIdentity | undefined = undefined;
  @Prop working: boolean = false;
  @Prop awaitingBrowser: boolean = false;
  @Prop emailWorking: boolean = false;
  @Prop emailStep: AccountEmailStep | undefined = undefined;
  @Prop error: string = '';
  @Prop relayConfigured: boolean = false;
  @Prop connectProfileOpen: boolean = false;
  @Prop registeredServers: RelayEnvironment[] = [];
  @Prop registeredServersLoaded: boolean = false;
  @Prop registeredServersLoading: boolean = false;
  @Prop registeredServersError: string = '';
  @Prop deregisteringEnvironmentId: string = '';
  @Prop deregisterError: string = '';
  @State private emailAddress: string = '';
  @State private credential: string = '';
  @State private nameDraft: AccountNameDraft | undefined = undefined;
  @State private savingName: boolean = false;
  @State private nameError: string = '';
  private active: boolean = false;
  private confirmingDeregister: boolean = false;
  private nameEditEpoch: number = 0;
  onStart: (mode: AccountMode) => void = () => {};
  onEmail: (action: AccountEmailAction) => void = () => {};
  onSaveProfileName: (identity: AccountIdentity, update: AccountNameUpdate) => Promise<void> = async () => {};
  onListSessions: (identity: AccountIdentity) => Promise<AccountDeviceSession[]> = async () => [];
  onRevokeSession: (identity: AccountIdentity, sessionId: string) => Promise<void> = async () => {};
  onCancel: () => void = () => {};
  onSignOut: () => void = () => {};
  onRetry: () => void = () => {};
  onBack: () => void = () => {};
  onOpenConnectProfile: () => void = () => {};
  onRefreshServers: () => void = () => {};
  onDeregisterServer: (environment: RelayEnvironment) => void = () => {};

  aboutToAppear(): void {
    this.active = true;
  }

  aboutToDisappear(): void {
    this.active = false;
    this.nameEditEpoch++;
  }

  private profileIdentityChanged(): void {
    const draft = this.nameDraft;
    if (draft && (draft.identity.userId !== this.identity?.userId ||
      draft.identity.sessionId !== this.identity?.sessionId)) {
      this.resetNameDraft();
    }
  }

  private resetNameDraft(): void {
    this.nameEditEpoch++;
    this.nameDraft = undefined;
    this.savingName = false;
    this.nameError = '';
  }

  private editName(): void {
    const identity = this.identity;
    if (!identity || this.working) return;
    this.nameDraft = { identity, firstName: identity.firstName, lastName: identity.lastName };
  }

  private changeName(firstName: string, lastName: string): void {
    const draft = this.nameDraft;
    if (!draft || this.savingName) return;
    this.nameDraft = { identity: draft.identity, firstName, lastName };
  }

  private nameChanges(): AccountNameUpdate | undefined {
    const draft = this.nameDraft;
    if (!draft || this.working || this.savingName) return undefined;
    const firstName = draft.firstName.trim();
    const lastName = draft.lastName.trim();
    const update: AccountNameUpdate = {};
    if (firstName !== draft.identity.firstName.trim()) update.firstName = firstName;
    if (lastName !== draft.identity.lastName.trim()) update.lastName = lastName;
    return update.firstName !== undefined || update.lastName !== undefined ? update : undefined;
  }

  private async saveName(): Promise<void> {
    const draft = this.nameDraft;
    const update = this.nameChanges();
    if (!draft || !update) return;
    const epoch = this.nameEditEpoch;
    this.savingName = true;
    this.nameError = '';
    try {
      await this.onSaveProfileName(draft.identity, update);
      if (epoch === this.nameEditEpoch) this.resetNameDraft();
    } catch (error) {
      if (epoch === this.nameEditEpoch) {
        this.nameError = (error as Error).message || '无法保存姓名，请重试。';
      }
    } finally {
      if (epoch === this.nameEditEpoch) this.savingName = false;
    }
  }

  private startEmail(): void {
    if (this.working || !this.emailAddress.trim()) return;
    this.onEmail({ kind: 'start', value: this.emailAddress });
  }

  private verifyEmail(): void {
    const value = this.emailStep?.kind === 'password' ? this.credential : this.credential.trim();
    if (this.working || !value) return;
    this.credential = '';
    this.onEmail({ kind: 'verify', value });
  }

  private emailAction(kind: 'password' | 'emailCode' | 'resend'): void {
    this.credential = '';
    this.onEmail({ kind });
  }

  private credentialLabel(): string {
    if (this.emailStep?.kind === 'password') return '密码';
    if (this.emailStep?.kind === 'totp') return '身份验证器中的验证码';
    if (this.emailStep?.kind === 'backupCode') return '备用验证码';
    return '邮箱验证码';
  }

  private credentialInputType(): InputType {
    if (this.emailStep?.kind === 'password') return InputType.Password;
    if (this.emailStep?.kind === 'backupCode') return InputType.Normal;
    if (this.emailStep?.kind === 'totp') return InputType.Number;
    return InputType.ONE_TIME_CODE;
  }

  @Builder
  private Profile() {
    if (this.nameDraft) {
      Text('名')
        .fontSize(15)
        .fontColor($r('sys.color.font_primary'))
      TextInput({ text: this.nameDraft.firstName })
        .accessibilityText('名')
        .width('100%')
        .height(46)
        .enabled(!this.savingName)
        .onChange((value: string) => this.changeName(value, this.nameDraft?.lastName ?? ''))
      Text('姓')
        .fontSize(15)
        .fontColor($r('sys.color.font_primary'))
      TextInput({ text: this.nameDraft.lastName })
        .accessibilityText('姓')
        .width('100%')
        .height(46)
        .enabled(!this.savingName)
        .enterKeyType(EnterKeyType.Done)
        .onChange((value: string) => this.changeName(this.nameDraft?.firstName ?? '', value))
        .onSubmit(() => { void this.saveName(); })
      if (this.nameError) {
        Text(this.nameError)
          .fontSize(15)
          .fontColor($r('sys.color.font_primary'))
      }
      Row({ space: 8 }) {
        Button(this.savingName ? '正在保存…' : '保存姓名')
          .height(44)
          .enabled(!!this.nameChanges())
          .onClick(() => { void this.saveName(); })
        Button('取消', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(44)
          .enabled(!this.savingName)
          .onClick(() => this.resetNameDraft())
      }
      .width('100%')
    } else {
      Button('编辑姓名', { buttonStyle: ButtonStyleMode.NORMAL })
        .height(44)
        .onClick(() => this.editName())
    }
  }

  private describeServer(environment: RelayEnvironment): string {
    const linkedAt = new Date(environment.linkedAt);
    const linked = Number.isNaN(linkedAt.getTime()) ? '关联日期未知' : `关联于 ${linkedAt.toLocaleDateString()}`;
    const endpoint = environment.endpoint.providerKind === 'cloudflare_tunnel' ? '托管隧道' : '仅发布活动';
    return `${linked} · ${endpoint}`;
  }

  private async confirmDeregister(environment: RelayEnvironment): Promise<void> {
    const identity = this.identity;
    if (!identity || !this.connectProfileOpen || this.working || this.registeredServersLoading ||
      this.deregisteringEnvironmentId || this.confirmingDeregister) return;
    this.confirmingDeregister = true;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '注销服务器？',
        message: `“${environment.label}”将从此账号移除。T3 Connect 访问权限将被撤销，托管隧道将被移除，并释放一个主机名额。仍可使用设备上保存的本地连接。`,
        buttons: [{ text: '取消', color: '#5070a1' }, { text: '注销', color: '#c8353c' }],
      });
      if (result.index === 1 && this.active && this.connectProfileOpen && !this.working &&
        !this.registeredServersLoading && !this.deregisteringEnvironmentId &&
        this.identity?.userId === identity.userId && this.identity?.sessionId === identity.sessionId &&
        this.registeredServers.some((row: RelayEnvironment) =>
          row.environmentId === environment.environmentId && row.linkedAt === environment.linkedAt)) {
        this.onDeregisterServer(environment);
      }
    } catch (_) {} finally {
      this.confirmingDeregister = false;
    }
  }

  private refreshRegisteredServers(): void {
    if (!this.registeredServersLoading && !this.deregisteringEnvironmentId) this.onRefreshServers();
  }

  @Builder
  private ConnectProfileEntry() {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 12 }) {
        Text('T3 Connect').fontSize(16).fontColor($r('sys.color.font_primary')).layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14).fontColor([$r('sys.color.icon_secondary')])
      }.width('100%')
    }
    .id('account-connect-profile-open')
    .width('100%')
    .height(48)
    .padding({ left: 12, right: 12 })
    .onClick(() => this.onOpenConnectProfile())
  }

  @Builder
  private ServerDetails(title: string, detail: string) {
    Column({ space: 2 }) {
      Text(title)
        .fontSize(16)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(detail)
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  @Builder
  private ServerActions(environment: RelayEnvironment) {
    Menu() {
      MenuItem({ content: '注销' })
        .id(`account-connect-deregister-${environment.environmentId}`)
        .contentFontColor('#c8353c')
        .onClick(() => { void this.confirmDeregister(environment); })
    }
  }

  @Builder
  private RegisteredServers() {
    Column() {
      Text('已注册的服务器')
        .width('100%')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_secondary'))
        .padding({ left: 24, right: 24, top: 32, bottom: 16 })
      Divider().color($r('sys.color.comp_divider'))
      if (this.registeredServersLoading && !this.registeredServersLoaded && this.registeredServers.length === 0) {
        Row({ space: 12 }) {
          LoadingProgress().width(20).height(20)
          Text('正在加载服务器').fontSize(16).fontColor($r('sys.color.font_secondary'))
        }
        .id('account-connect-loading')
        .width('100%')
        .padding({ left: 24, right: 24, top: 16, bottom: 16 })
      } else if (this.registeredServersError && !this.registeredServersLoading) {
        Row() {
          this.ServerDetails('无法加载 T3 Connect 环境', this.registeredServersError)
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 16, bottom: 16 })
        Divider().color($r('sys.color.comp_divider'))
        Button('重试', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .id('account-connect-retry')
          .height(44)
          .margin({ left: 12 })
          .enabled(!this.deregisteringEnvironmentId)
          .onClick(() => this.refreshRegisteredServers())
        Divider().color($r('sys.color.comp_divider'))
      } else if (this.registeredServers.length > 0) {
        ForEach(this.registeredServers, (environment: RelayEnvironment) => {
          Row({ space: 12 }) {
            this.ServerDetails(environment.label, this.describeServer(environment))
            if (this.deregisteringEnvironmentId === environment.environmentId) {
              LoadingProgress().width(20).height(20).accessibilityText('正在注销服务器')
            } else {
              Button({ type: ButtonType.Circle }) {
                Text('⋮').fontSize(20).fontColor($r('sys.color.icon_secondary'))
              }
                .id(`account-connect-server-actions-${environment.environmentId}`)
                .width(44)
                .height(44)
                .backgroundColor(Color.Transparent)
                .accessibilityText(environment.label + ' 的操作')
                .enabled(!this.working && !this.registeredServersLoading && !this.deregisteringEnvironmentId)
                .bindMenu(this.ServerActions(environment))
            }
          }
          .width('100%')
          .padding({ left: 24, right: 16, top: 14, bottom: 14 })
          Divider().color($r('sys.color.comp_divider'))
        }, (environment: RelayEnvironment) =>
          `${environment.environmentId}\n${environment.linkedAt}\n${environment.label}\n${environment.endpoint.providerKind}`)
      } else {
        Row() {
          this.ServerDetails('暂无已注册的服务器', '在服务器的本地设置中关联 T3 Connect，即可通过 T3 Connect 访问。')
        }
        .id('account-connect-empty')
        .width('100%')
        .padding({ left: 24, right: 24, top: 16, bottom: 16 })
        Divider().color($r('sys.color.comp_divider'))
      }
      if (this.deregisterError) {
        Text(this.deregisterError)
          .width('100%')
          .fontSize(15)
          .fontColor($r('sys.color.font_primary'))
          .padding({ left: 24, right: 24, top: 16 })
      }
      Text('此设备的连接可在设置中管理。')
        .width('100%')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .padding({ left: 24, right: 24, top: 24, bottom: 32 })
    }
    .width('100%')
    .constraintSize({ maxWidth: 480 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ConnectProfile() {
    Column() {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(22).fontColor([$r('sys.color.icon_primary')])
        }
        .id('account-connect-profile-back')
        .width(44)
        .height(44)
        .backgroundColor(Color.Transparent)
        .accessibilityText('返回 T3 账号')
        .onClick(() => this.onBack())
        Text('T3 Connect').fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
      }.width('100%').height(56).padding({ left: 8, right: 12 })

      Refresh({ refreshing: this.registeredServersLoading &&
        (this.registeredServersLoaded || this.registeredServers.length > 0) }) {
        Scroll() {
          this.RegisteredServers()
        }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off)
      }
      .id('account-connect-profile-refresh')
      .width('100%')
      .layoutWeight(1)
      .pullToRefresh(!this.deregisteringEnvironmentId)
      .onRefreshing(() => this.refreshRegisteredServers())
    }
    .id('account-connect-profile')
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.comp_background_primary'))
  }

  @Builder
  private EmailForm() {
    if (!this.emailStep) {
      TextInput({ placeholder: '邮箱地址', text: this.emailAddress })
        .type(InputType.Email)
        .enterKeyType(EnterKeyType.Go)
        .accessibilityText('邮箱地址')
        .width('100%')
        .height(46)
        .enabled(!this.working)
        .onChange((value: string) => { this.emailAddress = value; })
        .onSubmit(() => this.startEmail())
      Button('继续')
        .width('100%')
        .height(46)
        .enabled(!this.working && !!this.emailAddress.trim())
        .onClick(() => this.startEmail())
    } else if (this.emailStep.kind === 'hosted') {
      Text('请在浏览器中继续登录。')
        .fontSize(15)
        .fontColor($r('sys.color.font_secondary'))
    } else if (this.emailStep.kind !== 'complete') {
      Text(this.emailAddress.trim())
        .fontSize(15)
        .fontColor($r('sys.color.font_secondary'))
      TextInput({ placeholder: this.credentialLabel(), text: this.credential })
        .type(this.credentialInputType())
        .enterKeyType(EnterKeyType.Go)
        .accessibilityText(this.credentialLabel())
        .width('100%')
        .height(46)
        .enabled(!this.working)
        .onChange((value: string) => { this.credential = value; })
        .onSubmit(() => this.verifyEmail())
      Button(this.emailStep.kind === 'password' ? '登录' : '验证')
        .width('100%')
        .height(46)
        .enabled(!this.working && !!this.credential)
        .onClick(() => this.verifyEmail())
      if (this.emailStep.kind === 'emailCode' || this.emailStep.kind === 'mfaEmail') {
        Button('重新发送验证码', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(44)
          .enabled(!this.working)
          .onClick(() => this.emailAction('resend'))
      }
      if (this.emailStep.kind === 'emailCode' && this.emailStep.passwordAvailable) {
        Button('改用密码', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(44)
          .enabled(!this.working)
          .onClick(() => this.emailAction('password'))
      }
      if (this.emailStep.kind === 'password' && this.emailStep.emailCodeAvailable) {
        Button('改用邮箱验证码', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(44)
          .enabled(!this.working)
          .onClick(() => this.emailAction('emailCode'))
      }
    }
    if (this.emailWorking || this.emailStep) {
      Button(this.emailWorking ? '取消' : '更换邮箱', { buttonStyle: ButtonStyleMode.TEXTUAL })
        .height(44)
        .onClick(() => {
          this.credential = '';
          this.onCancel();
        })
    }
    Button('在浏览器中登录', { buttonStyle: ButtonStyleMode.NORMAL })
      .width('100%')
      .height(46)
      .enabled(!this.working)
      .onClick(() => {
        this.credential = '';
        this.onStart('sign-in');
      })
    if (!this.emailStep) {
      Button('创建账号', { buttonStyle: ButtonStyleMode.TEXTUAL })
        .width('100%')
        .height(46)
        .enabled(!this.working)
        .onClick(() => this.onStart('sign-up'))
    }
  }

  @Builder
  private AccountPage() {
    Column() {
      Row({ space: 8 }) {
        Button('返回', { type: ButtonType.Normal })
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
          .backgroundColor(Color.Transparent)
          .height(44)
          .onClick(() => {
            this.credential = '';
            this.onBack();
          })
        Text('T3 账号')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 12 })

      Scroll() {
        Column({ space: 12 }) {
          if (this.identity) {
            Text(this.identity.displayName)
              .fontSize(21)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.identity.email && this.identity.email !== this.identity.displayName) {
              Text(this.identity.email)
                .fontSize(15)
                .fontColor($r('sys.color.font_secondary'))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          if (!this.configured) {
            Text('此版本未配置 T3 账号登录。')
              .fontSize(15)
              .fontColor($r('sys.color.font_secondary'))
          } else if ((this.working && !this.emailWorking) || this.awaitingBrowser) {
            Row({ space: 12 }) {
              LoadingProgress().width(24).height(24)
              Text(this.awaitingBrowser ? '请在浏览器中完成，然后返回 T3 Code。' : '正在处理账号请求…')
                .fontSize(15)
                .fontColor($r('sys.color.font_secondary'))
                .layoutWeight(1)
            }.width('100%')
            if (this.awaitingBrowser) {
              Button('取消', { buttonStyle: ButtonStyleMode.TEXTUAL })
                .height(44)
                .onClick(() => this.onCancel())
            }
          } else if (this.identity) {
            this.Profile()
            Button('退出登录', { buttonStyle: ButtonStyleMode.NORMAL })
              .height(44)
              .enabled(!this.deregisteringEnvironmentId && !this.savingName)
              .onClick(() => this.onSignOut())
            Divider().color($r('sys.color.comp_divider'))
            AccountSessions({
              identity: this.identity,
              onListSessions: this.onListSessions,
              onRevokeSession: this.onRevokeSession,
            })
            if (this.relayConfigured) {
              Divider().color($r('sys.color.comp_divider'))
              this.ConnectProfileEntry()
            }
          } else {
            if (this.emailWorking) {
              Row({ space: 12 }) {
                LoadingProgress().width(24).height(24)
                Text('正在处理邮箱登录…')
                  .fontSize(15)
                  .fontColor($r('sys.color.font_secondary'))
              }.width('100%')
            }
            this.EmailForm()
          }
          if (this.error) {
            Text(this.error)
              .fontSize(15)
              .fontColor($r('sys.color.font_primary'))
            if (this.configured && !this.working && !this.awaitingBrowser && !this.emailStep) {
              Button('重试', { buttonStyle: ButtonStyleMode.TEXTUAL })
                .height(44)
                .onClick(() => this.onRetry())
            }
          } else if (!this.working && this.emailStep?.error) {
            Text(this.emailStep.error)
              .fontSize(15)
              .fontColor($r('sys.color.font_primary'))
          }
        }
        .width('100%')
        .constraintSize({ maxWidth: 480 })
        .alignItems(HorizontalAlign.Start)
        .padding(20)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }

  build() {
    if (this.configured && this.identity && this.relayConfigured && this.connectProfileOpen) {
      this.ConnectProfile()
    } else {
      this.AccountPage()
    }
  }
}
